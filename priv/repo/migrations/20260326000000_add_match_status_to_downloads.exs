defmodule Mydia.Repo.Migrations.AddMatchStatusToDownloads do
  use Ecto.Migration

  def change do
    alter table(:downloads) do
      add :match_status, :string
    end
  end
end
