defmodule Mydia.Repo.Migrations.AddScheduleFieldsToPluginConfigs do
  use Ecto.Migration

  # Scheduler bookkeeping for the fixed-interval plugin tick (U4).
  #
  # `last_scheduled_at` is written on *completion* of a scheduled run, so a crash
  # mid-invocation re-runs on the next due tick (acceptable because R15
  # idempotence holds). `consecutive_schedule_failures` drives exponential
  # backoff; it is `null: false, default: 0` because nullable counter arithmetic
  # is a silent-skip bug.
  def change do
    alter table(:plugin_configs) do
      add :last_scheduled_at, :utc_datetime_usec
      add :consecutive_schedule_failures, :integer, null: false, default: 0
    end
  end
end
