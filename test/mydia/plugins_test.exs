defmodule Mydia.PluginsTest do
  # async: false — activation starts real pools under the app-wide PoolRegistry
  # and registers descriptors in the app-wide Plugins.Registry.
  use Mydia.DataCase, async: false

  alias Mydia.Plugins
  alias Mydia.Plugins.Host
  alias Mydia.Plugins.Index.Entry
  alias Mydia.Plugins.Manifest
  alias Mydia.Plugins.Registry
  alias Mydia.Settings

  # A prebuilt wasm32-wasip2 component implementing the mydia:plugin@1.0.0
  # contract. The host runs the component model, and WAT cannot express
  # components, so a core-wasm `(module ...)` fixture fails to instantiate
  # (surfaced as a :host_version "incompatible plugin contract" error). These
  # tests only exercise the install/activation lifecycle — none invoke the
  # guest — so any conforming component that instantiates works; reuse the
  # checked-in host_test fixture (see test/support/fixtures/plugins/).
  @guest_fixture Path.join([
                   __DIR__,
                   "..",
                   "support",
                   "fixtures",
                   "plugins",
                   "host_test_fixture.wasm"
                 ])

  defp guest_wasm, do: File.read!(@guest_fixture)

  defp manifest!(overrides \\ %{}) do
    base = %{
      "slug" => "webhook-notifier",
      "name" => "Webhook Notifier",
      "version" => "1.0.0",
      "capabilities" => %{
        "events:subscribe" => ["media_item.added"],
        "net:http" => ["discord.com"]
      }
    }

    {:ok, manifest} = Manifest.parse(Map.merge(base, overrides))
    manifest
  end

  defp entry(bypass, manifest, wasm) do
    %Entry{
      slug: manifest.slug,
      name: manifest.name,
      version: manifest.version,
      package_url: "http://allowed.test:#{bypass.port}/pkg.wasm",
      integrity: "sha256:#{:crypto.hash(:sha256, wasm) |> Base.encode16(case: :lower)}",
      manifest: manifest
    }
  end

  defp serve_package(bypass, wasm) do
    Bypass.stub(bypass, "GET", "/pkg.wasm", fn conn -> Plug.Conn.resp(conn, 200, wasm) end)
  end

  defp gate_opts, do: [allow_private: true, resolver: fn _ -> {:ok, [{127, 0, 0, 1}]} end]

  setup do
    Registry.clear()

    # Lifecycle functions call Plugins.reload/0, which replaces the global
    # :runtime_config with a snapshot computed from this test's sandboxed DB
    # and current env — restore it so the pollution doesn't outlive the test.
    # Delete (not put nil) when it was unset: readers rely on get_env's default.
    original_runtime = Application.get_env(:mydia, :runtime_config)

    on_exit(fn ->
      if original_runtime do
        Application.put_env(:mydia, :runtime_config, original_runtime)
      else
        Application.delete_env(:mydia, :runtime_config)
      end

      Enum.each(Registry.list(), &Host.stop_plugin(&1.slug))
      Registry.clear()
    end)

    {:ok, bypass: Bypass.open()}
  end

  describe "install/2 and approve/2 (AE1, R7, deny-by-default)" do
    test "installing without grants does not activate; approving then activates with exactly the declared grants",
         %{bypass: bypass} do
      wasm = guest_wasm()
      manifest = manifest!()
      serve_package(bypass, wasm)

      # Install without approving any capability.
      assert {:ok, :inactive} =
               Plugins.install(entry(bypass, manifest, wasm), [grants: %{}] ++ gate_opts())

      refute Registry.registered?("webhook-notifier")
      refute Host.running?("webhook-notifier")
      assert Settings.get_plugin_config_by_slug("webhook-notifier").enabled == false

      # Approve: grants the full declared set and activates.
      assert {:ok, descriptor} = Plugins.approve("webhook-notifier")
      assert descriptor.granted_capabilities == manifest.capabilities
      assert Registry.registered?("webhook-notifier")
      assert Host.running?("webhook-notifier")
    end

    test "installing with the default (full) approval activates immediately", %{bypass: bypass} do
      wasm = guest_wasm()
      manifest = manifest!()
      serve_package(bypass, wasm)

      assert {:ok, descriptor} = Plugins.install(entry(bypass, manifest, wasm), gate_opts())
      assert descriptor.enabled
      assert descriptor.granted_capabilities["net:http"] == ["discord.com"]
      assert Host.running?("webhook-notifier")
    end

    test "a tampered package is rejected before anything is persisted", %{bypass: bypass} do
      wasm = guest_wasm()
      manifest = manifest!()
      serve_package(bypass, wasm)
      bad = %{entry(bypass, manifest, wasm) | integrity: "sha256:deadbeef"}

      assert {:error, %{type: :integrity_mismatch}} = Plugins.install(bad, gate_opts())
      assert Settings.get_plugin_config_by_slug("webhook-notifier") == nil
    end
  end

  describe "revoke/1 and remove/1 (R8, R14)" do
    setup %{bypass: bypass} do
      wasm = guest_wasm()
      serve_package(bypass, wasm)
      {:ok, _} = Plugins.install(entry(bypass, manifest!(), wasm), gate_opts())
      :ok
    end

    test "revoke clears grants and deactivates, keeping the config" do
      assert Host.running?("webhook-notifier")
      assert {:ok, :revoked} = Plugins.revoke("webhook-notifier")

      refute Registry.registered?("webhook-notifier")
      refute Host.running?("webhook-notifier")

      config = Settings.get_plugin_config_by_slug("webhook-notifier")
      assert config.enabled == false
      assert config.granted_capabilities == %{}
    end

    test "remove deactivates and deletes the config" do
      assert {:ok, :removed} = Plugins.remove("webhook-notifier")
      refute Registry.registered?("webhook-notifier")
      refute Host.running?("webhook-notifier")
      assert Settings.get_plugin_config_by_slug("webhook-notifier") == nil
    end

    test "set_enabled toggles activation" do
      assert {:ok, :disabled} = Plugins.set_enabled("webhook-notifier", false)
      refute Host.running?("webhook-notifier")

      assert {:ok, _} = Plugins.set_enabled("webhook-notifier", true)
      assert Host.running?("webhook-notifier")
    end
  end

  describe "update_settings/2 host-granting recomputation (KTD1, R2)" do
    defp schema_manifest do
      manifest!(%{
        "settings_schema" => [
          %{"key" => "webhook_url", "type" => "url", "grants_host" => true},
          %{"key" => "backup_url", "type" => "url", "grants_host" => true}
        ]
      })
    end

    defp granted_hosts(slug) do
      Settings.get_plugin_config_by_slug(slug).granted_capabilities["net:http"]
    end

    setup %{bypass: bypass} do
      wasm = guest_wasm()
      serve_package(bypass, wasm)
      {:ok, _} = Plugins.install(entry(bypass, schema_manifest(), wasm), gate_opts())
      :ok
    end

    test "configuring a host-granting url adds its host to the effective grant" do
      assert {:ok, _} =
               Plugins.update_settings("webhook-notifier", %{
                 "webhook_url" => "https://ntfy.example.com/mydia"
               })

      hosts = granted_hosts("webhook-notifier")
      assert "ntfy.example.com" in hosts
      assert "discord.com" in hosts
    end

    test "changing the url drops the previous host (full replacement)" do
      {:ok, _} =
        Plugins.update_settings("webhook-notifier", %{"webhook_url" => "https://a.example.com/x"})

      {:ok, _} =
        Plugins.update_settings("webhook-notifier", %{"webhook_url" => "https://b.example.com/x"})

      hosts = granted_hosts("webhook-notifier")
      assert "b.example.com" in hosts
      refute "a.example.com" in hosts
    end

    test "blank or unparseable url derives no host and keeps static hosts" do
      {:ok, _} = Plugins.update_settings("webhook-notifier", %{"webhook_url" => ""})
      assert granted_hosts("webhook-notifier") == ["discord.com"]
    end

    test "multiple host-granting fields union their hosts" do
      {:ok, _} =
        Plugins.update_settings("webhook-notifier", %{
          "webhook_url" => "https://one.example.com/x",
          "backup_url" => "https://two.example.com/y"
        })

      hosts = granted_hosts("webhook-notifier")
      assert "one.example.com" in hosts
      assert "two.example.com" in hosts
    end

    test "the live registry descriptor reflects the new host without a pool restart" do
      assert Host.running?("webhook-notifier")

      {:ok, _} =
        Plugins.update_settings("webhook-notifier", %{
          "webhook_url" => "https://ntfy.example.com/mydia"
        })

      {:ok, descriptor} = Registry.lookup("webhook-notifier")
      assert "ntfy.example.com" in descriptor.granted_capabilities["net:http"]
      assert Host.running?("webhook-notifier")
    end
  end

  describe "update_settings/2 deny-by-default (R2, R3)" do
    test "does not grant net:http for an unapproved plugin", %{bypass: bypass} do
      wasm = guest_wasm()
      serve_package(bypass, wasm)

      {:ok, :inactive} =
        Plugins.install(entry(bypass, schema_manifest(), wasm), [grants: %{}] ++ gate_opts())

      {:ok, _} =
        Plugins.update_settings("webhook-notifier", %{
          "webhook_url" => "https://ntfy.example.com/mydia"
        })

      config = Settings.get_plugin_config_by_slug("webhook-notifier")
      assert config.settings["webhook_url"] == "https://ntfy.example.com/mydia"
      refute Map.has_key?(config.granted_capabilities, "net:http")
    end
  end

  describe "ensure_bundled/0 manifest reconciliation" do
    test "refreshes a stale stored manifest while leaving admin state untouched" do
      # A bundled row seeded before settings_schema was added to the JSON: its
      # stored manifest lacks the field, so the Settings UI can't render.
      {:ok, config} =
        Settings.create_plugin_config(%{
          slug: "webhook-notifier",
          name: "Webhook Notifier",
          version: "1.0.0",
          source_url: "bundled",
          enabled: true,
          granted_capabilities: %{"net:http" => ["discord.com"]},
          settings: %{"target" => "ntfy"},
          manifest: %{
            "slug" => "webhook-notifier",
            "name" => "Webhook Notifier",
            "version" => "1.0.0",
            "capabilities" => %{"net:http" => ["discord.com"]}
          }
        })

      refute get_in(config.manifest, ["settings_schema"])

      Plugins.ensure_bundled()

      refreshed = Settings.get_plugin_config_by_slug("webhook-notifier")
      schema = get_in(refreshed.manifest, ["settings_schema"])

      assert is_list(schema) and schema != []
      assert Enum.any?(schema, &(&1["key"] == "webhook_url" and &1["grants_host"] == true))

      # Admin state must survive a built-in upgrade.
      assert refreshed.enabled
      assert refreshed.granted_capabilities == %{"net:http" => ["discord.com"]}
      assert refreshed.settings == %{"target" => "ntfy"}
    end
  end

  describe "detect_updates/2 (R14)" do
    defp config(slug, version), do: %Mydia.Settings.PluginConfig{slug: slug, version: version}

    defp avail(slug, version) do
      %Entry{
        slug: slug,
        name: slug,
        version: version,
        package_url: "https://x/#{slug}.wasm",
        integrity: "sha256:ab",
        manifest: manifest!()
      }
    end

    test "flags a slug with a newer available version" do
      updates = Plugins.detect_updates([config("p", "1.0.0")], [avail("p", "1.2.0")])
      assert [%{slug: "p", current: "1.0.0", latest: "1.2.0"}] = updates
    end

    test "does not flag when versions match" do
      assert [] = Plugins.detect_updates([config("p", "1.0.0")], [avail("p", "1.0.0")])
    end

    test "does not flag when the available version is older" do
      assert [] = Plugins.detect_updates([config("p", "2.0.0")], [avail("p", "1.0.0")])
    end

    test "ignores slugs that are not installed" do
      assert [] = Plugins.detect_updates([config("p", "1.0.0")], [avail("other", "9.0.0")])
    end
  end
end
