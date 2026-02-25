defmodule Mydia.Repo.Migrations.AddTrashedAtToMediaFiles do
  use Ecto.Migration

  def change do
    alter table(:media_files) do
      add :trashed_at, :utc_datetime
    end

    create index(:media_files, [:trashed_at])
  end
end
