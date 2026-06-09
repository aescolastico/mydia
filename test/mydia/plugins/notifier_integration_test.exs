defmodule Mydia.Plugins.NotifierIntegrationTest do
  # async: false — installs/activates the real bundled notifier under the
  # app-wide registries.
  use Mydia.DataCase, async: false

  alias Mydia.Plugins
  alias Mydia.Plugins.Host
  alias Mydia.Plugins.Registry
  alias Mydia.Settings

  @slug "webhook-notifier"

  setup do
    Registry.clear()

    on_exit(fn ->
      Host.stop_plugin(@slug)
      Registry.clear()
    end)

    :ok
  end

  test "R17: the bundled notifier installs and runs through the generic plugin plumbing (no new core surface)" do
    # Seeded from priv/plugins, pending approval — the same path any plugin takes,
    # with no notifier-specific route or LiveView.
    assert :ok = Plugins.ensure_bundled()

    config = Settings.get_plugin_config_by_slug(@slug)
    assert config.enabled == false
    assert config.granted_capabilities == %{}
    assert config.settings["delivery"] == "durable"
    assert config.manifest["capabilities"]["net:http"] == ["discord.com"]
    # No bytes are copied into the DB — they resolve from the filesystem.
    assert config.wasm_module == nil
    assert config.integrity_hash == nil
    refute Host.running?(@slug)

    # Approving via the generic lifecycle activates it as a durable plugin, so
    # the dispatcher routes its events through the Oban delivery worker (U10).
    assert {:ok, descriptor} = Plugins.approve(@slug)
    assert descriptor.delivery == :durable
    assert descriptor.events == ["media_item.added", "download.completed"]
    assert Host.running?(@slug)
  end

  test "ensure_bundled does not clobber an already-installed notifier" do
    {:ok, _} =
      Settings.create_plugin_config(%{
        slug: @slug,
        name: "Webhook Notifier",
        version: "0.9.0",
        granted_capabilities: %{"net:http" => ["discord.com"]},
        settings: %{"webhook_url" => "https://discord.com/api/webhooks/x"}
      })

    assert :ok = Plugins.ensure_bundled()

    # The admin's existing grants/settings/version survive.
    config = Settings.get_plugin_config_by_slug(@slug)
    assert config.version == "0.9.0"
    assert config.settings["webhook_url"] == "https://discord.com/api/webhooks/x"
  end

  test "ensure_bundled reconciles stale DB bytes on a pre-existing bundled row" do
    # Simulate an install that ran the old copy-into-DB seeding: a bundled row
    # carrying wasm bytes + an integrity hash in the DB.
    {:ok, _} =
      Settings.create_plugin_config(%{
        slug: @slug,
        name: "Webhook Notifier",
        version: "1.0.0",
        source_url: "bundled",
        wasm_module: "STALE-BYTES",
        integrity_hash: "deadbeef",
        granted_capabilities: %{"net:http" => ["discord.com"]},
        enabled: true,
        settings: %{"delivery" => "durable"}
      })

    assert :ok = Plugins.ensure_bundled()

    config = Settings.get_plugin_config_by_slug(@slug)
    # Stale bytes nulled so the resolver falls through to the filesystem.
    assert config.wasm_module == nil
    assert config.integrity_hash == nil
    # Admin state is preserved.
    assert config.granted_capabilities == %{"net:http" => ["discord.com"]}
    assert config.enabled == true
    assert config.settings["delivery"] == "durable"
  end

  test "ensure_bundled never clobbers a non-bundled (index) plugin's DB bytes" do
    {:ok, _} =
      Settings.create_plugin_config(%{
        slug: "an-index-plugin",
        name: "An Index Plugin",
        version: "1.0.0",
        source_url: "https://plugins.example.com/an-index-plugin.wasm",
        wasm_module: "INDEX-BYTES",
        integrity_hash: "abc123",
        enabled: true
      })

    assert :ok = Plugins.ensure_bundled()

    config = Settings.get_plugin_config_by_slug("an-index-plugin")
    # Reconcile only touches source_url == "bundled" rows.
    assert config.wasm_module == "INDEX-BYTES"
    assert config.integrity_hash == "abc123"
  end
end
