defmodule Mydia.Library.ProviderHealerTest do
  use Mydia.DataCase, async: true

  import Mydia.MediaFixtures

  alias Mydia.Library.ProviderHealer
  alias Mydia.Media.MediaItem
  alias Mydia.Repo

  describe "heal_from_path/2" do
    test "backfills a missing tmdb id from the path" do
      show =
        media_item_fixture(%{type: "tv_show", title: "A Thousand Blows", tvdb_id: 423_901})

      assert is_nil(show.tmdb_id)

      healed =
        ProviderHealer.heal_from_path(
          show,
          "/media/A Thousand Blows (2025) {tmdb-208851}/Season 1/ep.mkv"
        )

      assert healed.tmdb_id == 208_851
      assert Repo.get!(MediaItem, show.id).tmdb_id == 208_851
    end

    test "backfills a missing imdb id (string) from the path" do
      movie = media_item_fixture(%{type: "movie", title: "Casino Royale", tmdb_id: 36_557})

      healed =
        ProviderHealer.heal_from_path(movie, "/media/Casino Royale (2006) [imdb-tt0381061].mkv")

      assert healed.imdb_id == "tt0381061"
    end

    test "backfills every missing provider id from the path" do
      show = media_item_fixture(%{type: "tv_show", title: "Severance"})

      healed =
        ProviderHealer.heal_from_path(
          show,
          "/media/tv/Severance (2022) {tvdbid-371980}/Season 1/Severance.S01E01.[tmdb-95396].{imdb-tt11280740}.mkv"
        )

      assert healed.tvdb_id == 371_980
      assert healed.tmdb_id == 95_396
      assert healed.imdb_id == "tt11280740"

      reloaded = Repo.get!(MediaItem, show.id)
      assert reloaded.tvdb_id == 371_980
      assert reloaded.tmdb_id == 95_396
      assert reloaded.imdb_id == "tt11280740"
    end

    test "prefers filename tags over folder tags for the same provider" do
      movie = media_item_fixture(%{type: "movie", title: "Twister"})

      healed =
        ProviderHealer.heal_from_path(
          movie,
          "/media/movies/Twister (1996) {tmdb-664}/Twister.1996.[tmdb-999999].mkv"
        )

      assert healed.tmdb_id == 999_999
      assert Repo.get!(MediaItem, movie.id).tmdb_id == 999_999
    end

    test "ignores invalid numeric provider ids" do
      movie = media_item_fixture(%{type: "movie", title: "Bad Tag"})

      healed = ProviderHealer.heal_from_path(movie, "/media/Bad Tag (2024) {tmdb-123abc}.mkv")

      assert is_nil(healed.tmdb_id)
      assert is_nil(Repo.get!(MediaItem, movie.id).tmdb_id)
    end

    test "does not overwrite an existing provider id" do
      movie = media_item_fixture(%{type: "movie", title: "Blades", tmdb_id: 107_463})

      healed =
        ProviderHealer.heal_from_path(movie, "/media/Blades (2024) {tmdb-999999}/file.mkv")

      assert healed.tmdb_id == 107_463
    end

    test "returns the item unchanged when no provider tag is present" do
      show = media_item_fixture(%{type: "tv_show", title: "No Tag", tvdb_id: 555})

      healed = ProviderHealer.heal_from_path(show, "/media/No Tag (2024)/Season 1/ep.mkv")

      assert is_nil(healed.tmdb_id)
      assert healed.tvdb_id == 555
    end
  end
end
