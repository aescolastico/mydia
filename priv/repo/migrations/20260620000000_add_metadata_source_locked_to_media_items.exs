defmodule Mydia.Repo.Migrations.AddMetadataSourceLockedToMediaItems do
  use Ecto.Migration

  # Marks a TV show whose provider was chosen explicitly (e.g. a folder tagged
  # `{tmdb-...}`/`[tvdbid-...]`). Locked shows are never auto-reidentified to
  # a different provider on refresh, even when the library prefers another one.
  # Portable boolean column add — works on both SQLite and PostgreSQL.
  def change do
    alter table(:media_items) do
      add :metadata_source_locked, :boolean, default: false, null: false
    end
  end
end
