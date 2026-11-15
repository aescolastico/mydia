defmodule MydiaWeb.AdminFileNamingLiveTest do
  use MydiaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Mydia.Accounts
  alias Mydia.Settings
  alias Mydia.Settings.Naming
  alias Mydia.Settings.RuntimeConfig

  setup %{conn: conn} do
    original_config = Application.get_env(:mydia, :runtime_config)

    on_exit(fn ->
      if original_config,
        do: Application.put_env(:mydia, :runtime_config, original_config),
        else: Application.delete_env(:mydia, :runtime_config)
    end)

    unique = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.create_user(%{
        email: "naming_admin_#{unique}@example.com",
        username: "naming_admin_#{unique}",
        password_hash: "$2b$12$test",
        role: "admin"
      })

    {:ok, token, _claims} = Mydia.Auth.Guardian.encode_and_sign(user)

    conn =
      conn
      |> init_test_session(%{})
      |> put_session(:guardian_default_token, token)
      |> put_req_header("authorization", "Bearer #{token}")

    %{conn: conn, user: user}
  end

  test "shows previews and rejects templates that lose episode identity", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/file-naming")

    assert has_element?(view, "#file-naming-form")
    assert render(view) =~ "Casino Royale"

    params =
      RuntimeConfig.get_naming_config()
      |> Naming.params()
      |> Map.put("episode_file", "{{title}} - {{episode}}")

    html = render_change(view, "validate", %{"naming" => params})

    assert html =~ "must contain {{sxxeyy}}"
    assert has_element?(view, "#file-naming-form button[type='submit'][disabled]")
  end

  test "saves templates and applies them without a restart", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/admin/file-naming")

    params =
      RuntimeConfig.get_naming_config()
      |> Naming.params()
      |> Map.merge(%{
        "season_folders" => "false",
        "movie_file" => "{{title}} {tmdb-{{tmdb}}} {{quality}}{{release_group}}"
      })

    html = render_submit(view, "save", %{"naming" => params})

    assert html =~ "File naming settings saved"
    assert Settings.get_config_setting_by_key("naming.movie_file").updated_by_id == user.id
    assert RuntimeConfig.get_naming_config().season_folders == false
    assert RuntimeConfig.get_naming_config().movie_file == params["movie_file"]
  end
end
