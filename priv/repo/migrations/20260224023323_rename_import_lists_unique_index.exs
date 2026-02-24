defmodule Mydia.Repo.Migrations.RenameImportListsUniqueIndex do
  use Ecto.Migration

  # Rename the unique index to match Ecto's default naming convention
  # so that unique_constraint/3 works without a custom :name option.
  #
  # SQLite matches constraints by columns (name doesn't matter), but
  # PostgreSQL matches by the actual index name. The original migration
  # created the index as "import_lists_type_media_type_unique" while
  # Ecto's default is "import_lists_type_media_type_index".
  #
  # SQLite doesn't support ALTER INDEX, but doesn't need the rename.

  def up do
    if repo().__adapter__() == Ecto.Adapters.Postgres do
      execute(
        "ALTER INDEX IF EXISTS import_lists_type_media_type_unique RENAME TO import_lists_type_media_type_index"
      )
    end
  end

  def down do
    if repo().__adapter__() == Ecto.Adapters.Postgres do
      execute(
        "ALTER INDEX IF EXISTS import_lists_type_media_type_index RENAME TO import_lists_type_media_type_unique"
      )
    end
  end
end
