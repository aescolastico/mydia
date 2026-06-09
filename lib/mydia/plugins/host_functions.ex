defmodule Mydia.Plugins.HostFunctions do
  @moduledoc """
  Elixir host functions exposed to WASM guests (U6).

  Host functions are the plugin platform's capability model: a guest can only
  affect the outside world by calling an imported host function, and each one
  enforces the plugin's **server-side** grant (deny-by-default) before doing any
  work. Grants are resolved from the runtime registry on *every* call, so a
  revoked capability takes effect immediately (a plugin can never widen its own
  grant — KTD6).

  ## Host-function ABI (v1)

  Imports live under the `"mydia"` namespace. Each takes a request buffer and a
  caller-provided response buffer:

      (param req_ptr i32) (param req_len i32) (param resp_ptr i32) (param resp_cap i32)
      (result i32)

  The host reads the JSON request at `req_ptr`/`req_len` (via the callback
  `caller`, never an outer store — KTD2), does the gated work, JSON-encodes the
  response, and writes it into the guest-provided buffer at `resp_ptr` (capacity
  `resp_cap`). The return value is:

    * `>= 0` — number of response bytes written (a JSON object; on a gated
      failure this is an `{"error": ..., "type": ...}` envelope the guest can read)
    * `-1` — response did not fit in `resp_cap` (guest should retry with a
      larger buffer)
    * `-2` — request JSON was malformed

  Writing into a buffer the guest already allocated keeps the ABI re-entrancy
  free: the host never calls back into a guest export from inside a host-function
  callback. (This realizes KTD2's "host writes the response into guest memory"
  intent without the re-entrant allocator hop.)
  """

  require Logger

  alias Mydia.Media
  alias Mydia.Plugins
  alias Mydia.Plugins.Error
  alias Mydia.Plugins.Logs
  alias Mydia.Plugins.Net.Gate
  alias Mydia.Plugins.Plugin

  @namespace "mydia"

  @overflow -1
  @malformed -2

  @invocation_registry Mydia.Plugins.InvocationRegistry

  # Per-invocation guest log-line cap. `log` is ungated, so a buggy or hostile
  # guest could spam it in a loop and flood plugin_logs before retention fires;
  # fuel bounds total work but not rows inserted. Past the cap we drop further
  # lines and emit one sentinel (U3).
  @log_line_cap 1000

  @doc """
  Builds the wasmex imports map for a plugin pool.

  The closures capture the `slug`; the current grants are looked up per call, so
  revocation is honored without restarting the pool. `gate_opts` are host-side
  options forwarded to the gate (e.g. the `:allow_private`/`:resolver` test
  seams) — production passes none, so a guest can never influence them.
  """
  @spec imports_for(String.t(), keyword()) :: map()
  def imports_for(slug, gate_opts \\ []) when is_binary(slug) do
    %{
      @namespace => %{
        "http_request" => host_fn(slug, &http_request/3, gate_opts),
        "data_read" =>
          host_fn(slug, fn plugin, req, _opts -> data_read(plugin, req) end, gate_opts),
        "log" => log_fn(slug)
      }
    }
  end

  # `log(level, message)` is ungated — every guest may emit diagnostics with no
  # capability grant (U3, R1). The callback runs in the instance process, so
  # `context.pid` resolves the active invocation via the InvocationRegistry. It
  # returns 0 (no response bytes) and never raises into the guest.
  defp log_fn(slug) do
    {:fn, [:i32, :i32, :i32, :i32], [:i32],
     fn %{memory: memory, caller: caller, pid: pid}, req_ptr, req_len, _resp_ptr, _resp_cap ->
       handle_log(slug, pid, caller, memory, req_ptr, req_len)
       0
     end}
  end

  defp handle_log(slug, pid, caller, memory, req_ptr, req_len) do
    with {:ok, req} <- decode_request(caller, memory, req_ptr, req_len) do
      {invocation_id, counter, test_run} = invocation_for(pid, slug)
      record_guest_line(slug, invocation_id, counter, test_run, req)
    end

    :ok
  rescue
    e ->
      Logger.warning("plugin log for #{slug} raised: #{Exception.message(e)}")
      :ok
  end

  defp invocation_for(pid, slug) do
    case Registry.lookup(@invocation_registry, pid) do
      [{_owner, {^slug, invocation_id, counter, test_run}}] ->
        {invocation_id, counter, test_run}

      _ ->
        # Defensive: a `log` call with no live correlation entry. Store it
        # uncorrelated rather than dropping or raising.
        {"uncorrelated", nil, false}
    end
  end

  # No counter (uncorrelated) — store without enforcing the cap.
  defp record_guest_line(slug, invocation_id, nil, test_run, req) do
    write_guest_line(slug, invocation_id, test_run, req)
  end

  defp record_guest_line(slug, invocation_id, counter, test_run, req) do
    :counters.add(counter, 1, 1)
    n = :counters.get(counter, 1)

    cond do
      n <= @log_line_cap ->
        write_guest_line(slug, invocation_id, test_run, req)

      n == @log_line_cap + 1 ->
        Logs.create_async(%{
          slug: slug,
          invocation_id: invocation_id,
          source: :host,
          level: :warn,
          message: "log limit reached (#{@log_line_cap} lines) — further guest lines dropped",
          test_run: test_run
        })

      true ->
        :ok
    end
  end

  defp write_guest_line(slug, invocation_id, test_run, req) do
    Logs.create_async(%{
      slug: slug,
      invocation_id: invocation_id,
      source: :guest,
      level: normalize_level(Map.get(req, "level")),
      message: to_string(Map.get(req, "message", "")),
      test_run: test_run
    })
  end

  defp normalize_level(level) when is_binary(level) do
    case String.downcase(level) do
      "debug" -> :debug
      "info" -> :info
      "warn" -> :warn
      "warning" -> :warn
      "error" -> :error
      _ -> :info
    end
  end

  defp normalize_level(_), do: :info

  # Wraps a {plugin, request_map, gate_opts} -> {:ok, map} | {:error, Error}
  # function as a wasmex (req_ptr, req_len, resp_ptr, resp_cap) -> i32 import.
  defp host_fn(slug, fun, gate_opts) do
    {:fn, [:i32, :i32, :i32, :i32], [:i32],
     fn %{memory: memory, caller: caller}, req_ptr, req_len, resp_ptr, resp_cap ->
       with {:ok, req} <- decode_request(caller, memory, req_ptr, req_len),
            {:ok, plugin} <- Plugins.get_plugin(slug) do
         response = run(fun, plugin, req, gate_opts)
         write_response(caller, memory, resp_ptr, resp_cap, response)
       else
         {:error, :malformed} ->
           @malformed

         {:error, %Error{} = err} ->
           write_response(caller, memory, resp_ptr, resp_cap, error_envelope(err))
       end
     end}
  end

  # A host function raising must never crash the Wasmex instance process running
  # the guest — degrade to an error envelope the guest can read.
  defp run(fun, plugin, req, gate_opts) do
    case fun.(plugin, req, gate_opts) do
      {:ok, map} -> map
      {:error, %Error{} = err} -> error_envelope(err)
    end
  rescue
    e ->
      Logger.warning("host function for #{plugin.slug} raised: #{Exception.message(e)}")
      error_envelope(Error.new(:unknown, "host function error"))
  end

  defp decode_request(caller, memory, ptr, len) do
    json = Wasmex.Memory.read_binary(caller, memory, ptr, len)

    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> {:error, :malformed}
    end
  end

  defp write_response(caller, memory, resp_ptr, resp_cap, map) do
    json = Jason.encode!(map)
    len = byte_size(json)

    if len <= resp_cap do
      Wasmex.Memory.write_binary(caller, memory, resp_ptr, json)
      len
    else
      @overflow
    end
  end

  defp error_envelope(%Error{type: type, message: message}) do
    %{"error" => message, "type" => to_string(type)}
  end

  # ── http_request (net:http) ───────────────────────────────────────────────

  @doc """
  Performs a gated outbound HTTP request on behalf of `plugin`.

  Enforces the plugin's `net:http` grant (deny-by-default) and routes through
  `Mydia.Plugins.Net.Gate`. `request` is the guest's decoded JSON map:
  `%{"url" => url, "method" => "POST", "headers" => %{}, "body" => "..."}`.

  `opts` are host-side only (e.g. the `:allow_private` test seam) — never derived
  from the guest request.
  """
  @spec http_request(Plugin.t(), map(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def http_request(%Plugin{} = plugin, request, opts \\ []) do
    with :ok <- require_capability(plugin, "net:http"),
         {:ok, url} <- fetch_string(request, "url") do
      hosts = Plugin.granted_http_hosts(plugin)

      gate_opts =
        [
          allowed_hosts: hosts,
          slug: plugin.slug,
          method: Map.get(request, "method", "GET"),
          headers: Map.get(request, "headers", %{}),
          body: Map.get(request, "body")
        ] ++ Keyword.take(opts, [:allow_private, :resolver, :max_bytes, :timeout])

      case Gate.request(url, gate_opts) do
        {:ok, resp} -> {:ok, http_response_map(resp)}
        {:error, _} = err -> err
      end
    end
  end

  defp http_response_map(%{status: status, body: body}) do
    base = %{"status" => status, "ok" => status in 200..299}

    if String.valid?(body) do
      Map.put(base, "body", body)
    else
      Map.put(base, "body_encoding", "binary")
    end
  end

  # ── data_read (data:read) ─────────────────────────────────────────────────

  @doc """
  Returns a curated, read-only projection of a domain resource for `plugin`.

  Enforces the plugin's `data:read` grant scoped to the requested namespace
  (deny-by-default). Only a hand-picked, non-sensitive set of fields is ever
  returned — never raw rows or secrets. `request` is `%{"resource" => ns,
  "id" => id}`.
  """
  @spec data_read(Plugin.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def data_read(%Plugin{} = plugin, %{"resource" => "media_item"} = request) do
    with :ok <- require_data_namespace(plugin, "media_item"),
         {:ok, id} <- fetch_string(request, "id"),
         {:ok, item} <- fetch_media_item(id) do
      {:ok, project_media_item(item)}
    end
  end

  def data_read(%Plugin{}, %{"resource" => other}) do
    {:error, Error.new(:invalid_request, "unknown data:read resource: #{other}")}
  end

  def data_read(%Plugin{}, _request) do
    {:error, Error.new(:invalid_request, "data:read request requires a resource")}
  end

  defp fetch_media_item(id) do
    {:ok, Media.get_media_item!(id)}
  rescue
    Ecto.NoResultsError -> {:error, Error.new(:not_found, "media_item #{id} not found")}
    Ecto.Query.CastError -> {:error, Error.new(:invalid_request, "invalid media_item id")}
  end

  # Hand-picked, non-sensitive projection. Adding a field here is a deliberate
  # decision to expose it to plugins — do not splat the struct.
  defp project_media_item(item) do
    md = item.metadata

    %{
      "id" => item.id,
      "type" => item.type,
      "title" => item.title,
      "original_title" => item.original_title,
      "year" => item.year,
      "tmdb_id" => item.tmdb_id,
      "tvdb_id" => item.tvdb_id,
      "imdb_id" => item.imdb_id,
      "overview" => md && md.overview,
      "tagline" => md && md.tagline,
      "runtime" => md && md.runtime,
      "genres" => md && md.genres,
      "poster_path" => md && md.poster_path,
      "backdrop_path" => md && md.backdrop_path,
      "rating" => md && md.vote_average
    }
  end

  # ── Capability checks (deny-by-default) ───────────────────────────────────

  defp require_capability(plugin, class) do
    if Plugin.granted?(plugin, class) do
      :ok
    else
      {:error, Error.new(:capability_denied, "capability #{class} not granted to #{plugin.slug}")}
    end
  end

  defp require_data_namespace(plugin, namespace) do
    granted = Map.get(plugin.granted_capabilities, "data:read", [])

    if namespace in granted do
      :ok
    else
      {:error,
       Error.new(
         :capability_denied,
         "data:read namespace #{namespace} not granted to #{plugin.slug}"
       )}
    end
  end

  defp fetch_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, Error.new(:invalid_request, "missing or invalid #{key}")}
    end
  end
end
