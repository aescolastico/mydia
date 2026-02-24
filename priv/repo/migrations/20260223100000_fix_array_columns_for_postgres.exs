defmodule Mydia.Repo.Migrations.FixArrayColumnsForPostgres do
  use Ecto.Migration
  import Mydia.Repo.Migrations.Helpers

  @moduledoc """
  Convert columns that store JSON-encoded arrays from text to text[] on PostgreSQL.

  These columns were originally created as :text (which works on SQLite) but their
  Ecto schemas define them as {:array, :string}. PostgreSQL requires proper text[]
  columns for this type mapping.

  On SQLite this migration is a no-op since :text columns handle JSON arrays fine.

  The conversion uses a two-step approach per column because PostgreSQL doesn't
  support subqueries in ALTER COLUMN USING expressions:
  1. Add a temporary text[] column
  2. Populate it from the JSON text via a subquery UPDATE
  3. Drop the old column and rename the new one
  """

  @columns [
    {:api_keys, :permissions},
    {:indexer_configs, :indexer_ids},
    {:indexer_configs, :categories},
    {:remote_access_config, :direct_urls}
  ]

  def up do
    if postgres?() do
      for {table, column} <- @columns do
        # Step 1: Add temp column
        execute "ALTER TABLE #{table} ADD COLUMN #{column}_new text[]"

        # Step 2: Populate from JSON text using UPDATE with subquery
        execute """
        UPDATE #{table}
        SET #{column}_new = (
          SELECT array_agg(elem)
          FROM jsonb_array_elements_text(#{column}::jsonb) AS elem
        )
        WHERE #{column} IS NOT NULL AND #{column} != ''
        """

        # Step 3: Drop old, rename new
        execute "ALTER TABLE #{table} DROP COLUMN #{column}"
        execute "ALTER TABLE #{table} RENAME COLUMN #{column}_new TO #{column}"
      end
    end
  end

  def down do
    if postgres?() do
      for {table, column} <- @columns do
        # Step 1: Add temp text column
        execute "ALTER TABLE #{table} ADD COLUMN #{column}_new text"

        # Step 2: Convert array back to JSON text
        execute """
        UPDATE #{table}
        SET #{column}_new = (
          SELECT jsonb_agg(elem)::text
          FROM unnest(#{column}) AS elem
        )
        WHERE #{column} IS NOT NULL
        """

        # Step 3: Drop old, rename new
        execute "ALTER TABLE #{table} DROP COLUMN #{column}"
        execute "ALTER TABLE #{table} RENAME COLUMN #{column}_new TO #{column}"
      end
    end
  end
end
