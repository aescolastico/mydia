defmodule Mydia.Repo.Migrations.CreatePluginConfigs do
  use Ecto.Migration

  # Dual-engine (SQLite + Postgres): `settings` and `granted_capabilities` are
  # :text columns holding JSON (via Mydia.Settings.JsonMapType); integrity_hash
  # is an ASCII hex string (Base.encode16), never raw bytes — raw bytes pass on
  # SQLite but fail Postgres with a UTF-8 error (KTD10).
  def change do
    create table(:plugin_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :version, :string
      add :enabled, :boolean, default: false
      add :priority, :integer, default: 1
      add :settings, :text
      add :granted_capabilities, :text
      add :source_url, :string
      add :integrity_hash, :string
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:plugin_configs, [:slug])
    create index(:plugin_configs, [:enabled])
  end
end
