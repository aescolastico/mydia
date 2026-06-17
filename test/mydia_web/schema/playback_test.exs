defmodule MydiaWeb.Schema.PlaybackTest do
  use MydiaWeb.ConnCase

  alias Mydia.Playback
  alias Mydia.AccountsFixtures
  alias Mydia.MediaFixtures

  @mark_season_watched_mutation """
  mutation MarkSeasonWatched($showId: ID!, $seasonNumber: Int!) {
    markSeasonWatched(showId: $showId, seasonNumber: $seasonNumber) {
      id
      title
    }
  }
  """

  @mark_season_unwatched_mutation """
  mutation MarkSeasonUnwatched($showId: ID!, $seasonNumber: Int!) {
    markSeasonUnwatched(showId: $showId, seasonNumber: $seasonNumber) {
      id
      title
    }
  }
  """

  @mark_episodes_up_to_watched_mutation """
  mutation MarkEpisodesUpToWatched($episodeId: ID!) {
    markEpisodesUpToWatched(episodeId: $episodeId) {
      id
      title
    }
  }
  """

  setup do
    user = AccountsFixtures.user_fixture()
    show = MediaFixtures.media_item_fixture(%{type: "tv_show"})

    episodes =
      for n <- 1..4 do
        MediaFixtures.episode_fixture(%{
          media_item_id: show.id,
          season_number: 1,
          episode_number: n
        })
      end

    %{user: user, show: show, episodes: episodes}
  end

  describe "markSeasonUnwatched mutation" do
    test "clears the season's progress and returns the show", ctx do
      Enum.each(
        ctx.episodes,
        &(:changed = Playback.ensure_watched(ctx.user.id, episode_id: &1.id))
      )

      result =
        run_query(
          @mark_season_unwatched_mutation,
          %{"showId" => ctx.show.id, "seasonNumber" => 1},
          ctx.user
        )

      assert {:ok, %{data: %{"markSeasonUnwatched" => %{"id" => id}}}} = result
      assert id == ctx.show.id

      for ep <- ctx.episodes do
        assert Playback.get_progress(ctx.user.id, episode_id: ep.id) == nil
      end
    end

    test "requires authentication and makes no DB change", ctx do
      :changed = Playback.ensure_watched(ctx.user.id, episode_id: hd(ctx.episodes).id)

      result =
        run_query(@mark_season_unwatched_mutation, %{
          "showId" => ctx.show.id,
          "seasonNumber" => 1
        })

      assert {:ok, %{errors: [%{message: "Authentication required"}]}} = result
      assert Playback.get_progress(ctx.user.id, episode_id: hd(ctx.episodes).id).watched == true
    end

    test "unknown show id returns a graceful error, not a 500", ctx do
      result =
        run_query(
          @mark_season_unwatched_mutation,
          %{"showId" => Ecto.UUID.generate(), "seasonNumber" => 1},
          ctx.user
        )

      assert {:ok, %{errors: [%{message: "Show not found"}]}} = result
    end
  end

  describe "markEpisodesUpToWatched mutation" do
    test "marks the anchor and earlier episodes and returns the show", ctx do
      [_e1, _e2, e3, _e4] = ctx.episodes

      result =
        run_query(
          @mark_episodes_up_to_watched_mutation,
          %{"episodeId" => e3.id},
          ctx.user
        )

      assert {:ok, %{data: %{"markEpisodesUpToWatched" => %{"id" => id}}}} = result
      assert id == ctx.show.id

      [e1, e2, e3, e4] = ctx.episodes
      assert Playback.get_progress(ctx.user.id, episode_id: e1.id).watched == true
      assert Playback.get_progress(ctx.user.id, episode_id: e2.id).watched == true
      assert Playback.get_progress(ctx.user.id, episode_id: e3.id).watched == true
      assert Playback.get_progress(ctx.user.id, episode_id: e4.id) == nil
    end

    test "requires authentication and makes no DB change", ctx do
      result =
        run_query(@mark_episodes_up_to_watched_mutation, %{"episodeId" => hd(ctx.episodes).id})

      assert {:ok, %{errors: [%{message: "Authentication required"}]}} = result
      assert Playback.get_progress(ctx.user.id, episode_id: hd(ctx.episodes).id) == nil
    end

    test "unknown episode id returns a graceful error, not a 500", ctx do
      result =
        run_query(
          @mark_episodes_up_to_watched_mutation,
          %{"episodeId" => Ecto.UUID.generate()},
          ctx.user
        )

      assert {:ok, %{errors: [%{message: "Episode not found"}]}} = result
    end
  end

  describe "markSeasonWatched mutation (regression after context refactor)" do
    test "marks every episode in the season watched and returns the show", ctx do
      result =
        run_query(
          @mark_season_watched_mutation,
          %{"showId" => ctx.show.id, "seasonNumber" => 1},
          ctx.user
        )

      assert {:ok, %{data: %{"markSeasonWatched" => %{"id" => id}}}} = result
      assert id == ctx.show.id

      for ep <- ctx.episodes do
        assert Playback.get_progress(ctx.user.id, episode_id: ep.id).watched == true
      end
    end

    test "requires authentication", ctx do
      result =
        run_query(@mark_season_watched_mutation, %{"showId" => ctx.show.id, "seasonNumber" => 1})

      assert {:ok, %{errors: [%{message: "Authentication required"}]}} = result
    end
  end

  defp run_query(query, variables, user \\ nil) do
    context = if user, do: %{current_user: user}, else: %{}
    Absinthe.run(query, MydiaWeb.Schema, variables: variables, context: context)
  end
end
