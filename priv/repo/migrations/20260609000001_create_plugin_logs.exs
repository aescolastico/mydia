defmodule Mydia.Repo.Migrations.CreatePluginLogs do
  use Ecto.Migration

  # Per-invocation debug log lines for the plugin platform (U1). Three sources
  # converge here keyed by `invocation_id`: guest `log()` calls, captured WASI
  # stdout/stderr, and host invocation/outcome markers.
  #
  # Dual-engine (SQLite + Postgres): `message` and `metadata` are :text. Guest
  # output is sanitized to valid UTF-8 before insert (KTD10 — raw bytes pass on
  # SQLite but fail Postgres with a UTF-8 error). `metadata` is JSON via
  # Mydia.Settings.JsonMapType. Logs are immutable: inserted_at only.
  #
  # `plugin_config_id` is nullable so logs survive a config delete only via the
  # FK cascade; queries are driven by the denormalized `slug` so a log row is
  # never orphaned from its plugin identity.
  def change do
    create table(:plugin_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :plugin_config_id,
          references(:plugin_configs, type: :binary_id, on_delete: :delete_all)

      add :slug, :string, null: false
      add :invocation_id, :string, null: false
      add :source, :string, null: false
      add :level, :string, null: false
      add :message, :text
      add :metadata, :text
      add :test_run, :boolean, null: false, default: false

      # Microsecond precision keeps a single invocation's rows ordered (see
      # Mydia.Plugins.Log).
      timestamps(inserted_at: :inserted_at, updated_at: false, type: :utc_datetime_usec)
    end

    # Tail query for the detail UI (most-recent per plugin) and the per-plugin
    # retention sweep both lead with slug + time.
    create index(:plugin_logs, [:slug, :inserted_at])
    # Grouping a run's lines and the per-plugin invocation-cap sweep.
    create index(:plugin_logs, [:invocation_id])
  end
end
