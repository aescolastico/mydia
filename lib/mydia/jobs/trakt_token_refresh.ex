defmodule Mydia.Jobs.TraktTokenRefresh do
  @moduledoc """
  Oban worker that proactively refreshes Trakt tokens expiring within 7 days.
  """
  use Oban.Worker, queue: :integrations, max_attempts: 3

  alias Mydia.Integrations

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    integrations = Integrations.list_integrations_needing_refresh(7)

    Logger.info("Checking #{length(integrations)} integration(s) for token refresh")

    Enum.each(integrations, fn integration ->
      case Integrations.refresh_trakt_token(integration) do
        {:ok, _} ->
          Logger.info("Refreshed Trakt token for user #{integration.user_id}")

        {:error, reason} ->
          Logger.warning(
            "Failed to refresh Trakt token for user #{integration.user_id}: #{inspect(reason)}"
          )
      end
    end)

    :ok
  end
end
