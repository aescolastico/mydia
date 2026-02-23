defmodule Mydia.Repo.Migrations.AddTvdbId do
  use Ecto.Migration

  def change do
    alter table(:media_items) do
      add :tvdb_id, :integer
    end

    create unique_index(:media_items, [:tvdb_id],
             where: "tvdb_id IS NOT NULL",
             name: :media_items_tvdb_id_index
           )

    alter table(:media_requests) do
      add :tvdb_id, :integer
    end

    create index(:media_requests, [:tvdb_id])
  end
end
