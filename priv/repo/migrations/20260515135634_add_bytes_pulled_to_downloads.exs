defmodule Mydia.Repo.Migrations.AddBytesPulledToDownloads do
  use Ecto.Migration

  def change do
    alter table(:downloads) do
      add :bytes_pulled, :bigint
    end
  end
end
