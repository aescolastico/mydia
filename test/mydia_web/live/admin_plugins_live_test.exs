defmodule MydiaWeb.AdminPluginsLiveTest do
  # async: false — connected LiveView under the Postgres sandbox, and activation
  # starts pools under the app-wide PoolRegistry.
  use MydiaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Mydia.Accounts
  alias Mydia.Plugins.Host
  alias Mydia.Plugins.Registry
  alias Mydia.Settings

  # A prebuilt wasm32-wasip2 component (the host only accepts components, not
  # core-wasm modules) — see test/support/fixtures/plugins/host_test_fixture/.
  @guest_fixture Path.join([
                   __DIR__,
                   "..",
                   "..",
                   "support",
                   "fixtures",
                   "plugins",
                   "host_test_fixture.wasm"
                 ])

  defp guest_wasm, do: File.read!(@guest_fixture)

  defp manifest_map(slug, name) do
    %{
      "slug" => slug,
      "name" => name,
      "version" => "1.0.0",
      "capabilities" => %{
        "events:subscribe" => ["media_item.added"],
        "net:http" => ["discord.com"]
      }
    }
  end

  defp seed_plugin(slug, name, opts) do
    {:ok, config} =
      Settings.create_plugin_config(%{
        slug: slug,
        name: name,
        version: "1.0.0",
        manifest: manifest_map(slug, name),
        wasm_module: guest_wasm(),
        granted_capabilities: Keyword.get(opts, :granted, %{}),
        enabled: Keyword.get(opts, :enabled, false)
      })

    config
  end

  defp schema_manifest_map(slug, name) do
    Map.put(manifest_map(slug, name), "settings_schema", [
      %{
        "key" => "target",
        "type" => "enum",
        "label" => "Target service",
        "options" => ["discord", "ntfy"]
      },
      %{
        "key" => "webhook_url",
        "type" => "url",
        "label" => "Webhook / server URL",
        "grants_host" => true
      },
      %{"key" => "ntfy_token", "type" => "secret", "label" => "Access token"}
    ])
  end

  defp seed_with_schema(slug, name, opts) do
    {:ok, config} =
      Settings.create_plugin_config(%{
        slug: slug,
        name: name,
        version: "1.0.0",
        manifest: schema_manifest_map(slug, name),
        wasm_module: guest_wasm(),
        granted_capabilities:
          Keyword.get(opts, :granted, %{
            "net:http" => ["discord.com"],
            "events:subscribe" => ["media_item.added"]
          }),
        enabled: Keyword.get(opts, :enabled, true),
        settings: Keyword.get(opts, :settings, %{})
      })

    config
  end

  setup %{conn: conn} do
    unique = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.create_user(%{
        email: "admin_#{unique}@example.com",
        username: "admin_#{unique}",
        password_hash: "$2b$12$test",
        role: "admin"
      })

    {:ok, token, _} = Mydia.Auth.Guardian.encode_and_sign(user)

    # Approval/lifecycle events call Plugins.reload/0, which replaces the global
    # :runtime_config — restore it so the pollution doesn't outlive the test.
    original_runtime = Application.get_env(:mydia, :runtime_config)

    on_exit(fn ->
      Application.put_env(:mydia, :runtime_config, original_runtime)
      Enum.each(Registry.list(), &Host.stop_plugin(&1.slug))
      Registry.clear()
    end)

    conn =
      conn
      |> init_test_session(%{})
      |> put_session(:guardian_default_token, token)
      |> put_req_header("authorization", "Bearer #{token}")

    %{conn: conn}
  end

  test "redirects unauthenticated users", %{} do
    {:error, {:redirect, %{to: path}}} = live(build_conn(), ~p"/admin/config/plugins")
    assert path =~ "/auth"
  end

  test "renders an empty state when no plugins are installed", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/config/plugins")
    assert has_element?(view, "#plugins-installed")
    assert render(view) =~ "No plugins installed"
  end

  describe "capability approval (AE1, R7)" do
    test "a pending plugin shows the approval modal with capabilities and network destination, gated until approval",
         %{conn: conn} do
      seed_plugin("webhook-notifier", "Webhook Notifier", enabled: false)

      {:ok, view, _} = live(conn, ~p"/admin/config/plugins")

      # Pending plugin is inactive and offers a review/approve action.
      assert has_element?(view, "#plugin-row-webhook-notifier")
      assert has_element?(view, "#approve-webhook-notifier")
      refute has_element?(view, "#approval-modal")
      refute Host.running?("webhook-notifier")

      # Opening review shows the approval modal with the requested capabilities
      # and the network destination in plain language.
      view |> element("#approve-webhook-notifier") |> render_click()
      assert has_element?(view, "#approval-modal")
      assert has_element?(view, "#approval-capabilities")
      assert render(view) =~ "discord.com"
      assert has_element?(view, "#confirm-approval")

      # Approving activates the plugin.
      view |> element("#confirm-approval") |> render_click()
      refute has_element?(view, "#approval-modal")
      assert Host.running?("webhook-notifier")
      assert render(view) =~ "active"
    end

    test "declining closes the modal without activating", %{conn: conn} do
      seed_plugin("webhook-notifier", "Webhook Notifier", enabled: false)
      {:ok, view, _} = live(conn, ~p"/admin/config/plugins")

      view |> element("#approve-webhook-notifier") |> render_click()
      view |> element("#decline-approval") |> render_click()

      refute has_element?(view, "#approval-modal")
      refute Host.running?("webhook-notifier")
    end
  end

  describe "lifecycle (R14)" do
    test "remove deletes the plugin row", %{conn: conn} do
      seed_plugin("notifier", "Notifier",
        enabled: true,
        granted: %{"net:http" => ["discord.com"]}
      )

      {:ok, view, _} = live(conn, ~p"/admin/config/plugins")

      assert has_element?(view, "#plugin-row-notifier")
      view |> element("#remove-notifier") |> render_click()

      refute has_element?(view, "#plugin-row-notifier")
      assert Settings.get_plugin_config_by_slug("notifier") == nil
    end

    test "an update-available plugin shows the update badge", %{conn: conn} do
      seed_plugin("notifier", "Notifier",
        enabled: true,
        granted: %{"net:http" => ["discord.com"]}
      )

      {:ok, _} =
        Mydia.Events.create_event(%{
          category: "plugin",
          type: "plugin.update_available",
          actor_type: :system,
          actor_id: "notifier",
          metadata: %{"slug" => "notifier"}
        })

      {:ok, view, _} = live(conn, ~p"/admin/config/plugins")
      assert has_element?(view, "#update-badge-notifier")
    end
  end

  describe "operator settings + host disclosure (U3, U4)" do
    test "configuring a host-granting url grants its host (R5, R6)", %{conn: conn} do
      seed_with_schema("webhook-notifier", "Webhook Notifier", enabled: true)
      {:ok, view, _} = live(conn, ~p"/admin/config/plugins")

      assert has_element?(view, "#settings-webhook-notifier")
      view |> element("#settings-webhook-notifier") |> render_click()
      assert has_element?(view, "#plugin-settings-form")

      view
      |> form("#plugin-settings-form", %{
        "target" => "ntfy",
        "webhook_url" => "https://ntfy.example.com/mydia"
      })
      |> render_submit()

      refute has_element?(view, "#settings-modal")

      config = Settings.get_plugin_config_by_slug("webhook-notifier")
      assert config.settings["webhook_url"] == "https://ntfy.example.com/mydia"
      assert "ntfy.example.com" in config.granted_capabilities["net:http"]
    end

    test "rejects a scheme-less webhook_url instead of silently dropping the grant", %{conn: conn} do
      seed_with_schema("webhook-notifier", "Webhook Notifier", enabled: true)
      {:ok, view, _} = live(conn, ~p"/admin/config/plugins")
      view |> element("#settings-webhook-notifier") |> render_click()

      html =
        view
        |> form("#plugin-settings-form", %{
          "target" => "ntfy",
          "webhook_url" => "ntfy.example.com/mydia"
        })
        |> render_submit()

      # Modal stays open with an error; nothing is persisted.
      assert has_element?(view, "#settings-modal")
      assert html =~ "full URL"
      config = Settings.get_plugin_config_by_slug("webhook-notifier")
      refute Map.has_key?(config.settings, "webhook_url")
    end

    test "secret values are not echoed back into the form", %{conn: conn} do
      seed_with_schema("webhook-notifier", "Webhook Notifier",
        enabled: true,
        settings: %{"ntfy_token" => "tk_supersecret"}
      )

      {:ok, view, _} = live(conn, ~p"/admin/config/plugins")
      view |> element("#settings-webhook-notifier") |> render_click()

      refute render(view) =~ "tk_supersecret"
    end

    test "a blank secret on save preserves the stored value", %{conn: conn} do
      seed_with_schema("webhook-notifier", "Webhook Notifier",
        enabled: true,
        settings: %{"ntfy_token" => "tk_keep", "target" => "ntfy"}
      )

      {:ok, view, _} = live(conn, ~p"/admin/config/plugins")
      view |> element("#settings-webhook-notifier") |> render_click()

      view
      |> form("#plugin-settings-form", %{
        "webhook_url" => "https://ntfy.example.com/x",
        "ntfy_token" => ""
      })
      |> render_submit()

      config = Settings.get_plugin_config_by_slug("webhook-notifier")
      assert config.settings["ntfy_token"] == "tk_keep"
    end

    test "the approval modal discloses the host-granting field (U4)", %{conn: conn} do
      seed_with_schema("webhook-notifier", "Webhook Notifier", enabled: false, granted: %{})
      {:ok, view, _} = live(conn, ~p"/admin/config/plugins")

      view |> element("#approve-webhook-notifier") |> render_click()
      assert has_element?(view, "#approval-host-grant")
      assert render(view) =~ "Webhook / server URL"
    end

    test "a plugin without a settings schema shows a disabled Settings button with a reason",
         %{conn: conn} do
      seed_plugin("notifier", "Notifier",
        enabled: true,
        granted: %{"net:http" => ["discord.com"]}
      )

      {:ok, view, _} = live(conn, ~p"/admin/config/plugins")
      assert has_element?(view, "#plugin-row-notifier")
      # The button is always present (never silently hidden) but disabled here.
      assert has_element?(view, "#settings-notifier[disabled]")
      assert render(view) =~ "no configurable settings"
    end
  end

  describe "provenance (AE6)" do
    test "an env-sourced plugin renders read-only with a source badge", %{conn: conn} do
      original = Application.get_env(:mydia, :runtime_config)

      install = %Mydia.Config.Schema.PluginInstall{
        slug: "envp",
        name: "Env Plugin",
        version: "1.0.0",
        enabled: true,
        granted_capabilities: %{"events:subscribe" => ["media_item.added"]}
      }

      Application.put_env(:mydia, :runtime_config, %{original | plugin_installs: [install]})
      on_exit(fn -> Application.put_env(:mydia, :runtime_config, original) end)

      {:ok, view, _} = live(conn, ~p"/admin/config/plugins")

      assert has_element?(view, "#plugin-row-envp")
      assert render(view) =~ "configured via env"
      # Read-only: no lifecycle controls for an env-sourced row.
      refute has_element?(view, "#remove-envp")
      refute has_element?(view, "#toggle-envp")
    end
  end

  describe "debug logs and test trigger (U6, U7)" do
    alias Mydia.Plugins.Logs

    defp seed_enabled_notifier do
      seed_plugin("notifier", "Notifier",
        enabled: true,
        granted: %{"events:subscribe" => ["media_item.added"]}
      )
    end

    defp log!(attrs) do
      {:ok, log} =
        Logs.create(
          Map.merge(
            %{slug: "notifier", invocation_id: "inv", source: :guest, level: :info, message: "m"},
            attrs
          )
        )

      log
    end

    test "the detail modal renders the activity log with existing rows", %{conn: conn} do
      seed_enabled_notifier()
      log!(%{message: "posting to webhook"})

      {:ok, view, _} = live(conn, ~p"/admin/config/plugins")
      view |> element("#details-notifier") |> render_click()

      assert has_element?(view, "#plugin-logs")
      assert render(view) =~ "posting to webhook"
    end

    test "the level filter re-queries the timeline", %{conn: conn} do
      seed_enabled_notifier()
      log!(%{level: :debug, message: "debug noise"})
      log!(%{source: :host, level: :error, message: "boom trap"})

      {:ok, view, _} = live(conn, ~p"/admin/config/plugins")
      view |> element("#details-notifier") |> render_click()
      assert render(view) =~ "debug noise"

      html = view |> form("#log-filter-form") |> render_change(%{"level" => "error"})
      refute html =~ "debug noise"
      assert html =~ "boom trap"
    end

    test "a broadcast log line appends to the open timeline live", %{conn: conn} do
      seed_enabled_notifier()
      {:ok, view, _} = live(conn, ~p"/admin/config/plugins")
      view |> element("#details-notifier") |> render_click()

      log!(%{invocation_id: "live", message: "live tail line"})

      assert render(view) =~ "live tail line"
    end

    test "the Test control renders for an enabled plugin with subscribed events", %{conn: conn} do
      seed_enabled_notifier()
      {:ok, view, _} = live(conn, ~p"/admin/config/plugins")
      view |> element("#details-notifier") |> render_click()

      assert has_element?(view, "#test-plugin")
    end
  end
end
