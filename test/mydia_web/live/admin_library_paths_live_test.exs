defmodule MydiaWeb.AdminLibraryPathsLiveTest do
  use MydiaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias Mydia.Accounts

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
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/config/library-paths")
      assert path =~ "/auth"
    end
  end

  describe "Library Paths" do
    setup %{conn: conn, token: token} do
      start_supervised!(Mydia.Indexers.Health)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:guardian_default_token, token)
        |> put_req_header("authorization", "Bearer #{token}")

      {:ok, view, _html} = live(conn, ~p"/admin/config/library-paths")
      %{conn: conn, view: view}
    end

    test "displays empty state when no paths exist", %{conn: conn, token: token} do
      Mydia.Settings.list_library_paths()
      |> Enum.each(fn library_path ->
        unless is_binary(library_path.id) and String.starts_with?(library_path.id, "runtime::") do
          Mydia.Settings.delete_library_path(library_path)
        end
      end)

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:guardian_default_token, token)
        |> put_req_header("authorization", "Bearer #{token}")

      {:ok, _view, html} = live(conn, ~p"/admin/config/library-paths")
      assert html =~ "Library Paths"
    end

    test "creates a new library path", %{view: view} do
      test_dir =
        Path.join(System.tmp_dir!(), "test_library_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(test_dir)

      on_exit(fn ->
        File.rm_rf(test_dir)
      end)

      view
      |> element(~s{button[phx-click="new_library_path"]})
      |> render_click()

      view
      |> form("#library-path-form",
        library_path: %{
          path: test_dir,
          type: "movies",
          monitored: "true"
        }
      )
      |> render_submit()

      Process.sleep(100)

      html = render(view)
      assert html =~ test_dir
      refute has_element?(view, ~s{div[class*="modal-open"]})
    end

    test "shows TV metadata source select for series libraries and persists it", %{view: view} do
      test_dir =
        Path.join(System.tmp_dir!(), "test_series_#{:erlang.unique_integer([:positive])}")

      File.mkdir_p!(test_dir)
      on_exit(fn -> File.rm_rf(test_dir) end)

      view
      |> element(~s{button[phx-click="new_library_path"]})
      |> render_click()

      # Type defaults to nil; switching to series reveals the gated select.
      html =
        view
        |> form("#library-path-form", library_path: %{type: "series"})
        |> render_change()

      assert html =~ "TV Metadata Source"

      view
      |> form("#library-path-form",
        library_path: %{
          path: test_dir,
          type: "series",
          monitored: "true",
          tv_metadata_source: "tmdb"
        }
      )
      |> render_submit()

      Process.sleep(100)

      library_path = Enum.find(Mydia.Settings.list_library_paths(), &(&1.path == test_dir))
      assert library_path.tv_metadata_source == :tmdb
    end

    test "hides TV metadata source select for movie libraries", %{view: view} do
      view
      |> element(~s{button[phx-click="new_library_path"]})
      |> render_click()

      html =
        view
        |> form("#library-path-form", library_path: %{type: "movies"})
        |> render_change()

      refute html =~ "TV Metadata Source"
    end

    test "shows the metadata source badge for series/mixed libraries in the list", %{
      conn: conn,
      token: token
    } do
      {:ok, series} =
        Mydia.Settings.create_library_path(%{
          path: "/tmp/series_#{System.unique_integer([:positive])}",
          type: "series",
          tv_metadata_source: "tmdb"
        })

      {:ok, _movie} =
        Mydia.Settings.create_library_path(%{
          path: "/tmp/movies_#{System.unique_integer([:positive])}",
          type: "movies"
        })

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:guardian_default_token, token)
        |> put_req_header("authorization", "Bearer #{token}")

      {:ok, view, _html} = live(conn, ~p"/admin/config/library-paths")

      # The series library shows a metadata-source badge reflecting its provider.
      assert has_element?(view, ~s{[data-tip="TV metadata source"]}, "TMDB")
      # The movie library has no metadata-source badge.
      refute has_element?(view, ~s{[data-tip="TV metadata source"]}, "TVDB")

      on_exit(fn -> Mydia.Settings.delete_library_path(series) end)
    end
  end
end
