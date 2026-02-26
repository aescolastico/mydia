defmodule Mydia.MediaServer.WatchedSync.Plex do
  @moduledoc """
  Plex adapter for watched status sync.

  Implements the `WatchedSync` behaviour by calling Plex API endpoints
  to fetch watched items, mark items as watched/unwatched, and build
  a server index for export operations.
  """

  @behaviour Mydia.MediaServer.WatchedSync

  alias Mydia.MediaServer.Client.Plex, as: PlexClient

  require Logger

  @impl true
  def fetch_watched(config) do
    with {:ok, sections} <- PlexClient.list_sections(config) do
      items =
        sections
        |> Enum.flat_map(fn section -> fetch_watched_from_section(config, section) end)

      {:ok, items}
    end
  end

  @impl true
  def mark_watched(config, rating_key) do
    PlexClient.scrobble(config, rating_key)
  end

  @impl true
  def mark_unwatched(config, rating_key) do
    PlexClient.unscrobble(config, rating_key)
  end

  @impl true
  def build_server_index(config) do
    with {:ok, sections} <- PlexClient.list_sections(config) do
      index =
        sections
        |> Enum.flat_map(fn section -> index_section(config, section) end)
        |> Map.new()

      {:ok, index}
    end
  end

  # ── Private Helpers ────────────────────────────────────────────────

  defp fetch_watched_from_section(config, %{type: "movie", key: key}) do
    case PlexClient.list_section_items(config, key) do
      {:ok, items} ->
        items
        |> Enum.filter(fn item -> item.view_count > 0 end)
        |> Enum.map(fn item ->
          %{
            type: :movie,
            external_ids: item.guids,
            title: item.title,
            season_number: nil,
            episode_number: nil,
            server_item_id: item.rating_key
          }
        end)

      {:error, reason} ->
        Logger.warning("Failed to fetch Plex movie section #{key}: #{inspect(reason)}")
        []
    end
  end

  defp fetch_watched_from_section(config, %{type: "show", key: key}) do
    case PlexClient.list_section_items(config, key) do
      {:ok, shows} ->
        Enum.flat_map(shows, fn show ->
          fetch_watched_episodes(config, show)
        end)

      {:error, reason} ->
        Logger.warning("Failed to fetch Plex show section #{key}: #{inspect(reason)}")
        []
    end
  end

  defp fetch_watched_from_section(_config, %{type: type, key: key}) do
    Logger.debug("Skipping unsupported Plex section type #{type} (key: #{key})")
    []
  end

  defp fetch_watched_episodes(config, show) do
    case PlexClient.list_show_episodes(config, show.rating_key) do
      {:ok, episodes} ->
        episodes
        |> Enum.filter(fn ep -> ep.view_count > 0 end)
        |> Enum.map(fn ep ->
          %{
            type: :episode,
            external_ids: show.guids,
            title: "#{show.title} S#{ep.season_number}E#{ep.episode_number}",
            season_number: ep.season_number,
            episode_number: ep.episode_number,
            server_item_id: ep.rating_key
          }
        end)

      {:error, reason} ->
        Logger.warning("Failed to fetch episodes for Plex show #{show.title}: #{inspect(reason)}")

        []
    end
  end

  defp index_section(config, %{type: "movie", key: key}) do
    case PlexClient.list_section_items(config, key) do
      {:ok, items} ->
        Enum.flat_map(items, fn item ->
          build_index_entries("movie", item.guids, item.rating_key)
        end)

      {:error, reason} ->
        Logger.warning("Failed to index Plex movie section #{key}: #{inspect(reason)}")
        []
    end
  end

  defp index_section(config, %{type: "show", key: key}) do
    case PlexClient.list_section_items(config, key) do
      {:ok, shows} ->
        Enum.flat_map(shows, fn show ->
          case PlexClient.list_show_episodes(config, show.rating_key) do
            {:ok, episodes} ->
              Enum.flat_map(episodes, fn ep ->
                # For episodes, the index key includes season/episode numbers
                ep_key_suffix = "s#{ep.season_number}e#{ep.episode_number}"

                show.guids
                |> Enum.flat_map(fn {provider, id} ->
                  [{"episode:#{provider}:#{id}:#{ep_key_suffix}", ep.rating_key}]
                end)
              end)

            {:error, _} ->
              []
          end
        end)

      {:error, reason} ->
        Logger.warning("Failed to index Plex show section #{key}: #{inspect(reason)}")
        []
    end
  end

  defp index_section(_config, _section), do: []

  defp build_index_entries(type, guids, rating_key) do
    Enum.map(guids, fn {provider, id} ->
      {"#{type}:#{provider}:#{id}", rating_key}
    end)
  end
end
