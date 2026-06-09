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
end
