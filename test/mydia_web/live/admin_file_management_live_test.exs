defmodule MydiaWeb.AdminFileManagementLiveTest do
  use MydiaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias Mydia.{Accounts, Settings}

  setup do
    # The "save" flow calls Mydia.Config.Loader.reload/0, which mutates the
    # global :runtime_config application env. Snapshot and restore it so this
    # test does not leak naming config into other (sync) tests.
    original_config = Application.get_env(:mydia, :runtime_config)

    on_exit(fn ->
      if original_config do
        Application.put_env(:mydia, :runtime_config, original_config)
      else
        Application.delete_env(:mydia, :runtime_config)
      end
    end)

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

  defp authed_conn(conn, token) do
    conn
    |> init_test_session(%{})
    |> put_session(:guardian_default_token, token)
    |> put_req_header("authorization", "Bearer #{token}")
  end

  describe "Authentication" do
    test "redirects unauthenticated users", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/config/file-management")
      assert path =~ "/auth"
    end
  end

  describe "File management settings" do
    setup %{conn: conn, token: token} do
      {:ok, view, _html} = live(authed_conn(conn, token), ~p"/admin/config/file-management")
      %{view: view}
    end

    test "renders the form with defaults", %{view: view} do
      assert has_element?(view, "#file-management-form")
      assert has_element?(view, "input[name='naming[movie_file]']")
      assert has_element?(view, "input[name='naming[episode_file]']")
    end

    test "shows a live preview as templates change", %{view: view} do
      html =
        view
        |> element("#file-management-form")
        |> render_change(%{
          "naming" => %{
            "movie_folder" => "{{title}} ({{year}})",
            "tv_folder" => "{{title}}",
            "season_folder" => "Season {{season}}",
            "movie_file" => "{{title}}",
            "episode_file" => "{{title}}",
            "season_folders" => "true"
          }
        })

      assert html =~ "Casino Royale (2006)"
      assert html =~ "The Office (US)"
    end

    test "flags unknown tokens and blocks save", %{view: view} do
      html =
        view
        |> element("#file-management-form")
        |> render_change(%{
          "naming" => %{
            "movie_folder" => "{{title}} ({{year}})",
            "tv_folder" => "{{title}}",
            "season_folder" => "Season {{season}}",
            "movie_file" => "{{title}} {{bogus}}",
            "episode_file" => "{{title}}",
            "season_folders" => "true"
          }
        })

      assert html =~ "Unknown token"
      assert has_element?(view, "button[type='submit'][disabled]")
    end

    test "saves valid templates and persists config settings", %{view: view} do
      view
      |> form("#file-management-form", %{
        "naming" => %{
          "movie_folder" => "{{title}} [{{year}}]",
          "tv_folder" => "{{title}}",
          "season_folder" => "Season {{season}}",
          "movie_file" => "{{title}} ({{year}})",
          "episode_file" => "{{title}} - {{sxxeyy}}",
          "season_folders" => "false"
        }
      })
      |> render_submit()

      assert Settings.get_config_setting_by_key("naming.movie_folder").value ==
               "{{title}} [{{year}}]"

      assert Settings.get_config_setting_by_key("naming.season_folders").value == "false"
    end

    test "keeps season folder template in the DOM when subfolders are disabled", %{view: view} do
      html =
        view
        |> element("#file-management-form")
        |> render_change(%{
          "naming" => %{
            "movie_folder" => "{{title}} ({{year}})",
            "tv_folder" => "{{title}}",
            "season_folder" => "Season {{season}}",
            "movie_file" => "{{title}}",
            "episode_file" => "{{title}}",
            "season_folders" => "false"
          }
        })

      # The input must stay in the DOM (hidden) so its value is still submitted;
      # otherwise the required `season_folder` is saved blank and reload fails.
      assert html =~ ~s(name="naming[season_folder]")
      assert has_element?(view, "input[name='naming[season_folder]']")
    end

    test "blocks saving a blank required template", %{view: view} do
      html =
        view
        |> element("#file-management-form")
        |> render_change(%{
          "naming" => %{
            "movie_folder" => "",
            "tv_folder" => "{{title}}",
            "season_folder" => "Season {{season}}",
            "movie_file" => "{{title}}",
            "episode_file" => "{{title}}",
            "season_folders" => "true"
          }
        })

      assert html =~ "can&#39;t be blank"
      assert has_element?(view, "button[type=submit][disabled]")
    end
  end
end
