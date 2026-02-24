defmodule Mydia.Repo.Migrations.RenameImportListsUniqueIndex do
  use Ecto.Migration

  def change do
    # Rename the unique index to match Ecto's default convention so that
    # unique_constraint/3 works on both SQLite and PostgreSQL without
    # needing a custom :name option.
    drop_if_exists unique_index(:import_lists, [:type, :media_type],
                     name: :import_lists_type_media_type_unique
                   )

    create_if_not_exists unique_index(:import_lists, [:type, :media_type],
                           name: :import_lists_type_media_type_index
                         )
  end
end
