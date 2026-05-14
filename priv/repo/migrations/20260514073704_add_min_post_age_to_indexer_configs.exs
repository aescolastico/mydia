defmodule Mydia.Repo.Migrations.AddMinPostAgeToIndexerConfigs do
  use Ecto.Migration

  def change do
    alter table(:indexer_configs) do
      # NZB-only filter: when set, results posted to Usenet within the last
      # `min_post_age_minutes` minutes are filtered out of search results so
      # the indexer has time to receive all article parts. Nullable: no
      # filtering by default. Torrent-protocol indexers ignore this field.
      add :min_post_age_minutes, :integer
    end
  end
end
