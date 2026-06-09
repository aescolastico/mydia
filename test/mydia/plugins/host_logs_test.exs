defmodule Mydia.Plugins.HostLogsTest do
  # async: false — pools register app-wide and the DataCase shared sandbox lets
  # the guest `log` callback (which runs in the instance process) persist rows.
  use Mydia.DataCase, async: false

  alias Mydia.Plugins.Error
  alias Mydia.Plugins.Host
  alias Mydia.Plugins.HostFunctions
  alias Mydia.Plugins.Logs

  # Minimal v1-ABI guest: mydia_alloc + handle(ptr,len) -> i64, returns
  # {"first":true} (14 bytes at offset 100).
  @abi_wat """
  (module
    (memory (export "memory") 2)
    (data (i32.const 100) "{\\"first\\":true}")
    (func (export "mydia_alloc") (param $len i32) (result i32) (i32.const 2048))
    (func (export "handle") (param $ptr i32) (param $len i32) (result i64)
      (i64.or (i64.shl (i64.const 100) (i64.const 32)) (i64.const 14))))
  """

  # Traps immediately (Rust-`panic!` analogue at the wasm level).
  @trap_wat """
  (module
    (memory (export "memory") 1)
    (func (export "mydia_alloc") (param $len i32) (result i32) (i32.const 1024))
    (func (export "handle") (param $ptr i32) (param $len i32) (result i64)
      (unreachable)))
  """

  # Calls the imported mydia.log host function once, then returns {"ok":true}.
  # The log request JSON lives at offset 100 (45 bytes).
  @log_wat """
  (module
    (import "mydia" "log" (func $log (param i32 i32 i32 i32) (result i32)))
    (memory (export "memory") 2)
    (data (i32.const 100) "{\\"level\\":\\"info\\",\\"message\\":\\"hello from guest\\"}")
    (data (i32.const 200) "{\\"ok\\":true}")
    (func (export "mydia_alloc") (param $len i32) (result i32) (i32.const 2048))
    (func (export "handle") (param $ptr i32) (param $len i32) (result i64)
      (drop (call $log (i32.const 100) (i32.const 45) (i32.const 1024) (i32.const 512)))
      (i64.or (i64.shl (i64.const 200) (i64.const 32)) (i64.const 11))))
  """

  # Writes a line to WASI stdout (fd 1) via fd_write, then returns {"ok":true}.
  @stdout_wat """
  (module
    (import "wasi_snapshot_preview1" "fd_write"
      (func $fd_write (param i32 i32 i32 i32) (result i32)))
    (memory (export "memory") 1)
    (data (i32.const 100) "stdout line from guest\\n")
    (data (i32.const 200) "{\\"ok\\":true}")
    (func (export "mydia_alloc") (param $len i32) (result i32) (i32.const 2048))
    (func (export "handle") (param $ptr i32) (param $len i32) (result i64)
      (i32.store (i32.const 300) (i32.const 100))
      (i32.store (i32.const 304) (i32.const 23))
      (drop (call $fd_write (i32.const 1) (i32.const 300) (i32.const 1) (i32.const 320)))
      (i64.or (i64.shl (i64.const 200) (i64.const 32)) (i64.const 11))))
  """

  defp start!(slug, wat, opts \\ []) do
    {:ok, bytes} = Wasmex.Wat.to_wasm(wat)
    opts = Keyword.put_new(opts, :imports, HostFunctions.imports_for(slug))
    {:ok, _pid} = Host.start_plugin(slug, bytes, opts)
    on_exit(fn -> Host.stop_plugin(slug) end)
    :ok
  end

  describe "host outcome markers (U2)" do
    test "a successful invocation gets a start marker and an ok end marker" do
      start!("mk-ok", @abi_wat)
      assert {:ok, _} = Host.call("mk-ok", "handle", %{"event" => "media_item.added"})

      host = "mk-ok" |> Logs.recent() |> Enum.filter(&(&1.source == :host))
      assert Enum.any?(host, &(&1.metadata["phase"] == "start"))

      end_marker = Enum.find(host, &(&1.metadata["phase"] == "end"))
      assert end_marker.metadata["outcome"] == "ok"
      assert is_integer(end_marker.metadata["duration_ms"])
      # the triggering event is captured on the start marker
      assert Enum.any?(host, &(&1.metadata["event"] == "media_item.added"))
    end

    test "a trap is recorded as an error end marker, not silence (AE1)" do
      start!("mk-trap", @trap_wat)
      assert {:error, %Error{type: :trap}} = Host.call("mk-trap", "handle", %{})

      rows = Logs.recent("mk-trap")

      assert Enum.any?(rows, fn r ->
               r.source == :host and r.level == :error and r.metadata["outcome"] == "trap"
             end)
    end
  end

  describe "guest log host function (U3)" do
    test "a guest log() line is captured and correlated to the invocation" do
      start!("lg", @log_wat)
      assert {:ok, _} = Host.call("lg", "handle", %{})

      rows = Logs.recent("lg")
      guest = Enum.find(rows, &(&1.source == :guest))

      assert guest, "expected a guest-source log row"
      assert guest.message == "hello from guest"
      assert guest.level == :info

      host_invocation = rows |> Enum.find(&(&1.source == :host)) |> Map.get(:invocation_id)
      assert guest.invocation_id == host_invocation
    end
  end

  describe "WASI stdout/stderr capture (U4)" do
    test "guest stdout is captured as a wasi-source row" do
      start!("so", @stdout_wat)
      assert {:ok, _} = Host.call("so", "handle", %{})

      wasi = "so" |> Logs.recent() |> Enum.find(&(&1.source == :wasi))

      assert wasi, "expected a wasi-source log row"
      assert wasi.message =~ "stdout line from guest"
      assert wasi.level == :info
    end
  end
end
