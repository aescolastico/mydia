defmodule Mydia.Integrations.Trakt.Scrobbler do
  @moduledoc """
  Dispatches Trakt scrobble events (start, stop, progress) asynchronously.

  All scrobble calls are fire-and-forget via `Task.Supervisor` to avoid
  blocking playback or streaming operations.
  """

  alias Mydia.Integrations
  alias Mydia.Integrations.Trakt.Client
  alias Mydia.Media
  alias Mydia.Repo

  require Logger

  @doc """
  Fires a scrobble start event for the given user and content.
  `content_id` is `[media_item_id: id]` or `[episode_id: id]`.
  """
  def scrobble_start(user_id, content_id, progress_pct \\ 0.0) do
    dispatch_async(user_id, :start, content_id, progress_pct)
  end

  @doc """
  Fires a scrobble stop event (user finished or stopped watching).
  """
  def scrobble_stop(user_id, content_id, progress_pct \\ 100.0) do
    dispatch_async(user_id, :stop, content_id, progress_pct)
  end

  @doc """
  Fires a scrobble progress update.
  Only dispatches to avoid excessive API calls.
  """
  def scrobble_progress(user_id, content_id, progress_pct) do
    dispatch_async(user_id, :pause, content_id, progress_pct)
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp dispatch_async(user_id, action, content_id, progress_pct) do
    Task.Supervisor.start_child(Mydia.TaskSupervisor, fn ->
      do_scrobble(user_id, action, content_id, progress_pct)
    end)
  end

  defp do_scrobble(user_id, action, content_id, progress_pct) do
    with {:ok, token} <- Integrations.get_trakt_token(user_id),
         {:ok, body} <- build_scrobble_body(content_id, progress_pct) do
      result =
        case action do
          :start -> Client.scrobble_start(body, token)
          :stop -> Client.scrobble_stop(body, token)
          :pause -> Client.scrobble_pause(body, token)
        end

      case result do
        {:ok, _} ->
          Logger.debug("Trakt scrobble #{action} succeeded for user #{user_id}")

        {:error, reason} ->
          Logger.warning(
            "Trakt scrobble #{action} failed for user #{user_id}: #{inspect(reason)}"
          )
      end
    else
      {:error, :not_connected} -> :ok
      {:error, :disabled} -> :ok
      {:error, reason} -> Logger.debug("Skipping scrobble: #{inspect(reason)}")
    end
  end

  @doc false
  def build_scrobble_body(content_id, progress_pct) do
    case content_id do
      [media_item_id: id] ->
        build_movie_body(id, progress_pct)

      [episode_id: id] ->
        build_episode_body(id, progress_pct)

      _ ->
        {:error, :unknown_content_type}
    end
  end

  defp build_movie_body(media_item_id, progress_pct) do
    case Repo.get(Media.MediaItem, media_item_id) do
      nil ->
        {:error, :not_found}

      %{type: "movie"} = item ->
        movie =
          %{title: item.title, year: item.year}
          |> maybe_put_ids(item)

        {:ok, %{movie: movie, progress: progress_pct}}

      _ ->
        {:error, :not_a_movie}
    end
  end

  defp build_episode_body(episode_id, progress_pct) do
    case Repo.get(Media.Episode, episode_id) |> Repo.preload(:media_item) do
      nil ->
        {:error, :not_found}

      episode ->
        show = episode.media_item

        show_data =
          %{title: show.title, year: show.year}
          |> maybe_put_ids(show)

        episode_data = %{
          season: episode.season_number,
          number: episode.episode_number
        }

        {:ok, %{show: show_data, episode: episode_data, progress: progress_pct}}
    end
  end

  defp maybe_put_ids(map, item) do
    map
    |> then(fn m ->
      if item.imdb_id, do: Map.put(m, :ids, %{imdb: item.imdb_id}), else: m
    end)
    |> then(fn m ->
      if item.tmdb_id do
        ids = Map.get(m, :ids, %{})
        Map.put(m, :ids, Map.put(ids, :tmdb, item.tmdb_id))
      else
        m
      end
    end)
    |> then(fn m ->
      if item.tvdb_id do
        ids = Map.get(m, :ids, %{})
        Map.put(m, :ids, Map.put(ids, :tvdb, item.tvdb_id))
      else
        m
      end
    end)
  end
end
