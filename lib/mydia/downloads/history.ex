defmodule Mydia.Downloads.History do
  @moduledoc false

  import Ecto.Query, warn: false
  import Mydia.QueryHelpers

  use Mydia.QueryHelpers.Filterable,
    function_name: :apply_download_filters,
    filters: [
      media_item_id: :eq,
      episode_id: :eq
    ]

  alias Mydia.Repo
  alias Mydia.Downloads.Download
  alias Mydia.Downloads.Client
  alias Mydia.Downloads.Structs.DownloadMetadata
  alias Mydia.Downloads.Structs.EnrichedDownload
  alias Mydia.Settings
  alias Phoenix.PubSub
  require Logger

  ## Public Functions

  def list_downloads(opts \\ []) do
    Download
    |> apply_download_filters(opts)
    |> maybe_preload(opts[:preload])
    |> order_by([d], desc: d.inserted_at)
    |> Repo.all()
  end

  def list_downloads_with_status(opts \\ []) do
    # Get all download records from database
    # Preload episode.media_item to get parent show info for episode downloads
    downloads = list_downloads(preload: [:media_item, episode: :media_item])

    # Get all configured download clients
    clients = get_configured_clients()

    if clients == [] do
      Logger.warning("No download clients configured")
      # Return downloads with empty status
      Enum.map(downloads, &enrich_download_with_empty_status/1)
    else
      # Get status from all clients
      client_statuses = fetch_all_client_statuses(clients)

      # Enrich downloads with client status
      downloads
      |> Enum.map(&enrich_download_with_status(&1, client_statuses))
      |> apply_status_filters(opts[:filter] || :all)
    end
  end

  def get_download!(id, opts \\ []) do
    Download
    |> maybe_preload(opts[:preload])
    |> Repo.get!(id)
  end

  def create_download(attrs \\ %{}) do
    result =
      %Download{}
      |> Download.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, download} ->
        broadcast_download_update(download.id)
        {:ok, download}

      error ->
        error
    end
  end

  def update_download(%Download{} = download, attrs) do
    result =
      download
      |> Download.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated_download} ->
        broadcast_download_update(updated_download.id)
        {:ok, updated_download}

      error ->
        error
    end
  end

  def mark_download_completed(%Download{} = download) do
    download
    |> Download.changeset(%{completed_at: DateTime.utc_now()})
    |> Repo.update()
  end

  def mark_download_failed(%Download{} = download, error_message) do
    download
    |> Download.changeset(%{error_message: error_message})
    |> Repo.update()
  end

  def delete_download(%Download{} = download) do
    result = Repo.delete(download)

    case result do
      {:ok, deleted_download} ->
        broadcast_download_update(deleted_download.id)
        {:ok, deleted_download}

      error ->
        error
    end
  end

  def change_download(%Download{} = download, attrs \\ %{}) do
    Download.changeset(download, attrs)
  end

  def list_active_downloads(opts \\ []) do
    list_downloads_with_status(Keyword.put(opts, :filter, :active))
  end

  def count_active_downloads do
    list_active_downloads()
    |> length()
  end

  def list_stuck_downloads(opts \\ []) do
    threshold_minutes = Keyword.get(opts, :threshold_minutes, 60)
    threshold_time = DateTime.add(DateTime.utc_now(), -threshold_minutes, :minute)

    Download
    |> where([d], not is_nil(d.completed_at))
    |> where([d], is_nil(d.imported_at))
    |> where([d], is_nil(d.import_failed_at))
    |> where([d], d.completed_at < ^threshold_time)
    |> maybe_preload(opts[:preload])
    |> Repo.all()
  end

  def broadcast_download_update(download_id) do
    PubSub.broadcast(Mydia.PubSub, "downloads", {:download_updated, download_id})
  end

  ## Private Functions - Client Status Fetching

  defp get_configured_clients do
    Settings.list_download_client_configs()
    |> Enum.filter(& &1.enabled)
  end

  defp fetch_all_client_statuses(clients) do
    # Fetch torrents from all clients concurrently
    clients
    |> Task.async_stream(
      fn client_config ->
        adapter = get_adapter_module(client_config.type)
        config = config_to_map(client_config)

        case Client.list_torrents(adapter, config, []) do
          {:ok, torrents} ->
            {client_config.name, torrents}

          {:error, error} ->
            Logger.warning(
              "Failed to fetch torrents from #{client_config.name}: #{inspect(error)}"
            )

            {client_config.name, []}
        end
      end,
      timeout: :infinity,
      max_concurrency: 10
    )
    |> Enum.reduce(%{}, fn
      {:ok, {client_name, torrents}}, acc ->
        # Index torrents by client_id for fast lookup
        torrents_map =
          torrents
          |> Enum.map(fn torrent -> {torrent.id, torrent} end)
          |> Map.new()

        Map.put(acc, client_name, torrents_map)

      _, acc ->
        acc
    end)
  end

  defp enrich_download_with_status(download, client_statuses) do
    # Find the torrent status from the appropriate client
    torrent_status =
      client_statuses
      |> Map.get(download.download_client, %{})
      |> Map.get(download.download_client_id)

    if torrent_status do
      # Convert metadata map to struct for type-safe access
      metadata = DownloadMetadata.from_map(download.metadata)

      # Merge download DB record with real-time client status
      EnrichedDownload.new(%{
        id: download.id,
        media_item_id: download.media_item_id,
        episode_id: download.episode_id,
        media_item: download.media_item,
        episode: download.episode,
        title: download.title,
        indexer: download.indexer,
        download_url: download.download_url,
        download_client: download.download_client,
        download_client_id: download.download_client_id,
        metadata: download.metadata,
        match_status: download.match_status,
        inserted_at: download.inserted_at,
        # Real-time fields from client
        status: status_from_torrent_state(torrent_status.state),
        progress: torrent_status.progress,
        download_speed: torrent_status.download_speed,
        upload_speed: torrent_status.upload_speed,
        eta: torrent_status.eta,
        size: torrent_status.size,
        downloaded: torrent_status.downloaded,
        uploaded: torrent_status.uploaded,
        ratio: torrent_status.ratio,
        seeders: if(metadata, do: metadata.seeders, else: nil),
        leechers: if(metadata, do: metadata.leechers, else: nil),
        save_path: torrent_status.save_path,
        completed_at: download.completed_at || torrent_status.completed_at,
        error_message: download.error_message,
        # Preserve database completed_at for tracking if we've already processed it
        db_completed_at: download.completed_at,
        imported_at: download.imported_at,
        import_retry_count: download.import_retry_count,
        import_last_error: download.import_last_error,
        import_next_retry_at: download.import_next_retry_at,
        import_failed_at: download.import_failed_at
      })
    else
      # Download not found in client - might be removed or completed
      enrich_download_with_empty_status(download)
    end
  end

  defp enrich_download_with_empty_status(download) do
    # Download exists in DB but not in client
    # Could be completed and removed, or manually deleted from client
    status =
      cond do
        download.imported_at -> "imported"
        download.completed_at -> "completed"
        download.error_message -> "failed"
        true -> "missing"
      end

    # Convert metadata map to struct for type-safe access
    metadata = DownloadMetadata.from_map(download.metadata)

    EnrichedDownload.new(%{
      id: download.id,
      media_item_id: download.media_item_id,
      episode_id: download.episode_id,
      media_item: download.media_item,
      episode: download.episode,
      title: download.title,
      indexer: download.indexer,
      download_url: download.download_url,
      download_client: download.download_client,
      download_client_id: download.download_client_id,
      metadata: download.metadata,
      match_status: download.match_status,
      inserted_at: download.inserted_at,
      status: status,
      progress: if(download.completed_at, do: 100.0, else: 0.0),
      download_speed: 0,
      upload_speed: 0,
      eta: nil,
      size: if(metadata, do: metadata.size, else: 0),
      downloaded: 0,
      uploaded: 0,
      ratio: 0.0,
      seeders: nil,
      leechers: nil,
      save_path: nil,
      completed_at: download.completed_at,
      error_message: download.error_message,
      # Preserve database completed_at for tracking if we've already processed it
      db_completed_at: download.completed_at,
      imported_at: download.imported_at,
      import_retry_count: download.import_retry_count,
      import_last_error: download.import_last_error,
      import_next_retry_at: download.import_next_retry_at,
      import_failed_at: download.import_failed_at
    })
  end

  defp status_from_torrent_state(state) do
    case state do
      :downloading -> "downloading"
      :seeding -> "seeding"
      :completed -> "completed"
      :paused -> "paused"
      :checking -> "checking"
      :error -> "failed"
      _ -> "unknown"
    end
  end

  defp apply_status_filters(downloads, :all), do: downloads

  defp apply_status_filters(downloads, :active) do
    Enum.filter(downloads, fn d ->
      # Active downloads are those that haven't been imported yet
      # and are currently downloading, seeding, checking, or paused
      is_nil(d.imported_at) and d.status in ["downloading", "seeding", "checking", "paused"]
    end)
  end

  defp apply_status_filters(downloads, :completed) do
    Enum.filter(downloads, &(&1.status == "completed"))
  end

  # Filter for imported downloads (shown in Completed tab)
  # These are downloads that have been successfully imported to the library
  # but may still be seeding in the download client
  defp apply_status_filters(downloads, :imported) do
    Enum.filter(downloads, fn d ->
      not is_nil(d.imported_at)
    end)
  end

  defp apply_status_filters(downloads, :failed) do
    Enum.filter(downloads, fn d ->
      # Show downloads that failed in the client OR have import failures
      # Exclude unmatched and unresolved_files which have their own sections
      (d.status in ["failed", "missing"] || not is_nil(d.import_failed_at)) and
        d.match_status not in ["unmatched", "unresolved_files"]
    end)
  end

  defp apply_status_filters(downloads, :unmatched) do
    Enum.filter(downloads, fn d ->
      d.match_status == "unmatched"
    end)
  end

  defp apply_status_filters(downloads, :unresolved_files) do
    Enum.filter(downloads, fn d ->
      d.match_status == "unresolved_files"
    end)
  end

  defp get_adapter_module(:qbittorrent), do: Mydia.Downloads.Client.QBittorrent
  defp get_adapter_module(:transmission), do: Mydia.Downloads.Client.Transmission
  defp get_adapter_module(:rtorrent), do: Mydia.Downloads.Client.Rtorrent
  defp get_adapter_module(:blackhole), do: Mydia.Downloads.Client.Blackhole
  defp get_adapter_module(:http), do: Mydia.Downloads.Client.HTTP
  defp get_adapter_module(:sabnzbd), do: Mydia.Downloads.Client.Sabnzbd
  defp get_adapter_module(:nzbget), do: Mydia.Downloads.Client.Nzbget
  defp get_adapter_module(_), do: nil

  defp config_to_map(config) do
    %{
      type: config.type,
      host: config.host,
      port: config.port,
      use_ssl: config.use_ssl,
      username: config.username,
      password: config.password,
      url_base: config.url_base,
      api_key: config.api_key,
      connection_settings: config.connection_settings || %{},
      options: config.connection_settings || %{}
    }
  end
end
