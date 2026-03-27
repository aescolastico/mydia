defmodule Mydia.Repo.Migrations.AddMatchStatusToDownloads do
  use Ecto.Migration

  def change do
    alter table(:downloads) do
      add :match_status, :string
    end

    create index(:downloads, [:match_status])
  end
end
