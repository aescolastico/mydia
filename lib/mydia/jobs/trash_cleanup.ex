defmodule Mydia.Jobs.TrashCleanup do
  @moduledoc """
  Background job for permanently deleting media files that have been in trash
  beyond the configured retention period.

  Runs daily to purge trashed files older than the retention period.
  Default retention is 30 days.

  ## Configuration

  Set the retention period in your config:

      config :mydia, :trash_retention_days, 30
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3

  require Logger
  alias Mydia.Library

  @default_retention_days 30

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    retention_days = Application.get_env(:mydia, :trash_retention_days, @default_retention_days)

    Logger.info("Starting trash cleanup job",
      retention_days: retention_days
    )

    case Library.purge_old_trashed_media_files(retention_days) do
      {:ok, count} ->
        Logger.info("Trash cleanup completed",
          deleted_count: count,
          retention_days: retention_days
        )

        :ok
    end
  end
end
