defmodule Mydia.Repo.Migrations.AddUsenetImprovementColumns do
  use Ecto.Migration

  @moduledoc """
  Wave-2 schema foundation for the Usenet improvements rollout.

  Additive only. No NOT NULL constraints on existing rows.

  download_client_configs:
    - webhook_secret: server-generated secret used to authenticate post-processing
      webhooks (SABnzbd/NZBGet). Nullable; populated on next save via the schema
      changeset auto-generate path. Never cast from user input.
    - categories: JSON map keyed by content_type ("movie", "tv", "music") -> client
      native category string. Replaces the single `:category` column eventually;
      kept alongside for backwards compatibility.
    - priority_profile: JSON map of 5-tier priority taxonomy
      (:verylow|:low|:normal|:high|:veryhigh) -> client-native string/int. Empty
      map falls back to today's hardcoded mapping in each adapter.
    - incomplete_grace_minutes: stall detection grace window. Defaults to 60.

  downloads:
    - last_progress_at: timestamp of last observed progress increment. Used by
      the stall-detection circuit breaker. Nullable for pre-existing rows.
    - last_known_bytes: bytes downloaded at last_progress_at. Defaults to 0.
  """

  def change do
    alter table(:download_client_configs) do
      add :webhook_secret, :string
      add :categories, :map, default: %{}
      add :priority_profile, :map, default: %{}
      add :incomplete_grace_minutes, :integer, default: 60
    end

    alter table(:downloads) do
      add :last_progress_at, :utc_datetime_usec
      add :last_known_bytes, :integer, default: 0
    end
  end
end
