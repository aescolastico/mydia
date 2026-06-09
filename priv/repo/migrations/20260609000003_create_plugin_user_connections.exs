defmodule Mydia.Repo.Migrations.CreatePluginUserConnections do
  use Ecto.Migration

  # Per-user connections a plugin holds (U7): the OAuth token plus the external
  # account identity and a status lifecycle. The host stores and lifecycle-manages
  # these; the plugin reads identity + status (never the token) via
  # connections-list, and references a connection by id for host-attached auth.
  #
  # Dual-engine (SQLite + Postgres): `meta` is :text via Mydia.Settings.JsonMapType;
  # `access_token` is a plain string column, matching the user_integrations
  # precedent (encryption-at-rest is a tracked follow-up across both tables). The
  # schema marks it `redact: true` so struct inspection never leaks it into logs.
  #
  # `plugin_config_id` is `null: false` with `on_delete: :delete_all` (the
  # plugin_logs/plugin_kv pattern), so uninstalling a plugin cascades its
  # connections; `user_id` cascades on user deletion. The denormalized
  # `plugin_slug` keys the unique constraint and the per-plugin reads.
  def change do
    create table(:plugin_user_connections, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :plugin_config_id,
          references(:plugin_configs, type: :binary_id, on_delete: :delete_all),
          null: false

      add :plugin_slug, :string, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :status, :string, null: false, default: "connected"
      add :access_token, :string
      add :external_user_id, :string
      add :external_username, :string
      add :meta, :text

      timestamps(type: :utc_datetime_usec)
    end

    # One connection per (plugin, user); the consent boundary.
    create unique_index(:plugin_user_connections, [:plugin_slug, :user_id])
    # Per-plugin reads (connections-list, consent-scoping) and uninstall counts.
    create index(:plugin_user_connections, [:plugin_slug])
    # Cascade-driving lookups on user deletion.
    create index(:plugin_user_connections, [:user_id])
  end
end
