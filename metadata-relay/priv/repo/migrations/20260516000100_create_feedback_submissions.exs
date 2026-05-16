defmodule MetadataRelay.Repo.Migrations.CreateFeedbackSubmissions do
  use Ecto.Migration

  def change do
    create table(:feedback_submissions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :message, :text, null: false
      add :contact, :string
      add :instance_id, :string
      add :mydia_version, :string
      add :source_ip, :string
      add :state, :string, null: false, default: "unread"
      add :github_ref, :string

      timestamps(type: :utc_datetime)
    end

    create index(:feedback_submissions, [:state, :inserted_at])
    create index(:feedback_submissions, [:type])
  end
end
