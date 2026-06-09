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

  # A minimal, compilable guest implementing the handler ABI.
  @guest_wat """
  (module
    (memory (export "memory") 1)
    (data (i32.const 100) "{}")
    (func (export "mydia_alloc") (param $len i32) (result i32) (i32.const 1024))
    (func (export "handle") (param $ptr i32) (param $len i32) (result i64)
      (i64.or (i64.shl (i64.const 100) (i64.const 32)) (i64.const 2))))
  """

  defp guest_wasm do
    {:ok, bytes} = Wasmex.Wat.to_wasm(@guest_wat)
    bytes
  end

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

    on_exit(fn ->
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
