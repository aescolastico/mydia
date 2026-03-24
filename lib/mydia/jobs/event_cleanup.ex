defmodule Mydia.Jobs.EventCleanup do
  @moduledoc """
  Background job for cleaning up old events based on retention policy.

  Runs weekly to delete events older than the configured retention period.
  Default retention is 90 days.

  ## Configuration

  Set the retention period in your config:

      config :mydia, :event_retention_days, 90
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3

  require Logger
  alias Mydia.Events

  @default_retention_days 90

  @spec perform(Oban.Job.t()) :: :ok | {:ok, term()} | {:error, term()} | {:snooze, pos_integer()}
  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    retention_days = Application.get_env(:mydia, :event_retention_days, @default_retention_days)

    Logger.info("Starting event cleanup job",
      retention_days: retention_days
    )

    case Events.delete_old_events(retention_days) do
      {:ok, count} ->
        Logger.info("Event cleanup completed",
          deleted_count: count,
          retention_days: retention_days
        )

        :ok
    end
  end
end
