defmodule Mydia.Repo.Migrations.CreateReleaseBlacklist do
  @moduledoc """
  Creates the release_blacklist table for U7 of the Usenet improvements rollout.

  When a download enters the `:error` state we record an `(indexer, guid)` pair
  here so the next search excludes the offending release. This implements the
  "filter, don't rank" convention: the orchestrators (TvShowSearch /
  MovieSearch) drop matching results before they reach `ReleaseRanker`.

  ## Columns

  - `indexer`   — the source indexer name, lowercased on write.
  - `guid`      — the release's stable identifier; falls back to a hash of
                  (indexer, title, size) when an indexer omits it.
  - `title`     — human-readable label shown in the admin UI.
  - `failure_reason` — short tag (e.g. `"par2_failed"`,
                  `"client_reported_failure"`, `"stalled"`).
  - `expires_at`— nullable TTL. NULL means blocked forever; non-null rows are
                  pruned by `Mydia.Jobs.BlacklistCleanup`.
  - `inserted_at` — timestamp of the block.

  ## Indexes

  A unique index on `(indexer, guid)` lets the context upsert duplicates
  rather than error.
  """
  use Ecto.Migration

  def change do
    create table(:release_blacklist, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :indexer, :string, null: false
      add :guid, :string, null: false
      add :title, :string, null: false
      add :failure_reason, :string, null: false
      add :expires_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:release_blacklist, [:indexer, :guid],
             name: :release_blacklist_indexer_guid_unique
           )

    # Index used by BlacklistCleanup to delete expired rows efficiently.
    create index(:release_blacklist, [:expires_at])
  end
end
