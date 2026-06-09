defmodule Mydia.Jobs.PluginLogCleanup do
  @moduledoc """
  Periodic Oban worker that prunes per-invocation plugin debug logs (U5, R6).

  Two retention policies apply together (see `Mydia.Plugins.Logs.prune/1`):

    * rows older than `max_age_days` are deleted, and
    * per plugin, only the most recent `max_invocations_per_plugin`
      invocations' rows are kept.

  Both bounds are tunable via the cron entry's `args` in `config/config.exs`;
  the defaults below apply otherwise. Scheduled via `Oban.Plugins.Cron`.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3

  require Logger

  alias Mydia.Plugins.Logs

  @default_max_age_days 7
  @default_max_invocations 200

  @spec perform(Oban.Job.t()) :: :ok
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    opts = [
      max_age_days: Map.get(args, "max_age_days", @default_max_age_days),
      max_invocations_per_plugin:
        Map.get(args, "max_invocations_per_plugin", @default_max_invocations)
    ]

    {:ok, deleted} = Logs.prune(opts)

    Logger.info("plugin log cleanup completed", deleted_count: deleted)

    :ok
  end
end
