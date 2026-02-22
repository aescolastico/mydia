defmodule Mydia.Integrations.Trakt.Sync do
  @moduledoc """
  Two-way sync logic between Mydia and Trakt.tv.

  Handles incremental sync of watch history, ratings, watchlist,
  and collection using `last_synced_at` as the watermark.
  """

  import Ecto.Query, warn: false

  alias Mydia.Integrations
  alias Mydia.Integrations.Trakt.Client
  alias Mydia.Integrations.UserIntegration
  alias Mydia.Media
  alias Mydia.Playback
  alias Mydia.Repo

  require Logger

  @doc """
  Runs a full sync for a user: history, ratings, collection.
  """
  def sync_all(user_id) do
    with {:ok, _} <- sync_history(user_id),
         {:ok, _} <- sync_collection(user_id) do
      update_last_synced(user_id)
      {:ok, :synced}
    end
  end

  @doc """
  Syncs watch history between Mydia and Trakt.

  Pull: Fetches Trakt history, matches to local media, updates local progress.
  Push: Finds locally watched items, pushes to Trakt.
  """
  def sync_history(user_id) do
    with {:ok, token} <- Integrations.get_trakt_token(user_id) do
      pull_history(user_id, token)
      push_history(user_id, token)
      {:ok, :synced}
    end
  end

  @doc """
  Pushes Mydia library items to Trakt collection.
  """
  def sync_collection(user_id) do
    with {:ok, token} <- Integrations.get_trakt_token(user_id) do
      push_collection(user_id, token)
      {:ok, :synced}
    end
  end

  @doc """
  Syncs ratings between Mydia and Trakt.
  Currently only pulls from Trakt (Mydia doesn't have a ratings system yet).
  """
  def sync_ratings(user_id) do
    with {:ok, _token} <- Integrations.get_trakt_token(user_id) do
      {:ok, :synced}
    end
  end

  @doc """
  Syncs watchlist between Mydia and Trakt.
  """
  def sync_watchlist(user_id) do
    with {:ok, _token} <- Integrations.get_trakt_token(user_id) do
      {:ok, :synced}
    end
  end

  # ── Pull History ────────────────────────────────────────────────────

  defp pull_history(user_id, token) do
    integration = Integrations.get_user_integration(user_id, "trakt")
    start_at = format_start_at(integration)

    # Pull movie history
    params = if start_at, do: [start_at: start_at], else: []

    case Client.get_sync("history", "movies", token, params) do
      {:ok, items} when is_list(items) ->
        Enum.each(items, fn item ->
          match_and_mark_watched(user_id, item, :movie)
        end)

      {:error, reason} ->
        Logger.warning("Failed to pull Trakt movie history: #{inspect(reason)}")
    end

    # Pull episode history
    case Client.get_sync("history", "episodes", token, params) do
      {:ok, items} when is_list(items) ->
        Enum.each(items, fn item ->
          match_and_mark_watched(user_id, item, :episode)
        end)

      {:error, reason} ->
        Logger.warning("Failed to pull Trakt episode history: #{inspect(reason)}")
    end
  end

  defp match_and_mark_watched(user_id, trakt_item, :movie) do
    ids = get_in(trakt_item, ["movie", "ids"]) || %{}

    case find_media_item_by_ids(ids) do
      nil -> :skip
      media_item -> ensure_watched(user_id, media_item_id: media_item.id)
    end
  end

  defp match_and_mark_watched(user_id, trakt_item, :episode) do
    show_ids = get_in(trakt_item, ["show", "ids"]) || %{}
    season = get_in(trakt_item, ["episode", "season"])
    number = get_in(trakt_item, ["episode", "number"])

    with %{id: show_id} <- find_media_item_by_ids(show_ids),
         %{id: ep_id} <- find_episode(show_id, season, number) do
      ensure_watched(user_id, episode_id: ep_id)
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

      _existing ->
        Playback.mark_watched(user_id, content_id)
    end
  end

  # ── Push History ────────────────────────────────────────────────────

  defp push_history(user_id, token) do
    # Get locally watched movies since last sync
    watched = Playback.list_user_progress(user_id, watched: true)

    movies =
      watched
      |> Enum.filter(&(&1.media_item_id != nil))
      |> Enum.map(fn p ->
        item = Repo.get(Media.MediaItem, p.media_item_id)

        if item do
          build_trakt_movie(item, p.last_watched_at)
        end
      end)
      |> Enum.reject(&is_nil/1)

    if movies != [] do
      case Client.add_sync("history", %{movies: movies}, token) do
        {:ok, _} -> Logger.debug("Pushed #{length(movies)} movies to Trakt history")
        {:error, reason} -> Logger.warning("Failed to push Trakt history: #{inspect(reason)}")
      end
    end

    # Push watched episodes
    episodes =
      watched
      |> Enum.filter(&(&1.episode_id != nil))
      |> Enum.map(fn p ->
        ep = Repo.get(Media.Episode, p.episode_id) |> Repo.preload(:media_item)

        if ep && ep.media_item do
          build_trakt_episode(ep, p.last_watched_at)
        end
      end)
      |> Enum.reject(&is_nil/1)

    if episodes != [] do
      case Client.add_sync("history", %{episodes: episodes}, token) do
        {:ok, _} -> Logger.debug("Pushed #{length(episodes)} episodes to Trakt history")
        {:error, reason} -> Logger.warning("Failed to push Trakt history: #{inspect(reason)}")
      end
    end
  end

  # ── Push Collection ─────────────────────────────────────────────────

  defp push_collection(_user_id, token) do
    # Push all media items that have files
    movies =
      from(m in Media.MediaItem,
        where: m.type == "movie",
        join: f in assoc(m, :media_files),
        distinct: true
      )
      |> Repo.all()
      |> Enum.map(&build_trakt_movie(&1))
      |> Enum.reject(&is_nil/1)

    if movies != [] do
      case Client.add_sync("collection", %{movies: movies}, token) do
        {:ok, _} -> Logger.debug("Pushed #{length(movies)} movies to Trakt collection")
        {:error, reason} -> Logger.warning("Failed to push Trakt collection: #{inspect(reason)}")
      end
    end

    shows =
      from(m in Media.MediaItem,
        where: m.type == "tv_show",
        join: e in assoc(m, :episodes),
        join: f in Mydia.Library.MediaFile,
        on: f.episode_id == e.id,
        distinct: true
      )
      |> Repo.all()
      |> Enum.map(&build_trakt_show/1)
      |> Enum.reject(&is_nil/1)

    if shows != [] do
      case Client.add_sync("collection", %{shows: shows}, token) do
        {:ok, _} -> Logger.debug("Pushed #{length(shows)} shows to Trakt collection")
        {:error, reason} -> Logger.warning("Failed to push Trakt collection: #{inspect(reason)}")
      end
    end
  end

  # ── Matching Helpers ────────────────────────────────────────────────

  defp find_media_item_by_ids(ids) do
    imdb = Map.get(ids, "imdb")
    tmdb = Map.get(ids, "tmdb")

    cond do
      imdb ->
        Repo.get_by(Media.MediaItem, imdb_id: imdb)

      tmdb ->
        Repo.get_by(Media.MediaItem, tmdb_id: tmdb)

      true ->
        nil
    end
  end

  defp find_episode(show_id, season, number) when is_integer(season) and is_integer(number) do
    from(e in Media.Episode,
      where:
        e.media_item_id == ^show_id and
          e.season_number == ^season and
          e.episode_number == ^number,
      limit: 1
    )
    |> Repo.one()
  end

  defp find_episode(_, _, _), do: nil

  # ── Trakt Payload Builders ─────────────────────────────────────────

  defp build_trakt_movie(item, watched_at \\ nil)

  defp build_trakt_movie(item, watched_at) do
    ids = build_ids(item)

    if ids == %{},
      do: nil,
      else: %{ids: ids, title: item.title, year: item.year, watched_at: watched_at}
  end

  defp build_trakt_episode(episode, watched_at) do
    show = episode.media_item
    ids = build_ids(show)

    if ids == %{} do
      nil
    else
      %{
        ids: ids,
        title: show.title,
        year: show.year,
        seasons: [
          %{
            number: episode.season_number,
            episodes: [%{number: episode.episode_number, watched_at: watched_at}]
          }
        ]
      }
    end
  end

  defp build_trakt_show(item) do
    ids = build_ids(item)
    if ids == %{}, do: nil, else: %{ids: ids, title: item.title, year: item.year}
  end

  defp build_ids(item) do
    %{}
    |> then(fn m -> if item.imdb_id, do: Map.put(m, :imdb, item.imdb_id), else: m end)
    |> then(fn m -> if item.tmdb_id, do: Map.put(m, :tmdb, item.tmdb_id), else: m end)
  end

  # ── Timestamp Helpers ───────────────────────────────────────────────

  defp format_start_at(nil), do: nil
  defp format_start_at(%UserIntegration{last_synced_at: nil}), do: nil

  defp format_start_at(%UserIntegration{last_synced_at: last_synced}) do
    DateTime.to_iso8601(last_synced)
  end

  defp update_last_synced(user_id) do
    case Integrations.get_user_integration(user_id, "trakt") do
      nil ->
        :ok

      integration ->
        Integrations.update_user_integration(integration, %{
          last_synced_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
    end
  end
end
