defmodule Mydia.Jobs.PluginUpdateCheck do
  @moduledoc """
  Periodic check for newer versions of installed plugins (U8, R14).

  Delegates to `Mydia.Plugins.check_for_updates/1`, which fetches every
  configured source, compares versions against installed plugins, and emits a
  `plugin.update_available` event for each newer version found. The admin UI
  (U9) surfaces those as an update badge. Scheduled via `Oban.Plugins.Cron`.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3

  require Logger

  @spec perform(Oban.Job.t()) :: :ok
  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    updates = Mydia.Plugins.check_for_updates()

    if updates != [] do
      Logger.info("plugin update check found #{length(updates)} update(s) available")
    end

    :ok
  end
end
