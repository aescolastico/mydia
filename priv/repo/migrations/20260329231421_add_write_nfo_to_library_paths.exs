defmodule Mydia.Repo.Migrations.AddWriteNfoToLibraryPaths do
  use Ecto.Migration

  def change do
    alter table(:library_paths) do
      add :write_nfo, :boolean, default: false, null: false
    end
  end
end
