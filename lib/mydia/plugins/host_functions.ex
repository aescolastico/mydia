defmodule Mydia.Plugins.HostFunctions do
  @moduledoc """
  Typed WIT host imports exposed to component guests (U4).

  Host functions are the plugin platform's capability model: a guest can only
  affect the outside world by calling an imported host function, and each one
  enforces the plugin's **server-side** grant (deny-by-default) before doing any
  work. Grants are resolved from the runtime registry on *every* call, so a
  revoked capability takes effect immediately (a plugin can never widen its own
  grant — KTD6).

  ## Component import ABI (v1)

  Imports live under the `"mydia:plugin/host@1.0.0"` interface namespace and
  receive/return **typed WIT records** — no linear-memory marshalling. Wasmex
  hands each import closure the decoded record (atom-keyed map; `option<T>` as
  `{:some, v}` / `:none`; `list<tuple>` as `[{k, v}]`) and marshals the closure's
  return value back across the boundary:

    * `http-request(outbound-request) -> result<outbound-response, host-error>`
    * `data-read(data-request) -> result<read-result, host-error>`
    * `log(string, string)` — ungated, fire-and-forget

  A closure must return exactly the WIT-declared shape: `{:ok, record}` /
  `{:error, host-error}` for the `result` functions. A wrong-typed return can
  panic the wasmex NIF, so every closure is wrapped in a shim
  (`typed_result/1`) that converts any raise into a well-formed `internal`
  error variant rather than letting a bad value reach the boundary.

  ## Imports are built per invocation

  Unlike the core-wasm host (one shared imports map), the component host builds
  the imports map per invocation through `imports_for/2`, which returns a builder
  `(invocation_ctx -> map)`. The closures capture the invocation context
  directly, so a guest `log` line correlates to its run without a shared
  registry; the per-invocation log-line counter lives in the builder closure.
  """

  require Logger

  alias Mydia.Media
  alias Mydia.Plugins
  alias Mydia.Plugins.Error
  alias Mydia.Plugins.Logs
  alias Mydia.Plugins.Net.Gate
  alias Mydia.Plugins.Plugin

  # The WIT host interface namespace. The version suffix is the ABI version —
  # wasmtime's linker matches it exactly at instantiation.
  @namespace "mydia:plugin/host@1.0.0"

  # Per-invocation guest log-line cap. `log` is ungated, so a buggy or hostile
  # guest could spam it in a loop and flood plugin_logs before retention fires.
  # Past the cap we drop further lines and emit one sentinel.
  @log_line_cap 1000

  @doc """
  Builds the per-invocation imports builder for a plugin pool.

  Returns a 1-arity function `(invocation_ctx -> imports_map)` that
  `Mydia.Plugins.Host` invokes for each call, so the `log` closure can capture
  the run's `invocation_id`/`test_run` directly. The closures capture `slug`; the
  current grants are looked up per call, so revocation is honored without
  restarting the pool. `gate_opts` are host-side options forwarded to the gate
  (e.g. the `:allow_private`/`:resolver` test seams) — production passes none, so
  a guest can never influence them.
  """
  @spec imports_for(String.t(), keyword()) :: (map() -> map())
  def imports_for(slug, gate_opts \\ []) when is_binary(slug) do
    fn ctx ->
      %{
        @namespace => %{
          "http-request" => {:fn, http_import(slug, gate_opts)},
          "data-read" => {:fn, data_import(slug)},
          "log" => {:fn, log_import(slug, ctx)}
        }
      }
    end
  end

  # ── http-request import ────────────────────────────────────────────────────

  defp http_import(slug, gate_opts) do
    fn req ->
      typed_result(fn ->
        with {:ok, plugin} <- Plugins.get_plugin(slug),
             {:ok, resp} <- http_request(plugin, from_outbound_request(req), gate_opts) do
          {:ok, to_outbound_response(resp)}
        end
      end)
    end
  end

  # WIT outbound-request record -> the string-key request map the gated logic
  # expects. `headers` arrives as a list of {k, v} tuples; the gate wants a map.
  defp from_outbound_request(req) do
    %{
      "url" => Map.get(req, :url, ""),
      "method" => Map.get(req, :method, "GET"),
      "headers" => req |> Map.get(:headers, []) |> Map.new(),
      "body" => from_option(Map.get(req, :body))
    }
  end

  defp to_outbound_response(%{"status" => status} = resp) do
    %{
      status: status,
      ok: Map.get(resp, "ok", false),
      body: to_option(Map.get(resp, "body")),
      "body-encoding": to_option(Map.get(resp, "body_encoding"))
    }
  end

  # ── data-read import ───────────────────────────────────────────────────────

  defp data_import(slug) do
    fn req ->
      typed_result(fn ->
        with {:ok, plugin} <- Plugins.get_plugin(slug),
             {:ok, projection} <- data_read(plugin, from_data_request(req)) do
          {:ok, {:"media-item", to_media_item(projection)}}
        end
      end)
    end
  end

  defp from_data_request(req) do
    %{"resource" => Map.get(req, :namespace, ""), "id" => Map.get(req, :id, "")}
  end

  # String-key projection map -> the WIT media-item record (kebab atom keys,
  # option-wrapped optionals). Field set mirrors project_media_item/1 exactly.
  defp to_media_item(p) do
    %{
      id: get(p, "id", ""),
      "item-type": get(p, "type", ""),
      title: get(p, "title", ""),
      "original-title": to_option(get(p, "original_title")),
      year: to_option(get(p, "year")),
      "tmdb-id": to_option(get(p, "tmdb_id")),
      "tvdb-id": to_option(get(p, "tvdb_id")),
      "imdb-id": to_option(get(p, "imdb_id")),
      overview: to_option(get(p, "overview")),
      tagline: to_option(get(p, "tagline")),
      runtime: to_option(get(p, "runtime")),
      genres: get(p, "genres") || [],
      "poster-path": to_option(get(p, "poster_path")),
      "backdrop-path": to_option(get(p, "backdrop_path")),
      rating: to_option(get(p, "rating"))
    }
  end

  defp get(map, key, default \\ nil), do: Map.get(map, key, default)

  # ── log import (ungated) ───────────────────────────────────────────────────

  # `log(level, message)` is ungated — every guest may emit diagnostics with no
  # capability grant (R1). Built per invocation, so `ctx` correlates the line to
  # its run and the counter (captured here) caps lines within the invocation. It
  # returns the empty list (the WIT function has no result) and never raises into
  # the guest.
  defp log_import(slug, ctx) do
    counter = :counters.new(1, [:write_concurrency])

    fn level, message ->
      try do
        record_guest_line(slug, ctx, counter, level, message)
        []
      rescue
        e ->
          Logger.warning("plugin log for #{slug} raised: #{Exception.message(e)}")
          []
      end
    end
  end

  defp record_guest_line(slug, ctx, counter, level, message) do
    :counters.add(counter, 1, 1)
    n = :counters.get(counter, 1)

    cond do
      n <= @log_line_cap ->
        write_guest_line(slug, ctx, level, message)

      n == @log_line_cap + 1 ->
        Logs.create_async(%{
          slug: slug,
          invocation_id: ctx[:invocation_id],
          source: :host,
          level: :warn,
          message: "log limit reached (#{@log_line_cap} lines) — further guest lines dropped",
          test_run: ctx[:test_run] || false
        })

      true ->
        :ok
    end
  end

  defp write_guest_line(slug, ctx, level, message) do
    Logs.create_async(%{
      slug: slug,
      invocation_id: ctx[:invocation_id],
      source: :guest,
      level: normalize_level(level),
      message: to_string(message),
      test_run: ctx[:test_run] || false
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

  # ── Return-type shim ───────────────────────────────────────────────────────

  # Guarantees the import returns a well-formed WIT `result`: maps an Error to
  # the matching host-error variant, and catches any raise so a wrong-typed value
  # never reaches the boundary (which can NIF-panic).
  defp typed_result(fun) do
    case fun.() do
      {:ok, record} -> {:ok, record}
      {:error, %Error{} = err} -> {:error, host_error(err)}
    end
  rescue
    e ->
      Logger.warning("host function raised: #{Exception.message(e)}")
      {:error, {:internal, "host function error"}}
  end

  defp host_error(%Error{type: type, message: message}) do
    tag =
      case type do
        :capability_denied -> :denied
        :invalid_request -> :"invalid-request"
        :invalid_output -> :"invalid-request"
        :invalid_url -> :"invalid-request"
        :not_found -> :"not-found"
        :network -> :network
        :network_error -> :network
        :timeout -> :network
        :too_large -> :network
        :blocked -> :network
        _ -> :internal
      end

    {tag, to_string(message)}
  end

  # ── option<T> marshalling ──────────────────────────────────────────────────

  defp to_option(nil), do: :none
  defp to_option(value), do: {:some, value}

  defp from_option({:some, value}), do: value
  defp from_option(:none), do: nil
  defp from_option(nil), do: nil

  # ── http_request (net:http) ───────────────────────────────────────────────

  @doc """
  Performs a gated outbound HTTP request on behalf of `plugin`.

  Enforces the plugin's `net:http` grant (deny-by-default) and routes through
  `Mydia.Plugins.Net.Gate`. `request` is the string-key map adapted from the WIT
  `outbound-request`: `%{"url" => url, "method" => "POST", "headers" => %{},
  "body" => "..."}`.

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
