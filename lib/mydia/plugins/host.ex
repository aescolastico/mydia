defmodule Mydia.Plugins.Host do
  @moduledoc """
  WASM runtime host for the plugin platform.

  Each installed plugin gets its own `NimblePool` of warm-able workers. The
  expensive `Wasmex.Module` compilation is paid once per plugin (KTD9) and the
  compiled module + engine are shared, immutable NIF resources held in the
  pool's worker state. Each *invocation* checks out a slot from the pool and
  runs against a **fresh `Wasmex.Store`** (KTD9) so guests never share mutable
  linear memory across calls. The pool size bounds how many guests run
  concurrently on the dirty NIF schedulers.

  ## Sandbox (R1)

  Stores are created with deny-by-default WASI: no args, no env, no preopened
  directories, so a guest has no ambient filesystem or OS access. The only way
  out is an explicit host function import (the gated HTTP function lands in U6).

  ## Resource limiting (KTD4)

  `Wasmex.StoreLimits` caps linear memory on every store, always. The engine is
  compiled with `consume_fuel: true` so fuel metering is *available*; whether a
  given invocation enforces a finite fuel budget is decided per call:

    * the global default (`plugins.fuel_enabled`, defaults **off** for speed)
      governs direct calls, and
    * the event-dispatch path passes `force_fuel: true` (the user-chosen safety
      floor), so a runaway guest dispatched off an event always traps rather
      than starving a dirty NIF thread.

  When fuel is not enforced the store is still given a very large budget (the
  engine has fuel checks compiled in), so the overhead is the fuel-counting
  instrumentation, not a hard CPU cap. wasmex 0.14 exposes no epoch
  interruption, so with fuel unenforced a hung guest holds its slot until the OS
  reclaims the thread — an accepted, bounded residual under the curated-index
  trust model.

  ## Boundary (KTD2)

  The host↔guest boundary is JSON over linear memory. For each call the host:

    1. encodes the payload to JSON,
    2. calls the guest's exported allocator `mydia_alloc(len) -> ptr`,
    3. writes the JSON bytes at `ptr`,
    4. calls the handler `fun(ptr, len) -> packed` where `packed` is an `i64`
       holding `(out_ptr << 32) | out_len`,
    5. reads `out_len` bytes at `out_ptr` and JSON-decodes the result.

  Memory is read/written through the high-level `Wasmex` GenServer's store
  *between* calls (never inside a host-function callback, which must use the
  `caller` to avoid the store-mutex deadlock — see U6).
  """

  @behaviour NimblePool

  require Logger

  alias Mydia.Plugins.Error
  alias Mydia.Plugins.Log
  alias Mydia.Plugins.Logs
  alias Wasmex.Wasi.WasiOptions

  @registry Mydia.Plugins.PoolRegistry
  @supervisor Mydia.Plugins.PoolSupervisor
  @invocation_registry Mydia.Plugins.InvocationRegistry

  # Cap on captured WASI stdout/stderr per invocation (per pipe). Bounds the
  # in-memory drain and the maximum :text row written to plugin_logs (U4).
  @max_wasi_bytes 64 * 1024

  # Large fuel budget used when fuel is not being enforced. The engine has
  # consume_fuel compiled in, so the store must be funded or it traps at once.
  @unenforced_fuel 0x7FFF_FFFF_FFFF_FFFF

  @type slug :: String.t()

  # ── Public API ──────────────────────────────────────────────────────────

  @doc """
  Compiles `wasm_bytes` and starts a pool for `slug`.

  Options:

    * `:imports` - host-function import map passed to every instance
      (defaults to `%{}`; U6 supplies the gated HTTP function)
    * `:pool_size` - worker count (defaults to `plugins.pool_size` config)
  """
  @spec start_plugin(slug(), binary(), keyword()) ::
          {:ok, pid()} | {:error, Error.t()}
  def start_plugin(slug, wasm_bytes, opts \\ [])
      when is_binary(slug) and is_binary(wasm_bytes) do
    with {:ok, compiled} <- compile(wasm_bytes) do
      worker_arg = %{
        slug: slug,
        engine: compiled.engine,
        module: compiled.module,
        imports: Keyword.get(opts, :imports, %{})
      }

      pool_opts = [
        worker: {__MODULE__, worker_arg},
        pool_size: Keyword.get(opts, :pool_size, config().pool_size),
        lazy: true,
        name: via(slug)
      ]

      case DynamicSupervisor.start_child(@supervisor, pool_child_spec(slug, pool_opts)) do
        {:ok, pid} -> {:ok, pid}
        {:error, {:already_started, pid}} -> {:ok, pid}
        {:error, reason} -> {:error, Error.new(:instantiate_failed, inspect(reason))}
      end
    end
  end

  @doc "Stops the pool for `slug`, if running."
  @spec stop_plugin(slug()) :: :ok
  def stop_plugin(slug) do
    case Registry.lookup(@registry, slug) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(@supervisor, pid)
      [] -> :ok
    end

    :ok
  end

  @doc "True when a pool is running for `slug`."
  @spec running?(slug()) :: boolean()
  def running?(slug), do: Registry.lookup(@registry, slug) != []

  @doc """
  Invokes exported `function` on `slug`'s guest with `payload` (a JSON-encodable
  map), returning the decoded result map.

  Options:

    * `:force_fuel` - enforce a finite fuel budget even when the global default
      is off (the dispatch path sets this)
    * `:fuel_limit` - override the fuel budget for this call
    * `:timeout` - per-call deadline in ms (defaults to config)
  """
  @spec call(slug(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def call(slug, function, payload, opts \\ [])
      when is_binary(slug) and is_binary(function) and is_map(payload) do
    cfg = config()
    timeout = Keyword.get(opts, :timeout, cfg.invocation_timeout_ms)

    enforce_fuel? = Keyword.get(opts, :force_fuel, false) or cfg.fuel_enabled

    fuel =
      if enforce_fuel?, do: Keyword.get(opts, :fuel_limit, cfg.fuel_limit), else: @unenforced_fuel

    invocation = %{
      slug: slug,
      invocation_id: Ecto.UUID.generate(),
      test_run: Keyword.get(opts, :test_run, false),
      function: function,
      payload: payload,
      memory_limit_bytes: cfg.memory_limit_bytes,
      fuel: fuel,
      timeout: timeout
    }

    # Host markers bracket every invocation on both call paths (dispatch and
    # direct) so a run is always visible in the timeline — even one that traps
    # before the guest emits anything (R3, AE1).
    emit_start_marker(invocation)
    started_at = System.monotonic_time(:millisecond)

    result =
      try do
        # The checkout deadline gives the slot back even if the run wedges; the
        # inner per-call timeouts are the primary deadline.
        NimblePool.checkout!(
          via(slug),
          :checkout,
          fn _from, worker ->
            {run_invocation(worker, invocation), :ok}
          end,
          timeout + 1_000
        )
      catch
        :exit, {:noproc, _} ->
          {:error, Error.new(:not_found, "plugin #{slug} is not running")}

        :exit, {:timeout, _} ->
          {:error, Error.new(:timeout, "plugin #{slug} timed out after #{timeout}ms")}
      end

    emit_end_marker(invocation, result, System.monotonic_time(:millisecond) - started_at)
    result
  end

  # ── Compilation ─────────────────────────────────────────────────────────

  @doc false
  @spec compile(binary()) :: {:ok, %{engine: term(), module: term()}} | {:error, Error.t()}
  def compile(wasm_bytes) do
    # consume_fuel is always compiled in so the dispatch path can force fuel on
    # regardless of the global default (KTD4 + the chosen safety floor).
    engine_config = %Wasmex.EngineConfig{} |> Wasmex.EngineConfig.consume_fuel(true)

    with {:ok, engine} <- Wasmex.Engine.new(engine_config),
         {:ok, store} <- Wasmex.Store.new(nil, engine),
         {:ok, module} <- Wasmex.Module.compile(store, wasm_bytes) do
      {:ok, %{engine: engine, module: module}}
    else
      {:error, reason} -> {:error, Error.new(:compile_failed, to_string_reason(reason))}
    end
  end

  # ── Invocation ──────────────────────────────────────────────────────────

  defp run_invocation(worker, inv) do
    %{engine: engine, module: module, imports: imports} = worker

    limits = %Wasmex.StoreLimits{memory_size: inv.memory_limit_bytes}

    # Fresh stdout/stderr pipes per invocation capture the guest's WASI output
    # (println!/panic text). Fresh-store-per-call means each pipe holds exactly
    # this run's bytes — no offset bookkeeping (U4).
    {:ok, stdout} = Wasmex.Pipe.new()
    {:ok, stderr} = Wasmex.Pipe.new()

    wasi = %WasiOptions{args: [], env: %{}, preopen: [], stdout: stdout, stderr: stderr}

    with {:ok, store} <- Wasmex.Store.new_wasi(wasi, limits, engine),
         :ok <- set_fuel(store, inv.fuel),
         {:ok, pid} <- start_instance(store, module, imports) do
      # Correlate guest `log` calls (which run in the instance process) to this
      # invocation. The entry is owned by this (calling) process, so it is
      # auto-removed if we die; we also unregister explicitly below.
      counter = :counters.new(1, [:write_concurrency])

      Registry.register(
        @invocation_registry,
        pid,
        {inv.slug, inv.invocation_id, counter, inv.test_run}
      )

      try do
        invoke(pid, store, inv)
      after
        # Drain the pipes BEFORE killing the instance (the store dies with it).
        capture_wasi(inv, stdout, stderr)
        Registry.unregister(@invocation_registry, pid)
        Process.exit(pid, :kill)
      end
    else
      {:error, %Error{} = err} -> {:error, err}
      {:error, reason} -> {:error, Error.new(:instantiate_failed, to_string_reason(reason))}
    end
  end

  defp start_instance(store, module, imports) do
    # Wasmex only offers start_link, which links the instance to the checkout
    # process. We unlink immediately so killing the disposable instance (in the
    # `after` clause, or on a hung guest) never propagates an exit signal back
    # to the caller. The instance is monitored implicitly via the explicit kill.
    case Wasmex.start_link(%{store: store, module: module, imports: imports}) do
      {:ok, pid} ->
        Process.unlink(pid)
        {:ok, pid}

      {:error, reason} ->
        {:error, Error.new(:instantiate_failed, to_string_reason(reason))}
    end
  end

  defp set_fuel(store, fuel) do
    case Wasmex.StoreOrCaller.set_fuel(store, fuel) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, Error.new(:trap, "set_fuel failed: #{to_string_reason(reason)}")}
    end
  end

  defp invoke(pid, store, inv) do
    json = Jason.encode!(inv.payload)
    len = byte_size(json)

    with {:ok, memory} <- Wasmex.memory(pid),
         {:ok, in_ptr} <- alloc(pid, len, inv.timeout),
         :ok <- Wasmex.Memory.write_binary(store, memory, in_ptr, json),
         {:ok, packed} <- call_handler(pid, inv.function, in_ptr, len, inv.timeout),
         {:ok, result} <- read_result(store, memory, packed) do
      {:ok, result}
    end
  catch
    :exit, {:timeout, _} ->
      {:error, Error.new(:timeout, "invocation timed out after #{inv.timeout}ms")}
  end

  defp alloc(pid, len, timeout) do
    case Wasmex.call_function(pid, "mydia_alloc", [len], timeout) do
      {:ok, [ptr]} when is_integer(ptr) and ptr > 0 ->
        {:ok, ptr}

      {:ok, other} ->
        {:error, Error.new(:invalid_output, "mydia_alloc returned #{inspect(other)}")}

      {:error, reason} ->
        {:error, Error.new(:trap, "mydia_alloc failed: #{to_string_reason(reason)}")}
    end
  end

  defp call_handler(pid, function, in_ptr, len, timeout) do
    case Wasmex.call_function(pid, function, [in_ptr, len], timeout) do
      {:ok, [packed]} when is_integer(packed) ->
        {:ok, packed}

      {:ok, other} ->
        {:error, Error.new(:invalid_output, "#{function} returned #{inspect(other)}")}

      {:error, reason} ->
        {:error, Error.new(:trap, "#{function} trapped: #{to_string_reason(reason)}")}
    end
  end

  # Unpack the i64 (out_ptr << 32) | out_len and decode the JSON it points at.
  defp read_result(store, memory, packed) do
    <<out_ptr::unsigned-32, out_len::unsigned-32>> = <<packed::unsigned-64>>

    cond do
      out_len == 0 ->
        {:ok, %{}}

      true ->
        bytes = Wasmex.Memory.read_binary(store, memory, out_ptr, out_len)

        case Jason.decode(bytes) do
          {:ok, decoded} when is_map(decoded) ->
            {:ok, decoded}

          {:ok, other} ->
            {:error,
             Error.new(:invalid_output, "guest result is not a JSON object: #{inspect(other)}")}

          {:error, _} ->
            {:error, Error.new(:invalid_output, "guest result is not valid JSON")}
        end
    end
  end

  # ── Debug log markers + WASI capture (U2, U4) ─────────────────────────────

  defp emit_start_marker(inv) do
    Logs.create_async(%{
      slug: inv.slug,
      invocation_id: inv.invocation_id,
      source: :host,
      level: :debug,
      message: "invoke #{inv.function}",
      metadata: start_metadata(inv),
      test_run: inv.test_run
    })
  end

  defp start_metadata(inv) do
    base = %{"phase" => "start", "function" => inv.function}

    case event_type(inv.payload) do
      nil -> base
      type -> Map.put(base, "event", type)
    end
  end

  defp event_type(payload) when is_map(payload),
    do: Map.get(payload, :event) || Map.get(payload, "event")

  defp event_type(_), do: nil

  defp emit_end_marker(inv, result, duration_ms) do
    {level, outcome, detail} = classify_outcome(result)

    metadata =
      %{
        "phase" => "end",
        "function" => inv.function,
        "outcome" => outcome,
        "duration_ms" => duration_ms
      }
      |> maybe_put("detail", detail)

    Logs.create_async(%{
      slug: inv.slug,
      invocation_id: inv.invocation_id,
      source: :host,
      level: level,
      message: end_message(outcome, inv.function, duration_ms),
      metadata: metadata,
      test_run: inv.test_run
    })
  end

  defp classify_outcome({:ok, _}), do: {:info, "ok", nil}

  defp classify_outcome({:error, %Error{type: type, message: message}}),
    do: {:error, to_string(type), sanitize_detail(message)}

  # Defensive: every current run_invocation path is {:ok,_}|{:error,%Error{}},
  # but a catch-all keeps an unexpected shape from raising in the marker path.
  defp classify_outcome(_other), do: {:error, "unknown", nil}

  # A guest panic message (via to_string_reason) can carry non-UTF-8 bytes; this
  # detail lands in marker metadata which JsonMapType encodes with Jason, which
  # raises on invalid UTF-8 — dropping the very end-marker that records the trap.
  defp sanitize_detail(nil), do: nil
  defp sanitize_detail(message) when is_binary(message), do: Log.sanitize(message)
  defp sanitize_detail(message), do: message

  defp end_message(outcome, function, ms), do: "#{function} #{outcome} (#{ms}ms)"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Drains the per-invocation WASI pipes into wasi-source log rows (U4).
  #
  # Target-triple dependency (U8): captured stdout/stderr only carries text for
  # guests built against a WASI target (wasm32-wasip1), whose libc routes
  # println!/panic output through fd 1/2. A `wasm32-unknown-unknown` guest (the
  # bundled webhook notifier today) has no WASI stdio, so this yields nothing —
  # the host trap marker (U2) still records the *outcome*, and the guest can
  # still narrate via the `log` host function (target-independent), but the Rust
  # panic *message text* is only captured for WASI-target guests. For those,
  # also avoid `panic_immediate_abort`, which strips the message to a bare trap.
  defp capture_wasi(inv, stdout, stderr) do
    emit_wasi(inv, stdout, :info)
    emit_wasi(inv, stderr, :warn)
  end

  defp emit_wasi(inv, pipe, level) do
    Wasmex.Pipe.seek(pipe, 0)

    case Wasmex.Pipe.read(pipe) do
      bytes when is_binary(bytes) and byte_size(bytes) > 0 ->
        Logs.create_async(%{
          slug: inv.slug,
          invocation_id: inv.invocation_id,
          source: :wasi,
          level: level,
          message: truncate(bytes, @max_wasi_bytes),
          test_run: inv.test_run
        })

      _ ->
        :ok
    end
  end

  defp truncate(bytes, max) when byte_size(bytes) > max,
    do: binary_part(bytes, 0, max) <> " … [truncated]"

  defp truncate(bytes, _max), do: bytes

  # ── NimblePool callbacks ────────────────────────────────────────────────

  @impl NimblePool
  def init_worker(pool_state) do
    # The compiled module + engine are immutable, shareable NIF resources; the
    # worker just carries them. Fresh stores are made per invocation, so there
    # is no per-worker store to build here.
    {:ok, pool_state, pool_state}
  end

  @impl NimblePool
  def handle_checkout(:checkout, _from, worker_state, pool_state) do
    {:ok, worker_state, worker_state, pool_state}
  end

  @impl NimblePool
  def handle_checkin(_client_state, _from, worker_state, pool_state) do
    {:ok, worker_state, pool_state}
  end

  @impl NimblePool
  def terminate_worker(_reason, _worker_state, pool_state) do
    {:ok, pool_state}
  end

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp pool_child_spec(slug, pool_opts) do
    Supervisor.child_spec({NimblePool, pool_opts}, id: {__MODULE__, slug})
  end

  defp via(slug), do: {:via, Registry, {@registry, slug}}

  defp config do
    case Application.get_env(:mydia, :runtime_config) do
      %{plugins: %{} = plugins} -> plugins
      _ -> Mydia.Config.Schema.defaults().plugins
    end
  end

  defp to_string_reason(reason) when is_binary(reason), do: reason
  defp to_string_reason(reason), do: inspect(reason)
end
