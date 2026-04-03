defmodule MydiaWeb.AdminDownloadClientsLiveTest do
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
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/config/clients")
      assert path =~ "/auth"
    end
  end

  describe "Download Clients" do
    setup %{conn: conn, token: token} do
      start_supervised!(Mydia.Indexers.Health)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:guardian_default_token, token)
        |> put_req_header("authorization", "Bearer #{token}")

      {:ok, view, _html} = live(conn, ~p"/admin/config/clients")
      %{conn: conn, view: view}
    end

    test "displays empty state when no clients exist", %{conn: conn, token: token} do
      Mydia.Settings.list_download_client_configs()
      |> Enum.each(fn client_config ->
        unless is_binary(client_config.id) and String.starts_with?(client_config.id, "runtime::") do
          Mydia.Settings.delete_download_client_config(client_config)
        end
      end)

      Mydia.Downloads.Client.Registry.unregister(:transmission)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:guardian_default_token, token)
        |> put_req_header("authorization", "Bearer #{token}")

      {:ok, _view, html} = live(conn, ~p"/admin/config/clients")
      assert html =~ "Download Clients"
    end

    test "creates a new download client", %{view: view} do
      view
      |> element(~s{button[phx-click="new_download_client"]})
      |> render_click()

      view
      |> form("#download-client-form",
        download_client_config: %{
          name: "qBittorrent",
          type: "qbittorrent",
          host: "localhost",
          port: "8080",
          username: "admin",
          password: "password",
          enabled: "true",
          priority: "1"
        }
      )
      |> render_submit()

      html = render(view)
      assert html =~ "qBittorrent"
      refute has_element?(view, ~s{div[class*="modal-open"]})
    end
  end

  describe "Runtime Config Protection" do
    setup %{conn: conn, token: token} do
      start_supervised!(Mydia.Indexers.Health)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:guardian_default_token, token)
        |> put_req_header("authorization", "Bearer #{token}")

      %{conn: conn}
    end

    test "runtime_config?/1 identifies runtime configs correctly" do
      runtime_client = %Mydia.Settings.DownloadClientConfig{
        id: "runtime::download_client::Test Client"
      }

      assert Settings.runtime_config?(runtime_client) == true

      db_client = %Mydia.Settings.DownloadClientConfig{
        id: Ecto.UUID.generate()
      }

      assert Settings.runtime_config?(db_client) == false

      int_client = %Mydia.Settings.DownloadClientConfig{
        id: 123
      }

      assert Settings.runtime_config?(int_client) == false
    end

    test "template shows disabled buttons for runtime configs", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/config/clients")

      if html =~ "runtime::download_client" do
        assert html =~ "Cannot edit runtime-configured clients"
        assert html =~ "Cannot delete runtime-configured clients"
      end
    end

    test "template shows ENV badge for runtime configs", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/config/clients")

      if html =~ "runtime::download_client" do
        assert html =~ "ENV"
        assert html =~ "Configured via environment variables"
      end
    end
  end
end
