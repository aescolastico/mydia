defmodule Mydia.Repo.Migrations.AddTvMetadataSourceToLibraryPaths do
  use Ecto.Migration

  def change do
    alter table(:library_paths) do
      add :tv_metadata_source, :string, default: "tvdb", null: false
    end
  end
end
