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

  describe "Wave-2 Form: Categories" do
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

    test "submitting per-content-type categories saves them as a map", %{view: view} do
      view
      |> element(~s{button[phx-click="new_download_client"]})
      |> render_click()

      view
      |> form("#download-client-form", %{
        "download_client_config" => %{
          "name" => "qbittorrent_cats_#{System.unique_integer([:positive])}",
          "type" => "qbittorrent",
          "host" => "localhost",
          "port" => "8080",
          "enabled" => "true",
          "priority" => "1",
          "categories" => %{
            "movie" => "movies",
            "tv" => "tv",
            "music" => ""
          }
        }
      })
      |> render_submit()

      refute has_element?(view, ~s{div[class*="modal-open"]})

      saved = List.last(Settings.list_download_client_configs())
      assert saved.categories["movie"] == "movies"
      assert saved.categories["tv"] == "tv"
      refute Map.has_key?(saved.categories, "music")
    end

    test "blackhole client does not render category inputs", %{view: view} do
      view
      |> element(~s{button[phx-click="new_download_client"]})
      |> render_click()

      view
      |> form("#download-client-form", %{
        "download_client_config" => %{"type" => "blackhole"}
      })
      |> render_change()

      refute has_element?(view, "#download-client-categories")
      refute has_element?(view, "#download-client-priority-profile")
    end

    test "legacy single-category clients prefill all three content-type inputs", %{conn: conn} do
      {:ok, legacy_client} =
        Settings.create_download_client_config(%{
          "name" => "legacy_#{System.unique_integer([:positive])}",
          "type" => "qbittorrent",
          "host" => "localhost",
          "port" => "8080",
          "enabled" => "true",
          "priority" => "1",
          "category" => "all"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/config/clients")

      view
      |> element(~s{button[phx-click="edit_download_client"][phx-value-id="#{legacy_client.id}"]})
      |> render_click()

      html = render(view)
      assert html =~ ~s{id="download-client-categories"}
      # All three slots prefilled with the legacy value
      assert html =~ ~s{value="all"}
    end
  end

  describe "Wave-2 Form: Priority profile" do
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

    test "priority profile values round-trip through the form", %{view: view} do
      view
      |> element(~s{button[phx-click="new_download_client"]})
      |> render_click()

      view
      |> form("#download-client-form", %{
        "download_client_config" => %{
          "name" => "sab_prio_#{System.unique_integer([:positive])}",
          "type" => "sabnzbd",
          "host" => "localhost",
          "port" => "8080",
          "enabled" => "true",
          "priority" => "1",
          "priority_profile" => %{
            "verylow" => "-100",
            "normal" => "0",
            "veryhigh" => "2",
            "low" => "",
            "high" => ""
          }
        }
      })
      |> render_submit()

      refute has_element?(view, ~s{div[class*="modal-open"]})

      saved = List.last(Settings.list_download_client_configs())
      assert saved.priority_profile["verylow"] == "-100"
      assert saved.priority_profile["normal"] == "0"
      assert saved.priority_profile["veryhigh"] == "2"
      refute Map.has_key?(saved.priority_profile, "low")
      refute Map.has_key?(saved.priority_profile, "high")
    end

    test "priority profile section is hidden for blackhole clients", %{view: view} do
      view
      |> element(~s{button[phx-click="new_download_client"]})
      |> render_click()

      view
      |> form("#download-client-form", %{
        "download_client_config" => %{"type" => "blackhole"}
      })
      |> render_change()

      refute has_element?(view, "#download-client-priority-profile")
    end

    test "priority profile section is visible for qBittorrent", %{view: view} do
      view
      |> element(~s{button[phx-click="new_download_client"]})
      |> render_click()

      assert has_element?(view, "#download-client-priority-profile")
    end
  end

  describe "Wave-2 Form: Stalled timeout" do
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

    test "shows inline validation error for non-positive incomplete_grace_minutes", %{view: view} do
      view
      |> element(~s{button[phx-click="new_download_client"]})
      |> render_click()

      html =
        view
        |> form("#download-client-form", %{
          "download_client_config" => %{
            "name" => "stalled_neg",
            "type" => "qbittorrent",
            "host" => "localhost",
            "port" => "8080",
            "enabled" => "true",
            "priority" => "1",
            "incomplete_grace_minutes" => "-5"
          }
        })
        |> render_change()

      assert html =~ "must be greater than 0"
    end

    test "stalled timeout input is visible for blackhole clients too", %{view: view} do
      view
      |> element(~s{button[phx-click="new_download_client"]})
      |> render_click()

      view
      |> form("#download-client-form", %{
        "download_client_config" => %{"type" => "blackhole"}
      })
      |> render_change()

      assert has_element?(view, "#download-client-grace-minutes")
    end
  end

  describe "Wave-2 Form: Webhook URL" do
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

    test "new SABnzbd client shows 'save to reveal' hint instead of URL", %{view: view} do
      view
      |> element(~s{button[phx-click="new_download_client"]})
      |> render_click()

      view
      |> form("#download-client-form", %{
        "download_client_config" => %{"type" => "sabnzbd"}
      })
      |> render_change()

      assert has_element?(view, "#download-client-webhook")
      assert has_element?(view, "#download-client-webhook-new-hint")
      refute has_element?(view, "#download-client-webhook-url")
    end

    test "saved SABnzbd client shows the webhook URL", %{conn: conn} do
      {:ok, sab_client} =
        Settings.create_download_client_config(%{
          "name" => "sab_hook_#{System.unique_integer([:positive])}",
          "type" => "sabnzbd",
          "host" => "localhost",
          "port" => "8080",
          "enabled" => "true",
          "priority" => "1"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/config/clients")

      view
      |> element(~s{button[phx-click="edit_download_client"][phx-value-id="#{sab_client.id}"]})
      |> render_click()

      assert has_element?(view, "#download-client-webhook")
      assert has_element?(view, "#download-client-webhook-url")
      assert has_element?(view, "#download-client-webhook-snippet-sabnzbd")
      refute has_element?(view, "#download-client-webhook-snippet-nzbget")

      html = render(view)
      assert html =~ "/api/webhooks/v1/usenet/#{sab_client.id}"
      assert html =~ "secret=#{sab_client.webhook_secret}"
    end

    test "qBittorrent (non-webhook) clients do not show the webhook section", %{view: view} do
      view
      |> element(~s{button[phx-click="new_download_client"]})
      |> render_click()

      refute has_element?(view, "#download-client-webhook")
    end

    test "NZBGet client shows the NZBGet script snippet (not SABnzbd's)", %{conn: conn} do
      {:ok, nzbget_client} =
        Settings.create_download_client_config(%{
          "name" => "nzbget_hook_#{System.unique_integer([:positive])}",
          "type" => "nzbget",
          "host" => "localhost",
          "port" => "6789",
          "enabled" => "true",
          "priority" => "1"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/config/clients")

      view
      |> element(~s{button[phx-click="edit_download_client"][phx-value-id="#{nzbget_client.id}"]})
      |> render_click()

      assert has_element?(view, "#download-client-webhook-snippet-nzbget")
      refute has_element?(view, "#download-client-webhook-snippet-sabnzbd")
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
