defmodule Mydia.Repo.Migrations.MakeMediaFilesPathNullable do
  @moduledoc """
  Make the `path` column nullable in `media_files` table.

  The `path` field is deprecated in favor of `relative_path` + `library_path_id`.
  This migration allows new media files to be created without an absolute path.

  Note: SQLite doesn't support ALTER COLUMN, so we recreate the table.
  PostgreSQL supports ALTER COLUMN directly.
  """

  use Ecto.Migration
  import Mydia.Repo.Migrations.Helpers

  def up do
    # Drop the unique index on path first
    drop_if_exists unique_index(:media_files, [:path])

    # Use database-specific approach
    if postgres?() do
      # PostgreSQL: simply alter the column
      execute "ALTER TABLE media_files ALTER COLUMN path DROP NOT NULL"
    else
      # SQLite: recreate the table with nullable path
      # Strategy: create new table with temp name, copy data, drop original, rename.
      # This preserves FK references in other tables (subtitles, transcode_jobs, etc.)
      execute """
      CREATE TABLE "media_files_new" (
        "id" TEXT PRIMARY KEY,
        "media_item_id" TEXT CONSTRAINT "media_files_media_item_id_fkey" REFERENCES "media_items"("id") ON DELETE CASCADE,
        "episode_id" TEXT CONSTRAINT "media_files_episode_id_fkey" REFERENCES "episodes"("id") ON DELETE CASCADE,
        "path" TEXT,
        "size" INTEGER,
        "quality_profile_id" TEXT CONSTRAINT "media_files_quality_profile_id_fkey" REFERENCES "quality_profiles"("id"),
        "resolution" TEXT,
        "codec" TEXT,
        "hdr_format" TEXT,
        "audio_codec" TEXT,
        "bitrate" INTEGER,
        "verified_at" TEXT,
        "metadata" TEXT,
        "relative_path" TEXT,
        "library_path_id" TEXT CONSTRAINT "media_files_library_path_id_fkey" REFERENCES "library_paths"("id") ON DELETE CASCADE,
        "inserted_at" TEXT NOT NULL,
        "updated_at" TEXT NOT NULL
      )
      """

      execute """
      INSERT INTO media_files_new (id, media_item_id, episode_id, path, size, quality_profile_id,
                               resolution, codec, hdr_format, audio_codec, bitrate, verified_at,
                               metadata, relative_path, library_path_id, inserted_at, updated_at)
      SELECT id, media_item_id, episode_id, path, size, quality_profile_id,
             resolution, codec, hdr_format, audio_codec, bitrate, verified_at,
             metadata, relative_path, library_path_id, inserted_at, updated_at
      FROM media_files
      """

      drop table(:media_files)
      rename table(:media_files_new), to: table(:media_files)

      # Recreate indexes
      create index(:media_files, [:media_item_id])
      create index(:media_files, [:episode_id])
      create index(:media_files, [:library_path_id])
    end
  end

  def down do
    if postgres?() do
      # PostgreSQL: add NOT NULL back (will fail if there are NULL values)
      execute "ALTER TABLE media_files ALTER COLUMN path SET NOT NULL"
      create unique_index(:media_files, [:path])
    else
      # SQLite: recreate with NOT NULL constraint (same create-new strategy)
      execute """
      CREATE TABLE "media_files_new" (
        "id" TEXT PRIMARY KEY,
        "media_item_id" TEXT CONSTRAINT "media_files_media_item_id_fkey" REFERENCES "media_items"("id") ON DELETE CASCADE,
        "episode_id" TEXT CONSTRAINT "media_files_episode_id_fkey" REFERENCES "episodes"("id") ON DELETE CASCADE,
        "path" TEXT NOT NULL,
        "size" INTEGER,
        "quality_profile_id" TEXT CONSTRAINT "media_files_quality_profile_id_fkey" REFERENCES "quality_profiles"("id"),
        "resolution" TEXT,
        "codec" TEXT,
        "hdr_format" TEXT,
        "audio_codec" TEXT,
        "bitrate" INTEGER,
        "verified_at" TEXT,
        "metadata" TEXT,
        "relative_path" TEXT,
        "library_path_id" TEXT CONSTRAINT "media_files_library_path_id_fkey" REFERENCES "library_paths"("id") ON DELETE CASCADE,
        "inserted_at" TEXT NOT NULL,
        "updated_at" TEXT NOT NULL
      )
      """

      execute """
      INSERT INTO media_files_new (id, media_item_id, episode_id, path, size, quality_profile_id,
                               resolution, codec, hdr_format, audio_codec, bitrate, verified_at,
                               metadata, relative_path, library_path_id, inserted_at, updated_at)
      SELECT id, media_item_id, episode_id, path, size, quality_profile_id,
             resolution, codec, hdr_format, audio_codec, bitrate, verified_at,
             metadata, relative_path, library_path_id, inserted_at, updated_at
      FROM media_files
      """

      drop table(:media_files)
      rename table(:media_files_new), to: table(:media_files)

      create unique_index(:media_files, [:path])
      create index(:media_files, [:media_item_id])
      create index(:media_files, [:episode_id])
      create index(:media_files, [:library_path_id])
    end
  end
end
