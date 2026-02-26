defmodule Mydia.MediaServer.WatchedSync.Orchestrator do
  @moduledoc """
  Generic bidirectional sync orchestrator for media server watched status.

  Adapter-agnostic: uses `WatchedSync` behaviour callbacks to communicate
  with any supported media server (Plex, Jellyfin, etc.).

  Conflict resolution: "watched wins" — if an item is watched on either side,
  it gets marked as watched on both. Unwatch is never propagated.
  """

  alias Mydia.Media
  alias Mydia.MediaServer.WatchedSync
  alias Mydia.Playback
  alias Mydia.Repo

  require Logger

  @doc """
  Runs bidirectional sync (import + export) for a media server config and user.

  Options:
    - `:direction` - `:import`, `:export`, or `:bidirectional` (default)
  """
  def sync(config, user_id, opts \\ []) do
    direction = Keyword.get(opts, :direction, :bidirectional)

    with {:ok, adapter} <- WatchedSync.adapter_for(config) do
      case direction do
        :import ->
          import_watched(adapter, config, user_id)

        :export ->
          export_watched(adapter, config, user_id)

        :bidirectional ->
          import_result = import_watched(adapter, config, user_id)
          export_result = export_watched(adapter, config, user_id)

          case {import_result, export_result} do
            {{:ok, import_stats}, {:ok, export_stats}} ->
              {:ok, Map.merge(import_stats, export_stats)}

            {{:error, _} = err, _} ->
              err

            {_, {:error, _} = err} ->
              err
          end
      end
    end
  end

  @doc """
  Imports watched status from the media server into Mydia.

  Fetches all watched items from the server, matches them to local media
  items by external IDs, and marks them as watched locally.
  """
  def import_watched(adapter, config, user_id) do
    Logger.info("Importing watched status from #{config.name}")

    with {:ok, watched_items} <- adapter.fetch_watched(config) do
      stats =
        Enum.reduce(watched_items, %{imported: 0, skipped: 0, not_found: 0}, fn item, acc ->
          case match_and_mark_watched(user_id, item) do
            :marked -> %{acc | imported: acc.imported + 1}
            :already_watched -> %{acc | skipped: acc.skipped + 1}
            :not_found -> %{acc | not_found: acc.not_found + 1}
          end
        end)

      Logger.info(
        "Import from #{config.name} complete: " <>
          "#{stats.imported} imported, #{stats.skipped} skipped, #{stats.not_found} not found"
      )

      {:ok, stats}
    end
  end

  @doc """
  Exports watched status from Mydia to the media server.

  Finds all locally watched items, looks up their server counterparts
  via external ID index, and marks them as watched on the server.
  """
  def export_watched(adapter, config, user_id) do
    Logger.info("Exporting watched status to #{config.name}")

    with {:ok, server_index} <- adapter.build_server_index(config) do
      watched_progress = Playback.list_user_progress(user_id, watched: true)

      stats =
        Enum.reduce(watched_progress, %{exported: 0, export_skipped: 0}, fn progress, acc ->
          case export_single_item(adapter, config, server_index, progress) do
            :marked -> %{acc | exported: acc.exported + 1}
            :not_found -> %{acc | export_skipped: acc.export_skipped + 1}
          end
        end)

      Logger.info(
        "Export to #{config.name} complete: " <>
          "#{stats.exported} exported, #{stats.export_skipped} skipped"
      )

      {:ok, stats}
    end
  end

  # ── Import Helpers ────────────────────────────────────────────────

  defp match_and_mark_watched(user_id, %{type: :movie} = item) do
    case Media.find_by_external_ids(item.external_ids) do
      nil ->
        :not_found

      media_item ->
        ensure_watched(user_id, media_item_id: media_item.id)
    end
  end

  defp match_and_mark_watched(user_id, %{type: :episode} = item) do
    with %{id: show_id} <- Media.find_by_external_ids(item.external_ids),
         %{id: ep_id} <- Media.find_episode(show_id, item.season_number, item.episode_number) do
      ensure_watched(user_id, episode_id: ep_id)
    else
      _ -> :not_found
    end
  end

  defp ensure_watched(user_id, content_id) do
    case Playback.get_progress(user_id, content_id) do
      %{watched: true} ->
        :already_watched

      nil ->
        Playback.save_progress(user_id, content_id, %{
          position_seconds: 0,
          duration_seconds: 1,
          watched: true
        })

        :marked

      _existing ->
        Playback.mark_watched(user_id, content_id)
        :marked
    end
  end

  # ── Export Helpers ────────────────────────────────────────────────

  defp export_single_item(adapter, config, server_index, progress) do
    cond do
      progress.media_item_id != nil ->
        export_movie(adapter, config, server_index, progress.media_item_id)

      progress.episode_id != nil ->
        export_episode(adapter, config, server_index, progress.episode_id)

      true ->
        :not_found
    end
  end

  defp export_movie(adapter, config, server_index, media_item_id) do
    media_item = Repo.get(Media.MediaItem, media_item_id)

    if media_item do
      case find_in_server_index(server_index, "movie", media_item) do
        nil -> :not_found
        rating_key -> mark_on_server(adapter, config, rating_key)
      end
    else
      :not_found
    end
  end

  defp export_episode(adapter, config, server_index, episode_id) do
    episode = Repo.get(Media.Episode, episode_id) |> Repo.preload(:media_item)

    if episode && episode.media_item do
      show = episode.media_item
      ep_key_suffix = "s#{episode.season_number}e#{episode.episode_number}"

      case find_in_server_index(server_index, "episode", show, ep_key_suffix) do
        nil -> :not_found
        rating_key -> mark_on_server(adapter, config, rating_key)
      end
    else
      :not_found
    end
  end

  defp find_in_server_index(server_index, type, media_item, suffix \\ nil) do
    providers = [
      {:imdb, media_item.imdb_id},
      {:tvdb, media_item.tvdb_id},
      {:tmdb, media_item.tmdb_id}
    ]

    Enum.find_value(providers, fn {provider, id} ->
      if id do
        key =
          if suffix do
            "#{type}:#{provider}:#{id}:#{suffix}"
          else
            "#{type}:#{provider}:#{id}"
          end

        Map.get(server_index, key)
      end
    end)
  end

  defp mark_on_server(adapter, config, rating_key) do
    case adapter.mark_watched(config, rating_key) do
      :ok ->
        :marked

      {:error, reason} ->
        Logger.warning("Failed to mark watched on server: #{inspect(reason)}")
        :not_found
    end
  end
end
