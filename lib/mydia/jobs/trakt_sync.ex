defmodule Mydia.Jobs.TraktSync do
  @moduledoc """
  Oban worker for syncing data between Mydia and Trakt.tv.

  Supports sync types: "history", "ratings", "collection", "watchlist", "full".
  """
  use Oban.Worker, queue: :integrations, max_attempts: 3

  alias Mydia.Integrations.Trakt.Sync

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "sync_type" => sync_type}}) do
    Logger.info("Starting Trakt #{sync_type} sync for user #{user_id}")

    result =
      case sync_type do
        "full" -> Sync.sync_all(user_id)
        "history" -> Sync.sync_history(user_id)
        "ratings" -> Sync.sync_ratings(user_id)
        "collection" -> Sync.sync_collection(user_id)
        "watchlist" -> Sync.sync_watchlist(user_id)
        other -> {:error, "Unknown sync type: #{other}"}
      end

    case result do
      {:ok, _} ->
        Logger.info("Trakt #{sync_type} sync completed for user #{user_id}")
        :ok

      {:error, :not_connected} ->
        Logger.debug("Skipping Trakt sync for user #{user_id}: not connected")
        :ok

      {:error, :disabled} ->
        Logger.debug("Skipping Trakt sync for user #{user_id}: disabled")
        :ok

      {:error, reason} ->
        Logger.error("Trakt #{sync_type} sync failed for user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
