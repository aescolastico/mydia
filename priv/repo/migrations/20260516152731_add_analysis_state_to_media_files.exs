defmodule Mydia.Repo.Migrations.AddAnalysisStateToMediaFiles do
  use Ecto.Migration

  def change do
    alter table(:media_files) do
      add :analyzed_at, :utc_datetime
      add :analysis_attempts, :integer, default: 0, null: false
      add :last_analysis_error, :text
    end

    create index(:media_files, [:analysis_attempts, :inserted_at, :id],
             where: "analyzed_at IS NULL",
             name: :media_files_unanalyzed_idx
           )

    execute(
      "UPDATE media_files SET analyzed_at = updated_at WHERE codec IS NOT NULL",
      "UPDATE media_files SET analyzed_at = NULL"
    )
  end
end
