defmodule MydiaWeb.AdminIndexersLiveTest do
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
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/config/indexers")
      assert path =~ "/auth"
    end
  end

  describe "Indexers" do
    setup %{conn: conn, token: token} do
      start_supervised!(Mydia.Indexers.Health)
      # Ensure real adapters are registered — other async:false test modules (e.g.
      # RegistryTest) call Registry.clear() in their setup and may leave the registry
      # empty or populated with test-only adapters.
      Mydia.Indexers.register_adapters()

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:guardian_default_token, token)
        |> put_req_header("authorization", "Bearer #{token}")

      {:ok, view, _html} = live(conn, ~p"/admin/config/indexers")
      %{conn: conn, view: view}
    end

    test "displays empty state when no indexers exist", %{conn: conn, token: token} do
      Mydia.Settings.list_indexer_configs()
      |> Enum.each(fn indexer_config ->
        unless is_binary(indexer_config.id) and
                 String.starts_with?(indexer_config.id, "runtime::") do
          Mydia.Settings.delete_indexer_config(indexer_config)
        end
      end)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:guardian_default_token, token)
        |> put_req_header("authorization", "Bearer #{token}")

      {:ok, _view, html} = live(conn, ~p"/admin/config/indexers")
      assert html =~ "Indexers"
    end

    test "creates a new indexer", %{view: view} do
      view
      |> element(~s{button[phx-click="new_indexer"]})
      |> render_click()

      view
      |> form("#indexer-form",
        indexer_config: %{
          name: "Prowlarr",
          type: "prowlarr",
          base_url: "http://localhost:9696",
          api_key: "test-api-key",
          enabled: "true",
          priority: "1"
        }
      )
      |> render_submit()

      html = render(view)
      assert html =~ "Prowlarr"
      refute has_element?(view, ~s{div[class*="modal-open"]})
    end

    @tag :skip
    test "test connection succeeds with valid prowlarr server", %{view: view} do
      bypass = Bypass.open()
      Mydia.IndexerMock.mock_prowlarr_status(bypass, version: "1.25.0")

      base_url = "http://127.0.0.1:#{bypass.port}"

      assert {:ok, %{version: "1.25.0"}} =
               Mydia.Indexers.test_connection(%{
                 type: :prowlarr,
                 base_url: base_url,
                 api_key: "test-api-key"
               })

      view
      |> element(~s{button[phx-click="new_indexer"]})
      |> render_click()

      view
      |> form("#indexer-form",
        indexer_config: %{
          name: "Test Prowlarr",
          type: "prowlarr",
          base_url: base_url,
          api_key: "test-api-key",
          enabled: "true",
          priority: "1"
        }
      )
      |> render_change()

      html =
        view
        |> element(~s{button[phx-click="test_indexer_connection"]})
        |> render_click()

      if html =~ "Connection failed" do
        error_snippet =
          case Regex.run(~r/Connection failed[^<"]*/, html) do
            [match] -> match
            _ -> "Could not extract error message"
          end

        flunk("Expected 'Connection successful' but got: #{error_snippet}")
      end

      assert html =~ "Connection successful",
             "Expected a flash message with 'Connection successful' but found neither " <>
               "'Connection successful' nor 'Connection failed' in the response"
    end

    @tag :skip
    test "test connection shows error for invalid prowlarr server", %{view: view} do
      bypass = Bypass.open()

      Bypass.stub(bypass, "GET", "/api/v1/system/status", fn conn ->
        Plug.Conn.resp(conn, 401, "Unauthorized")
      end)

      view
      |> element(~s{button[phx-click="new_indexer"]})
      |> render_click()

      view
      |> form("#indexer-form",
        indexer_config: %{
          name: "Invalid Prowlarr",
          type: "prowlarr",
          base_url: "http://127.0.0.1:#{bypass.port}",
          api_key: "bad-api-key",
          enabled: "true",
          priority: "1"
        }
      )
      |> render_change()

      html =
        view
        |> element(~s{button[phx-click="test_indexer_connection"]})
        |> render_click()

      assert html =~ "Connection failed",
             "Expected flash 'Connection failed' after test connection. " <>
               "HTML snippet: #{String.slice(html, 0..500)}"
    end
  end

  describe "Runtime Config Protection" do
    setup %{conn: conn, token: token} do
      start_supervised!(Mydia.Indexers.Health)
      Mydia.Indexers.register_adapters()

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:guardian_default_token, token)
        |> put_req_header("authorization", "Bearer #{token}")

      %{conn: conn}
    end

    test "runtime_config?/1 works with indexer configs" do
      runtime_indexer = %Mydia.Settings.IndexerConfig{
        id: "runtime::indexer::Test Indexer"
      }

      assert Settings.runtime_config?(runtime_indexer) == true

      db_indexer = %Mydia.Settings.IndexerConfig{
        id: Ecto.UUID.generate()
      }

      assert Settings.runtime_config?(db_indexer) == false
    end
  end

  describe "FlareSolverr panel" do
    setup %{conn: conn, token: token} do
      start_supervised!(Mydia.Indexers.Health)
      Mydia.Indexers.register_adapters()

      System.delete_env("FLARESOLVERR_URL")
      System.delete_env("FLARESOLVERR_ENABLED")
      on_exit(fn -> System.delete_env("FLARESOLVERR_URL") end)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:guardian_default_token, token)
        |> put_req_header("authorization", "Bearer #{token}")

      %{conn: conn}
    end

    test "renders the FlareSolverr row, always visible when unconfigured", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/config/indexers")

      assert has_element?(view, "#flaresolverr-panel")
      assert render(view) =~ "FlareSolverr"
      assert render(view) =~ "not configured"
      assert has_element?(view, ~s{button[phx-click="edit_flaresolverr"]})
    end

    test "env-sourced config shows an ENV badge on the row", %{conn: conn} do
      System.put_env("FLARESOLVERR_URL", "http://env-flaresolverr:8191")

      {:ok, view, _html} = live(conn, ~p"/admin/config/indexers")

      assert render(element(view, "#flaresolverr-panel")) =~ "ENV"
    end

    test "Edit opens a modal form with the four config fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/config/indexers")

      view
      |> element(~s{button[phx-click="edit_flaresolverr"]})
      |> render_click()

      assert has_element?(view, "#flaresolverr-form")
      assert has_element?(view, ~s{#flaresolverr-form input[name="flaresolverr[url]"]})
      assert has_element?(view, ~s{#flaresolverr-form input[name="flaresolverr[timeout]"]})
    end

    test "saving the modal form upserts the settings", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/config/indexers")

      view |> element(~s{button[phx-click="edit_flaresolverr"]}) |> render_click()

      view
      |> form("#flaresolverr-form",
        flaresolverr: %{
          enabled: "true",
          url: "http://flaresolverr:8191",
          timeout: "60000",
          max_timeout: "120000"
        }
      )
      |> render_submit()

      url = Settings.get_config_setting_by_key("flaresolverr.url")
      assert url.value == "http://flaresolverr:8191"
      assert url.category == :flaresolverr
      assert Settings.get_config_setting_by_key("flaresolverr.timeout").value == "60000"
      refute has_element?(view, "#flaresolverr-form")
    end

    test "invalid timeout shows a validation error and writes no setting", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/config/indexers")

      view |> element(~s{button[phx-click="edit_flaresolverr"]}) |> render_click()

      html =
        view
        |> form("#flaresolverr-form",
          flaresolverr: %{enabled: "false", url: "", timeout: "0", max_timeout: "120000"}
        )
        |> render_submit()

      assert html =~ "must be greater than 0"
      assert is_nil(Settings.get_config_setting_by_key("flaresolverr.timeout"))
      assert has_element?(view, "#flaresolverr-form")
    end

    test "Test Connection from the row is handled without crashing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/config/indexers")

      view
      |> element(~s{button[phx-click="test_flaresolverr"]})
      |> render_click()

      assert has_element?(view, "#flaresolverr-panel")
    end
  end
end
