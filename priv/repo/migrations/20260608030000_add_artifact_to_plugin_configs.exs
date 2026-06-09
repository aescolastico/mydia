defmodule Mydia.Repo.Migrations.AddArtifactToPluginConfigs do
  use Ecto.Migration

  # Persist the verified wasm artifact and the plugin manifest so an installed
  # plugin can be activated at boot without re-fetching from its source (offline
  # boot, self-hosted). `wasm_module` is a true binary column (SQLite BLOB /
  # Postgres BYTEA) — raw bytes belong here, never in a :text/:string column
  # (KTD10). `manifest` is :text JSON via Mydia.Settings.JsonMapType.
  def change do
    alter table(:plugin_configs) do
      add :wasm_module, :binary
      add :manifest, :text
    end
  end
end
