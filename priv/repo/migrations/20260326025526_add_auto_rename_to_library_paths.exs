defmodule Mydia.Repo.Migrations.AddAutoRenameToLibraryPaths do
  use Ecto.Migration

  def change do
    alter table(:library_paths) do
      add :auto_rename, :boolean, default: true
    end

    # Set existing library paths to false to preserve current behavior.
    # Only new library paths will default to true.
    execute "UPDATE library_paths SET auto_rename = false", "SELECT 1"
  end
end
