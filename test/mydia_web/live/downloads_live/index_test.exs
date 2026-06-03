defmodule MydiaWeb.DownloadsLive.IndexTest do
  use MydiaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mydia.AccountsFixtures
  import Mydia.DownloadsFixtures
  import Mydia.MediaFixtures

  alias Mydia.Downloads

  setup %{conn: conn} do
    admin = admin_user_fixture()
    %{conn: log_in_user(conn, admin), admin: admin}
  end

  # No download client is configured in these tests, so list_downloads_with_status
  # returns every download regardless of tab filter. That's fine here — we assert
  # on sort ordering and control state, not on tab filtering or live client fields.

  defp completed_download(title, attrs \\ %{}) do
    media_item = media_item_fixture(%{title: title})

    download_fixture(
      Map.merge(
        %{
          media_item_id: media_item.id,
          imported_at: DateTime.utc_now() |> DateTime.truncate(:second)
        },
        attrs
      )
    )
  end

  # Returns the given substrings ordered by where they appear in the html.
  defp order_in(html, substrings) do
    substrings
    |> Enum.map(fn s ->
      {pos, _len} = :binary.match(html, s)
      {s, pos}
    end)
    |> Enum.sort_by(fn {_s, pos} -> pos end)
    |> Enum.map(fn {s, _pos} -> s end)
  end

  describe "sort control" do
    test "defaults to newest-first and renders the control when rows exist", %{conn: conn} do
      completed_download("Alpha Movie")

      {:ok, view, _html} = live(conn, ~p"/downloads")

      assert has_element?(view, "#downloads-sort")
      assert has_element?(view, "#downloads-sort option[value='added_desc'][selected]")
    end

    test "is hidden when the active tab has no rows", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/downloads")

      refute has_element?(view, "#downloads-sort")
    end

    test "offers tab-appropriate options", %{conn: conn} do
      completed_download("Alpha Movie")

      {:ok, view, _html} = live(conn, ~p"/downloads")

      # Queue tab: ETA is meaningful, ratio is not.
      assert has_element?(view, "#downloads-sort option[value='eta_asc']")
      refute has_element?(view, "#downloads-sort option[value='ratio_desc']")

      html = view |> element("button[phx-value-tab='completed']") |> render_click()

      # Completed tab: ratio/imported are meaningful, ETA is not.
      assert html =~ "ratio_desc"
      assert has_element?(view, "#downloads-sort option[value='ratio_desc']")
      refute has_element?(view, "#downloads-sort option[value='eta_asc']")
    end
  end

  describe "sorting rows" do
    setup do
      completed_download("Gamma Movie", %{metadata: %{size: 3_000_000_000}})
      completed_download("Alpha Movie", %{metadata: %{size: 1_000_000_000}})
      completed_download("Beta Movie", %{metadata: %{size: 2_000_000_000}})
      :ok
    end

    test "sorts by name ascending and descending", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/downloads")
      titles = ["Alpha Movie", "Beta Movie", "Gamma Movie"]

      html = view |> element("#downloads-sort-form") |> render_change(%{"sort_by" => "name_asc"})
      assert order_in(html, titles) == ["Alpha Movie", "Beta Movie", "Gamma Movie"]
      assert has_element?(view, "#downloads-sort option[value='name_asc'][selected]")

      html = view |> element("#downloads-sort-form") |> render_change(%{"sort_by" => "name_desc"})
      assert order_in(html, titles) == ["Gamma Movie", "Beta Movie", "Alpha Movie"]
    end

    test "sorts by size descending (largest first)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/downloads")

      html = view |> element("#downloads-sort-form") |> render_change(%{"sort_by" => "size_desc"})

      assert order_in(html, ["Alpha Movie", "Beta Movie", "Gamma Movie"]) ==
               ["Gamma Movie", "Beta Movie", "Alpha Movie"]

      assert has_element?(view, "#downloads-sort option[value='size_desc'][selected]")
    end

    test "an unknown sort value leaves the current sort unchanged", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/downloads")

      # No crash, default remains selected.
      html = view |> element("#downloads-sort-form") |> render_change(%{"sort_by" => "bogus"})
      assert html =~ ~s(value="added_desc")
      assert has_element?(view, "#downloads-sort option[value='added_desc'][selected]")
    end
  end

  describe "clear completed modal" do
    test "opens with the delete-files checkbox off and a scope-accurate count", %{conn: conn} do
      completed_download("Alpha Movie")
      completed_download("Beta Movie")

      {:ok, view, _html} = live(conn, ~p"/downloads")

      refute has_element?(view, "#clear-completed-modal[open]")

      html =
        view |> element("button[phx-click='open_clear_completed_modal']") |> render_click()

      assert has_element?(view, "#clear-completed-modal[open]")
      assert html =~ "2 completed download(s)"
      # Default (unchecked) confirm button is non-destructive.
      assert html =~ "Clear Completed"
      refute html =~ "Clear and Delete Files"
    end

    test "checking the box switches the confirm button to destructive", %{conn: conn} do
      completed_download("Alpha Movie")

      {:ok, view, _html} = live(conn, ~p"/downloads")
      view |> element("button[phx-click='open_clear_completed_modal']") |> render_click()

      html =
        view |> element("#clear-completed-form") |> render_change(%{"delete_files" => "true"})

      assert html =~ "Clear and Delete Files"
      assert html =~ "btn-error"
      assert html =~ "cannot be undone"
    end

    test "reopening the modal resets the checkbox", %{conn: conn} do
      completed_download("Alpha Movie")

      {:ok, view, _html} = live(conn, ~p"/downloads")
      view |> element("button[phx-click='open_clear_completed_modal']") |> render_click()
      view |> element("#clear-completed-form") |> render_change(%{"delete_files" => "true"})

      view
      |> element(".modal-action button[phx-click='close_clear_completed_modal']")
      |> render_click()

      html =
        view |> element("button[phx-click='open_clear_completed_modal']") |> render_click()

      assert html =~ "Clear and Delete Files" == false
      assert html =~ "Clear Completed"
    end

    test "submitting without the box clears without deleting files", %{conn: conn} do
      completed_download("Alpha Movie")

      {:ok, view, _html} = live(conn, ~p"/downloads")
      view |> element("button[phx-click='open_clear_completed_modal']") |> render_click()

      html = view |> element("#clear-completed-form") |> render_submit(%{})

      assert html =~ "completed download(s) cleared"
      refute html =~ "files deleted from disk"
      assert Downloads.count_completed() == 0
    end

    test "submitting with the box checked reports files deleted", %{conn: conn} do
      completed_download("Alpha Movie")

      {:ok, view, _html} = live(conn, ~p"/downloads")
      view |> element("button[phx-click='open_clear_completed_modal']") |> render_click()

      html =
        view |> element("#clear-completed-form") |> render_submit(%{"delete_files" => "true"})

      assert html =~ "cleared and files deleted from disk"
      assert Downloads.count_completed() == 0
    end

    test "a readonly user cannot clear completed downloads", %{conn: conn} do
      completed_download("Alpha Movie")
      readonly = user_fixture(%{role: "readonly"})
      conn = log_in_user(conn, readonly)

      {:ok, view, _html} = live(conn, ~p"/downloads")
      view |> element("button[phx-click='open_clear_completed_modal']") |> render_click()

      html =
        view |> element("#clear-completed-form") |> render_submit(%{"delete_files" => "true"})

      assert html =~ "do not have permission"
      assert Downloads.count_completed() == 1
    end
  end
end
