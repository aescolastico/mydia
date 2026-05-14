defmodule Mydia.Jobs.BlacklistCleanup do
  @moduledoc """
  Periodic Oban worker that purges expired release-blacklist rows (issue
  #123).

  Rows whose `expires_at` is in the past are deleted. Rows with `expires_at
  = nil` (blocked forever) are left alone.

  Scheduled daily via the Oban cron entry in `config/config.exs`.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3

  require Logger

  alias Mydia.Downloads.Blacklists

  @spec perform(Oban.Job.t()) :: :ok
  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    deleted = Blacklists.cleanup_expired()

    Logger.info("Release blacklist cleanup completed",
      deleted_count: deleted
    )

    :ok
  end
end
