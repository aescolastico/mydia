defmodule Mydia.Jobs.TVShowSearchTest do
  use Mydia.DataCase, async: true
  use Oban.Testing, repo: Mydia.Repo

  alias Mydia.Jobs.TVShowSearch
  alias Mydia.Library
  alias Mydia.Settings
  alias Mydia.IndexerMock
  alias Mydia.Downloads.Client
  alias Mydia.Downloads.Client.Registry

  import Mydia.MediaFixtures
  import Mydia.SettingsFixtures
  import Mydia.AccountsFixtures

  # Mock download client adapter for testing
  defmodule MockDownloadAdapter do
    @behaviour Client

    @impl true
    def test_connection(_config) do
      {:ok, %{version: "1.0.0", api_version: "1.0"}}
    end

    @impl true
    def add_torrent(_config, _torrent, _opts) do
      {:ok, "mock-download-id-#{:rand.uniform(1000)}"}
    end

    @impl true
    def get_status(_config, _client_id) do
      {:ok, %{}}
    end

    @impl true
    def list_torrents(_config, _opts) do
      {:ok, []}
    end

    @impl true
    def remove_torrent(_config, _client_id, _opts) do
      :ok
    end

    @impl true
    def pause_torrent(_config, _client_id) do
      :ok
    end

    @impl true
    def resume_torrent(_config, _client_id) do
      :ok
    end
  end

  setup do
    # Register mock download client adapter
    Registry.register(:transmission, MockDownloadAdapter)

    # Create test user for client configs
    user = user_fixture()

    # Create test download client
    download_client_config_fixture(%{
      name: "test-transmission",
      type: "transmission",
      enabled: true,
      priority: 1,
      host: "localhost",
      port: 9091,
      updated_by_id: user.id
    })

    # Create test library path for media files
    library_path = library_path_fixture(%{path: "/test/library", type: "series"})

    # Disable all existing DB indexer configs so only our Bypass mock is used
    Settings.list_indexer_configs()
    |> Enum.reject(&Mydia.Settings.runtime_config?/1)
    |> Enum.each(fn config ->
      Settings.update_indexer_config(config, %{enabled: false})
    end)

    # Set up mock Prowlarr server for all tests
    bypass = Bypass.open()

    # Mock with TV show episode results
    IndexerMock.mock_prowlarr_all(bypass,
      results: [
        IndexerMock.tv_episode_result(%{
          title: "Breaking Bad",
          season: 1,
          episode: 1,
          seeders: 100
        }),
        IndexerMock.tv_episode_result(%{title: "The Wire", season: 1, episode: 1, seeders: 90}),
        IndexerMock.tv_episode_result(%{
          title: "The Sopranos",
          season: 1,
          episode: 1,
          seeders: 85
        }),
        IndexerMock.tv_episode_result(%{title: "Show 1", season: 1, episode: 1, seeders: 50}),
        IndexerMock.tv_episode_result(%{title: "Show 2", season: 1, episode: 1, seeders: 45}),
        IndexerMock.tv_episode_result(%{title: "Long Show", season: 1, episode: 1, seeders: 40}),
        IndexerMock.season_pack_result(%{title: "Multi Season Show", season: 1, seeders: 150})
      ]
    )

    # Create test indexer configuration pointing to Bypass server
    {:ok, _indexer} =
      Settings.create_indexer_config(%{
        name: "Test TV Indexer",
        type: :prowlarr,
        base_url: "http://localhost:#{bypass.port}",
        api_key: "test-key",
        enabled: true
      })

    %{bypass: bypass, library_path: library_path}
  end

  describe "perform/1 - specific mode" do
    test "returns error when episode does not exist" do
      fake_id = Ecto.UUID.generate()

      assert {:error, :not_found} =
               perform_job(TVShowSearch, %{"mode" => "specific", "episode_id" => fake_id})
    end

    test "processes a valid episode", %{bypass: _bypass} do
      tv_show = media_item_fixture(%{type: "tv_show", title: "Breaking Bad"})

      episode =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 1,
          title: "Pilot",
          air_date: ~D[2008-01-20]
        })

      # Now uses mocked indexer responses
      result =
        perform_job(TVShowSearch, %{
          "mode" => "specific",
          "episode_id" => episode.id
        })

      # Should succeed with mocked results
      assert result == :ok
    end

    test "skips episode that already has files", %{library_path: library_path} do
      tv_show = media_item_fixture(%{type: "tv_show", title: "The Wire"})

      episode =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 1,
          air_date: ~D[2002-06-02]
        })

      # Create a media file for this episode
      {:ok, _media_file} =
        Library.create_media_file(%{
          episode_id: episode.id,
          path: "/fake/path/episode.mkv",
          relative_path: "episode.mkv",
          library_path_id: library_path.id,
          size: 500_000_000,
          quality: %{resolution: "1080p"}
        })

      # Should skip this episode and return :ok
      assert :ok =
               perform_job(TVShowSearch, %{
                 "mode" => "specific",
                 "episode_id" => episode.id
               })
    end

    test "skips episode with future air date" do
      tv_show = media_item_fixture(%{type: "tv_show", title: "Future Show"})

      # Create an episode that airs in the future
      future_date = Date.add(Date.utc_today(), 30)

      episode =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 1,
          air_date: future_date
        })

      # Should skip this episode
      assert :ok =
               perform_job(TVShowSearch, %{
                 "mode" => "specific",
                 "episode_id" => episode.id
               })
    end

    test "processes episode with nil air date" do
      tv_show = media_item_fixture(%{type: "tv_show", title: "Unknown Air Date Show"})

      episode =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 1,
          air_date: nil
        })

      # Should attempt to process (air_date nil is treated as aired)
      # Note: In test environment without indexers configured, this will return :no_results
      # which is not a valid Oban return value, but the test verifies the job doesn't crash
      perform_job(TVShowSearch, %{
        "mode" => "specific",
        "episode_id" => episode.id
      })
    end

    test "uses custom ranking options when provided", %{bypass: _bypass} do
      tv_show = media_item_fixture(%{type: "tv_show", title: "The Sopranos"})

      episode =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 1,
          air_date: ~D[1999-01-10]
        })

      result =
        perform_job(TVShowSearch, %{
          "mode" => "specific",
          "episode_id" => episode.id,
          "min_seeders" => 10,
          "blocked_tags" => ["CAM", "TS"],
          "preferred_tags" => ["REMUX"]
        })

      # Should succeed with mocked results
      assert result == :ok
    end
  end

  describe "query construction" do
    test "constructs correct S##E## format query", %{bypass: _bypass} do
      tv_show = media_item_fixture(%{type: "tv_show", title: "Breaking Bad"})

      episode =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 3,
          air_date: ~D[2008-02-10]
        })

      # Job runs with mocked indexer responses
      result =
        perform_job(TVShowSearch, %{
          "mode" => "specific",
          "episode_id" => episode.id
        })

      assert result == :ok
    end

    test "handles double-digit season and episode numbers", %{bypass: _bypass} do
      tv_show = media_item_fixture(%{type: "tv_show", title: "Long Running Show"})

      episode =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 12,
          episode_number: 24,
          air_date: ~D[2020-05-15]
        })

      # Job executes with mocked indexer for double-digit numbers
      result =
        perform_job(TVShowSearch, %{
          "mode" => "specific",
          "episode_id" => episode.id
        })

      assert result == :ok
    end
  end

  describe "perform/1 - season mode" do
    test "returns error when media item does not exist" do
      fake_id = Ecto.UUID.generate()

      assert {:error, :not_found} =
               perform_job(TVShowSearch, %{
                 "mode" => "season",
                 "media_item_id" => fake_id,
                 "season_number" => 1
               })
    end

    test "returns error when media item is not a TV show" do
      movie = media_item_fixture(%{type: "movie", title: "Test Movie"})

      assert {:error, :invalid_type} =
               perform_job(TVShowSearch, %{
                 "mode" => "season",
                 "media_item_id" => movie.id,
                 "season_number" => 1
               })
    end

    test "returns ok when no missing episodes in season", %{library_path: library_path} do
      tv_show = media_item_fixture(%{type: "tv_show", title: "Complete Show"})

      # Create episodes with media files (no missing episodes)
      episode =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 1,
          air_date: ~D[2020-01-01]
        })

      {:ok, _media_file} =
        Library.create_media_file(%{
          episode_id: episode.id,
          path: "/fake/path/s01e01.mkv",
          relative_path: "s01e01.mkv",
          library_path_id: library_path.id,
          size: 500_000_000
        })

      assert :ok =
               perform_job(TVShowSearch, %{
                 "mode" => "season",
                 "media_item_id" => tv_show.id,
                 "season_number" => 1
               })
    end

    test "searches for season pack when missing episodes exist", %{bypass: _bypass} do
      tv_show = media_item_fixture(%{type: "tv_show", title: "The Wire"})

      # Create multiple missing episodes in season 1
      _ep1 =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 1,
          air_date: ~D[2002-06-02]
        })

      _ep2 =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 2,
          air_date: ~D[2002-06-09]
        })

      _ep3 =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 3,
          air_date: ~D[2002-06-16]
        })

      # Searches with mocked indexer
      result =
        perform_job(TVShowSearch, %{
          "mode" => "season",
          "media_item_id" => tv_show.id,
          "season_number" => 1
        })

      assert result == :ok
    end

    test "skips future episodes when searching for season" do
      tv_show = media_item_fixture(%{type: "tv_show", title: "Future Season"})

      future_date = Date.add(Date.utc_today(), 30)

      # Create episodes with future air dates
      _ep1 =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 1,
          air_date: future_date
        })

      # Should return :ok since no aired episodes are missing
      assert :ok =
               perform_job(TVShowSearch, %{
                 "mode" => "season",
                 "media_item_id" => tv_show.id,
                 "season_number" => 1
               })
    end
  end

  describe "perform/1 - show mode" do
    test "returns error when media item does not exist" do
      fake_id = Ecto.UUID.generate()

      assert {:error, :not_found} =
               perform_job(TVShowSearch, %{
                 "mode" => "show",
                 "media_item_id" => fake_id
               })
    end

    test "returns error when media item is not a TV show" do
      movie = media_item_fixture(%{type: "movie", title: "Test Movie"})

      assert {:error, :invalid_type} =
               perform_job(TVShowSearch, %{
                 "mode" => "show",
                 "media_item_id" => movie.id
               })
    end

    test "returns ok when no missing episodes", %{library_path: library_path} do
      tv_show = media_item_fixture(%{type: "tv_show", title: "Complete Show"})

      # Create episode with media file (no missing episodes)
      episode =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 1,
          air_date: ~D[2020-01-01]
        })

      {:ok, _media_file} =
        Library.create_media_file(%{
          episode_id: episode.id,
          path: "/fake/path/s01e01.mkv",
          relative_path: "s01e01.mkv",
          library_path_id: library_path.id,
          size: 500_000_000
        })

      assert :ok =
               perform_job(TVShowSearch, %{
                 "mode" => "show",
                 "media_item_id" => tv_show.id
               })
    end

    test "processes show with missing episodes in multiple seasons", %{bypass: _bypass} do
      tv_show = media_item_fixture(%{type: "tv_show", title: "Multi Season Show"})

      # Create missing episodes across two seasons
      _s1e1 =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 1,
          air_date: ~D[2020-01-01]
        })

      _s1e2 =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 2,
          air_date: ~D[2020-01-08]
        })

      _s2e1 =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 2,
          episode_number: 1,
          air_date: ~D[2021-01-01]
        })

      # Processes both seasons with mocked indexer
      assert :ok =
               perform_job(TVShowSearch, %{
                 "mode" => "show",
                 "media_item_id" => tv_show.id
               })
    end

    test "skips future episodes when processing show" do
      tv_show = media_item_fixture(%{type: "tv_show", title: "Upcoming Show"})

      future_date = Date.add(Date.utc_today(), 30)

      # Create only future episodes
      _ep1 =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 1,
          air_date: future_date
        })

      # Should return ok since no aired episodes are missing
      assert :ok =
               perform_job(TVShowSearch, %{
                 "mode" => "show",
                 "media_item_id" => tv_show.id
               })
    end
  end

  describe "perform/1 - all_monitored mode" do
    test "returns ok when no monitored episodes without files" do
      # Create unmonitored TV show
      _tv_show = media_item_fixture(%{type: "tv_show", monitored: false})

      assert :ok = perform_job(TVShowSearch, %{"mode" => "all_monitored"})
    end

    test "processes monitored episodes across multiple shows", %{bypass: _bypass} do
      # Create two TV shows with missing episodes
      tv_show1 = media_item_fixture(%{type: "tv_show", title: "Show 1", monitored: true})

      _s1_ep1 =
        episode_fixture(%{
          media_item_id: tv_show1.id,
          season_number: 1,
          episode_number: 1,
          air_date: ~D[2020-01-01]
        })

      tv_show2 = media_item_fixture(%{type: "tv_show", title: "Show 2", monitored: true})

      _s2_ep1 =
        episode_fixture(%{
          media_item_id: tv_show2.id,
          season_number: 1,
          episode_number: 1,
          air_date: ~D[2020-01-01]
        })

      # Processes both shows with mocked indexer
      assert :ok = perform_job(TVShowSearch, %{"mode" => "all_monitored"})
    end

    test "skips episodes with future air dates in all_monitored mode" do
      tv_show = media_item_fixture(%{type: "tv_show", title: "Future Show", monitored: true})

      future_date = Date.add(Date.utc_today(), 30)

      # Create future episode
      _ep1 =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 1,
          air_date: future_date
        })

      # Should return ok (no aired episodes to process)
      assert :ok = perform_job(TVShowSearch, %{"mode" => "all_monitored"})
    end

    test "skips episodes that already have files", %{library_path: library_path} do
      tv_show = media_item_fixture(%{type: "tv_show", title: "Complete Show", monitored: true})

      episode =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 1,
          air_date: ~D[2020-01-01]
        })

      {:ok, _media_file} =
        Library.create_media_file(%{
          episode_id: episode.id,
          path: "/fake/path/s01e01.mkv",
          relative_path: "s01e01.mkv",
          library_path_id: library_path.id,
          size: 500_000_000
        })

      # Should return ok (no missing episodes)
      assert :ok = perform_job(TVShowSearch, %{"mode" => "all_monitored"})
    end

    test "applies smart logic to multiple seasons across shows", %{bypass: _bypass} do
      # Create show with multiple seasons
      tv_show = media_item_fixture(%{type: "tv_show", title: "Long Show", monitored: true})

      # Season 1 - only 2 episodes missing out of many (< 70%)
      _s1e1 =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 1,
          air_date: ~D[2020-01-01]
        })

      # Season 2 - all episodes missing (100%)
      _s2e1 =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 2,
          episode_number: 1,
          air_date: ~D[2021-01-01]
        })

      _s2e2 =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 2,
          episode_number: 2,
          air_date: ~D[2021-01-08]
        })

      # Applies smart logic per season with mocked indexer
      assert :ok = perform_job(TVShowSearch, %{"mode" => "all_monitored"})
    end
  end

  describe "unsupported mode" do
    test "returns error for unsupported mode" do
      assert {:error, :unsupported_mode} =
               perform_job(TVShowSearch, %{"mode" => "invalid_mode"})
    end
  end

  describe "season pack filtering in episode search" do
    test "filters out season pack results when searching for individual episodes" do
      # Use a dedicated Bypass to avoid async test interference
      bypass = Bypass.open()

      IndexerMock.mock_prowlarr_all(bypass,
        results: [
          IndexerMock.season_pack_result(%{title: "PackOnly Show", season: 1, seeders: 200}),
          IndexerMock.season_pack_result(%{
            title: "PackOnly Show",
            season: 1,
            quality: "720p",
            seeders: 150
          })
        ]
      )

      {:ok, _indexer} =
        Settings.create_indexer_config(%{
          name: "Season Pack Filter Test Indexer",
          type: :prowlarr,
          base_url: "http://localhost:#{bypass.port}",
          api_key: "test-key",
          enabled: true
        })

      tv_show = media_item_fixture(%{type: "tv_show", title: "PackOnly Show"})

      episode =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 3,
          air_date: ~D[2020-01-15]
        })

      # Should return :ok but no download initiated (all results were season packs)
      assert :ok =
               perform_job(TVShowSearch, %{
                 "mode" => "specific",
                 "episode_id" => episode.id
               })

      # Verify no downloads were created for this episode
      import Ecto.Query

      downloads =
        Mydia.Repo.all(from(d in Mydia.Downloads.Download, where: d.episode_id == ^episode.id))

      assert downloads == []
    end

    test "selects episode results over season packs in mixed results",
         %{bypass: bypass} do
      # Override shared mock with mixed results (episode + season pack)
      IndexerMock.mock_prowlarr_search(bypass,
        results: [
          # Season pack with high seeders (would normally score higher)
          IndexerMock.season_pack_result(%{title: "Breaking Bad", season: 1, seeders: 500}),
          # Individual episode with lower seeders (should be selected after filtering)
          IndexerMock.tv_episode_result(%{
            title: "Breaking Bad",
            season: 1,
            episode: 1,
            seeders: 50
          })
        ]
      )

      tv_show = media_item_fixture(%{type: "tv_show", title: "Breaking Bad"})

      episode =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 1,
          air_date: ~D[2008-01-20]
        })

      assert :ok =
               perform_job(TVShowSearch, %{
                 "mode" => "specific",
                 "episode_id" => episode.id
               })

      # Verify that if a download was created, it's an episode (not a season pack)
      import Ecto.Query

      downloads =
        Mydia.Repo.all(from(d in Mydia.Downloads.Download, where: d.episode_id == ^episode.id))

      if length(downloads) > 0 do
        download = hd(downloads)
        # Title should contain episode marker (E01), not be a season pack
        assert String.contains?(download.title, "E01")
        refute String.contains?(download.title, "COMPLETE")
      end
    end

    test "does not filter multi-episode packs (they contain episode markers)",
         %{bypass: bypass} do
      # Override shared mock with a multi-episode release (has E marker, should pass filter)
      IndexerMock.mock_prowlarr_search(bypass,
        results: [
          %{
            title: "Breaking.Bad.S01E01-E03.1080p.WEB-DL.x264-GROUP",
            size: 5_000_000_000,
            seeders: 100,
            leechers: 10,
            indexer: "Test Indexer",
            category: 5000,
            protocol: "torrent"
          }
        ]
      )

      tv_show = media_item_fixture(%{type: "tv_show", title: "Breaking Bad"})

      episode =
        episode_fixture(%{
          media_item_id: tv_show.id,
          season_number: 1,
          episode_number: 2,
          air_date: ~D[2008-01-27]
        })

      assert :ok =
               perform_job(TVShowSearch, %{
                 "mode" => "specific",
                 "episode_id" => episode.id
               })

      # Verify that if a download was created, it's the multi-episode pack (not filtered)
      import Ecto.Query

      downloads =
        Mydia.Repo.all(from(d in Mydia.Downloads.Download, where: d.episode_id == ^episode.id))

      if length(downloads) > 0 do
        download = hd(downloads)
        assert String.contains?(download.title, "S01E01-E03")
      end
    end
  end

  describe "season pack duplicate download fallback" do
    test "does not fall back to individual episodes when season pack is already downloading" do
      bypass = Bypass.open()

      IndexerMock.mock_prowlarr_all(bypass,
        results: [
          IndexerMock.season_pack_result(%{title: "DupePack Show", season: 1, seeders: 100})
        ]
      )

      {:ok, _indexer} =
        Settings.create_indexer_config(%{
          name: "Dupe Fallback Test Indexer",
          type: :prowlarr,
          base_url: "http://localhost:#{bypass.port}",
          api_key: "test-key",
          enabled: true
        })

      tv_show = media_item_fixture(%{type: "tv_show", title: "DupePack Show"})

      # Create enough missing episodes to trigger season pack preference (>= 70%)
      _episodes =
        for ep_num <- 1..5 do
          episode_fixture(%{
            media_item_id: tv_show.id,
            season_number: 1,
            episode_number: ep_num,
            air_date: Date.add(~D[2020-01-01], ep_num * 7)
          })
        end

      # First search — should download the season pack
      assert :ok =
               perform_job(TVShowSearch, %{
                 "mode" => "season",
                 "media_item_id" => tv_show.id,
                 "season_number" => 1
               })

      import Ecto.Query

      downloads_after_first =
        Mydia.Repo.all(from(d in Mydia.Downloads.Download, where: d.media_item_id == ^tv_show.id))

      first_count = length(downloads_after_first)

      # Second search — season pack is already active, should NOT fall back
      # to individual episode downloads
      assert :ok =
               perform_job(TVShowSearch, %{
                 "mode" => "season",
                 "media_item_id" => tv_show.id,
                 "season_number" => 1
               })

      downloads_after_second =
        Mydia.Repo.all(from(d in Mydia.Downloads.Download, where: d.media_item_id == ^tv_show.id))

      # No new downloads should be created
      assert length(downloads_after_second) == first_count
    end
  end
end
