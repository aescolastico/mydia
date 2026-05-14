defmodule MydiaWeb.AdminSettingsLiveTest do
  use MydiaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias Mydia.{Accounts, Settings}

  setup do
    unique_id = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.create_user(%{
        email: "admin_#{unique_id}@example.com",
        username: "admin_#{unique_id}",
        password_hash: "$2b$12$test",
        role: "admin"
      })

    {:ok, token, _claims} = Mydia.Auth.Guardian.encode_and_sign(user)

    %{user: user, token: token}
  end

  describe "Authentication" do
    test "redirects unauthenticated users", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/config/settings")
      assert path =~ "/auth"
    end
  end

  describe "General Settings" do
    setup %{conn: conn, token: token} do
      start_supervised!(Mydia.Indexers.Health)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:guardian_default_token, token)
        |> put_req_header("authorization", "Bearer #{token}")

      {:ok, view, _html} = live(conn, ~p"/admin/config/settings")
      %{conn: conn, view: view}
    end

    test "toggles authentication settings without :atom.cast/1 error", %{view: view} do
      html =
        view
        |> element("input[type='checkbox'][phx-value-key='auth.local_enabled']")
        |> render_click()

      assert html =~ "Setting updated successfully"
      assert has_element?(view, "div.bg-base-200.rounded-box")
    end

    test "toggles crash reporting setting without category validation error", %{
      view: view,
      user: user
    } do
      case Settings.get_config_setting_by_key("crash_reporting.enabled") do
        nil -> :ok
        existing -> Settings.delete_config_setting(existing)
      end

      html =
        view
        |> element("input[type='checkbox'][phx-value-key='crash_reporting.enabled']")
        |> render_click()

      refute html =~ "Category can&#39;t be blank",
             "Should not have 'Category can't be blank' error"

      refute html =~ "Category can't be blank", "Should not have 'Category can't be blank' error"

      assert html =~ "Setting updated successfully", "Should have success message"
      assert has_element?(view, ".alert-info", "Setting updated successfully")

      setting = Settings.get_config_setting_by_key("crash_reporting.enabled")
      assert setting != nil
      assert setting.category == :crash_reporting
      assert setting.updated_by_id == user.id
    end

    test "toggle persists a value the crash reporter recognises as enabled", %{conn: conn} do
      case Settings.get_config_setting_by_key("crash_reporting.enabled") do
        nil -> :ok
        existing -> Settings.delete_config_setting(existing)
      end

      {:ok, view, _html} = live(conn, ~p"/admin/config/settings")

      view
      |> element("input[type='checkbox'][phx-value-key='crash_reporting.enabled']")
      |> render_click()

      assert Mydia.CrashReporter.enabled?(),
             "expected toggle click to leave CrashReporter.enabled?/0 returning true"
    end

    test "self-heals legacy 'on' value written by older versions", %{conn: conn, user: user} do
      case Settings.get_config_setting_by_key("crash_reporting.enabled") do
        nil -> :ok
        existing -> Settings.delete_config_setting(existing)
      end

      {:ok, _} =
        Settings.create_config_setting(%{
          "key" => "crash_reporting.enabled",
          "value" => "on",
          "category" => "crash_reporting",
          "updated_by_id" => user.id
        })

      assert Mydia.CrashReporter.enabled?(),
             "legacy 'on' value should be interpreted as enabled"

      {:ok, fresh_view, _html} = live(conn, ~p"/admin/config/settings")

      assert has_element?(
               fresh_view,
               "input[type='checkbox'][phx-value-key='crash_reporting.enabled'][checked]"
             ),
             "toggle should render checked when DB holds the legacy 'on' value"
    end
  end
end
