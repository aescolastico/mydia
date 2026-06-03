defmodule MydiaWeb.DownloadsLive.IndexTest do
  use MydiaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mydia.AccountsFixtures
  import Mydia.DownloadsFixtures
  import Mydia.MediaFixtures

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
end
