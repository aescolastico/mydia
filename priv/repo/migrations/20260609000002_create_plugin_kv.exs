defmodule Mydia.Repo.Migrations.CreatePluginKv do
  use Ecto.Migration

  # Per-plugin key/value state (U3): watermarks, cursors, dedupe sets that must
  # survive across invocations. Gated by the `state:kv` capability.
  #
  # Dual-engine (SQLite + Postgres): `value` is :text. WIT `string` guarantees
  # valid Unicode, so KV values are always valid UTF-8 by construction — no raw
  # bytes ever reach this column (KTD10). Values are opaque strings to the host,
  # never JSON-decoded server-side.
  #
  # `plugin_config_id` is `null: false` with an `on_delete: :delete_all` cascade
  # (the full plugin_logs pattern, plus the not-null): an uninstall racing an
  # in-flight `kv-set` then fails on the FK constraint instead of resurrecting
  # state under a since-deleted plugin. The denormalized `plugin_slug` keys the
  # unique constraint and the per-plugin reads so a row is never orphaned from
  # its plugin identity.
  def change do
    create table(:plugin_kv, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :plugin_config_id,
          references(:plugin_configs, type: :binary_id, on_delete: :delete_all),
          null: false

      add :plugin_slug, :string, null: false
      add :key, :string, null: false
      add :value, :text

      timestamps(type: :utc_datetime_usec)
    end

    # One value per (plugin, key); also the upsert conflict target.
    create unique_index(:plugin_kv, [:plugin_slug, :key])
    # Per-plugin reads, key-count quota counts, and the conn/<id>/ prefix sweep.
    create index(:plugin_kv, [:plugin_slug])
  end
end
