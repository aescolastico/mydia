defmodule Mydia.Library.FileRenamerHealTest do
  use Mydia.DataCase, async: true

  import Mydia.MediaFixtures
  import Mydia.SettingsFixtures

  alias Mydia.Library.FileRenamer
  alias Mydia.Media.MediaItem
  alias Mydia.Repo

  describe "generate_rename_preview/1 provider association healing" do
    test "backfills a missing tmdb id parsed from the file path" do
      show =
        media_item_fixture(%{
          type: "tv_show",
          title: "A Thousand Blows",
          year: 2025,
          tvdb_id: 423_901
        })

      assert is_nil(show.tmdb_id)

      episode =
        episode_fixture(%{
          media_item_id: show.id,
          season_number: 1,
          episode_number: 2,
          title: "Episode 2"
        })

      library_path = library_path_fixture(%{type: "series"})

      file =
        media_file_fixture(%{
          episode_id: episode.id,
          library_path_id: library_path.id,
          relative_path:
            "A Thousand Blows (2025) {tmdb-208851}/Season 1/A Thousand Blows - S01E02 - Episode 2.mkv"
        })

      _preview = FileRenamer.generate_rename_preview(file)

      healed = Repo.get!(MediaItem, show.id)
      assert healed.tmdb_id == 208_851
      assert healed.tvdb_id == 423_901
    end

    test "does not overwrite an existing provider id" do
      show =
        media_item_fixture(%{
          type: "tv_show",
          title: "Blades",
          year: 2024,
          tmdb_id: 107_463
        })

      episode =
        episode_fixture(%{
          media_item_id: show.id,
          season_number: 1,
          episode_number: 1,
          title: "Pilot"
        })

      library_path = library_path_fixture(%{type: "series"})

      file =
        media_file_fixture(%{
          episode_id: episode.id,
          library_path_id: library_path.id,
          relative_path: "Blades (2024) {tmdb-999999}/Season 1/Blades - S01E01 - Pilot.mkv"
        })

      _preview = FileRenamer.generate_rename_preview(file)

      unchanged = Repo.get!(MediaItem, show.id)
      assert unchanged.tmdb_id == 107_463
    end

    test "leaves media item unchanged when path has no provider tag" do
      show =
        media_item_fixture(%{
          type: "tv_show",
          title: "No Tag Show",
          year: 2024,
          tvdb_id: 555
        })

      episode =
        episode_fixture(%{
          media_item_id: show.id,
          season_number: 1,
          episode_number: 1,
          title: "Pilot"
        })

      library_path = library_path_fixture(%{type: "series"})

      file =
        media_file_fixture(%{
          episode_id: episode.id,
          library_path_id: library_path.id,
          relative_path: "No Tag Show (2024)/Season 1/No Tag Show - S01E01 - Pilot.mkv"
        })

      _preview = FileRenamer.generate_rename_preview(file)

      unchanged = Repo.get!(MediaItem, show.id)
      assert is_nil(unchanged.tmdb_id)
      assert unchanged.tvdb_id == 555
    end
  end
end
