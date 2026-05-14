defmodule Mydia.Jobs.DownloadMonitor do
  @moduledoc """
  Background job for monitoring downloads and handling completion.

  With download clients as the source of truth, this job now focuses on:
  - Detecting completed downloads in clients
  - Marking downloads as completed in the database
  - Triggering media import jobs for completed downloads
  - Recording errors for failed downloads
  - Flagging downloads that were removed from clients

  ## Missing Download Detection

  When a download is manually removed from a download client (e.g., Transmission),
  the job will detect this and mark the download as "missing" with an error message.
  This preserves the download in the Issues tab so users can investigate why the
  download was removed before import completed. Users can manually delete from
  the Issues tab if desired.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 5

  require Logger
  alias Mydia.Downloads
  alias Mydia.Downloads.Blacklists
  alias Mydia.Downloads.StallDetector
  alias Mydia.Downloads.UntrackedMatcher
  alias Mydia.Events
  alias Mydia.Settings

  # Fallback grace window (minutes) when a download has no resolvable client
  # config. The DB schema's default is also 60; this just guards against a nil.
  @default_grace_minutes 60

  @spec perform(Oban.Job.t()) :: :ok | {:ok, term()} | {:error, term()} | {:snooze, pos_integer()}
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    start_time = System.monotonic_time(:millisecond)
    Logger.info("Starting download completion monitoring", args: args)

    # Allow tests to inject a deterministic clock via job args (`"now" => iso8601`).
    now = resolve_now(args)

    # Get all downloads with their real-time status from clients
    downloads = Downloads.list_downloads_with_status(filter: :all)

    # Find downloads that have completed or failed
    # Note: "seeding" means download is complete and now seeding (100% progress)
    # A torrent can also be paused at 100% progress (manually paused after completion)
    # We check db_completed_at to see if we've already marked it as completed in our database
    completed =
      Enum.filter(downloads, fn d ->
        is_nil(d.db_completed_at) and
          (d.status in ["completed", "seeding"] or
             (d.status == "paused" and d.progress == 100.0))
      end)

    failed = Enum.filter(downloads, &(&1.status == "failed" and is_nil(&1.error_message)))

    # Find downloads that no longer exist in any tracker
    # These are downloads that were manually removed from the client
    # Status is "missing" when download exists in DB but not in any client
    missing =
      Enum.filter(downloads, fn d ->
        d.status == "missing" and is_nil(d.db_completed_at) and is_nil(d.error_message)
      end)

    # Active downloads we should track for stall detection. Skip terminal
    # states (completed/seeding/failed/missing/imported) and anything already
    # flagged as import_failed_at — the latter prevents stomping a previous
    # stall annotation on every subsequent poll.
    active_for_stall_check =
      Enum.filter(downloads, fn d ->
        d.status in ["downloading", "checking"] and
          is_nil(d.import_failed_at) and
          is_nil(d.imported_at)
      end)

    Logger.info(
      "Found #{length(completed)} newly completed, #{length(failed)} newly failed, #{length(missing)} missing downloads, #{length(active_for_stall_check)} active for stall check"
    )

    # Handle completions
    Enum.each(completed, &handle_completion/1)

    # Handle failures
    Enum.each(failed, &handle_failure/1)

    # Handle missing downloads
    Enum.each(missing, &handle_missing/1)

    # Track progress / flag stalled downloads. Grace minutes are read from each
    # download's configured client (DB or runtime config) — cached per poll.
    grace_map = build_grace_map()
    stalled_count = check_progress(active_for_stall_check, grace_map, now)

    # Find and match untracked torrents (manually added to clients)
    untracked_downloads = UntrackedMatcher.find_and_match_untracked()
    Logger.info("Matched #{length(untracked_downloads)} untracked torrent(s) to library items")

    # Detect stuck downloads (completed but never imported for >1 hour)
    stuck = Downloads.list_stuck_downloads(preload: [:media_item])
    Logger.info("Found #{length(stuck)} stuck downloads")
    Enum.each(stuck, &handle_stuck/1)

    duration = System.monotonic_time(:millisecond) - start_time

    Logger.info("Download monitoring completed",
      duration_ms: duration,
      completed_count: length(completed),
      failed_count: length(failed),
      missing_count: length(missing),
      stalled_count: stalled_count,
      stuck_count: length(stuck),
      untracked_matched: length(untracked_downloads)
    )

    :ok
  end

  ## Private Functions

  defp handle_completion(download_map) do
    Logger.info("Handling completed download",
      download_id: download_map.id,
      title: download_map.title,
      save_path: download_map.save_path
    )

    # Get the download struct from database (with media_item preloaded)
    download = Downloads.get_download!(download_map.id, preload: [:media_item])

    # Mark download as completed in database (prevents reprocessing on next monitor run)
    {:ok, download} = Downloads.mark_download_completed(download)

    # Track completion event
    Events.download_completed(download, media_item: download.media_item)

    # Enqueue import job - it will delete the download record after successful import
    case enqueue_import_job(download, download_map) do
      {:ok, _job} ->
        Logger.info("Import job enqueued for completed download",
          download_id: download.id
        )

        :ok

      {:error, reason} ->
        Logger.error("Failed to enqueue import job",
          download_id: download.id,
          reason: inspect(reason)
        )

        :ok
    end
  end

  defp handle_failure(download_map) do
    Logger.info("Handling failed download",
      download_id: download_map.id,
      title: download_map.title,
      error: download_map.error_message
    )

    # Get the download struct from database (with media_item preloaded)
    download = Downloads.get_download!(download_map.id, preload: [:media_item])

    error_msg = download_map.error_message || "Download failed in client"

    # Track failure event before deletion
    Events.download_failed(download, error_msg, media_item: download.media_item)

    # Blacklist the release so the next search excludes it (issue #123).
    # This MUST NOT block failure handling — wrap in try/rescue and log.
    record_blacklist_entry(download, "client_reported_failure")

    # Delete the download record - downloads table is ephemeral
    case Downloads.delete_download(download) do
      {:ok, _deleted} ->
        Logger.info("Download removed from queue (failed)",
          download_id: download_map.id,
          error: error_msg
        )

        :ok

      {:error, changeset} ->
        Logger.error("Failed to delete failed download",
          download_id: download.id,
          errors: inspect(changeset.errors)
        )

        :ok
    end
  end

  # --- Release blacklist (#123) ------------------------------------------

  # Inserts a `release_blacklist` row keyed by the download's
  # (indexer, guid) so future searches in `TvShowSearch` / `MovieSearch`
  # filter the result out. Best-effort: rescue all errors so a failing
  # blacklist write never blocks the rest of failure handling.
  defp record_blacklist_entry(download, failure_reason) do
    case extract_blacklist_key(download) do
      {:ok, indexer, guid} ->
        try do
          case Blacklists.add(indexer, guid, download.title || "", failure_reason) do
            {:ok, _row} ->
              Logger.info("Release blacklisted after failure",
                download_id: download.id,
                indexer: indexer,
                guid: guid,
                failure_reason: failure_reason
              )

              :ok

            {:error, reason} ->
              Logger.warning("Failed to blacklist release",
                download_id: download.id,
                indexer: indexer,
                guid: guid,
                reason: inspect(reason)
              )

              :ok
          end
        rescue
          error ->
            Logger.warning("Exception while blacklisting release — continuing",
              download_id: download.id,
              error: inspect(error)
            )

            :ok
        end

      {:error, reason} ->
        Logger.debug("Skipping blacklist write — no usable key",
          download_id: download.id,
          reason: reason
        )

        :ok
    end
  end

  # Returns `{:ok, indexer, guid}` when both are present on the download.
  # The `indexer` and `guid` should have been plumbed in at download
  # creation time (see `Mydia.Downloads.Queue.create_download_record/4`).
  defp extract_blacklist_key(download) do
    indexer = download.indexer || get_in(download.metadata || %{}, ["indexer"])
    guid = get_in(download.metadata || %{}, ["guid"])

    cond do
      is_nil(indexer) or indexer == "" -> {:error, :no_indexer}
      is_nil(guid) or guid == "" -> {:error, :no_guid}
      true -> {:ok, indexer, guid}
    end
  end

  defp handle_missing(download_map) do
    Logger.warning("Download missing from client - preserving for user investigation",
      download_id: download_map.id,
      title: download_map.title,
      client: download_map.download_client
    )

    # Get the download struct from database (with media_item preloaded)
    download = Downloads.get_download!(download_map.id, preload: [:media_item])

    # Instead of deleting, mark as missing with error message
    # This preserves the record in the Issues tab for user investigation
    error_msg =
      "Removed from download client '#{download_map.download_client}' before import completed. " <>
        "The download may have been manually deleted, or the client may have encountered an error."

    case Downloads.update_download(download, %{
           status: "missing",
           error_message: error_msg
         }) do
      {:ok, updated} ->
        Logger.info("Download marked as missing (preserved for Issues tab)",
          download_id: download_map.id,
          status: updated.status
        )

        # Track event for user visibility
        Events.download_failed(download, error_msg, media_item: download.media_item)
        :ok

      {:error, changeset} ->
        Logger.error("Failed to mark download as missing",
          download_id: download.id,
          errors: inspect(changeset.errors)
        )

        :ok
    end
  end

  defp handle_stuck(download) do
    # Calculate how long the download has been stuck
    hours_stuck =
      DateTime.diff(DateTime.utc_now(), download.completed_at, :hour)

    Logger.warning("Download stuck - completed but never imported",
      download_id: download.id,
      title: download.title,
      completed_at: download.completed_at,
      hours_stuck: hours_stuck
    )

    error_msg =
      "Import stalled - download completed #{hours_stuck} hour(s) ago but import never ran. " <>
        "This may indicate the import job failed silently or was never scheduled. " <>
        "A new import will be attempted automatically."

    # Flag as failed so it appears in Issues tab
    case Downloads.update_download(download, %{
           import_failed_at: DateTime.utc_now(),
           import_last_error: error_msg
         }) do
      {:ok, updated} ->
        Logger.info("Stuck download flagged for investigation",
          download_id: download.id
        )

        # Track event for user visibility
        Events.download_failed(download, error_msg, media_item: download.media_item)

        # Enqueue a new import job to retry
        enqueue_import_job(updated)

      {:error, changeset} ->
        Logger.error("Failed to flag stuck download",
          download_id: download.id,
          errors: inspect(changeset.errors)
        )
    end
  end

  # --- Stall detection ----------------------------------------------------

  # Build a `%{client_name => grace_minutes}` map once per poll. Both DB-backed
  # and runtime-config clients flow through `Settings.list_download_client_configs/0`,
  # so a single source is enough.
  defp build_grace_map do
    Settings.list_download_client_configs()
    |> Enum.into(%{}, fn config ->
      {config.name, config.incomplete_grace_minutes || @default_grace_minutes}
    end)
  end

  defp grace_minutes_for(client_name, grace_map) do
    Map.get(grace_map, client_name, @default_grace_minutes)
  end

  # Iterate active downloads and apply the StallDetector decision. Returns the
  # number of downloads newly flagged as stalled.
  defp check_progress(active_downloads, grace_map, now) do
    Enum.reduce(active_downloads, 0, fn download, stalled_acc ->
      grace = grace_minutes_for(download.download_client, grace_map)

      decision =
        StallDetector.evaluate(
          download.last_progress_at,
          download.last_known_bytes,
          download.downloaded || 0,
          grace,
          now
        )

      apply_progress_decision(download, decision) + stalled_acc
    end)
  end

  defp apply_progress_decision(_download, :no_change), do: 0

  defp apply_progress_decision(download, {:initialize, now}) do
    update_progress(download, %{
      last_progress_at: now,
      last_known_bytes: download.downloaded || 0
    })

    0
  end

  defp apply_progress_decision(download, {:progress, new_bytes, now}) do
    update_progress(download, %{
      last_progress_at: now,
      last_known_bytes: new_bytes
    })

    0
  end

  defp apply_progress_decision(download, {:stalled, error_message, now}) do
    Logger.warning("Download stalled — no progress within grace window",
      download_id: download.id,
      download_client: download.download_client,
      last_progress_at: download.last_progress_at,
      last_known_bytes: download.last_known_bytes,
      downloaded: download.downloaded,
      error: error_message
    )

    # IMPORTANT: do NOT cast `:status` here — `Download.changeset/2` silently
    # drops it (known bug, tracked separately). Use `import_failed_at` +
    # `import_last_error` as the stalled signal.
    db_download = Downloads.get_download!(download.id, preload: [:media_item])

    case Downloads.update_download(db_download, %{
           import_failed_at: now,
           import_last_error: error_message
         }) do
      {:ok, updated} ->
        Events.download_failed(updated, error_message, media_item: updated.media_item)
        1

      {:error, changeset} ->
        Logger.error("Failed to flag stalled download",
          download_id: download.id,
          errors: inspect(changeset.errors)
        )

        0
    end
  end

  defp update_progress(download, attrs) do
    db_download = Downloads.get_download!(download.id)

    case Downloads.update_download(db_download, attrs) do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        Logger.warning("Failed to update download progress tracking",
          download_id: download.id,
          errors: inspect(changeset.errors)
        )

        :ok
    end
  end

  # Resolve the current time from job args (test injection) or fall back to
  # `DateTime.utc_now/0`. Accepts ISO8601 strings or `DateTime` structs.
  defp resolve_now(args) when is_map(args) do
    case Map.get(args, "now") do
      nil ->
        DateTime.utc_now()

      %DateTime{} = dt ->
        dt

      iso when is_binary(iso) ->
        case DateTime.from_iso8601(iso) do
          {:ok, dt, _offset} ->
            dt

          {:error, _} ->
            Logger.warning("Invalid 'now' arg passed to DownloadMonitor, falling back to utc_now",
              value: iso
            )

            DateTime.utc_now()
        end
    end
  end

  defp resolve_now(_), do: DateTime.utc_now()

  # --- Import job helpers -------------------------------------------------

  # Enqueue import job with save_path from client status (normal completion flow)
  defp enqueue_import_job(download, download_map) do
    %{
      "download_id" => download.id,
      "save_path" => download_map.save_path,
      "cleanup_client" => true,
      "use_hardlinks" => true,
      "move_files" => false
    }
    |> Mydia.Jobs.MediaImport.new()
    |> Oban.insert()
  end

  # Enqueue import job for stuck downloads (save_path will be fetched by MediaImport)
  defp enqueue_import_job(download) do
    changeset =
      %{
        "download_id" => download.id,
        "cleanup_client" => true,
        "use_hardlinks" => true,
        "move_files" => false
      }
      |> Mydia.Jobs.MediaImport.new()

    # Use Oban.insert if available, otherwise fall back to Repo.insert for testing
    result =
      try do
        Oban.insert(changeset)
      rescue
        RuntimeError ->
          # In testing mode without running Oban, insert directly via Repo
          Mydia.Repo.insert(changeset)
      end

    case result do
      {:ok, job} ->
        Logger.info("Retry import job enqueued for stuck download",
          download_id: download.id,
          job_id: job.id
        )

        {:ok, job}

      {:error, reason} = error ->
        Logger.error("Failed to enqueue retry import job",
          download_id: download.id,
          reason: inspect(reason)
        )

        error
    end
  end
end
