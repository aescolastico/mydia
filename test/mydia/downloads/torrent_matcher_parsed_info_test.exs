defmodule Mydia.Downloads.TorrentMatcherParsedInfoTest do
  @moduledoc """
  Exercises TorrentMatcher consuming the native `%ParsedFileInfo{}` shape
  produced by `Mydia.Library.ReleaseParser` (U2), distinct from the legacy
  flat-map characterization suite.
  """
  use Mydia.DataCase, async: true

  alias Mydia.Downloads.TorrentMatcher
  alias Mydia.Library.Structs.ParsedFileInfo
  alias Mydia.Library.Structs.Quality

  import Mydia.Factory

  defp parsed(attrs) do
    defaults = %{original_filename: "release.mkv", confidence: 0.9, quality: Quality.empty()}
    struct!(ParsedFileInfo, Map.merge(defaults, Map.new(attrs)))
  end

  describe "movie matching from ParsedFileInfo" do
    test "matches a movie, reading quality from the Quality struct" do
      movie =
        insert(:media_item, %{type: "movie", title: "The Matrix", year: 1999, monitored: true})

      info =
        parsed(
          original_filename: "The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv",
          type: :movie,
          title: "The Matrix",
          year: 1999,
          quality: Quality.new(resolution: "1080p", source: "BluRay", codec: "x264")
        )

      assert {:ok, match} = TorrentMatcher.find_match(info)
      assert match.media_item.id == movie.id
    end
  end

  describe "TV matching from ParsedFileInfo" do
    setup do
      show = insert(:media_item, %{type: "tv_show", title: "From", monitored: true})
      episode = insert(:episode, %{media_item: show, season_number: 4, episode_number: 7})
      {:ok, %{show: show, episode: episode}}
    end

    test "single episode (episodes list) resolves the episode", %{show: show, episode: episode} do
      info =
        parsed(
          original_filename: "From.S04E07.1080p.WEB.h264-GROUP.mkv",
          type: :tv_show,
          title: "From",
          season: 4,
          episodes: [7]
        )

      assert {:ok, match} = TorrentMatcher.find_match(info)
      assert match.media_item.id == show.id
      assert match.episode.id == episode.id
    end

    test "season pack (season set, empty episodes) matches show with no episode", %{show: show} do
      info =
        parsed(
          original_filename: "From.S04.1080p.WEB-DL.x265-GROUP",
          type: :tv_show,
          title: "From",
          season: 4,
          episodes: nil
        )

      assert {:ok, match} = TorrentMatcher.find_match(info)
      assert match.media_item.id == show.id
      assert is_nil(match.episode)
      assert match.match_reason =~ "season pack"
    end
  end

  describe "ID-based matching from external_id/external_provider" do
    test "tmdb provider with string external_id matches by integer tmdb_id (behavior)" do
      movie =
        insert(:media_item, %{
          type: "movie",
          title: "Totally Different Name",
          tmdb_id: 603,
          monitored: true
        })

      info =
        parsed(
          type: :movie,
          title: "The Matrix",
          year: 1999,
          external_provider: :tmdb,
          external_id: "603"
        )

      assert {:ok, match} = TorrentMatcher.find_match(info)
      assert match.media_item.id == movie.id
      assert match.confidence == 0.98
      assert match.match_reason =~ "TMDB ID 603"
    end

    test "tvdb provider with string external_id matches by integer tvdb_id" do
      show =
        insert(:media_item, %{
          type: "tv_show",
          title: "Unrelated Title",
          tvdb_id: 121_361,
          monitored: true
        })

      episode = insert(:episode, %{media_item: show, season_number: 1, episode_number: 1})

      info =
        parsed(
          type: :tv_show,
          title: "Game of Thrones",
          season: 1,
          episodes: [1],
          external_provider: :tvdb,
          external_id: "121361"
        )

      assert {:ok, match} = TorrentMatcher.find_match(info)
      assert match.media_item.id == show.id
      assert match.episode.id == episode.id
      assert match.confidence == 0.98
    end

    test "non-numeric tvdb external_id does not crash and falls back to title" do
      insert(:media_item, %{type: "movie", title: "The Matrix", year: 1999, monitored: true})

      info =
        parsed(
          original_filename: "The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv",
          type: :movie,
          title: "The Matrix",
          year: 1999,
          external_provider: :tvdb,
          external_id: "not-a-number"
        )

      assert {:ok, match} = TorrentMatcher.find_match(info)
      # Fell back to title matching — not an ID match (the bad id was dropped, not cast to 0).
      refute match.match_reason =~ "ID-matched"
    end
  end

  describe "unknown type" do
    test "find_match never auto-matches an unknown release" do
      insert(:media_item, %{type: "movie", title: "The Matrix", year: 1999, monitored: true})
      info = parsed(type: :unknown, title: "The Matrix", confidence: 0.0)

      assert {:error, :no_match_found} = TorrentMatcher.find_match(info)
    end

    test "find_top_candidates still suggests from a usable-title unknown release" do
      insert(:media_item, %{type: "movie", title: "The Matrix", year: 1999, monitored: true})
      info = parsed(type: :unknown, title: "The Matrix", confidence: 0.0)

      candidates = TorrentMatcher.find_top_candidates(info, monitored_only: false)
      assert Enum.any?(candidates, fn c -> c.title == "The Matrix" end)
    end
  end
end
