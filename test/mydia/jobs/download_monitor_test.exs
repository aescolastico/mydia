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

  describe "stall detection" do
    test "initializes last_progress_at the first time an active download is observed" do
      # No clients configured — the active download will be in "missing" state,
      # so it won't reach the stall-tracking path. Initialization happens only
      # for downloads whose client reports them. Validate that path via Bypass.
      {bypass, client_config} = start_sabnzbd_bypass()

      mock_sabnzbd_queue(bypass, [
        sabnzbd_queue_item("nzo-init-1", "test.nzb", size_mb: 100.0, mb_left: 50.0)
      ])

      media_item = media_item_fixture()

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: client_config.name,
          download_client_id: "nzo-init-1",
          last_progress_at: nil,
          last_known_bytes: 0
        })

      now = ~U[2026-05-14 12:00:00.000000Z]

      assert :ok = perform_job(DownloadMonitor, %{"now" => DateTime.to_iso8601(now)})

      updated = Downloads.get_download!(download.id)

      # First observation: last_progress_at initialized to `now`, bytes captured.
      assert updated.last_progress_at == now
      assert updated.last_known_bytes == round(50.0 * 1024 * 1024)
      assert is_nil(updated.import_failed_at)
    end

    test "updates last_progress_at and last_known_bytes when bytes increase" do
      {bypass, client_config} = start_sabnzbd_bypass()

      mock_sabnzbd_queue(bypass, [
        sabnzbd_queue_item("nzo-progress-1", "test.nzb", size_mb: 100.0, mb_left: 40.0)
      ])

      media_item = media_item_fixture()

      first_seen = ~U[2026-05-14 11:00:00.000000Z]
      prev_bytes = round(50.0 * 1024 * 1024)

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: client_config.name,
          download_client_id: "nzo-progress-1",
          last_progress_at: first_seen,
          last_known_bytes: prev_bytes
        })

      now = ~U[2026-05-14 12:00:00.000000Z]
      assert :ok = perform_job(DownloadMonitor, %{"now" => DateTime.to_iso8601(now)})

      updated = Downloads.get_download!(download.id)
      # Bytes increased from ~50MB to ~60MB — progress recorded, no stall flag.
      assert updated.last_progress_at == now
      assert updated.last_known_bytes == round(60.0 * 1024 * 1024)
      assert is_nil(updated.import_failed_at)
    end

    test "leaves last_progress_at unchanged when bytes are unchanged within grace window" do
      {bypass, client_config} = start_sabnzbd_bypass(incomplete_grace_minutes: 60)

      same_bytes = round(50.0 * 1024 * 1024)

      mock_sabnzbd_queue(bypass, [
        sabnzbd_queue_item("nzo-stuck-1", "test.nzb", size_mb: 100.0, mb_left: 50.0)
      ])

      media_item = media_item_fixture()

      first_seen = ~U[2026-05-14 11:30:00.000000Z]

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: client_config.name,
          download_client_id: "nzo-stuck-1",
          last_progress_at: first_seen,
          last_known_bytes: same_bytes
        })

      # 30 minutes after first_seen — still within the 60-minute grace window.
      now = ~U[2026-05-14 12:00:00.000000Z]
      assert :ok = perform_job(DownloadMonitor, %{"now" => DateTime.to_iso8601(now)})

      updated = Downloads.get_download!(download.id)
      assert updated.last_progress_at == first_seen
      assert updated.last_known_bytes == same_bytes
      assert is_nil(updated.import_failed_at)
    end

    test "does not stall at the exact grace boundary (strict >)" do
      {bypass, client_config} = start_sabnzbd_bypass(incomplete_grace_minutes: 60)

      same_bytes = round(50.0 * 1024 * 1024)

      mock_sabnzbd_queue(bypass, [
        sabnzbd_queue_item("nzo-boundary-1", "test.nzb", size_mb: 100.0, mb_left: 50.0)
      ])

      media_item = media_item_fixture()

      first_seen = ~U[2026-05-14 11:00:00.000000Z]
      # exactly 60 minutes later (== grace) — strict > means NOT yet stalled.
      now = ~U[2026-05-14 12:00:00.000000Z]

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: client_config.name,
          download_client_id: "nzo-boundary-1",
          last_progress_at: first_seen,
          last_known_bytes: same_bytes
        })

      assert :ok = perform_job(DownloadMonitor, %{"now" => DateTime.to_iso8601(now)})

      updated = Downloads.get_download!(download.id)
      assert is_nil(updated.import_failed_at)
      assert is_nil(updated.import_last_error)
    end

    test "flags as stalled when bytes are unchanged past the grace window" do
      {bypass, client_config} = start_sabnzbd_bypass(incomplete_grace_minutes: 60)

      same_bytes = round(50.0 * 1024 * 1024)

      mock_sabnzbd_queue(bypass, [
        sabnzbd_queue_item("nzo-stalled-1", "test.nzb", size_mb: 100.0, mb_left: 50.0)
      ])

      media_item = media_item_fixture()

      first_seen = ~U[2026-05-14 10:00:00.000000Z]
      # 61 minutes later — past the 60m grace window by 1 minute.
      now = ~U[2026-05-14 11:01:00.000000Z]

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: client_config.name,
          download_client_id: "nzo-stalled-1",
          last_progress_at: first_seen,
          last_known_bytes: same_bytes
        })

      assert :ok = perform_job(DownloadMonitor, %{"now" => DateTime.to_iso8601(now)})

      updated = Downloads.get_download!(download.id)
      # import_failed_at is :utc_datetime (second precision), so compare via diff.
      assert updated.import_failed_at != nil
      assert DateTime.diff(updated.import_failed_at, now, :second) == 0
      assert updated.import_last_error =~ "stalled"
      assert updated.import_last_error == "stalled after 60m without progress"
    end

    test "respects per-client incomplete_grace_minutes" do
      {bypass, client_config} = start_sabnzbd_bypass(incomplete_grace_minutes: 15)

      same_bytes = round(50.0 * 1024 * 1024)

      mock_sabnzbd_queue(bypass, [
        sabnzbd_queue_item("nzo-grace15-1", "test.nzb", size_mb: 100.0, mb_left: 50.0)
      ])

      media_item = media_item_fixture()

      first_seen = ~U[2026-05-14 10:00:00.000000Z]
      # 16 minutes later — past the 15m grace window.
      now = ~U[2026-05-14 10:16:00.000000Z]

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: client_config.name,
          download_client_id: "nzo-grace15-1",
          last_progress_at: first_seen,
          last_known_bytes: same_bytes
        })

      assert :ok = perform_job(DownloadMonitor, %{"now" => DateTime.to_iso8601(now)})

      updated = Downloads.get_download!(download.id)
      assert updated.import_failed_at != nil
      assert DateTime.diff(updated.import_failed_at, now, :second) == 0
      assert updated.import_last_error == "stalled after 15m without progress"
    end

    test "does not flag stalled in terminal state (completed)" do
      {bypass, client_config} = start_sabnzbd_bypass(incomplete_grace_minutes: 5)

      mock_sabnzbd_queue(bypass, [],
        history: [
          sabnzbd_history_item("nzo-completed-1", "test.nzb", "Completed")
        ]
      )

      media_item = media_item_fixture()

      # Last progress was 1 hour ago — well past the 5-minute grace — but
      # the client now reports the download as completed, so stall detection
      # must not kick in. We also set `completed_at` and `imported_at` so the
      # other monitor branches (handle_completion, list_stuck_downloads) treat
      # this row as already done — leaving only the stall-tracking path under
      # test.
      first_seen = ~U[2026-05-14 10:00:00.000000Z]
      now = ~U[2026-05-14 11:00:00.000000Z]
      bytes = round(50.0 * 1024 * 1024)

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: client_config.name,
          download_client_id: "nzo-completed-1",
          last_progress_at: first_seen,
          last_known_bytes: bytes,
          completed_at: DateTime.utc_now() |> DateTime.truncate(:second),
          imported_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert :ok = perform_job(DownloadMonitor, %{"now" => DateTime.to_iso8601(now)})

      updated = Downloads.get_download!(download.id)
      assert is_nil(updated.import_failed_at)
    end

    test "does not stomp an existing import_failed_at on subsequent polls" do
      {bypass, client_config} = start_sabnzbd_bypass(incomplete_grace_minutes: 5)

      same_bytes = round(50.0 * 1024 * 1024)

      mock_sabnzbd_queue(bypass, [
        sabnzbd_queue_item("nzo-already-failed-1", "test.nzb",
          size_mb: 100.0,
          mb_left: 50.0
        )
      ])

      media_item = media_item_fixture()

      one_hour_ago = ~U[2026-05-14 10:00:00.000000Z]
      previous_failure_at = ~U[2026-05-14 10:30:00.000000Z]
      now = ~U[2026-05-14 11:00:00.000000Z]

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: client_config.name,
          download_client_id: "nzo-already-failed-1",
          last_progress_at: one_hour_ago,
          last_known_bytes: same_bytes,
          import_failed_at: previous_failure_at,
          import_last_error: "stalled after 5m without progress"
        })

      assert :ok = perform_job(DownloadMonitor, %{"now" => DateTime.to_iso8601(now)})

      updated = Downloads.get_download!(download.id)
      # Pre-existing failure_at must remain — we don't re-flag every poll.
      assert DateTime.diff(updated.import_failed_at, previous_failure_at, :second) == 0
    end
  end

  describe "release blacklist on failure (#123)" do
    test "writes a (indexer, guid) row when a download is reported failed" do
      {bypass, client_config} = start_sabnzbd_bypass()

      mock_sabnzbd_queue(bypass, [],
        history: [
          sabnzbd_history_item("nzo-failed-1", "Show.S01E01.par2_corrupt.nzb", "Failed")
        ]
      )

      media_item = media_item_fixture()

      _download =
        download_fixture(%{
          media_item_id: media_item.id,
          title: "Show.S01E01.par2_corrupt",
          indexer: "nzbhydra2",
          download_client: client_config.name,
          download_client_id: "nzo-failed-1",
          metadata: %{
            size: 1_000_000_000,
            indexer: "nzbhydra2",
            guid: "stable-guid-123"
          }
        })

      assert :ok = perform_job(DownloadMonitor, %{})

      # The (indexer, guid) row must exist and be active.
      assert Mydia.Downloads.Blacklists.blacklisted?("nzbhydra2", "stable-guid-123")
    end

    test "indexer name is normalized to lowercase in the blacklist row" do
      {bypass, client_config} = start_sabnzbd_bypass()

      mock_sabnzbd_queue(bypass, [],
        history: [
          sabnzbd_history_item("nzo-failed-case", "Movie.failed.nzb", "Failed")
        ]
      )

      media_item = media_item_fixture()

      _download =
        download_fixture(%{
          media_item_id: media_item.id,
          title: "Movie.failed",
          indexer: "Prowlarr",
          download_client: client_config.name,
          download_client_id: "nzo-failed-case",
          metadata: %{
            size: 1_000_000_000,
            indexer: "Prowlarr",
            guid: "case-guid-xyz"
          }
        })

      assert :ok = perform_job(DownloadMonitor, %{})

      # Lookup via the original-cased indexer should match — Blacklists normalizes both ways.
      assert Mydia.Downloads.Blacklists.blacklisted?("Prowlarr", "case-guid-xyz")
      assert Mydia.Downloads.Blacklists.blacklisted?("prowlarr", "case-guid-xyz")
    end

    test "does not write a blacklist row when guid is missing" do
      {bypass, client_config} = start_sabnzbd_bypass()

      mock_sabnzbd_queue(bypass, [],
        history: [
          sabnzbd_history_item("nzo-no-guid", "Show.S01E02.nzb", "Failed")
        ]
      )

      media_item = media_item_fixture()

      _download =
        download_fixture(%{
          media_item_id: media_item.id,
          title: "Show.S01E02",
          indexer: "nzbhydra2",
          download_client: client_config.name,
          download_client_id: "nzo-no-guid",
          # Note: no guid in metadata.
          metadata: %{size: 1_000_000_000, indexer: "nzbhydra2"}
        })

      assert :ok = perform_job(DownloadMonitor, %{})

      # Nothing was added.
      assert Mydia.Downloads.Blacklists.list() == []
    end

    test "upserts an existing blacklist row when a release fails again" do
      # The try/rescue in `record_blacklist_entry/2` is the safety net for
      # *unexpected* DB exceptions; testing the exception path requires a
      # mocking library this repo doesn't use (Mox / :meck). The realistic
      # repeat-failure case is covered by `Blacklists.add/4`'s upsert
      # behaviour: when the same `(indexer, guid)` row already exists,
      # the second insert merges via `on_conflict: [set: ...]` rather
      # than raising. This test asserts that path completes cleanly and
      # the failed download is still removed.
      {bypass, client_config} = start_sabnzbd_bypass()

      mock_sabnzbd_queue(bypass, [],
        history: [
          sabnzbd_history_item("nzo-resilient-1", "Show.S01E03.nzb", "Failed")
        ]
      )

      media_item = media_item_fixture()

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          title: "Show.S01E03",
          indexer: "nzbhydra2",
          download_client: client_config.name,
          download_client_id: "nzo-resilient-1",
          metadata: %{
            size: 1_000_000_000,
            indexer: "nzbhydra2",
            guid: "resilient-guid"
          }
        })

      # Pre-seed the same key so we hit the upsert path.
      {:ok, _} =
        Mydia.Downloads.Blacklists.add(
          "nzbhydra2",
          "resilient-guid",
          "old",
          "stalled"
        )

      assert :ok = perform_job(DownloadMonitor, %{})

      # The download was deleted (downloads table is ephemeral on failure).
      assert_raise Ecto.NoResultsError, fn ->
        Mydia.Downloads.get_download!(download.id)
      end
    end
  end

  ## Helper Functions

  defp start_sabnzbd_bypass(opts \\ []) do
    bypass = Bypass.open()
    grace = Keyword.get(opts, :incomplete_grace_minutes, 60)

    {:ok, client_config} =
      Mydia.Settings.create_download_client_config(%{
        name: "SABnzbd-StallTest-#{System.unique_integer([:positive])}",
        type: :sabnzbd,
        host: "localhost",
        port: bypass.port,
        api_key: "test-api-key",
        enabled: true,
        priority: 1,
        incomplete_grace_minutes: grace
      })

    {bypass, client_config}
  end

  defp mock_sabnzbd_queue(bypass, queue_slots, opts \\ []) do
    history_slots = Keyword.get(opts, :history, [])

    Bypass.expect(bypass, "GET", "/api", fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      case conn.query_params["mode"] do
        "queue" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(%{"queue" => %{"slots" => queue_slots}}))

        "history" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(
            200,
            Jason.encode!(%{"history" => %{"slots" => history_slots}})
          )

        _other ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(200, Jason.encode!(%{}))
      end
    end)
  end

  defp sabnzbd_queue_item(nzo_id, filename, opts) do
    size_mb = Keyword.fetch!(opts, :size_mb)
    mb_left = Keyword.fetch!(opts, :mb_left)

    %{
      "nzo_id" => nzo_id,
      "filename" => filename,
      "status" => "Downloading",
      "mb" => size_mb,
      "mbleft" => mb_left,
      "kbpersec" => 0.0,
      "timeleft" => "0:00:00",
      "storage" => "/downloads",
      "added" => System.system_time(:second)
    }
  end

  defp sabnzbd_history_item(nzo_id, filename, status) do
    %{
      "nzo_id" => nzo_id,
      "filename" => filename,
      "status" => status,
      "bytes" => 1_000_000,
      "storage" => "/downloads",
      "completed" => System.system_time(:second)
    }
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
