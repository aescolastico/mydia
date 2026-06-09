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

  ## Settings schema

  An optional top-level `settings_schema` declares the operator-editable config
  fields a plugin exposes. Each field is an object with `key`, `type`
  (`string | url | secret | enum`), and optional `label`, `required`, and (for
  `enum`) `options`. A `url` field may carry `grants_host: true`, which marks it
  as **host-granting**: the host of the operator-configured value is added to the
  plugin's effective `net:http` allowlist at config time (see
  `Mydia.Plugins` host-grant recomputation). This lets a shared plugin reach a
  server the operator owns without the hostname ever appearing in the manifest,
  while the host — never the guest — computes the grant.
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
          capabilities: %{optional(String.t()) => [String.t()]},
          settings_schema: [map()]
        }

  defstruct slug: nil,
            name: nil,
            version: nil,
            description: nil,
            author: nil,
            entrypoint: "handle",
            events: [],
            capabilities: %{},
            settings_schema: []

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

  # Field types a `settings_schema` entry may declare.
  @setting_types ~w(string url secret enum)

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
    settings_schema = Map.get(map, "settings_schema", [])

    with :ok <- validate_required(map),
         {:ok, capabilities} <- validate_capabilities(capabilities),
         {:ok, settings_schema} <- validate_settings_schema(settings_schema) do
      {:ok,
       %__MODULE__{
         slug: map["slug"],
         name: map["name"],
         version: map["version"],
         description: map["description"],
         author: map["author"],
         entrypoint: Map.get(map, "entrypoint", "handle"),
         events: Map.get(capabilities, "events:subscribe", []),
         capabilities: capabilities,
         settings_schema: settings_schema
       }}
    end
  end

  @doc """
  Returns the host-granting field maps a manifest declares — `url` fields with
  `grants_host: true`. Accepts either a `%Manifest{}` or a raw `settings_schema`
  list (as stored on a persisted plugin config), so callers reading the JSON
  manifest map do not need to re-parse. The single source of truth for "which
  settings grant a host"; see `host_granting_keys/1`.
  """
  @spec host_granting_fields(t() | [map()] | nil) :: [map()]
  def host_granting_fields(%__MODULE__{settings_schema: schema}), do: host_granting_fields(schema)

  def host_granting_fields(schema) when is_list(schema) do
    Enum.filter(
      schema,
      &(Map.get(&1, "type") == "url" and Map.get(&1, "grants_host") == true)
    )
  end

  def host_granting_fields(_), do: []

  @doc """
  Returns the setting keys a manifest declares host-granting. Thin projection of
  `host_granting_fields/1` to the field `key`.
  """
  @spec host_granting_keys(t() | [map()] | nil) :: [String.t()]
  def host_granting_keys(schema_or_manifest) do
    schema_or_manifest |> host_granting_fields() |> Enum.map(&Map.get(&1, "key"))
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

  defp validate_settings_schema(nil), do: {:ok, []}

  defp validate_settings_schema(schema) when not is_list(schema),
    do: {:error, Error.new(:invalid_manifest, "settings_schema must be a list")}

  defp validate_settings_schema(schema) do
    with :ok <- validate_each_setting(schema),
         :ok <- validate_unique_setting_keys(schema) do
      {:ok, schema}
    end
  end

  defp validate_each_setting(schema) do
    Enum.reduce_while(schema, :ok, fn field, :ok ->
      case validate_setting_field(field) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_setting_field(field) when not is_map(field),
    do: {:error, Error.new(:invalid_manifest, "settings_schema field must be an object")}

  defp validate_setting_field(field) do
    key = Map.get(field, "key")
    type = Map.get(field, "type")

    cond do
      blank?(key) ->
        {:error, Error.new(:invalid_manifest, "settings_schema field key is blank")}

      type not in @setting_types ->
        {:error,
         Error.new(:invalid_manifest, "settings_schema field #{key} has unknown type: #{type}")}

      Map.get(field, "grants_host") == true and type != "url" ->
        {:error,
         Error.new(:invalid_manifest, "grants_host is only allowed on url fields: #{key}")}

      type == "enum" and not valid_options?(Map.get(field, "options")) ->
        {:error,
         Error.new(
           :invalid_manifest,
           "enum setting #{key} must declare a non-empty options list"
         )}

      true ->
        :ok
    end
  end

  defp valid_options?(options) when is_list(options) and options != [],
    do: Enum.all?(options, &(is_binary(&1) and not blank?(&1)))

  defp valid_options?(_), do: false

  defp validate_unique_setting_keys(schema) do
    keys = Enum.map(schema, &Map.get(&1, "key"))

    if length(Enum.uniq(keys)) == length(keys) do
      :ok
    else
      {:error, Error.new(:invalid_manifest, "settings_schema keys must be unique")}
    end
  end

  defp blank?(nil), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: false
end
