defmodule Mydia.MediaTest do
  use Mydia.DataCase

  alias Mydia.Media

  describe "media_items" do
    alias Mydia.Media.MediaItem

    import Mydia.MediaFixtures

    @invalid_attrs %{type: nil, title: nil}

    test "list_media_items/0 returns all media items" do
      media_item = media_item_fixture()
      assert Media.list_media_items() == [media_item]
    end

    test "get_media_item!/1 returns the media item with given id" do
      media_item = media_item_fixture()
      assert Media.get_media_item!(media_item.id) == media_item
    end

    test "create_media_item/1 with valid data creates a media item" do
      valid_attrs = %{
        type: "movie",
        title: "Test Movie",
        year: 2024,
        tmdb_id: 12345,
        monitored: true
      }

      assert {:ok, %MediaItem{} = media_item} = Media.create_media_item(valid_attrs)
      assert media_item.type == "movie"
      assert media_item.title == "Test Movie"
      assert media_item.year == 2024
      assert media_item.tmdb_id == 12345
      assert media_item.monitored == true
    end

    test "create_media_item/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Media.create_media_item(@invalid_attrs)
    end

    test "create_media_item/1 requires year for movies" do
      attrs_without_year = %{
        type: "movie",
        title: "Test Movie",
        tmdb_id: 12345,
        monitored: true
      }

      assert {:error, %Ecto.Changeset{} = changeset} =
               Media.create_media_item(attrs_without_year)

      assert %{year: ["is required for movies"]} = errors_on(changeset)
    end

    test "create_media_item/1 allows tv_shows without year" do
      attrs_without_year = %{
        type: "tv_show",
        title: "Test Show",
        tmdb_id: 12345,
        monitored: true
      }

      assert {:ok, %MediaItem{} = media_item} =
               Media.create_media_item(attrs_without_year, skip_episode_refresh: true)

      assert media_item.type == "tv_show"
      assert media_item.title == "Test Show"
      assert media_item.year == nil
    end

    test "update_media_item/2 with valid data updates the media item" do
      media_item = media_item_fixture()
      update_attrs = %{title: "Updated Title", monitored: false}

      assert {:ok, %MediaItem{} = media_item} =
               Media.update_media_item(media_item, update_attrs)

      assert media_item.title == "Updated Title"
      assert media_item.monitored == false
    end

    test "delete_media_item/1 deletes the media item" do
      media_item = media_item_fixture()
      assert {:ok, %MediaItem{}} = Media.delete_media_item(media_item)
      assert_raise Ecto.NoResultsError, fn -> Media.get_media_item!(media_item.id) end
    end

    test "change_media_item/1 returns a media item changeset" do
      media_item = media_item_fixture()
      assert %Ecto.Changeset{} = Media.change_media_item(media_item)
    end
  end

  describe "episodes" do
    alias Mydia.Media.Episode

    import Mydia.MediaFixtures

    @invalid_attrs %{season_number: nil, episode_number: nil}

    test "list_episodes/1 returns all episodes for a media item" do
      media_item = media_item_fixture(%{type: "tv_show"})
      episode = episode_fixture(media_item_id: media_item.id)
      assert Media.list_episodes(media_item.id) == [episode]
    end

    test "get_episode!/1 returns the episode with given id" do
      media_item = media_item_fixture(%{type: "tv_show"})
      episode = episode_fixture(media_item_id: media_item.id)
      assert Media.get_episode!(episode.id) == episode
    end

    test "create_episode/1 with valid data creates an episode" do
      media_item = media_item_fixture(%{type: "tv_show"})

      valid_attrs = %{
        media_item_id: media_item.id,
        season_number: 1,
        episode_number: 1,
        title: "Pilot"
      }

      assert {:ok, %Episode{} = episode} = Media.create_episode(valid_attrs)
      assert episode.season_number == 1
      assert episode.episode_number == 1
      assert episode.title == "Pilot"
    end

    test "create_episode/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Media.create_episode(@invalid_attrs)
    end

    test "update_episode/2 with valid data updates the episode" do
      media_item = media_item_fixture(%{type: "tv_show"})
      episode = episode_fixture(media_item_id: media_item.id)
      update_attrs = %{title: "Updated Episode Title"}

      assert {:ok, %Episode{} = episode} = Media.update_episode(episode, update_attrs)
      assert episode.title == "Updated Episode Title"
    end

    test "delete_episode/1 deletes the episode" do
      media_item = media_item_fixture(%{type: "tv_show"})
      episode = episode_fixture(media_item_id: media_item.id)
      assert {:ok, %Episode{}} = Media.delete_episode(episode)
      assert_raise Ecto.NoResultsError, fn -> Media.get_episode!(episode.id) end
    end
  end

  describe "category classification" do
    alias Mydia.Media.MediaItem

    import Mydia.MediaFixtures

    test "create_media_item/1 auto-classifies movies without animation genre" do
      attrs = %{
        type: "movie",
        title: "Regular Movie",
        year: 2024,
        metadata: %{genres: ["Drama", "Action"]}
      }

      assert {:ok, %MediaItem{} = media_item} = Media.create_media_item(attrs)
      assert media_item.category == "movie"
      assert media_item.category_override == false
    end

    test "create_media_item/1 auto-classifies anime movies" do
      attrs = %{
        type: "movie",
        title: "Anime Movie",
        year: 2024,
        metadata: %{
          genres: ["Animation", "Adventure"],
          origin_country: ["JP"],
          original_language: "ja"
        }
      }

      assert {:ok, %MediaItem{} = media_item} = Media.create_media_item(attrs)
      assert media_item.category == "anime_movie"
    end

    test "create_media_item/1 auto-classifies cartoon movies" do
      attrs = %{
        type: "movie",
        title: "Cartoon Movie",
        year: 2024,
        metadata: %{
          genres: ["Animation", "Family"],
          origin_country: ["US"],
          original_language: "en"
        }
      }

      assert {:ok, %MediaItem{} = media_item} = Media.create_media_item(attrs)
      assert media_item.category == "cartoon_movie"
    end

    test "create_media_item/1 auto-classifies TV shows" do
      attrs = %{
        type: "tv_show",
        title: "Regular TV Show",
        metadata: %{genres: ["Drama"]}
      }

      assert {:ok, %MediaItem{} = media_item} =
               Media.create_media_item(attrs, skip_episode_refresh: true)

      assert media_item.category == "tv_show"
    end

    test "create_media_item/1 auto-classifies anime series" do
      attrs = %{
        type: "tv_show",
        title: "Anime Series",
        metadata: %{
          genres: ["Animation", "Action"],
          origin_country: ["JP"]
        }
      }

      assert {:ok, %MediaItem{} = media_item} =
               Media.create_media_item(attrs, skip_episode_refresh: true)

      assert media_item.category == "anime_series"
    end

    test "create_media_item/1 auto-classifies cartoon series" do
      attrs = %{
        type: "tv_show",
        title: "Cartoon Series",
        metadata: %{
          genres: ["Animation", "Comedy"],
          origin_country: ["US"]
        }
      }

      assert {:ok, %MediaItem{} = media_item} =
               Media.create_media_item(attrs, skip_episode_refresh: true)

      assert media_item.category == "cartoon_series"
    end

    test "update_category/2 updates the category" do
      media_item = media_item_fixture()

      assert {:ok, %MediaItem{} = updated} = Media.update_category(media_item, :anime_movie)
      assert updated.category == "anime_movie"
      assert updated.category_override == false
    end

    test "update_category/3 with override: true sets the override flag" do
      media_item = media_item_fixture()

      assert {:ok, %MediaItem{} = updated} =
               Media.update_category(media_item, :anime_movie, override: true)

      assert updated.category == "anime_movie"
      assert updated.category_override == true
    end

    test "clear_category_override/1 clears the override flag" do
      media_item = media_item_fixture()
      {:ok, media_item} = Media.update_category(media_item, :anime_movie, override: true)

      assert media_item.category_override == true

      assert {:ok, %MediaItem{} = updated} = Media.clear_category_override(media_item)
      assert updated.category_override == false
    end

    test "reclassify_media_item/1 reclassifies based on metadata" do
      # Create a movie that gets classified as regular movie
      attrs = %{
        type: "movie",
        title: "Test Movie",
        year: 2024,
        metadata: %{genres: ["Drama"]}
      }

      {:ok, media_item} = Media.create_media_item(attrs)
      assert media_item.category == "movie"

      # Update metadata to make it anime
      {:ok, media_item} =
        Media.update_media_item(media_item, %{
          metadata: %{
            genres: ["Animation"],
            origin_country: ["JP"],
            original_language: "ja"
          }
        })

      # Reclassify
      assert {:ok, %MediaItem{} = reclassified} = Media.reclassify_media_item(media_item)
      assert reclassified.category == "anime_movie"
    end

    test "reclassify_media_item/1 respects category_override flag" do
      media_item = media_item_fixture()
      {:ok, media_item} = Media.update_category(media_item, :cartoon_movie, override: true)

      # Update metadata to indicate anime
      {:ok, media_item} =
        Media.update_media_item(media_item, %{
          metadata: %{genres: ["Animation"], origin_country: ["JP"]}
        })

      # Reclassify should NOT change the category
      assert {:ok, %MediaItem{} = unchanged} = Media.reclassify_media_item(media_item)
      assert unchanged.category == "cartoon_movie"
    end

    test "reclassify_media_item/2 with force: true ignores override" do
      media_item = media_item_fixture()
      {:ok, media_item} = Media.update_category(media_item, :cartoon_movie, override: true)

      # Update metadata to indicate anime
      {:ok, media_item} =
        Media.update_media_item(media_item, %{
          metadata: %{genres: ["Animation"], origin_country: ["JP"]}
        })

      # Reclassify with force should change the category
      assert {:ok, %MediaItem{} = forced} = Media.reclassify_media_item(media_item, force: true)
      assert forced.category == "anime_movie"
    end

    test "list_media_items/1 filters by category" do
      # Create movies with different categories
      {:ok, movie} =
        Media.create_media_item(%{
          type: "movie",
          title: "Regular Movie",
          year: 2024,
          metadata: %{genres: ["Drama"]}
        })

      {:ok, anime} =
        Media.create_media_item(%{
          type: "movie",
          title: "Anime Movie",
          year: 2024,
          metadata: %{genres: ["Animation"], origin_country: ["JP"]}
        })

      # Filter by category (atom)
      movies = Media.list_media_items(category: :movie)
      assert length(movies) == 1
      assert hd(movies).id == movie.id

      # Filter by category (string)
      anime_movies = Media.list_media_items(category: "anime_movie")
      assert length(anime_movies) == 1
      assert hd(anime_movies).id == anime.id
    end

    test "reclassify_all_media_items/0 reclassifies all non-override items" do
      # Create some items - they will be auto-classified
      {:ok, movie} =
        Media.create_media_item(%{
          type: "movie",
          title: "Test Movie 1",
          year: 2024,
          metadata: %{genres: ["Drama"]}
        })

      {:ok, _anime} =
        Media.create_media_item(%{
          type: "movie",
          title: "Test Movie 2",
          year: 2024,
          metadata: %{genres: ["Animation"], origin_country: ["JP"]}
        })

      # Set override on one
      {:ok, overridden} = Media.update_category(movie, :cartoon_movie, override: true)
      assert overridden.category_override == true

      # Reclassify all
      assert {:ok, count} = Media.reclassify_all_media_items()
      assert count >= 1

      # Overridden item should remain unchanged
      updated_movie = Media.get_media_item!(movie.id)
      assert updated_movie.category == "cartoon_movie"
    end

    test "reclassify_media_items/2 reclassifies selected items by ID" do
      # Create items with specific metadata
      {:ok, movie} =
        Media.create_media_item(%{
          type: "movie",
          title: "Regular Movie",
          year: 2024,
          metadata: %{genres: ["Drama"]}
        })

      {:ok, anime} =
        Media.create_media_item(%{
          type: "movie",
          title: "Anime Movie",
          year: 2024,
          metadata: %{genres: ["Animation"], origin_country: ["JP"]}
        })

      # Verify initial classifications
      assert movie.category == "movie"
      assert anime.category == "anime_movie"

      # Manually change anime to a wrong category (for testing re-classification)
      {:ok, _} = Media.update_category(anime, :movie)

      # Re-classify specific items
      {:ok, summary} = Media.reclassify_media_items([anime.id])

      assert summary.total == 1
      assert summary.updated == 1
      assert summary.skipped == 0
      assert summary.unchanged == 0

      # Verify it was reclassified correctly
      updated_anime = Media.get_media_item!(anime.id)
      assert updated_anime.category == "anime_movie"
    end

    test "reclassify_media_items/2 respects category_override flag" do
      {:ok, movie} =
        Media.create_media_item(%{
          type: "movie",
          title: "Overridden Movie",
          year: 2024,
          metadata: %{genres: ["Animation"], origin_country: ["JP"]}
        })

      # Should be classified as anime_movie
      assert movie.category == "anime_movie"

      # Set override to a different category
      {:ok, overridden} = Media.update_category(movie, :movie, override: true)
      assert overridden.category_override == true
      assert overridden.category == "movie"

      # Try to reclassify - should be skipped
      {:ok, summary} = Media.reclassify_media_items([movie.id])

      assert summary.total == 1
      assert summary.updated == 0
      assert summary.skipped == 1

      # Verify category unchanged
      still_overridden = Media.get_media_item!(movie.id)
      assert still_overridden.category == "movie"
    end

    test "reclassify_media_items/2 with force: true ignores override" do
      {:ok, movie} =
        Media.create_media_item(%{
          type: "movie",
          title: "Force Reclassify Movie",
          year: 2024,
          metadata: %{genres: ["Animation"], origin_country: ["JP"]}
        })

      # Set override to wrong category
      {:ok, overridden} = Media.update_category(movie, :movie, override: true)
      assert overridden.category == "movie"
      assert overridden.category_override == true

      # Force reclassify
      {:ok, summary} = Media.reclassify_media_items([movie.id], force: true)

      assert summary.updated == 1
      assert summary.skipped == 0

      # Verify it was reclassified
      updated = Media.get_media_item!(movie.id)
      assert updated.category == "anime_movie"
    end

    test "reclassify_media_items/2 returns correct summary with unchanged items" do
      {:ok, movie} =
        Media.create_media_item(%{
          type: "movie",
          title: "Already Correct Movie",
          year: 2024,
          metadata: %{genres: ["Drama"]}
        })

      # Verify it's already correctly classified
      assert movie.category == "movie"

      # Reclassify - should not change anything
      {:ok, summary} = Media.reclassify_media_items([movie.id])

      assert summary.total == 1
      assert summary.updated == 0
      assert summary.skipped == 0
      assert summary.unchanged == 1
    end
  end

  describe "monitoring presets" do
    alias Mydia.Media.{MediaItem, Episode}
    import Mydia.MediaFixtures

    test "monitoring_presets/0 returns all valid presets" do
      presets = Media.monitoring_presets()
      assert :all in presets
      assert :future in presets
      assert :missing in presets
      assert :existing in presets
      assert :first_season in presets
      assert :latest_season in presets
      assert :none in presets
      assert length(presets) == 7
    end

    test "apply_monitoring_preset/2 returns error for movies" do
      media_item = media_item_fixture(%{type: "movie"})

      assert {:error, {:invalid_type, _}} = Media.apply_monitoring_preset(media_item, :all)
    end

    test "apply_monitoring_preset/2 with :all monitors all episodes except specials" do
      media_item = media_item_fixture(%{type: "tv_show", monitored: true})

      # Create episodes in different seasons including specials
      episode_fixture(
        media_item_id: media_item.id,
        season_number: 0,
        episode_number: 1,
        monitored: false
      )

      episode_fixture(
        media_item_id: media_item.id,
        season_number: 1,
        episode_number: 1,
        monitored: false
      )

      episode_fixture(
        media_item_id: media_item.id,
        season_number: 1,
        episode_number: 2,
        monitored: false
      )

      episode_fixture(
        media_item_id: media_item.id,
        season_number: 2,
        episode_number: 1,
        monitored: false
      )

      {:ok, updated_item, count} = Media.apply_monitoring_preset(media_item, :all)

      assert updated_item.monitoring_preset == :all
      assert count == 4

      # Verify episode states
      episodes = Media.list_episodes(media_item.id)
      special = Enum.find(episodes, &(&1.season_number == 0))
      s1e1 = Enum.find(episodes, &(&1.season_number == 1 && &1.episode_number == 1))
      s1e2 = Enum.find(episodes, &(&1.season_number == 1 && &1.episode_number == 2))
      s2e1 = Enum.find(episodes, &(&1.season_number == 2 && &1.episode_number == 1))

      refute special.monitored
      assert s1e1.monitored
      assert s1e2.monitored
      assert s2e1.monitored
    end

    test "apply_monitoring_preset/2 with :none unmonitors all episodes" do
      media_item = media_item_fixture(%{type: "tv_show", monitored: true})

      # Create monitored episodes
      episode_fixture(
        media_item_id: media_item.id,
        season_number: 1,
        episode_number: 1,
        monitored: true
      )

      episode_fixture(
        media_item_id: media_item.id,
        season_number: 1,
        episode_number: 2,
        monitored: true
      )

      {:ok, updated_item, count} = Media.apply_monitoring_preset(media_item, :none)

      assert updated_item.monitoring_preset == :none
      assert count == 2

      # Verify all episodes are unmonitored
      episodes = Media.list_episodes(media_item.id)
      assert Enum.all?(episodes, &(!&1.monitored))
    end

    test "apply_monitoring_preset/2 with :future monitors only future episodes" do
      media_item = media_item_fixture(%{type: "tv_show", monitored: true})

      today = Date.utc_today()
      past_date = Date.add(today, -30)
      future_date = Date.add(today, 30)

      # Create past and future episodes
      episode_fixture(
        media_item_id: media_item.id,
        season_number: 1,
        episode_number: 1,
        air_date: past_date,
        monitored: true
      )

      episode_fixture(
        media_item_id: media_item.id,
        season_number: 1,
        episode_number: 2,
        air_date: future_date,
        monitored: false
      )

      {:ok, updated_item, _count} = Media.apply_monitoring_preset(media_item, :future)

      assert updated_item.monitoring_preset == :future

      # Verify episode states
      episodes = Media.list_episodes(media_item.id)
      past_ep = Enum.find(episodes, &(&1.air_date == past_date))
      future_ep = Enum.find(episodes, &(&1.air_date == future_date))

      refute past_ep.monitored
      assert future_ep.monitored
    end

    test "apply_monitoring_preset/2 with :first_season monitors only season 1" do
      media_item = media_item_fixture(%{type: "tv_show", monitored: true})

      # Create episodes in multiple seasons
      episode_fixture(
        media_item_id: media_item.id,
        season_number: 1,
        episode_number: 1,
        monitored: false
      )

      episode_fixture(
        media_item_id: media_item.id,
        season_number: 1,
        episode_number: 2,
        monitored: false
      )

      episode_fixture(
        media_item_id: media_item.id,
        season_number: 2,
        episode_number: 1,
        monitored: true
      )

      episode_fixture(
        media_item_id: media_item.id,
        season_number: 3,
        episode_number: 1,
        monitored: true
      )

      {:ok, updated_item, _count} = Media.apply_monitoring_preset(media_item, :first_season)

      assert updated_item.monitoring_preset == :first_season

      # Verify episode states
      episodes = Media.list_episodes(media_item.id)

      s1_episodes = Enum.filter(episodes, &(&1.season_number == 1))
      s2_episodes = Enum.filter(episodes, &(&1.season_number == 2))
      s3_episodes = Enum.filter(episodes, &(&1.season_number == 3))

      assert Enum.all?(s1_episodes, & &1.monitored)
      refute Enum.any?(s2_episodes, & &1.monitored)
      refute Enum.any?(s3_episodes, & &1.monitored)
    end

    test "apply_monitoring_preset/2 with :latest_season monitors only the latest season" do
      media_item = media_item_fixture(%{type: "tv_show", monitored: true})

      # Create episodes in multiple seasons
      episode_fixture(
        media_item_id: media_item.id,
        season_number: 1,
        episode_number: 1,
        monitored: true
      )

      episode_fixture(
        media_item_id: media_item.id,
        season_number: 2,
        episode_number: 1,
        monitored: false
      )

      episode_fixture(
        media_item_id: media_item.id,
        season_number: 3,
        episode_number: 1,
        monitored: false
      )

      episode_fixture(
        media_item_id: media_item.id,
        season_number: 3,
        episode_number: 2,
        monitored: false
      )

      {:ok, updated_item, _count} = Media.apply_monitoring_preset(media_item, :latest_season)

      assert updated_item.monitoring_preset == :latest_season

      # Verify episode states
      episodes = Media.list_episodes(media_item.id)

      s1_episodes = Enum.filter(episodes, &(&1.season_number == 1))
      s2_episodes = Enum.filter(episodes, &(&1.season_number == 2))
      s3_episodes = Enum.filter(episodes, &(&1.season_number == 3))

      refute Enum.any?(s1_episodes, & &1.monitored)
      refute Enum.any?(s2_episodes, & &1.monitored)
      assert Enum.all?(s3_episodes, & &1.monitored)
    end

    test "apply_monitoring_preset/2 with :existing monitors only episodes with files" do
      media_item = media_item_fixture(%{type: "tv_show", monitored: true})

      # Create episodes
      ep_with_file =
        episode_fixture(
          media_item_id: media_item.id,
          season_number: 1,
          episode_number: 1,
          monitored: false
        )

      _ep_without_file =
        episode_fixture(
          media_item_id: media_item.id,
          season_number: 1,
          episode_number: 2,
          monitored: true
        )

      # Add a media file to the first episode
      media_file_fixture(episode_id: ep_with_file.id)

      {:ok, updated_item, _count} = Media.apply_monitoring_preset(media_item, :existing)

      assert updated_item.monitoring_preset == :existing

      # Verify episode states
      episodes = Media.list_episodes(media_item.id, preload: [:media_files])

      ep_with = Enum.find(episodes, &(&1.episode_number == 1))
      ep_without = Enum.find(episodes, &(&1.episode_number == 2))

      assert ep_with.monitored
      refute ep_without.monitored
    end

    test "apply_monitoring_preset/2 with :missing monitors episodes without files or future" do
      media_item = media_item_fixture(%{type: "tv_show", monitored: true})

      today = Date.utc_today()
      future_date = Date.add(today, 30)

      # Create episodes
      ep_with_file =
        episode_fixture(
          media_item_id: media_item.id,
          season_number: 1,
          episode_number: 1,
          monitored: true
        )

      _ep_missing =
        episode_fixture(
          media_item_id: media_item.id,
          season_number: 1,
          episode_number: 2,
          monitored: false
        )

      _ep_future =
        episode_fixture(
          media_item_id: media_item.id,
          season_number: 1,
          episode_number: 3,
          air_date: future_date,
          monitored: false
        )

      # Add a media file to the first episode
      media_file_fixture(episode_id: ep_with_file.id)

      {:ok, updated_item, _count} = Media.apply_monitoring_preset(media_item, :missing)

      assert updated_item.monitoring_preset == :missing

      # Verify episode states
      episodes = Media.list_episodes(media_item.id, preload: [:media_files])

      ep_with = Enum.find(episodes, &(&1.episode_number == 1))
      ep_missing = Enum.find(episodes, &(&1.episode_number == 2))
      ep_future = Enum.find(episodes, &(&1.episode_number == 3))

      # Has file
      refute ep_with.monitored
      # Missing file
      assert ep_missing.monitored
      # Future
      assert ep_future.monitored
    end

    test "apply_monitoring_preset/2 persists the preset to media_item" do
      media_item = media_item_fixture(%{type: "tv_show"})

      # Create an episode
      episode_fixture(media_item_id: media_item.id, season_number: 1, episode_number: 1)

      {:ok, updated_item, _count} = Media.apply_monitoring_preset(media_item, :future)

      # Reload from database to ensure persistence
      reloaded = Media.get_media_item!(media_item.id)
      assert reloaded.monitoring_preset == :future
    end

    test "apply_monitoring_preset/2 handles empty episode list" do
      media_item = media_item_fixture(%{type: "tv_show"})

      # No episodes created

      {:ok, updated_item, count} = Media.apply_monitoring_preset(media_item, :all)

      assert updated_item.monitoring_preset == :all
      assert count == 0
    end
  end

  describe "list_movies_by_release_date/3" do
    alias Mydia.Media.Structs.CalendarEntry

    import Mydia.MediaFixtures

    test "returns movies with release dates in range" do
      media_item_fixture(%{
        type: "movie",
        title: "In Range Movie",
        year: 2025,
        metadata: %{
          provider_id: "1",
          provider: :metadata_relay,
          media_type: :movie,
          release_date: ~D[2025-06-15]
        }
      })

      entries = Media.list_movies_by_release_date(~D[2025-06-01], ~D[2025-06-30])

      assert [%CalendarEntry{} = entry] = entries
      assert entry.title == "In Range Movie"
      assert entry.air_date == ~D[2025-06-15]
      assert entry.type == "movie"
    end

    test "excludes movies with release dates outside range" do
      media_item_fixture(%{
        type: "movie",
        title: "Before Range",
        year: 2025,
        metadata: %{
          provider_id: "2",
          provider: :metadata_relay,
          media_type: :movie,
          release_date: ~D[2025-05-31]
        }
      })

      media_item_fixture(%{
        type: "movie",
        title: "After Range",
        year: 2025,
        metadata: %{
          provider_id: "3",
          provider: :metadata_relay,
          media_type: :movie,
          release_date: ~D[2025-07-01]
        }
      })

      entries = Media.list_movies_by_release_date(~D[2025-06-01], ~D[2025-06-30])
      assert entries == []
    end

    test "excludes movies without release dates" do
      media_item_fixture(%{
        type: "movie",
        title: "No Release Date",
        year: 2025,
        metadata: %{genres: ["Drama"]}
      })

      entries = Media.list_movies_by_release_date(~D[2025-01-01], ~D[2025-12-31])
      assert entries == []
    end

    test "includes boundary dates" do
      media_item_fixture(%{
        type: "movie",
        title: "Start Boundary",
        year: 2025,
        metadata: %{
          provider_id: "4",
          provider: :metadata_relay,
          media_type: :movie,
          release_date: ~D[2025-06-01]
        }
      })

      media_item_fixture(%{
        type: "movie",
        title: "End Boundary",
        year: 2025,
        metadata: %{
          provider_id: "5",
          provider: :metadata_relay,
          media_type: :movie,
          release_date: ~D[2025-06-30]
        }
      })

      entries = Media.list_movies_by_release_date(~D[2025-06-01], ~D[2025-06-30])
      assert length(entries) == 2
      titles = Enum.map(entries, & &1.title)
      assert "Start Boundary" in titles
      assert "End Boundary" in titles
    end

    test "sets has_files and has_downloads correctly" do
      movie =
        media_item_fixture(%{
          type: "movie",
          title: "Movie With File",
          year: 2025,
          metadata: %{
            provider_id: "6",
            provider: :metadata_relay,
            media_type: :movie,
            release_date: ~D[2025-06-15]
          }
        })

      media_file_fixture(media_item_id: movie.id)

      entries = Media.list_movies_by_release_date(~D[2025-06-01], ~D[2025-06-30])

      assert [%CalendarEntry{} = entry] = entries
      assert entry.has_files == true
      assert entry.has_downloads == false
    end
  end

  describe "resolve_library_provider/1 (U6)" do
    import Mydia.MediaFixtures
    import Mydia.SettingsFixtures

    test "returns the provider of a directly-linked file's series library" do
      item = media_item_fixture(%{type: "tv_show", title: "Show A"})
      lib = library_path_fixture(%{type: "series", tv_metadata_source: :tvdb})
      media_file_fixture(%{media_item_id: item.id, library_path_id: lib.id})

      assert Media.resolve_library_provider(item) == {:ok, :tvdb}
    end

    test "finds the library for an episode-linked file (media_item_id nil)" do
      item = media_item_fixture(%{type: "tv_show", title: "Show B"})
      lib = library_path_fixture(%{type: "series", tv_metadata_source: :tmdb})
      episode = episode_fixture(%{media_item_id: item.id, season_number: 1, episode_number: 1})
      media_file_fixture(%{episode_id: episode.id, library_path_id: lib.id})

      assert Media.resolve_library_provider(item) == {:ok, :tmdb}
    end

    test "is :ambiguous when files span libraries with different providers" do
      item = media_item_fixture(%{type: "tv_show", title: "Show C"})
      tvdb_lib = library_path_fixture(%{type: "series", tv_metadata_source: :tvdb})
      tmdb_lib = library_path_fixture(%{type: "mixed", tv_metadata_source: :tmdb})
      media_file_fixture(%{media_item_id: item.id, library_path_id: tvdb_lib.id})
      episode = episode_fixture(%{media_item_id: item.id, season_number: 1, episode_number: 1})
      media_file_fixture(%{episode_id: episode.id, library_path_id: tmdb_lib.id})

      assert Media.resolve_library_provider(item) == :ambiguous
    end

    test "is :none when the show is in no series/mixed library" do
      item = media_item_fixture(%{type: "tv_show", title: "Show D"})
      assert Media.resolve_library_provider(item) == :none
    end
  end

  describe "provider_refresh_decision/1 (U6)" do
    import Mydia.MediaFixtures
    import Mydia.SettingsFixtures

    test "re-fetches when stored source matches the library provider" do
      item = decision_tv_in_library(:tvdb, :tvdb)
      assert Media.provider_refresh_decision(item) == :refetch
    end

    test "re-identifies when the library provider differs from stored source" do
      item = decision_tv_in_library(:tvdb, :tmdb)
      assert Media.provider_refresh_decision(item) == {:reidentify, :tmdb}
    end

    test "re-fetches (no re-identify) when libraries are ambiguous" do
      item = media_item_fixture(%{type: "tv_show", title: "Amb", metadata_source: :tvdb})
      a = library_path_fixture(%{type: "series", tv_metadata_source: :tvdb})
      b = library_path_fixture(%{type: "series", tv_metadata_source: :tmdb})
      media_file_fixture(%{media_item_id: item.id, library_path_id: a.id})
      ep = episode_fixture(%{media_item_id: item.id, season_number: 1, episode_number: 1})
      media_file_fixture(%{episode_id: ep.id, library_path_id: b.id})

      assert Media.provider_refresh_decision(item) == :refetch
    end

    test "re-fetches when metadata_source is nil (pre-feature item)" do
      item = decision_tv_in_library(nil, :tmdb)
      assert Media.provider_refresh_decision(item) == :refetch
    end

    test "movies always re-fetch" do
      item = media_item_fixture(%{type: "movie", title: "A Movie", year: 2020})
      assert Media.provider_refresh_decision(item) == :refetch
    end

    defp decision_tv_in_library(metadata_source, lib_provider) do
      item =
        media_item_fixture(%{
          type: "tv_show",
          title: "Decision Show #{System.unique_integer([:positive])}",
          metadata_source: metadata_source
        })

      lib = library_path_fixture(%{type: "series", tv_metadata_source: lib_provider})
      media_file_fixture(%{media_item_id: item.id, library_path_id: lib.id})
      item
    end
  end

  describe "find_reidentify_candidate/3 (U6)" do
    import Mydia.MediaFixtures

    setup do
      bypass = Bypass.open()

      config = %{
        type: :metadata_relay,
        base_url: "http://localhost:#{bypass.port}",
        options: %{language: "en-US", include_adult: false}
      }

      %{bypass: bypass, config: config}
    end

    test "returns :confident for a near-exact title and matching year",
         %{bypass: bypass, config: config} do
      item = media_item_fixture(%{type: "tv_show", title: "Ghost in the Shell", year: 2002})

      Bypass.expect(bypass, "GET", "/tmdb/tv/search", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(tmdb_tv_search(9001, "Ghost in the Shell", 2002)))
      end)

      assert {:confident, candidate} = Media.find_reidentify_candidate(item, :tmdb, config)
      assert candidate.provider_id == "9001"
    end

    test "returns :needs_picker when no candidate matches confidently",
         %{bypass: bypass, config: config} do
      item = media_item_fixture(%{type: "tv_show", title: "Ghost in the Shell", year: 2002})

      Bypass.expect(bypass, "GET", "/tmdb/tv/search", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(tmdb_tv_search(9002, "Totally Different Show", 1990))
        )
      end)

      assert {:needs_picker, candidates} = Media.find_reidentify_candidate(item, :tmdb, config)
      assert length(candidates) == 1
    end

    defp tmdb_tv_search(id, name, year) do
      %{
        "results" => [
          %{"id" => id, "name" => name, "first_air_date" => "#{year}-01-01", "overview" => "x"}
        ]
      }
    end
  end

  describe "adopt_provider_switch/4 (U7)" do
    import Mydia.MediaFixtures
    import Mydia.SettingsFixtures

    setup do
      bypass = Bypass.open()

      config = %{
        type: :metadata_relay,
        base_url: "http://localhost:#{bypass.port}",
        options: %{language: "en-US", include_adult: false}
      }

      item =
        media_item_fixture(%{
          type: "tv_show",
          title: "Switch Show",
          year: 2010,
          tvdb_id: 555,
          metadata_source: :tvdb
        })

      lib = library_path_fixture(%{type: "series", tv_metadata_source: :tmdb})

      old_episode =
        episode_fixture(%{media_item_id: item.id, season_number: 1, episode_number: 1})

      media_file =
        media_file_fixture(%{
          episode_id: old_episode.id,
          library_path_id: lib.id,
          relative_path: "Switch Show/Season 01/Switch.Show.S01E01.1080p.mkv"
        })

      # Unique id per test: the metadata cache is keyed by provider_id and
      # persists across tests, so a fixed id would leak cached season data.
      new_id = System.unique_integer([:positive])

      candidate = %Mydia.Metadata.Structs.SearchResult{
        provider_id: to_string(new_id),
        provider: :metadata_relay,
        media_type: :tv_show,
        title: "Switch Show",
        year: 2010
      }

      %{
        bypass: bypass,
        config: config,
        item: item,
        old_episode: old_episode,
        media_file: media_file,
        candidate: candidate,
        new_id: new_id
      }
    end

    test "swaps provider ids, recreates episodes, and re-links files", ctx do
      stub_tmdb_show(ctx.bypass, ctx.new_id, "Switch Show", 2010)
      stub_tmdb_season(ctx.bypass, ctx.new_id, 1, [1, 2])

      assert {:ok, reconciled} =
               Media.adopt_provider_switch(ctx.item, ctx.candidate, :tmdb, ctx.config)

      # Provider ids swapped; provenance updated.
      assert reconciled.tmdb_id == ctx.new_id
      assert is_nil(reconciled.tvdb_id)
      assert reconciled.metadata_source == :tmdb

      # Episodes recreated under the new provider's numbering.
      episodes = Media.list_episodes(reconciled.id)
      numbers = episodes |> Enum.map(& &1.episode_number) |> Enum.sort()
      assert numbers == [1, 2]

      # The old episode row is gone (wiped, not left parallel).
      assert is_nil(Mydia.Repo.get(Mydia.Media.Episode, ctx.old_episode.id))

      # The previously episode-linked file is still attached to the show
      # (re-linked by filename), not orphaned with both ids null.
      media_file = Mydia.Repo.get(Mydia.Library.MediaFile, ctx.media_file.id)
      refute is_nil(media_file)
      refute is_nil(media_file.episode_id) and is_nil(media_file.media_item_id)

      relinked = Mydia.Repo.get(Mydia.Media.Episode, media_file.episode_id)
      assert relinked.season_number == 1
      assert relinked.episode_number == 1
    end

    test "a failed new-provider fetch leaves existing episodes intact", ctx do
      Bypass.expect(ctx.bypass, "GET", "/tmdb/tv/shows/#{ctx.new_id}", fn conn ->
        Plug.Conn.resp(conn, 404, "{}")
      end)

      assert {:error, _reason} =
               Media.adopt_provider_switch(ctx.item, ctx.candidate, :tmdb, ctx.config)

      # No mutation: old episode and provider ids untouched.
      assert Mydia.Repo.get(Mydia.Media.Episode, ctx.old_episode.id)
      item = Media.get_media_item!(ctx.item.id)
      assert item.tvdb_id == 555
      assert is_nil(item.tmdb_id)
      assert item.metadata_source == :tvdb
    end

    test "an empty season set aborts without wiping episodes", ctx do
      stub_tmdb_show(ctx.bypass, ctx.new_id, "Switch Show", 2010)
      stub_tmdb_season(ctx.bypass, ctx.new_id, 1, [])

      assert {:error, :no_episodes} =
               Media.adopt_provider_switch(ctx.item, ctx.candidate, :tmdb, ctx.config)

      assert Mydia.Repo.get(Mydia.Media.Episode, ctx.old_episode.id)
    end

    defp stub_tmdb_show(bypass, id, name, year) do
      body = %{
        "id" => id,
        "name" => name,
        "first_air_date" => "#{year}-01-01",
        "overview" => "x",
        "credits" => %{"cast" => [], "crew" => []},
        "genres" => [],
        "seasons" => [%{"season_number" => 1, "name" => "Season 1"}]
      }

      Bypass.expect(bypass, "GET", "/tmdb/tv/shows/#{id}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(body))
      end)
    end

    defp stub_tmdb_season(bypass, id, season_number, episode_numbers) do
      episodes =
        Enum.map(episode_numbers, fn n ->
          %{
            "season_number" => season_number,
            "episode_number" => n,
            "name" => "Episode #{n}",
            "air_date" => "2010-01-0#{n}"
          }
        end)

      body = %{"season_number" => season_number, "episodes" => episodes}

      Bypass.expect(bypass, "GET", "/tmdb/tv/shows/#{id}/#{season_number}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(body))
      end)
    end
  end
end
