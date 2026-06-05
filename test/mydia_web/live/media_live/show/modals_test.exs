defmodule MydiaWeb.MediaLive.Show.ModalsTest do
  use MydiaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MydiaWeb.MediaLive.Show.Modals
  alias Mydia.Metadata.Structs.SearchResult

  defp candidate(id, title, year) do
    %SearchResult{
      provider_id: to_string(id),
      provider: :metadata_relay,
      media_type: :tv_show,
      title: title,
      year: year
    }
  end

  describe "reidentify_modal/1" do
    test "renders candidates with selectable buttons wired to the select event" do
      html =
        render_component(&Modals.reidentify_modal/1,
          provider: :tmdb,
          candidates: [candidate(1396, "Ghost in the Shell", 2002)]
        )

      assert html =~ "Re-identify on TMDB"
      assert html =~ "Ghost in the Shell"
      assert html =~ "2002"
      assert html =~ ~s(phx-click="select_reidentify_candidate")
      assert html =~ ~s(phx-value-provider_id="1396")
      # Warns about the destructive consequence.
      assert html =~ "resets episode-level watch history"
    end

    test "renders an empty state when there are no candidates" do
      html =
        render_component(&Modals.reidentify_modal/1, provider: :tmdb, candidates: [])

      assert html =~ "No results found on TMDB"
      refute html =~ ~s(phx-click="select_reidentify_candidate")
    end

    test "always offers a cancel action" do
      html =
        render_component(&Modals.reidentify_modal/1, provider: :tvdb, candidates: [])

      assert html =~ ~s(phx-click="cancel_reidentify")
      assert html =~ "Re-identify on TheTVDB"
    end
  end
end
