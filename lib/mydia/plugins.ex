defmodule Mydia.Plugins do
  @moduledoc """
  Context for the WASM plugin platform.

  This is the public surface for the plugin platform: listing/resolving plugins,
  fanning events to them (U5), and the install/approve/revoke/remove lifecycle
  (U8) layered over the DB-overlay config (U4), the SSRF-gated host functions
  (U6), and the index (U7).

  ## Capability approval (KTD6, deny-by-default)

  Grants live **server-side** in `Mydia.Settings.PluginConfig`, never in the
  manifest. `install/2` activates a plugin only with the capabilities the admin
  approved; `revoke/1` clears them and deactivates. The runtime `Registry` holds
  only *active* (approved + enabled) descriptors — the set the dispatcher fans
  events to — while the DB holds every installed plugin for the admin UI.
  """

  require Logger

  alias Mydia.Plugins.Error
  alias Mydia.Plugins.Host
  alias Mydia.Plugins.HostFunctions
  alias Mydia.Plugins.Index
  alias Mydia.Plugins.Manifest
  alias Mydia.Plugins.Plugin
  alias Mydia.Plugins.Registry
  alias Mydia.Settings

  @doc "Lists all registered plugin descriptors."
  @spec list_plugins() :: [Plugin.t()]
  def list_plugins, do: Registry.list()

  @doc "Fetches a plugin descriptor by slug."
  @spec get_plugin(String.t()) :: {:ok, Plugin.t()} | {:error, Error.t()}
  def get_plugin(slug), do: Registry.lookup(slug)

  @doc "True when a plugin is registered under `slug`."
  @spec plugin_registered?(String.t()) :: boolean()
  def plugin_registered?(slug), do: Registry.registered?(slug)

  ## Event dispatch (U5)

  @doc """
  Returns the enabled plugins subscribed to `event_type`.

  A plugin subscribes by listing the event in its manifest `events:subscribe`
  capability; only enabled plugins are returned (deny-by-default).
  """
  @spec subscribers(String.t()) :: [Plugin.t()]
  def subscribers(event_type) when is_binary(event_type) do
    Registry.list()
    |> Enum.filter(fn %Plugin{} = p -> p.enabled and event_type in p.events end)
  end

  @doc """
  Invokes a plugin for an event, routing by the plugin's delivery mode.

  This is the dispatcher's default invoker. `:inline` plugins run their guest
  handler synchronously through `Mydia.Plugins.Host`. `:durable` plugins (the
  bundled notifier — U10) enqueue a durable Oban delivery job; that branch is
  wired in U10, so until then every plugin is dispatched inline.
  """
  @spec invoke_plugin(Plugin.t(), map()) :: {:ok, term()} | {:error, term()}
  def invoke_plugin(%Plugin{delivery: :durable} = plugin, event) do
    Mydia.Plugins.Notifier.Delivery.enqueue(plugin.slug, build_payload(event))
  end

  def invoke_plugin(%Plugin{} = plugin, event) do
    Host.call(plugin.slug, plugin.entrypoint, build_payload(event), force_fuel: true)
  end

  @doc """
  Builds the JSON-encodable payload handed to a guest for an event.

  Atoms (`actor_type`) are stringified so the boundary stays language-agnostic.
  """
  @spec build_payload(map()) :: map()
  def build_payload(event) do
    %{
      "event" => Map.get(event, :type),
      "category" => Map.get(event, :category),
      "severity" => to_string_or_nil(Map.get(event, :severity)),
      "actor_type" => to_string_or_nil(Map.get(event, :actor_type)),
      "actor_id" => Map.get(event, :actor_id),
      "resource_type" => Map.get(event, :resource_type),
      "resource_id" => Map.get(event, :resource_id),
      "metadata" => Map.get(event, :metadata) || %{}
    }
  end

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value), do: to_string(value)

  @doc """
  Fires a synthetic `event_type` at a single plugin for the admin Test button
  (U7, R10/R11).

  Calls `Host.call/4` directly (bypassing `invoke_plugin/2`'s delivery routing,
  so durable plugins like the bundled notifier run synchronously and surface
  immediately rather than via an Oban job) with `test_run: true`, so the markers
  and guest logs for the run are badged as a test. Runs in a supervised Task so
  the caller (LiveView) does not block. Returns `:ok` when the plugin is running,
  `{:error, :not_running}` otherwise.
  """
  @spec test_invoke(String.t(), String.t()) :: :ok | {:error, :not_running}
  def test_invoke(slug, event_type) when is_binary(slug) and is_binary(event_type) do
    case get_plugin(slug) do
      {:ok, %Plugin{} = plugin} ->
        payload = build_payload(synthetic_event(event_type))

        Task.Supervisor.start_child(Mydia.TaskSupervisor, fn ->
          Host.call(plugin.slug, plugin.entrypoint, payload, force_fuel: true, test_run: true)
        end)

        :ok

      _ ->
        {:error, :not_running}
    end
  end

  defp synthetic_event(event_type) do
    %{
      type: event_type,
      category: "media",
      severity: :info,
      actor_type: :system,
      actor_id: "plugin_test",
      resource_type: "media_item",
      resource_id: Ecto.UUID.generate(),
      metadata: %{
        "title" => "Test Movie",
        "media_type" => "movie",
        "year" => 2026,
        "test" => true
      }
    }
  end

  @doc """
  Rehydrates installed plugins into the runtime registry post-boot.

  Called from `Mydia.Application` after the supervision tree starts, mirroring
  `Mydia.Downloads.register_clients/0`. Loads every enabled `PluginConfig` that
  carries a verified artifact and activates it (registers the descriptor and
  starts its pool). Failures are logged and skipped so one bad plugin can't stop
  boot.
  """
  @spec register_plugins() :: :ok
  def register_plugins do
    # Seed the bundled notifier so it shows in the admin UI (pending approval).
    # Gated by the same flag the app uses for boot-time side effects, so the test
    # suite's app boot doesn't write to the shared DB (tests call ensure_bundled/0
    # explicitly when they need it).
    if Application.get_env(:mydia, :start_health_monitors, true), do: ensure_bundled()

    Settings.get_db_plugin_configs()
    |> Enum.filter(& &1.enabled)
    |> Enum.each(fn config ->
      case activate(config) do
        {:ok, _} ->
          :ok

        {:error, error} ->
          Logger.warning("could not activate plugin #{config.slug}: #{inspect(error)}")
      end
    end)
  end

  @doc """
  Ensures the bundled webhook notifier is installed (inactive, pending approval).

  Reads the shipped artifact + manifest from `priv/plugins/`, and if no plugin is
  installed under its slug, persists it disabled with no grants — the admin
  approves and configures it through the normal UI (R17: no new core surface).
  An already-installed row is left untouched so admin grants/settings survive.
  """
  @spec ensure_bundled() :: :ok
  def ensure_bundled do
    with {:ok, wasm} <- read_priv("webhook_notifier.wasm"),
         {:ok, manifest_json} <- read_priv("webhook_notifier.json"),
         {:ok, manifest} <- Manifest.parse(manifest_json),
         nil <- Settings.get_plugin_config_by_slug(manifest.slug) do
      hash = :crypto.hash(:sha256, wasm) |> Base.encode16(case: :lower)

      Settings.create_plugin_config(%{
        slug: manifest.slug,
        name: manifest.name,
        version: manifest.version,
        source_url: "bundled",
        integrity_hash: hash,
        manifest: manifest_to_map(manifest),
        wasm_module: wasm,
        granted_capabilities: %{},
        enabled: false,
        settings: %{"delivery" => "durable"}
      })

      :ok
    else
      %Settings.PluginConfig{} -> :ok
      {:error, reason} -> Logger.warning("could not seed bundled notifier: #{inspect(reason)}")
      _ -> :ok
    end
  end

  defp read_priv(file) do
    path = Application.app_dir(:mydia, Path.join("priv/plugins", file))
    File.read(path)
  end

  ## Install lifecycle (U8)

  @doc """
  Installs a plugin from a catalog `entry`, activating it with the approved
  capabilities.

  Fetches and integrity-verifies the package (U7), persists the verified
  artifact + manifest + **approved** grants server-side (U4), and — if any
  capability was granted — registers the descriptor and starts its pool.

  Approval is all-or-nothing in v1: `opts[:grants]` defaults to the manifest's
  full declared capability set. Passing `grants: %{}` installs the plugin
  **inactive** (deny-by-default) — nothing runs until `approve/2`. Extra `opts`
  (`:allow_private`, `:resolver`) are forwarded to the gate for tests.
  """
  @spec install(Index.Entry.t(), keyword()) :: {:ok, Plugin.t() | :inactive} | {:error, Error.t()}
  def install(%Index.Entry{} = entry, opts \\ []) do
    grants = Keyword.get(opts, :grants, entry.manifest.capabilities)

    with {:ok, %{wasm: wasm, hash: hash}} <- Index.fetch_package(entry, opts),
         {:ok, config} <- persist_install(entry, wasm, hash, grants) do
      finish_activation(config)
    end
  end

  @doc """
  Approves the full declared capability set for an already-installed plugin and
  activates it.

  Used by the install-then-approve flow (AE1) and by re-approval after a
  capability change — grants never auto-expand, so a manifest that newly requests
  more requires a fresh approval here.
  """
  @spec approve(String.t(), keyword()) :: {:ok, Plugin.t()} | {:error, Error.t()}
  def approve(slug, _opts \\ []) do
    with {:ok, config} <- fetch_config(slug),
         manifest when not is_nil(manifest) <- config.manifest,
         {:ok, config} <-
           Settings.update_plugin_config(config, %{
             granted_capabilities: manifest["capabilities"] || %{},
             enabled: true
           }) do
      activate_and_reload(config)
    else
      nil -> {:error, Error.new(:invalid_config, "plugin #{slug} has no stored manifest")}
      {:error, _} = err -> err
    end
  end

  @doc """
  Revokes all grants for `slug` and deactivates it.

  The plugin stays installed (its config and artifact remain) but inactive with
  no capabilities — re-approval is required to run it again (R8, R14).
  """
  @spec revoke(String.t()) :: {:ok, :revoked} | {:error, Error.t()}
  def revoke(slug) do
    with {:ok, config} <- fetch_config(slug),
         {:ok, _} <-
           Settings.update_plugin_config(config, %{granted_capabilities: %{}, enabled: false}) do
      deactivate(slug)
      reload()
      {:ok, :revoked}
    end
  end

  @doc "Removes a plugin entirely: deactivates it and deletes its config (R14)."
  @spec remove(String.t()) :: {:ok, :removed} | {:error, Error.t()}
  def remove(slug) do
    with {:ok, config} <- fetch_config(slug),
         {:ok, _} <- Settings.delete_plugin_config(config) do
      deactivate(slug)
      reload()
      {:ok, :removed}
    end
  end

  @doc "Enables or disables an installed plugin, starting/stopping its pool."
  @spec set_enabled(String.t(), boolean()) :: {:ok, Plugin.t() | :disabled} | {:error, Error.t()}
  def set_enabled(slug, true) do
    with {:ok, config} <- fetch_config(slug),
         {:ok, config} <- Settings.update_plugin_config(config, %{enabled: true}) do
      activate_and_reload(config)
    end
  end

  def set_enabled(slug, false) do
    with {:ok, config} <- fetch_config(slug),
         {:ok, _} <- Settings.update_plugin_config(config, %{enabled: false}) do
      deactivate(slug)
      reload()
      {:ok, :disabled}
    end
  end

  ## Update detection (U8, R14)

  @doc """
  Checks every configured source for newer versions of installed plugins and
  emits a `plugin.update_available` event per update found (surfaced in U9).

  Source fetch failures are logged and skipped. Returns the list of detected
  updates. Short-circuits (no fetch) when nothing is installed. `opts` are
  forwarded to the gate for tests.
  """
  @spec check_for_updates(keyword()) :: [map()]
  def check_for_updates(opts \\ []) do
    installed = Settings.get_db_plugin_configs()

    if installed == [] do
      []
    else
      entries = fetch_all_entries(opts)
      updates = detect_updates(installed, entries)
      Enum.each(updates, &emit_update_event/1)
      updates
    end
  end

  @doc """
  Pure comparison: returns `%{slug, current, latest}` for each installed config
  that a catalog `entry` offers in a newer version (R14, no false positives on
  equal versions).
  """
  @spec detect_updates([Settings.PluginConfig.t()], [Index.Entry.t()]) :: [map()]
  def detect_updates(installed, entries) do
    latest_by_slug =
      entries
      |> Enum.group_by(& &1.slug)
      |> Map.new(fn {slug, es} -> {slug, latest_version(es)} end)

    Enum.flat_map(installed, fn config ->
      latest = Map.get(latest_by_slug, config.slug)

      if latest && version_newer?(latest, config.version) do
        [%{slug: config.slug, current: config.version, latest: latest}]
      else
        []
      end
    end)
  end

  defp fetch_all_entries(opts) do
    (Keyword.get(opts, :sources) || Index.sources())
    |> Enum.flat_map(fn source ->
      case Index.fetch_catalog(source, opts) do
        {:ok, entries} ->
          entries

        {:error, error} ->
          Logger.warning("update check could not fetch #{source}: #{inspect(error)}")
          []
      end
    end)
  end

  defp latest_version(entries) do
    entries
    |> Enum.map(& &1.version)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort(&(not version_newer?(&2, &1)))
    |> List.first()
  end

  # True when `candidate` is a newer version than `current`. Uses semver when
  # both parse, falling back to string inequality.
  defp version_newer?(_candidate, nil), do: true

  defp version_newer?(candidate, current) do
    case {Version.parse(candidate), Version.parse(current)} do
      {{:ok, c}, {:ok, cur}} -> Version.compare(c, cur) == :gt
      _ -> candidate != current and candidate > current
    end
  end

  defp emit_update_event(%{slug: slug, current: current, latest: latest}) do
    Mydia.Events.create_event_async(%{
      category: "plugin",
      type: "plugin.update_available",
      actor_type: :system,
      actor_id: slug,
      metadata: %{"slug" => slug, "current_version" => current, "latest_version" => latest}
    })
  end

  # ── Internals ─────────────────────────────────────────────────────────────

  defp persist_install(entry, wasm, hash, grants) do
    Settings.upsert_plugin_config(%{
      slug: entry.slug,
      name: entry.name,
      version: entry.version,
      source_url: entry.package_url,
      integrity_hash: hash,
      manifest: manifest_to_map(entry.manifest),
      wasm_module: wasm,
      granted_capabilities: grants,
      enabled: grants != %{}
    })
  end

  # After install: activate when capabilities were granted, otherwise leave it
  # installed-but-inactive (deny-by-default).
  defp finish_activation(%{enabled: true} = config), do: activate_and_reload(config)

  defp finish_activation(%{enabled: false}) do
    reload()
    {:ok, :inactive}
  end

  defp activate_and_reload(config) do
    case activate(config) do
      {:ok, descriptor} ->
        reload()
        {:ok, descriptor}

      {:error, _} = err ->
        err
    end
  end

  # Builds the runtime descriptor from the persisted config + manifest and starts
  # its pool with the gated host-function imports.
  defp activate(config) do
    with manifest_map when not is_nil(manifest_map) <- config.manifest,
         wasm when is_binary(wasm) <- config.wasm_module,
         {:ok, manifest} <- Manifest.parse(manifest_map) do
      descriptor =
        Plugin.from_manifest(manifest,
          granted_capabilities: config.granted_capabilities || %{},
          enabled: true,
          source: :index,
          delivery: delivery_for(config)
        )

      with {:ok, _pid} <-
             Host.start_plugin(config.slug, wasm, imports: HostFunctions.imports_for(config.slug)) do
        Registry.register(config.slug, descriptor)
      end
    else
      nil ->
        {:error, Error.new(:invalid_config, "plugin #{config.slug} has no artifact to activate")}

      {:error, _} = err ->
        err
    end
  end

  defp deactivate(slug) do
    Host.stop_plugin(slug)
    Registry.unregister(slug)
    :ok
  end

  defp fetch_config(slug) do
    case Settings.get_plugin_config_by_slug(slug) do
      nil -> {:error, Error.new(:not_found, "no installed plugin for slug #{slug}")}
      config -> {:ok, config}
    end
  end

  defp delivery_for(config) do
    case config.settings do
      %{"delivery" => "durable"} -> :durable
      _ -> :inline
    end
  end

  defp manifest_to_map(%Manifest{} = m) do
    %{
      "slug" => m.slug,
      "name" => m.name,
      "version" => m.version,
      "description" => m.description,
      "author" => m.author,
      "entrypoint" => m.entrypoint,
      "capabilities" => m.capabilities
    }
  end

  defp reload do
    Mydia.Config.Loader.reload()
    :ok
  rescue
    e -> Logger.warning("plugin config reload failed: #{Exception.message(e)}")
  end
end
