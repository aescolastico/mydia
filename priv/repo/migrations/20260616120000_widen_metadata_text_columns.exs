defmodule Mydia.Repo.Migrations.WidenMetadataTextColumns do
  use Ecto.Migration
  import Mydia.Repo.Migrations.Helpers

  @moduledoc """
  Widen long-capable metadata columns from VARCHAR(255) to TEXT on PostgreSQL.

  In Ecto a bare `:string` column compiles to `varchar(255)` on PostgreSQL but to
  unconstrained `TEXT` affinity on SQLite. Provider-supplied metadata (long
  localized episode titles, full original titles) and filesystem paths (deeply
  nested libraries) legitimately exceed 255 characters, so the same import that
  succeeds on SQLite fails on PostgreSQL with `ERROR 22001
  (string_data_right_truncation)`. This widens the affected columns to `TEXT`.

  On SQLite this migration is a no-op: `:string` and `:text` are both stored as
  unconstrained `TEXT` affinity, so the declared `varchar` length is ignored and
  no table rebuild is required.

  The UNIQUE btree index on `media_files.path` and the index on
  `media_items.title` are preserved automatically by `ALTER COLUMN ... TYPE` — no
  index drop/recreate is needed.

  Note on reversibility: the up direction (`VARCHAR(255)` -> `TEXT`) is widening
  and non-lossy. The down direction (`TEXT` -> `VARCHAR(255)`) is written for a
  rollback executed *before* any value exceeds 255 chars; once long values are
  stored, the narrowing will hard-fail on PostgreSQL. Rollback is therefore
  effectively one-way after the fix is in use.
  """

  @columns [
    {:media_items, :title},
    {:media_items, :original_title},
    {:episodes, :title},
    {:media_files, :path},
    {:media_files, :relative_path},
    {:media_files, :last_analysis_error}
  ]

  def up do
    if postgres?() do
      for {table, column} <- @columns do
        execute "ALTER TABLE #{table} ALTER COLUMN #{column} TYPE TEXT"
      end
    end
  end

  def down do
    if postgres?() do
      for {table, column} <- @columns do
        execute "ALTER TABLE #{table} ALTER COLUMN #{column} TYPE VARCHAR(255)"
      end
    end
  end
end
