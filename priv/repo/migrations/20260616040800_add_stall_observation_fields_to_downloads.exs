defmodule Mydia.Repo.Migrations.AddStallObservationFieldsToDownloads do
  use Ecto.Migration

  def change do
    alter table(:downloads) do
      # Timestamp of the most recent poll in which this download was both
      # observable (client reachable) and actively downloading. The stall clock
      # only accrues over observed, active time; a gap since this value resets
      # the clock so a client outage or Mydia restart can't false-stall a live
      # torrent. Nil for rows created before this column existed.
      add :last_observed_at, :utc_datetime_usec

      # Marks a recoverable *soft* stall: set when a download is first detected
      # stalled, cleared on resumed progress or an observation-gap reset. Kept
      # distinct from the terminal `import_failed_at` so a soft stall keeps
      # occupying its episode and only escalates to a terminal failure after a
      # longer threshold. Nil when not soft-stalled.
      add :stalled_since, :utc_datetime_usec
    end
  end
end
