defmodule MydiaWeb.AdminPluginsLiveTest do
  # async: false — connected LiveView under the Postgres sandbox, and activation
  # starts pools under the app-wide PoolRegistry.
  use MydiaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Mydia.Accounts
  alias Mydia.Plugins.Host
  alias Mydia.Plugins.Registry
  alias Mydia.Settings

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

    on_exit(fn ->
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
end
