defmodule MydiaWeb.AdminPluginsLive.Index do
  @moduledoc """
  Admin plugin store and capability-approval UI (U9).

  Mirrors the service-config row+modal pattern (download clients / indexers).
  The emphasized surface is the **capability-approval modal**: activation is
  blocked until the admin explicitly accepts the declared capabilities, which are
  rendered in host-owned plain language (`MydiaWeb.AdminPluginsLive.Components`),
  with network egress made legible. Env/index-sourced rows render read-only with
  a source badge (provenance).
  """
  use MydiaWeb, :live_view

  require Logger

  alias Mydia.Events
  alias Mydia.Plugins
  alias Mydia.Plugins.Index
  alias Mydia.Plugins.Log
  alias Mydia.Plugins.Logs
  alias Mydia.Settings

  # Max log rows loaded into the detail timeline on open / filter.
  @log_limit 200

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Configuration - Plugins")
     |> assign(:active_tab, :plugins)
     |> assign(:catalog, [])
     |> assign(:browsing?, false)
     |> assign(:browse_error, nil)
     |> assign(:approval, nil)
     |> assign(:detail, nil)
     |> assign(:settings, nil)
     |> assign(:log_topic, nil)
     |> stream(:plugin_logs, [])
     |> load_installed()
     |> load_updates()}
  end

  ## Store browsing (R13)

  @impl true
  def handle_event("browse_store", _params, socket) do
    {entries, error} = browse()
    installed_slugs = MapSet.new(socket.assigns.installed, & &1.slug)
    available = Enum.reject(entries, &MapSet.member?(installed_slugs, &1.slug))

    {:noreply,
     socket
     |> assign(:catalog, available)
     |> assign(:browse_error, error)
     |> assign(:browsing?, false)}
  end

  ## Capability approval (KTD6, AE1)

  def handle_event("review_install", %{"slug" => slug}, socket) do
    case Enum.find(socket.assigns.catalog, &(&1.slug == slug)) do
      nil -> {:noreply, socket}
      entry -> {:noreply, assign(socket, :approval, approval_from_entry(entry))}
    end
  end

  def handle_event("review_approve", %{"slug" => slug}, socket) do
    case Settings.get_plugin_config_by_slug(slug) do
      nil -> {:noreply, socket}
      config -> {:noreply, assign(socket, :approval, approval_from_config(config))}
    end
  end

  def handle_event("decline_approval", _params, socket) do
    {:noreply, assign(socket, :approval, nil)}
  end

  def handle_event("confirm_approval", _params, %{assigns: %{approval: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("confirm_approval", _params, socket) do
    approval = socket.assigns.approval

    result =
      case approval.kind do
        :catalog -> Plugins.install(approval.entry)
        :installed -> Plugins.approve(approval.slug)
      end

    socket =
      case result do
        {:ok, _} ->
          socket
          |> put_flash(:info, "#{approval.name} approved and activated.")
          |> assign(:approval, nil)
          |> assign(:catalog, [])
          |> load_installed()

        {:error, error} ->
          put_flash(socket, :error, "Could not activate: #{error_message(error)}")
      end

    {:noreply, socket}
  end

  ## Lifecycle (R14)

  def handle_event("toggle_enabled", %{"slug" => slug}, socket) do
    config = Settings.get_plugin_config_by_slug(slug)
    enable? = !(config && config.enabled)
    apply_lifecycle(socket, fn -> Plugins.set_enabled(slug, enable?) end, "Updated #{slug}.")
  end

  def handle_event("revoke", %{"slug" => slug}, socket) do
    apply_lifecycle(socket, fn -> Plugins.revoke(slug) end, "Revoked #{slug}.")
  end

  def handle_event("remove", %{"slug" => slug}, socket) do
    apply_lifecycle(socket, fn -> Plugins.remove(slug) end, "Removed #{slug}.")
  end

  ## Settings modal (operator-editable config — U3)

  def handle_event("edit_settings", %{"slug" => slug}, socket) do
    case Settings.get_plugin_config_by_slug(slug) do
      nil -> {:noreply, socket}
      config -> {:noreply, assign(socket, :settings, settings_state(config))}
    end
  end

  def handle_event("close_settings", _params, socket) do
    {:noreply, assign(socket, :settings, nil)}
  end

  def handle_event("save_settings", %{"slug" => slug} = params, socket) do
    case Settings.get_plugin_config_by_slug(slug) do
      nil ->
        {:noreply, socket}

      config ->
        schema = settings_schema_of(config)
        settings = build_settings(schema, params)

        socket =
          with :ok <- validate_url_settings(schema, settings),
               {:ok, _} <- Plugins.update_settings(slug, settings) do
            socket
            |> put_flash(:info, "#{config.name} settings saved.")
            |> assign(:settings, nil)
            |> load_installed()
          else
            {:error, message} when is_binary(message) ->
              # Keep the modal open so the operator can correct the value.
              put_flash(socket, :error, message)

            {:error, error} ->
              put_flash(socket, :error, error_message(error))
          end

        {:noreply, socket}
    end
  end

  ## Detail modal (granted caps + egress audit)

  def handle_event("show_detail", %{"slug" => slug}, socket) do
    case Settings.get_plugin_config_by_slug(slug) do
      nil ->
        {:noreply, socket}

      config ->
        socket = subscribe_logs(socket, slug)
        logs = Logs.recent(slug, limit: @log_limit)

        {:noreply,
         socket
         |> assign(:detail, detail_for(config))
         |> stream(:plugin_logs, logs, reset: true)}
    end
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply,
     socket
     |> unsubscribe_logs()
     |> assign(:detail, nil)
     |> stream(:plugin_logs, [], reset: true)}
  end

  ## Debug logs (U6) — filter + live tail

  def handle_event("filter_logs", params, socket) do
    detail = socket.assigns.detail
    min_level = parse_level(params["level"])
    query = String.trim(params["query"] || "")
    logs = Logs.recent(detail.slug, limit: @log_limit, min_level: min_level, query: query)

    {:noreply,
     socket
     |> assign(:detail, %{detail | min_level: min_level, query: query})
     |> stream(:plugin_logs, logs, reset: true)}
  end

  ## Test trigger (U7)

  def handle_event("test_plugin", %{"slug" => slug, "event" => event_type}, socket) do
    case Plugins.test_invoke(slug, event_type) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Test #{event_type} dispatched to #{slug}.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "#{slug} is not running — enable it first.")}
    end
  end

  ## Live tail (U6)

  @impl true
  def handle_info({:plugin_log, %Log{} = log}, socket) do
    detail = socket.assigns.detail

    if detail && log.slug == detail.slug && level_visible?(log.level, detail.min_level) &&
         query_visible?(log.message, detail.query) do
      {:noreply, stream_insert(socket, :plugin_logs, log, at: 0)}
    else
      {:noreply, socket}
    end
  end

  ## Helpers

  defp subscribe_logs(socket, slug) do
    socket = unsubscribe_logs(socket)
    topic = Logs.topic(slug)
    if connected?(socket), do: Phoenix.PubSub.subscribe(Mydia.PubSub, topic)
    assign(socket, :log_topic, topic)
  end

  defp unsubscribe_logs(%{assigns: %{log_topic: nil}} = socket), do: socket

  defp unsubscribe_logs(%{assigns: %{log_topic: topic}} = socket) do
    if connected?(socket), do: Phoenix.PubSub.unsubscribe(Mydia.PubSub, topic)
    assign(socket, :log_topic, nil)
  end

  defp parse_level(level) do
    case level do
      l when l in ["debug", "info", "warn", "error"] -> String.to_existing_atom(l)
      _ -> :debug
    end
  end

  defp level_visible?(level, min_level), do: Log.level_rank(level) >= Log.level_rank(min_level)

  defp query_visible?(_message, query) when query in [nil, ""], do: true

  defp query_visible?(message, query),
    do: String.contains?(String.downcase(message || ""), String.downcase(query))

  defp apply_lifecycle(socket, fun, success_msg) do
    socket =
      case fun.() do
        {:ok, _} ->
          socket
          |> put_flash(:info, success_msg)
          |> assign(:detail, nil)
          |> load_installed()

        {:error, error} ->
          put_flash(socket, :error, error_message(error))
      end

    {:noreply, socket}
  end

  defp load_installed(socket) do
    rows = Settings.list_plugin_configs() |> Enum.map(&row/1)
    assign(socket, :installed, rows)
  end

  # Normalizes a config (DB or runtime/env) into a render row with provenance.
  defp row(config) do
    source = if Settings.runtime_config?(config), do: :env, else: :index
    capabilities = capabilities_of(config)
    settings_schema = settings_schema_of(config)
    granted = config.granted_capabilities || %{}

    %{
      slug: config.slug,
      name: config.name,
      version: config.version,
      enabled: config.enabled,
      source: source,
      read_only: source == :env,
      capabilities: capabilities,
      granted: granted,
      pending_approval: not config.enabled and capabilities != %{},
      has_settings: settings_schema != [],
      # Once approved, the granted net:http reflects the operator-configured host.
      network_hosts: Map.get(granted, "net:http", Map.get(capabilities, "net:http", []))
    }
  end

  defp capabilities_of(%{manifest: %{"capabilities" => caps}}) when is_map(caps), do: caps
  defp capabilities_of(%{granted_capabilities: caps}) when is_map(caps), do: caps
  defp capabilities_of(_), do: %{}

  defp settings_schema_of(%{manifest: %{"settings_schema" => schema}}) when is_list(schema),
    do: schema

  defp settings_schema_of(_), do: []

  # Builds the settings modal state. Secret values are not echoed back into the
  # form (write-only) — a blank secret on save preserves the stored one.
  defp settings_state(config) do
    schema = settings_schema_of(config)
    current = config.settings || %{}

    form_data =
      Enum.reduce(schema, %{}, fn field, acc ->
        if field["type"] == "secret",
          do: acc,
          else: Map.put(acc, field["key"], Map.get(current, field["key"]))
      end)

    %{
      slug: config.slug,
      name: config.name,
      schema: schema,
      form: to_form(form_data)
    }
  end

  # Rejects a non-blank url-typed setting that does not parse to an absolute
  # http(s) URL — otherwise a scheme-less value (e.g. "ntfy.example.com/x") would
  # derive no host, silently dropping the grant and breaking delivery.
  defp validate_url_settings(schema, settings) do
    schema
    |> Enum.filter(&(&1["type"] == "url"))
    |> Enum.reduce_while(:ok, fn field, :ok ->
      value = Map.get(settings, field["key"])

      if blank_value?(value) or absolute_url?(value) do
        {:cont, :ok}
      else
        label = field["label"] || field["key"]
        {:halt, {:error, "#{label} must be a full URL including https://"}}
      end
    end)
  end

  defp blank_value?(value), do: is_nil(value) or value == ""

  defp absolute_url?(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        true

      _ ->
        false
    end
  end

  defp absolute_url?(_), do: false

  # Extracts the schema-declared keys from submitted params. Blank secrets are
  # dropped so update_settings/2's merge preserves the existing value.
  defp build_settings(schema, params) do
    Enum.reduce(schema, %{}, fn field, acc ->
      key = field["key"]
      value = Map.get(params, key)

      cond do
        is_nil(value) -> acc
        field["type"] == "secret" and value == "" -> acc
        true -> Map.put(acc, key, value)
      end
    end)
  end

  defp load_updates(socket) do
    slugs =
      Events.list_events(category: "plugin", type: "plugin.update_available", limit: 100)
      |> Enum.map(& &1.actor_id)
      |> MapSet.new()

    assign(socket, :updates, slugs)
  end

  defp browse do
    Enum.reduce(Index.sources(), {[], nil}, fn source, {acc, err} ->
      case Index.fetch_catalog(source) do
        {:ok, entries} -> {acc ++ entries, err}
        {:error, error} -> {acc, err || error_message(error)}
      end
    end)
  end

  defp approval_from_entry(entry) do
    %{
      kind: :catalog,
      entry: entry,
      slug: entry.slug,
      name: entry.name,
      version: entry.version,
      capabilities: entry.manifest.capabilities,
      settings_schema: entry.manifest.settings_schema
    }
  end

  defp approval_from_config(config) do
    capabilities = capabilities_of(config)

    %{
      kind: :installed,
      slug: config.slug,
      name: config.name,
      version: config.version,
      capabilities: capabilities,
      settings_schema: settings_schema_of(config)
    }
  end

  defp detail_for(config) do
    audit =
      Events.list_events(
        type: "plugin.http_request",
        actor_type: :system,
        actor_id: config.slug,
        limit: 10
      )

    %{
      slug: config.slug,
      name: config.name,
      enabled: config.enabled,
      granted: config.granted_capabilities || %{},
      settings_schema: settings_schema_of(config),
      audit: audit,
      min_level: :debug,
      query: "",
      test_events: Map.get(config.granted_capabilities || %{}, "events:subscribe", [])
    }
  end

  defp error_message(%{__struct__: _} = error) do
    if function_exported?(error.__struct__, :message, 1) do
      error.__struct__.message(error)
    else
      inspect(error)
    end
  end

  defp error_message(other), do: inspect(other)
end
