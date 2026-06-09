defmodule Mydia.Plugins.Manifest do
  @moduledoc """
  Plugin manifest format and capability taxonomy.

  A manifest is the JSON document shipped with a plugin package. It *declares*
  metadata, the events the plugin subscribes to, and the capabilities it wants.
  Parsing validates the manifest and produces a `%Manifest{}`; it never confers
  any capability (grants are server-side — see `Mydia.Plugins.Plugin`).

  ## Format

      {
        "slug": "webhook-notifier",
        "name": "Webhook Notifier",
        "version": "1.0.0",
        "description": "Posts events to a webhook",
        "author": "Mydia",
        "entrypoint": "handle",
        "capabilities": {
          "events:subscribe": ["media_item.added", "download.completed"],
          "net:http": ["discord.com"]
        }
      }

  ## Capability taxonomy

    * `events:subscribe` — the list of event types the plugin reacts to. Each
      must be in the v1 catalog (`event_catalog/0`).
    * `net:http` — the exact hostnames the plugin may contact. **No wildcards**
      (a wildcard is a DNS-subdomain exfiltration channel — KTD5).
    * `data:read` — scoped read namespaces (e.g. `media_item`). Each namespace
      must be in the v1 read catalog (`data_namespaces/0`); the host honors it
      via the `data_read` host function (U6), which returns a curated read-only
      projection — never raw rows or secrets.
    * `surfaces:write` — write-back surfaces. **Reserved, not implemented in v1.**

  To avoid an approve-but-no-runtime gap (KTD8), a v1 manifest declaring a
  reserved-but-unimplemented class (only `surfaces:write` remains reserved) is
  rejected at parse time with a clear "capability not available in this version"
  error — the admin is never asked to approve a capability no host function
  honors.
  """

  alias Mydia.Plugins.Error

  @type t :: %__MODULE__{
          slug: String.t(),
          name: String.t(),
          version: String.t(),
          description: String.t() | nil,
          author: String.t() | nil,
          entrypoint: String.t(),
          events: [String.t()],
          capabilities: %{optional(String.t()) => [String.t()]}
        }

  defstruct slug: nil,
            name: nil,
            version: nil,
            description: nil,
            author: nil,
            entrypoint: "handle",
            events: [],
            capabilities: %{}

  # v1 event catalog (KTD3): a curated subset of existing event `type` strings
  # dispatched off the "events:all" bus.
  @event_catalog ~w(
    media_item.added
    media_item.updated
    media_item.removed
    media_file.imported
    download.completed
    download.failed
  )

  # All taxonomy classes (reserved + implemented). The schema/approval UI know
  # all four so they need no breaking change when the reserved ones land.
  @known_classes ~w(events:subscribe net:http data:read surfaces:write)

  # Implemented in v1; the rest are reserved-but-rejected (KTD8). `data:read`
  # is honored by the `data_read` host function (U6); `surfaces:write` stays
  # reserved.
  @available_classes ~w(events:subscribe net:http data:read)

  # v1 read catalog: the resource namespaces `data:read` may scope to. Each maps
  # to a curated projection in the `data_read` host function (U6).
  @data_namespaces ~w(media_item)

  @doc "Returns the v1 event catalog (allowed `events:subscribe` values)."
  @spec event_catalog() :: [String.t()]
  def event_catalog, do: @event_catalog

  @doc "Returns every capability class name (implemented and reserved)."
  @spec known_classes() :: [String.t()]
  def known_classes, do: @known_classes

  @doc "Returns the capability classes a host function honors in this version."
  @spec available_classes() :: [String.t()]
  def available_classes, do: @available_classes

  @doc "Returns the v1 `data:read` namespaces (allowed scoped-read values)."
  @spec data_namespaces() :: [String.t()]
  def data_namespaces, do: @data_namespaces

  @doc """
  Parses and validates a manifest from a JSON string or an already-decoded map.

  Returns `{:ok, %Manifest{}}` or `{:error, %Mydia.Plugins.Error{}}`. Parsing
  confers no capability (R5).
  """
  @spec parse(String.t() | map()) :: {:ok, t()} | {:error, Error.t()}
  def parse(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> parse(map)
      {:ok, _} -> {:error, Error.new(:invalid_manifest, "manifest must be a JSON object")}
      {:error, _} -> {:error, Error.new(:invalid_manifest, "manifest is not valid JSON")}
    end
  end

  def parse(map) when is_map(map) do
    capabilities = Map.get(map, "capabilities", %{})

    with :ok <- validate_required(map),
         {:ok, capabilities} <- validate_capabilities(capabilities) do
      {:ok,
       %__MODULE__{
         slug: map["slug"],
         name: map["name"],
         version: map["version"],
         description: map["description"],
         author: map["author"],
         entrypoint: Map.get(map, "entrypoint", "handle"),
         events: Map.get(capabilities, "events:subscribe", []),
         capabilities: capabilities
       }}
    end
  end

  # ── Validation ──────────────────────────────────────────────────────────

  defp validate_required(map) do
    missing = Enum.filter(~w(slug name version), &blank?(Map.get(map, &1)))

    case missing do
      [] ->
        :ok

      fields ->
        {:error,
         Error.new(:invalid_manifest, "missing required fields: #{Enum.join(fields, ", ")}")}
    end
  end

  defp validate_capabilities(capabilities) when not is_map(capabilities) do
    {:error, Error.new(:invalid_manifest, "capabilities must be an object")}
  end

  defp validate_capabilities(capabilities) when capabilities == %{} do
    {:error, Error.new(:invalid_manifest, "a plugin must declare at least one capability")}
  end

  defp validate_capabilities(capabilities) do
    with :ok <- validate_classes(Map.keys(capabilities)),
         :ok <- validate_events(Map.get(capabilities, "events:subscribe")),
         :ok <- validate_http_hosts(Map.get(capabilities, "net:http")),
         :ok <- validate_data_namespaces(Map.get(capabilities, "data:read")) do
      {:ok, capabilities}
    end
  end

  defp validate_classes(classes) do
    cond do
      unknown = Enum.find(classes, &(&1 not in @known_classes)) ->
        {:error, Error.new(:invalid_manifest, "unknown capability class: #{unknown}")}

      reserved = Enum.find(classes, &(&1 not in @available_classes)) ->
        {:error,
         Error.new(
           :capability_unavailable,
           "capability not available in this version: #{reserved}"
         )}

      "events:subscribe" not in classes ->
        {:error, Error.new(:invalid_manifest, "a plugin must declare events:subscribe")}

      true ->
        :ok
    end
  end

  defp validate_events(nil), do: :ok

  defp validate_events(events) when not is_list(events),
    do: {:error, Error.new(:invalid_manifest, "events:subscribe must be a list")}

  defp validate_events([]),
    do: {:error, Error.new(:invalid_manifest, "events:subscribe must not be empty")}

  defp validate_events(events) do
    case Enum.find(events, &(&1 not in @event_catalog)) do
      nil -> :ok
      bad -> {:error, Error.new(:invalid_manifest, "event not in v1 catalog: #{bad}")}
    end
  end

  defp validate_http_hosts(nil), do: :ok

  defp validate_http_hosts(hosts) when not is_list(hosts),
    do: {:error, Error.new(:invalid_manifest, "net:http must be a list of hostnames")}

  defp validate_http_hosts(hosts) do
    cond do
      bad = Enum.find(hosts, &(not is_binary(&1) or blank?(&1))) ->
        {:error, Error.new(:invalid_manifest, "net:http hostname is blank: #{inspect(bad)}")}

      wild = Enum.find(hosts, &String.contains?(&1, "*")) ->
        {:error,
         Error.new(
           :invalid_manifest,
           "net:http hostname must be exact, no wildcards: #{wild}"
         )}

      true ->
        :ok
    end
  end

  defp validate_data_namespaces(nil), do: :ok

  defp validate_data_namespaces(namespaces) when not is_list(namespaces),
    do: {:error, Error.new(:invalid_manifest, "data:read must be a list of namespaces")}

  defp validate_data_namespaces([]),
    do: {:error, Error.new(:invalid_manifest, "data:read must not be empty")}

  defp validate_data_namespaces(namespaces) do
    case Enum.find(namespaces, &(&1 not in @data_namespaces)) do
      nil ->
        :ok

      bad ->
        {:error, Error.new(:invalid_manifest, "data:read namespace not in v1 catalog: #{bad}")}
    end
  end

  defp blank?(nil), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: false
end
