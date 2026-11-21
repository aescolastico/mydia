defmodule MydiaWeb.MediaLive.IndexBulkRenameTest do
  use MydiaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mydia.AccountsFixtures
  import Mydia.MediaFixtures
  import Mydia.SettingsFixtures
  import MydiaWeb.AuthHelpers

  alias Mydia.Repo

  @moduletag :tmp_dir

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_user_fixture())}
  end

  test "movie selection uses the single-title preview and renames only checked files", %{
    conn: conn,
    tmp_dir: root
  } do
    library = library_path_fixture(%{path: root, type: "movies"})
    {first, first_file} = movie_file(library, root, "Amber Harbor", "amber-old.mkv")
    {second, second_file} = movie_file(library, root, "Blue Harbor", "blue-old.mkv")

    {:ok, view, _html} = live(conn, ~p"/movies")
    select_items(view, [first.id, second.id])
    view |> element("#batch-rename-files") |> render_click()

    assert has_element?(view, "#rename-item-#{first.id}", "Amber Harbor")
    assert has_element?(view, "#rename-item-#{second.id}", "Blue Harbor")
    assert has_element?(view, "#rename-file-#{first_file.id}[checked]")
    assert has_element?(view, "#rename-file-#{second_file.id}[checked]")

    view |> element("#rename-file-#{second_file.id}") |> render_click()
    view |> element("#rename-confirm") |> render_click()
    render_async(view)

    refute Repo.reload(first_file).relative_path == "amber-old.mkv"
    assert Repo.reload(second_file).relative_path == "blue-old.mkv"
    refute File.exists?(Path.join(root, "amber-old.mkv"))
    assert File.exists?(Path.join(root, "blue-old.mkv"))
    refute has_element?(view, "#rename-files-modal")
  end

  test "a TV season toggle affects only that selected show", %{conn: conn, tmp_dir: root} do
    library = library_path_fixture(%{path: root, type: "series"})
    {first, first_file} = show_file(library, root, "Amber Harbor", "amber-s1e1.mkv")
    {second, second_file} = show_file(library, root, "Blue Harbor", "blue-s1e1.mkv")

    {:ok, view, _html} = live(conn, ~p"/tv")
    select_items(view, [first.id, second.id])
    view |> element("#batch-rename-files") |> render_click()

    assert has_element?(view, "#rename-item-#{first.id}-season-1-toggle")
    assert has_element?(view, "#rename-item-#{second.id}-season-1-toggle")

    view |> element("#rename-item-#{first.id}-season-1-toggle") |> render_click()
    refute has_element?(view, "#rename-file-#{first_file.id}[checked]")
    assert has_element?(view, "#rename-file-#{second_file.id}[checked]")

    view |> element("#rename-confirm") |> render_click()
    render_async(view)

    assert Repo.reload(first_file).relative_path == "amber-s1e1.mkv"
    refute Repo.reload(second_file).relative_path == "blue-s1e1.mkv"
  end

  test "bulk preview includes an untitled episode without crashing", %{conn: conn, tmp_dir: root} do
    library = library_path_fixture(%{path: root, type: "series"})
    {first, _first_file} = show_file(library, root, "Amber Harbor", "amber-s1e1.mkv")
    {second, _second_file} = show_file(library, root, "Blue Harbor", "blue-s1e1.mkv")
    third = media_item_fixture(%{type: "tv_show", title: "Cedar Harbor", year: 2022})

    episode =
      episode_fixture(%{
        media_item_id: third.id,
        season_number: 1,
        episode_number: 2,
        title: nil
      })

    file =
      media_file_fixture(%{
        episode_id: episode.id,
        library_path_id: library.id,
        relative_path: "cedar-s1e2.mkv"
      })

    {:ok, view, _html} = live(conn, ~p"/tv")
    select_items(view, [first.id, second.id, third.id])
    view |> element("#batch-rename-files") |> render_click()

    assert has_element?(view, "#rename-item-#{first.id}")
    assert has_element?(view, "#rename-item-#{second.id}")
    assert has_element?(view, "#rename-item-#{third.id}")
    assert view |> element("#rename-file-#{file.id}") |> render() =~ "Episode 02"
  end

  test "a reader cannot open the rename dialog through a crafted event", %{
    conn: conn,
    tmp_dir: root
  } do
    library = library_path_fixture(%{path: root, type: "movies"})
    {movie, _file} = movie_file(library, root, "Amber Harbor", "amber-old.mkv")
    conn = log_in_user(conn, user_fixture(%{role: "readonly"}))

    {:ok, view, _html} = live(conn, ~p"/movies")
    select_items(view, [movie.id])
    render_click(view, "show_rename_modal", %{})

    refute has_element?(view, "#rename-files-modal")

    assert view |> element("#flash-error") |> render() =~
             "You do not have permission to modify media items"
  end

  defp select_items(view, ids) do
    render_click(view, "toggle_selection_mode", %{})

    Enum.each(ids, fn id ->
      render_click(view, "toggle_select", %{"id" => id})
    end)
  end

  defp movie_file(library, root, title, filename) do
    movie = media_item_fixture(%{type: "movie", title: title, year: 2022})
    File.write!(Path.join(root, filename), "bytes")

    file =
      media_file_fixture(%{
        media_item_id: movie.id,
        library_path_id: library.id,
        relative_path: filename
      })

    {movie, file}
  end

  defp show_file(library, root, title, filename) do
    show = media_item_fixture(%{type: "tv_show", title: title, year: 2022})
    episode = episode_fixture(%{media_item_id: show.id, season_number: 1, episode_number: 1})
    File.write!(Path.join(root, filename), "bytes")

    file =
      media_file_fixture(%{
        episode_id: episode.id,
        library_path_id: library.id,
        relative_path: filename
      })

    {show, file}
  end
end
