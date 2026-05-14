defmodule Mydia.Jobs.MediaImportTest do
  use Mydia.DataCase, async: true
  use Oban.Testing, repo: Mydia.Repo

  alias Mydia.Jobs.MediaImport
  alias Mydia.Settings
  import Mydia.MediaFixtures
  import Mydia.DownloadsFixtures

  @moduletag :tmp_dir

  describe "Args.parse/1" do
    test "parses save_path from job args" do
      args = MediaImport.Args.parse(%{"download_id" => "123", "save_path" => "/downloads/movie"})
      assert args.save_path == "/downloads/movie"
    end

    test "save_path is nil when not provided" do
      args = MediaImport.Args.parse(%{"download_id" => "123"})
      assert args.save_path == nil
    end

    test "save_path is nil when empty string is provided" do
      args = MediaImport.Args.parse(%{"download_id" => "123", "save_path" => ""})
      assert args.save_path == nil
    end

    test "preserves all other fields" do
      args =
        MediaImport.Args.parse(%{
          "download_id" => "123",
          "save_path" => "/path",
          "snooze_count" => 5,
          "use_hardlinks" => false,
          "move_files" => true,
          "rename_files" => true
        })

      assert args.download_id == "123"
      assert args.save_path == "/path"
      assert args.snooze_count == 5
      assert args.use_hardlinks == false
      assert args.move_files == true
      assert args.rename_files == true
    end
  end

  describe "detect_partial_pack/2" do
    test "returns 'partial_pack' when fewer episodes are imported than promised" do
      episode_id = Ecto.UUID.generate()

      download = %Mydia.Downloads.Download{
        id: Ecto.UUID.generate(),
        title: "Test.Show.S01.Pack",
        metadata: %{"episode_count" => 3}
      }

      # Only 1 distinct episode imported, but 3 were promised
      imported_files = [%{episode_id: episode_id}]

      assert "partial_pack" == MediaImport.detect_partial_pack(download, imported_files)
    end

    test "returns nil when all promised episodes are delivered" do
      ids = Enum.map(1..3, fn _ -> Ecto.UUID.generate() end)

      download = %Mydia.Downloads.Download{
        id: Ecto.UUID.generate(),
        title: "Test.Show.S01.Pack",
        metadata: %{"episode_count" => 3}
      }

      imported_files = Enum.map(ids, fn id -> %{episode_id: id} end)

      assert nil == MediaImport.detect_partial_pack(download, imported_files)
    end

    test "returns nil when metadata has no episode_count" do
      download = %Mydia.Downloads.Download{
        id: Ecto.UUID.generate(),
        title: "Test.Show.S01E01",
        metadata: %{}
      }

      imported_files = [%{episode_id: Ecto.UUID.generate()}]

      assert nil == MediaImport.detect_partial_pack(download, imported_files)
    end

    test "returns nil when download has no metadata" do
      download = %Mydia.Downloads.Download{
        id: Ecto.UUID.generate(),
        title: "Test.Show.S01E01",
        metadata: nil
      }

      imported_files = [%{episode_id: Ecto.UUID.generate()}]

      assert nil == MediaImport.detect_partial_pack(download, imported_files)
    end

    test "deduplicates episode_ids before comparing counts" do
      episode_id = Ecto.UUID.generate()

      download = %Mydia.Downloads.Download{
        id: Ecto.UUID.generate(),
        title: "Test.Show.S01.Pack",
        metadata: %{"episode_count" => 1}
      }

      # Two files pointing to the same episode — should count as 1 distinct episode
      imported_files = [%{episode_id: episode_id}, %{episode_id: episode_id}]

      assert nil == MediaImport.detect_partial_pack(download, imported_files)
    end

    test "ignores imported files without an episode_id (e.g. extras)" do
      episode_id = Ecto.UUID.generate()

      download = %Mydia.Downloads.Download{
        id: Ecto.UUID.generate(),
        title: "Test.Show.S01.Pack",
        metadata: %{"episode_count" => 2}
      }

      # One real episode + one file with no episode_id (extra/featurette)
      imported_files = [%{episode_id: episode_id}, %{episode_id: nil}]

      assert "partial_pack" == MediaImport.detect_partial_pack(download, imported_files)
    end
  end

  describe "perform/1" do
    test "schedules retry when download is not completed (first snooze)" do
      media_item = media_item_fixture()

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          status: "downloading",
          progress: 50
        })

      # First attempt with snooze_count = 0 should schedule a retry
      assert {:ok, :waiting_for_completion} =
               perform_job(MediaImport, %{"download_id" => download.id})

      # Verify a new job was scheduled with incremented snooze_count
      assert_enqueued(
        worker: MediaImport,
        args: %{"download_id" => download.id, "snooze_count" => 1}
      )
    end

    test "schedules retry with incremented snooze count when download not completed" do
      media_item = media_item_fixture()

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          status: "downloading",
          progress: 50
        })

      # With snooze_count = 5 should schedule a retry with snooze_count = 6
      assert {:ok, :waiting_for_completion} =
               perform_job(MediaImport, %{"download_id" => download.id, "snooze_count" => 5})

      assert_enqueued(
        worker: MediaImport,
        args: %{"download_id" => download.id, "snooze_count" => 6}
      )
    end

    test "marks as failed after max snooze count reached" do
      media_item = media_item_fixture()

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          status: "downloading",
          progress: 50
        })

      # With snooze_count = 12 (max), should fail and mark download
      assert {:error, :download_not_completed} =
               perform_job(MediaImport, %{"download_id" => download.id, "snooze_count" => 12})

      # Verify download now has import_failed_at set (visible in Issues tab)
      updated_download = Mydia.Downloads.get_download!(download.id)
      assert updated_download.import_failed_at != nil
      assert updated_download.import_last_error =~ "not yet complete"
    end

    test "proceeds with import when download completes during snooze period" do
      media_item = media_item_fixture(%{type: "movie", title: "Test Movie", year: 2024})

      # Start with incomplete download
      download =
        download_fixture(%{
          media_item_id: media_item.id,
          status: "downloading",
          progress: 50
        })

      # First check - not completed
      assert {:ok, :waiting_for_completion} =
               perform_job(MediaImport, %{"download_id" => download.id})

      # Simulate download completing
      {:ok, _} =
        Mydia.Downloads.update_download(download, %{
          status: "completed",
          progress: 100,
          completed_at: DateTime.utc_now()
        })

      # Second check with snooze_count = 1 - now should try to import
      # (will fail with :no_client since we don't have a mock, but proves it tries)
      assert {:error, :no_client} =
               perform_job(MediaImport, %{"download_id" => download.id, "snooze_count" => 1})
    end

    test "returns error if download does not exist" do
      fake_id = Ecto.UUID.generate()

      assert_raise Ecto.NoResultsError, fn ->
        perform_job(MediaImport, %{"download_id" => fake_id})
      end
    end

    test "returns error if download has no client info", %{tmp_dir: tmp_dir} do
      # Create a library path
      create_test_library_path(tmp_dir, :movies)

      media_item = media_item_fixture(%{type: "movie", title: "Test Movie", year: 2024})

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          status: "completed",
          completed_at: DateTime.utc_now(),
          download_client: nil,
          download_client_id: nil
        })

      assert {:error, :no_client} = perform_job(MediaImport, %{"download_id" => download.id})
    end

    test "returns error if no library path is configured", %{tmp_dir: _tmp_dir} do
      # Don't create any library paths
      # Use a DB-backed client config so it's isolated within this test's SQL sandbox,
      # avoiding races with other async tests that also write to Application env.
      {:ok, _} =
        Settings.create_download_client_config(%{
          name: "TestClient",
          type: :qbittorrent,
          host: "localhost",
          port: 8080,
          username: "test",
          password: "test",
          enabled: true,
          priority: 1
        })

      media_item = media_item_fixture(%{type: "movie", title: "Test Movie", year: 2024})

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          status: "completed",
          completed_at: DateTime.utc_now(),
          download_client: "TestClient",
          download_client_id: "test123"
        })

      # Note: The client config exists, but the actual download client isn't running.
      # The test will fail when trying to connect to the client, returning :client_error.
      # In a full test with mocking, we'd verify the library path check instead.

      assert {:error, :client_error} =
               perform_job(MediaImport, %{"download_id" => download.id})
    end

    test "successfully imports a movie file", %{tmp_dir: tmp_dir} do
      # Create a library path
      _library_path = create_test_library_path(tmp_dir, :movies)

      # Create a test download directory
      download_dir = Path.join(tmp_dir, "downloads")
      File.mkdir_p!(download_dir)

      # Create a test video file
      video_file = Path.join(download_dir, "Test.Movie.2024.1080p.mkv")
      File.write!(video_file, "fake video content")

      media_item = media_item_fixture(%{type: "movie", title: "Test Movie", year: 2024})

      _download =
        download_fixture(%{
          media_item_id: media_item.id,
          status: "completed",
          download_client: "TestClient",
          download_client_id: "test123"
        })

      # Setup runtime config with test client
      setup_runtime_config([build_test_client_config()])

      # Note: This test would need proper mocking of the download client adapter
      # to actually work. For now, it demonstrates the test structure.
      #
      # In a full implementation, we'd mock:
      # - Client.get_status to return %{save_path: video_file, ...}
      # - Or use a test adapter that we can control

      # Skip full execution for now since we'd need mocking infrastructure
      # assert {:ok, :imported} = perform_job(MediaImport, %{"download_id" => download.id})
    end

    test "successfully imports a TV episode file", %{tmp_dir: tmp_dir} do
      # Create a library path
      _library_path = create_test_library_path(tmp_dir, :series)

      # Create a test download directory
      download_dir = Path.join(tmp_dir, "downloads")
      File.mkdir_p!(download_dir)

      # Create a test video file
      video_file = Path.join(download_dir, "Show.S01E01.1080p.mkv")
      File.write!(video_file, "fake video content")

      media_item = media_item_fixture(%{type: "tv_show", title: "Test Show"})

      episode =
        episode_fixture(%{media_item_id: media_item.id, season_number: 1, episode_number: 1})

      _download =
        download_fixture(%{
          media_item_id: media_item.id,
          episode_id: episode.id,
          status: "completed",
          download_client: "TestClient",
          download_client_id: "test123"
        })

      # Setup runtime config with test client
      setup_runtime_config([build_test_client_config()])

      # Note: This test would need proper mocking of the download client adapter
      # Skip full execution for now
      # assert {:ok, :imported} = perform_job(MediaImport, %{"download_id" => download.id})
    end

    test "handles file conflicts gracefully", %{tmp_dir: _tmp_dir} do
      # This would test the conflict resolution logic
      # where a file already exists at the destination
    end

    test "handles video file filtering", %{tmp_dir: _tmp_dir} do
      # This would test that only video files are imported
      # and other files (like .nfo, .txt, etc.) are skipped
    end
  end

  describe "import with save_path fallback" do
    @tag :tmp_dir
    test "falls back to save_path when client query fails", %{tmp_dir: tmp_dir} do
      _library_path = create_test_library_path(tmp_dir, :movies)

      download_dir = Path.join(tmp_dir, "downloads")
      File.mkdir_p!(download_dir)
      video_file = Path.join(download_dir, "Fallback.Movie.2024.1080p.mkv")
      File.write!(video_file, "fake video content")

      media_item = media_item_fixture(%{type: "movie", title: "Fallback Movie", year: 2024})

      {:ok, _} =
        Settings.create_download_client_config(%{
          name: "FallbackClient",
          type: :qbittorrent,
          host: "nonexistent.invalid",
          port: 9999,
          username: "test",
          password: "test",
          enabled: true,
          priority: 1
        })

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          status: "completed",
          completed_at: DateTime.utc_now(),
          download_client: "FallbackClient",
          download_client_id: "test123"
        })

      assert {:ok, :imported} =
               perform_job(MediaImport, %{
                 "download_id" => download.id,
                 "save_path" => download_dir
               })

      updated = Mydia.Downloads.get_download!(download.id)
      assert updated.imported_at != nil
    end

    @tag :tmp_dir
    test "returns client_error when client fails and save_path is missing" do
      media_item = media_item_fixture(%{type: "movie", title: "No Save Path Movie", year: 2024})

      {:ok, _} =
        Settings.create_download_client_config(%{
          name: "NoSavePathClient",
          type: :qbittorrent,
          host: "nonexistent.invalid",
          port: 9999,
          username: "test",
          password: "test",
          enabled: true,
          priority: 1
        })

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          status: "completed",
          completed_at: DateTime.utc_now(),
          download_client: "NoSavePathClient",
          download_client_id: "test123"
        })

      assert {:error, :client_error} =
               perform_job(MediaImport, %{"download_id" => download.id})
    end

    @tag :tmp_dir
    test "returns client_error when client fails and save_path is empty string" do
      media_item = media_item_fixture(%{type: "movie", title: "Empty Path Movie", year: 2024})

      {:ok, _} =
        Settings.create_download_client_config(%{
          name: "EmptyPathClient",
          type: :qbittorrent,
          host: "nonexistent.invalid",
          port: 9999,
          username: "test",
          password: "test",
          enabled: true,
          priority: 1
        })

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          status: "completed",
          completed_at: DateTime.utc_now(),
          download_client: "EmptyPathClient",
          download_client_id: "test123"
        })

      assert {:error, :client_error} =
               perform_job(MediaImport, %{
                 "download_id" => download.id,
                 "save_path" => ""
               })
    end

    @tag :tmp_dir
    test "TV file with parsable season but nil episodes is flagged as unresolved", %{
      tmp_dir: tmp_dir
    } do
      # Regression: a file whose name parses to season=N but no episode
      # number (e.g. `Show.S01.mkv` or `Show Season 1 Foo.mkv`) used to
      # crash `import_file/5` with `FunctionClauseError` in `List.first/2`
      # because the clause did `List.first(parsed.episodes) || 1` without
      # guarding for nil. The job must route the file to the Issues tab
      # (via match_status: "unresolved_files") instead of raising or
      # silently importing as episode 1.
      _library_path = create_test_library_path(tmp_dir, :series)

      download_dir = Path.join(tmp_dir, "downloads")
      File.mkdir_p!(download_dir)

      # `Mystery.Show.S01.mkv` parses to season=1, episodes=nil.
      video_file = Path.join(download_dir, "Mystery.Show.S01.mkv")
      File.write!(video_file, "fake video content")

      media_item = media_item_fixture(%{type: "tv_show", title: "Mystery Show"})

      _episode =
        episode_fixture(%{
          media_item_id: media_item.id,
          season_number: 1,
          episode_number: 1
        })

      {:ok, _} =
        Settings.create_download_client_config(%{
          name: "NilEpisodesClient",
          type: :qbittorrent,
          host: "nonexistent.invalid",
          port: 9999,
          username: "test",
          password: "test",
          enabled: true,
          priority: 1
        })

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          status: "completed",
          completed_at: DateTime.utc_now(),
          download_client: "NilEpisodesClient",
          download_client_id: "nilep123"
        })

      assert {:error, :all_files_unresolved} =
               perform_job(MediaImport, %{
                 "download_id" => download.id,
                 "save_path" => download_dir
               })

      updated = Mydia.Downloads.get_download!(download.id)
      assert updated.match_status == "unresolved_files"
      assert [unresolved] = updated.metadata["unresolved_files"]
      assert unresolved["name"] == "Mystery.Show.S01.mkv"
      assert unresolved["parsed_season"] == 1
      assert unresolved["parsed_episode"] == nil
    end

    @tag :tmp_dir
    test "returns error when save_path points to non-existent path", %{tmp_dir: _tmp_dir} do
      media_item =
        media_item_fixture(%{type: "movie", title: "Bad Path Movie", year: 2024})

      {:ok, _} =
        Settings.create_download_client_config(%{
          name: "BadPathClient",
          type: :qbittorrent,
          host: "nonexistent.invalid",
          port: 9999,
          username: "test",
          password: "test",
          enabled: true,
          priority: 1
        })

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          status: "completed",
          completed_at: DateTime.utc_now(),
          download_client: "BadPathClient",
          download_client_id: "test123"
        })

      assert {:error, {:path_not_found, "/no/such/path/exists"}} =
               perform_job(MediaImport, %{
                 "download_id" => download.id,
                 "save_path" => "/no/such/path/exists"
               })

      updated = Mydia.Downloads.get_download!(download.id)
      assert updated.import_last_error =~ "Download path not found"
    end
  end

  # Helper functions

  defp create_test_library_path(base_path, type) do
    library_path = Path.join(base_path, "library")
    File.mkdir_p!(library_path)

    {:ok, path_record} =
      Settings.create_library_path(%{
        path: library_path,
        type: type,
        monitored: true
      })

    path_record
  end

  defp setup_runtime_config(download_clients) do
    config = %Mydia.Config.Schema{
      server: %Mydia.Config.Schema.Server{},
      database: %Mydia.Config.Schema.Database{},
      auth: %Mydia.Config.Schema.Auth{},
      media: %Mydia.Config.Schema.Media{},
      downloads: %Mydia.Config.Schema.Downloads{},
      logging: %Mydia.Config.Schema.Logging{},
      oban: %Mydia.Config.Schema.Oban{},
      download_clients: download_clients
    }

    Application.put_env(:mydia, :runtime_config, config)
  end

  defp build_test_client_config do
    %{
      name: "TestClient",
      type: :qbittorrent,
      host: "localhost",
      port: 8080,
      username: "test",
      password: "test",
      enabled: true,
      priority: 1,
      use_ssl: false
    }
  end

  describe "idempotency" do
    test "short-circuits with :ok when download.imported_at is already set" do
      media_item = media_item_fixture()

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: "AlreadyImportedClient",
          download_client_id: "imported-1"
        })

      {:ok, _} =
        Mydia.Downloads.update_download(download, %{
          completed_at: DateTime.utc_now(),
          imported_at: DateTime.utc_now()
        })

      # No client config exists; if we fell through to import_download/2 we
      # would hit {:error, :no_client}. The fact that we still return :ok
      # proves the short-circuit triggered first.
      assert :ok == perform_job(MediaImport, %{"download_id" => download.id})
    end

    test "duplicate inserts are deduped by Oban :unique" do
      media_item = media_item_fixture()

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: "UniqueClient",
          download_client_id: "unique-1"
        })

      args = %{"download_id" => download.id}

      assert {:ok, _job1} = args |> MediaImport.new() |> Oban.insert()
      assert {:ok, job2} = args |> MediaImport.new() |> Oban.insert()

      # Oban marks the duplicate insert with conflict?: true and reuses the
      # original job, so the queue still contains exactly one job for this
      # download.
      assert job2.conflict? == true
      assert [_one] = all_enqueued(worker: MediaImport, args: args)
    end

    test "scheduled (:scheduled) job dedupes against a freshly inserted webhook job" do
      # The snooze loop schedules :scheduled jobs while we wait for downloads
      # to finish. A webhook firing in that window must NOT enqueue a new
      # job — the unique config explicitly includes :scheduled for this
      # exact race.
      media_item = media_item_fixture()

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: "RaceClient",
          download_client_id: "race-1"
        })

      future = DateTime.add(DateTime.utc_now(), 300, :second)
      args = %{"download_id" => download.id}

      assert {:ok, _scheduled} =
               args |> MediaImport.new(scheduled_at: future) |> Oban.insert()

      assert {:ok, second} = args |> MediaImport.new() |> Oban.insert()

      assert second.conflict? == true
      assert [_one] = all_enqueued(worker: MediaImport, args: args)
    end
  end
end
