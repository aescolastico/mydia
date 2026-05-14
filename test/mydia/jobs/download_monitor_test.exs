defmodule Mydia.Jobs.DownloadMonitorTest do
  use Mydia.DataCase, async: true
  use Oban.Testing, repo: Mydia.Repo

  alias Mydia.Jobs.DownloadMonitor
  alias Mydia.Downloads
  import Mydia.MediaFixtures
  import Mydia.DownloadsFixtures

  describe "perform/1" do
    test "successfully monitors downloads with no active downloads" do
      setup_runtime_config([])
      assert :ok = perform_job(DownloadMonitor, %{})
    end

    test "handles no configured download clients gracefully" do
      setup_runtime_config([])

      # Create an active download
      media_item = media_item_fixture()
      download_fixture(%{media_item_id: media_item.id})

      assert :ok = perform_job(DownloadMonitor, %{})
    end

    test "successfully monitors active downloads" do
      setup_runtime_config([build_test_client_config()])
      media_item = media_item_fixture()

      # Create downloads with different completion states
      download_fixture(%{media_item_id: media_item.id})
      download_fixture(%{media_item_id: media_item.id})
      download_fixture(%{media_item_id: media_item.id, completed_at: DateTime.utc_now()})

      assert :ok = perform_job(DownloadMonitor, %{})
    end

    test "processes active and completed downloads" do
      setup_runtime_config([build_test_client_config()])
      media_item = media_item_fixture()

      # Create active downloads (will be marked missing since they don't exist in client)
      active1 = download_fixture(%{media_item_id: media_item.id})
      active2 = download_fixture(%{media_item_id: media_item.id})

      # Create completed and failed downloads (will be kept)
      completed =
        download_fixture(%{media_item_id: media_item.id, completed_at: DateTime.utc_now()})

      failed = download_fixture(%{media_item_id: media_item.id, error_message: "Failed"})

      # Job should complete successfully
      assert :ok = perform_job(DownloadMonitor, %{})

      # Active downloads should be marked with error_message (preserved for Issues tab)
      # Note: "status" is calculated dynamically, but error_message persists
      updated_active1 = Downloads.get_download!(active1.id)
      updated_active2 = Downloads.get_download!(active2.id)
      assert updated_active1.error_message =~ "Removed from download client"
      assert updated_active2.error_message =~ "Removed from download client"

      # Completed and failed downloads should still exist
      assert Downloads.get_download!(completed.id)
      assert Downloads.get_download!(failed.id)
    end

    test "marks downloads without an assigned client as missing" do
      setup_runtime_config([build_test_client_config()])
      media_item = media_item_fixture()

      # Create download without a download_client (will be marked as missing)
      download =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: nil
        })

      assert :ok = perform_job(DownloadMonitor, %{})

      # Download should have error_message set (preserved for Issues tab)
      updated = Downloads.get_download!(download.id)
      assert updated.error_message =~ "Removed from download client"
    end

    test "marks downloads with non-existent client as missing" do
      setup_runtime_config([build_test_client_config()])
      media_item = media_item_fixture()

      # Create download with a client that doesn't exist in config
      download =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: "NonExistentClient",
          download_client_id: "test123"
        })

      assert :ok = perform_job(DownloadMonitor, %{})

      # Download should have error_message set (preserved for Issues tab)
      updated = Downloads.get_download!(download.id)
      assert updated.error_message =~ "NonExistentClient"
    end

    test "processes multiple downloads in a single run" do
      setup_runtime_config([build_test_client_config()])
      media_item = media_item_fixture()

      # Create multiple downloads (will be marked missing since they don't exist in client)
      d1 =
        download_fixture(%{
          media_item_id: media_item.id,
          title: "Download 1"
        })

      d2 =
        download_fixture(%{
          media_item_id: media_item.id,
          title: "Download 2"
        })

      d3 = download_fixture(%{media_item_id: media_item.id, title: "Download 3"})

      # Should process all downloads without crashing
      assert :ok = perform_job(DownloadMonitor, %{})

      # All downloads should have error_message set (preserved for Issues tab)
      assert Downloads.get_download!(d1.id).error_message =~ "Removed from download client"
      assert Downloads.get_download!(d2.id).error_message =~ "Removed from download client"
      assert Downloads.get_download!(d3.id).error_message =~ "Removed from download client"
    end

    test "marks downloads from disabled clients as missing" do
      # Configure a disabled client
      disabled_client = %{
        build_test_client_config()
        | name: "DisabledClient",
          enabled: false
      }

      setup_runtime_config([disabled_client])
      media_item = media_item_fixture()

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: "DisabledClient",
          download_client_id: "test123"
        })

      assert :ok = perform_job(DownloadMonitor, %{})

      # Download should have error_message set since disabled clients are not queried
      updated = Downloads.get_download!(download.id)
      assert updated.error_message =~ "DisabledClient"
    end

    test "sorts download clients by priority" do
      # Configure multiple clients with different priorities
      client1 = %{build_test_client_config() | name: "Client1", priority: 3}
      client2 = %{build_test_client_config() | name: "Client2", priority: 1}
      client3 = %{build_test_client_config() | name: "Client3", priority: 2}

      setup_runtime_config([client1, client2, client3])

      # Job should complete successfully with clients sorted by priority
      assert :ok = perform_job(DownloadMonitor, %{})
    end

    test "handles downloads for different client types" do
      setup_runtime_config([
        build_test_client_config(%{name: "qBit", type: :qbittorrent}),
        build_test_client_config(%{name: "Trans", type: :transmission})
      ])

      media_item = media_item_fixture()

      download_fixture(%{
        media_item_id: media_item.id,
        download_client: "qBit",
        download_client_id: "hash1"
      })

      download_fixture(%{
        media_item_id: media_item.id,
        download_client: "Trans",
        download_client_id: "id2"
      })

      assert :ok = perform_job(DownloadMonitor, %{})
    end

    test "does NOT mark downloads missing when their client is unreachable" do
      # Client is configured by name but unreachable on the network. This is the
      # exact failure mode behind the recurring "qBittorrent downloads vanish"
      # reports: a brief client restart used to flag every active download as
      # missing within a single monitor cycle.
      setup_runtime_config([
        build_test_client_config(%{name: "qBit-down", host: "127.0.0.1", port: 1})
      ])

      media_item = media_item_fixture()

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: "qBit-down",
          download_client_id: "abc123def456abc123def456abc123def456abcd"
        })

      assert :ok = perform_job(DownloadMonitor, %{})

      # The download must NOT be marked missing — we can't tell from an
      # unreachable client whether the torrent is gone or not.
      updated = Downloads.get_download!(download.id)
      assert is_nil(updated.error_message)
      assert is_nil(updated.completed_at)
    end
  end

  describe "missing download detection" do
    test "marks downloads that no longer exist in any client as missing" do
      # Setup with no actual clients (simulates missing downloads)
      setup_runtime_config([])

      media_item = media_item_fixture()

      # Create a download that exists in DB but not in any client
      download =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: "test-client",
          download_client_id: "missing-123"
        })

      # Verify download exists before job runs
      assert Downloads.get_download!(download.id)

      # Run the job
      assert :ok = perform_job(DownloadMonitor, %{})

      # Download should have error_message set (preserved for Issues tab)
      updated = Downloads.get_download!(download.id)
      assert updated.error_message =~ "Removed from download client"
      assert updated.error_message =~ "test-client"
    end

    test "does not remove downloads that are already completed" do
      setup_runtime_config([])

      media_item = media_item_fixture()

      # Create a completed download
      download =
        download_fixture(%{
          media_item_id: media_item.id,
          completed_at: DateTime.utc_now()
        })

      # Run the job
      assert :ok = perform_job(DownloadMonitor, %{})

      # Completed download should still exist (status will be "completed")
      assert Downloads.get_download!(download.id)
    end

    test "does not remove downloads that have error messages" do
      setup_runtime_config([])

      media_item = media_item_fixture()

      # Create a failed download
      download =
        download_fixture(%{
          media_item_id: media_item.id,
          error_message: "Download failed"
        })

      # Run the job
      assert :ok = perform_job(DownloadMonitor, %{})

      # Failed download should still exist (status will be "failed")
      assert Downloads.get_download!(download.id)
    end

    test "marks multiple missing downloads in a single run" do
      setup_runtime_config([])

      media_item = media_item_fixture()

      # Create multiple downloads that don't exist in any client
      download1 =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: "test-client",
          download_client_id: "missing-1"
        })

      download2 =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: "test-client",
          download_client_id: "missing-2"
        })

      download3 =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: "test-client",
          download_client_id: "missing-3"
        })

      # Run the job
      assert :ok = perform_job(DownloadMonitor, %{})

      # All missing downloads should have error_message set (preserved for Issues tab)
      assert Downloads.get_download!(download1.id).error_message =~ "Removed from download client"
      assert Downloads.get_download!(download2.id).error_message =~ "Removed from download client"
      assert Downloads.get_download!(download3.id).error_message =~ "Removed from download client"
    end

    test "handles mix of missing, active, and completed downloads" do
      setup_runtime_config([])

      media_item = media_item_fixture()

      # Create a missing download (will be marked missing)
      missing_download =
        download_fixture(%{
          media_item_id: media_item.id,
          title: "Missing Download"
        })

      # Create a completed download (will be kept)
      completed_download =
        download_fixture(%{
          media_item_id: media_item.id,
          title: "Completed Download",
          completed_at: DateTime.utc_now()
        })

      # Create a failed download (will be kept)
      failed_download =
        download_fixture(%{
          media_item_id: media_item.id,
          title: "Failed Download",
          error_message: "Download failed in client"
        })

      # Run the job
      assert :ok = perform_job(DownloadMonitor, %{})

      # The missing download should have error_message set (preserved for Issues tab)
      updated_missing = Downloads.get_download!(missing_download.id)
      assert updated_missing.error_message =~ "Removed from download client"

      # Completed and failed downloads should still exist unchanged
      assert Downloads.get_download!(completed_download.id)
      assert Downloads.get_download!(failed_download.id)
    end

    test "broadcasts download update when marking missing download" do
      setup_runtime_config([])

      media_item = media_item_fixture()

      _download =
        download_fixture(%{
          media_item_id: media_item.id
        })

      # Subscribe to download updates
      Phoenix.PubSub.subscribe(Mydia.PubSub, "downloads")

      # Run the job
      assert :ok = perform_job(DownloadMonitor, %{})

      # Should receive update notification
      assert_received {:download_updated, _download_id}
    end
  end

  describe "stuck download detection" do
    test "detects and flags downloads that completed but never imported" do
      setup_runtime_config([])
      media_item = media_item_fixture()

      # Create a stuck download - completed more than 1 hour ago but never imported
      two_hours_ago = DateTime.add(DateTime.utc_now(), -2, :hour)

      stuck_download =
        download_fixture(%{
          media_item_id: media_item.id,
          title: "Stuck Download",
          download_client: "test-client",
          download_client_id: "stuck-123",
          completed_at: two_hours_ago,
          imported_at: nil,
          import_failed_at: nil
        })

      # Verify download exists and has no failure before job runs
      assert Downloads.get_download!(stuck_download.id)
      assert is_nil(stuck_download.import_failed_at)

      # Run the job
      assert :ok = perform_job(DownloadMonitor, %{})

      # Stuck download should now have import_failed_at set
      updated = Downloads.get_download!(stuck_download.id)
      assert updated.import_failed_at != nil
      assert updated.import_last_error =~ "Import stalled"
    end

    test "enqueues import retry job for stuck downloads" do
      setup_runtime_config([])
      media_item = media_item_fixture()

      # Create a stuck download
      two_hours_ago = DateTime.add(DateTime.utc_now(), -2, :hour)

      stuck_download =
        download_fixture(%{
          media_item_id: media_item.id,
          title: "Stuck Download",
          download_client: "test-client",
          download_client_id: "stuck-456",
          completed_at: two_hours_ago,
          imported_at: nil,
          import_failed_at: nil
        })

      # Run the job
      assert :ok = perform_job(DownloadMonitor, %{})

      # Should have enqueued a MediaImport job for the stuck download
      assert_enqueued(
        worker: Mydia.Jobs.MediaImport,
        args: %{"download_id" => stuck_download.id}
      )
    end

    test "does not flag recently completed downloads as stuck" do
      setup_runtime_config([])
      media_item = media_item_fixture()

      # Create a recently completed download (30 minutes ago - not stuck yet)
      thirty_minutes_ago = DateTime.add(DateTime.utc_now(), -30, :minute)

      recent_download =
        download_fixture(%{
          media_item_id: media_item.id,
          title: "Recent Download",
          download_client: "test-client",
          download_client_id: "recent-123",
          completed_at: thirty_minutes_ago,
          imported_at: nil,
          import_failed_at: nil
        })

      # Run the job
      assert :ok = perform_job(DownloadMonitor, %{})

      # Recent download should NOT have import_failed_at set
      # (but it will be marked as missing since it's not in any client)
      updated = Downloads.get_download!(recent_download.id)
      # import_failed_at should still be nil (not flagged as stuck)
      assert is_nil(updated.import_failed_at)
    end

    test "does not flag already imported downloads" do
      setup_runtime_config([])
      media_item = media_item_fixture()

      # Create an already imported download
      two_hours_ago = DateTime.add(DateTime.utc_now(), -2, :hour)

      imported_download =
        download_fixture(%{
          media_item_id: media_item.id,
          title: "Imported Download",
          download_client: "test-client",
          download_client_id: "imported-123",
          completed_at: two_hours_ago,
          imported_at: DateTime.utc_now(),
          import_failed_at: nil
        })

      # Run the job
      assert :ok = perform_job(DownloadMonitor, %{})

      # Should not be modified (already imported)
      updated = Downloads.get_download!(imported_download.id)
      assert is_nil(updated.import_failed_at)
      assert updated.imported_at != nil
    end

    test "does not flag downloads that already have import_failed_at" do
      setup_runtime_config([])
      media_item = media_item_fixture()

      # Create a download that already has a failure tracked
      two_hours_ago = DateTime.add(DateTime.utc_now(), -2, :hour)

      already_failed =
        download_fixture(%{
          media_item_id: media_item.id,
          title: "Already Failed Download",
          download_client: "test-client",
          download_client_id: "failed-123",
          completed_at: two_hours_ago,
          imported_at: nil,
          import_failed_at: two_hours_ago,
          import_last_error: "Previous failure"
        })

      # Run the job
      assert :ok = perform_job(DownloadMonitor, %{})

      # Should not be modified (already has failure)
      updated = Downloads.get_download!(already_failed.id)
      assert updated.import_last_error == "Previous failure"
    end
  end

  ## Helper Functions

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

  defp build_test_client_config(overrides \\ %{}) do
    defaults = %{
      name: "TestClient",
      type: :qbittorrent,
      enabled: true,
      priority: 1,
      host: "localhost",
      port: 8080,
      username: "admin",
      password: "admin",
      use_ssl: false,
      url_base: nil,
      category: nil,
      download_directory: nil
    }

    struct!(Mydia.Config.Schema.DownloadClient, Map.merge(defaults, overrides))
  end
end
