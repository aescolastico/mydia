defmodule Mydia.Plugins.HostTest do
  # async: false — pools register under the app-wide Mydia.Plugins.PoolRegistry.
  use ExUnit.Case, async: false

  alias Mydia.Plugins.Error
  alias Mydia.Plugins.Host

  # A guest implementing the v1 ABI: mydia_alloc + handle(ptr,len) -> i64.
  # `handle` flips a mutable global so a *reused* store would return
  # {"first": false}; a fresh store per call always returns {"first": true}.
  # `{"first":true}`  is 14 bytes at offset 100
  # `{"first":false}` is 15 bytes at offset 200
  @abi_wat """
  (module
    (memory (export "memory") 2)
    (global $seen (mut i32) (i32.const 0))
    (data (i32.const 100) "{\\"first\\":true}")
    (data (i32.const 200) "{\\"first\\":false}")
    (func (export "mydia_alloc") (param $len i32) (result i32)
      (i32.const 2048))
    (func (export "handle") (param $ptr i32) (param $len i32) (result i64)
      (if (result i64) (global.get $seen)
        (then
          (i64.or (i64.shl (i64.const 200) (i64.const 32)) (i64.const 15)))
        (else
          (global.set $seen (i32.const 1))
          (i64.or (i64.shl (i64.const 100) (i64.const 32)) (i64.const 14))))))
  """

  # A guest whose handle burns CPU forever — traps when fuel is enforced low.
  @burn_wat """
  (module
    (memory (export "memory") 1)
    (func (export "mydia_alloc") (param $len i32) (result i32) (i32.const 1024))
    (func (export "handle") (param $ptr i32) (param $len i32) (result i64)
      (loop $l (br $l))
      (i64.const 0)))
  """

  # Probes WASI: fd_prestat_get on fd 3 (the first preopen). With deny-all WASI
  # (no preopen) it returns errno 8 (EBADF) — proving no filesystem access.
  @fs_probe_wat """
  (module
    (import "wasi_snapshot_preview1" "fd_prestat_get"
      (func $fd_prestat_get (param i32 i32) (result i32)))
    (memory (export "memory") 1)
    (func (export "probe") (result i32)
      (call $fd_prestat_get (i32.const 3) (i32.const 0))))
  """

  # Grows memory by the requested pages; memory.grow returns -1 past the limit.
  @grow_wat """
  (module
    (memory (export "memory") 1)
    (func (export "grow") (param $pages i32) (result i32)
      (memory.grow (local.get $pages))))
  """

  defp wasm!(wat) do
    {:ok, bytes} = Wasmex.Wat.to_wasm(wat)
    bytes
  end

  defp start!(slug, wat, opts \\ []) do
    {:ok, _pid} = Host.start_plugin(slug, wasm!(wat), opts)
    on_exit(fn -> Host.stop_plugin(slug) end)
    :ok
  end

  describe "call/4 — JSON (ptr,len) boundary and pooling" do
    test "compiles a module once and decodes a JSON result from (ptr, len)" do
      start!("abi", @abi_wat)
      assert {:ok, %{"first" => true}} = Host.call("abi", "handle", %{"event" => "ping"})
    end

    test "each invocation runs against a fresh store (no shared mutable state)" do
      start!("abi-iso", @abi_wat)
      # If the store/instance were reused, the second call would see $seen = 1
      # and return {"first": false}. Fresh store per call => always true.
      assert {:ok, %{"first" => true}} = Host.call("abi-iso", "handle", %{})
      assert {:ok, %{"first" => true}} = Host.call("abi-iso", "handle", %{})
    end

    test "serves concurrent invocations across the pool without crashing" do
      start!("abi-conc", @abi_wat, pool_size: 4)

      results =
        1..16
        |> Task.async_stream(fn _ -> Host.call("abi-conc", "handle", %{}) end,
          max_concurrency: 8,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, res} -> res end)

      assert Enum.all?(results, &match?({:ok, %{"first" => true}}, &1))
    end

    test "calling an unknown slug returns a not_found error" do
      assert {:error, %Error{type: :not_found}} = Host.call("nope", "handle", %{})
    end
  end

  describe "sandbox (R1) — deny-by-default WASI" do
    test "a guest with empty WASI options cannot access the filesystem" do
      # Exercise the same deny-all store the Host builds, then probe for a
      # preopened fd. errno 8 (EBADF) means no preopen => no filesystem.
      {:ok, engine} =
        Wasmex.Engine.new(Wasmex.EngineConfig.consume_fuel(%Wasmex.EngineConfig{}, true))

      {:ok, store} =
        Wasmex.Store.new_wasi(
          %Wasmex.Wasi.WasiOptions{args: [], env: %{}, preopen: []},
          %Wasmex.StoreLimits{memory_size: 1_000_000},
          engine
        )

      :ok = Wasmex.StoreOrCaller.set_fuel(store, 1_000_000_000)
      {:ok, module} = Wasmex.Module.compile(store, wasm!(@fs_probe_wat))
      {:ok, pid} = Wasmex.start_link(%{store: store, module: module, imports: %{}})

      assert {:ok, [errno]} = Wasmex.call_function(pid, "probe", [], 5_000)
      assert errno != 0
    end
  end

  describe "fuel metering (R2 / AE3)" do
    test "force_fuel with a low limit traps a runaway guest without killing the host" do
      start!("burn", @burn_wat)

      assert {:error, %Error{type: type}} =
               Host.call("burn", "handle", %{}, force_fuel: true, fuel_limit: 100_000)

      assert type in [:trap, :timeout]

      # Host pool survives and other plugins keep working.
      start!("after-burn", @abi_wat)
      assert {:ok, %{"first" => true}} = Host.call("after-burn", "handle", %{})
    end
  end

  describe "memory limiting (StoreLimits)" do
    test "growing past memory_limit_bytes fails at grow time" do
      {:ok, engine} =
        Wasmex.Engine.new(Wasmex.EngineConfig.consume_fuel(%Wasmex.EngineConfig{}, true))

      # One page (64KiB) is allowed; limit to ~128KiB so growing many pages fails.
      {:ok, store} =
        Wasmex.Store.new_wasi(
          %Wasmex.Wasi.WasiOptions{args: [], env: %{}, preopen: []},
          %Wasmex.StoreLimits{memory_size: 131_072},
          engine
        )

      :ok = Wasmex.StoreOrCaller.set_fuel(store, 1_000_000_000)
      {:ok, module} = Wasmex.Module.compile(store, wasm!(@grow_wat))
      {:ok, pid} = Wasmex.start_link(%{store: store, module: module, imports: %{}})

      # Growing by 100 pages (6.4MiB) exceeds the 128KiB cap => -1.
      assert {:ok, [-1]} = Wasmex.call_function(pid, "grow", [100], 5_000)
    end
  end
end
