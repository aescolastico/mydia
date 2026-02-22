defmodule Mydia.Repo.Migrations.CreateUserIntegrations do
  use Ecto.Migration

  def change do
    create table(:user_integrations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :access_token, :string, null: false
      add :refresh_token, :string
      add :token_expires_at, :utc_datetime
      add :external_user_id, :string
      add :external_username, :string
      add :scopes, :string
      add :enabled, :boolean, null: false, default: true
      add :last_synced_at, :utc_datetime
      add :settings, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_integrations, [:user_id, :provider])
    create index(:user_integrations, [:provider])
  end
end
