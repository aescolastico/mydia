defmodule Mydia.Repo.Migrations.AddMetadataSourceToMediaItems do
  use Ecto.Migration
  import Ecto.Query

  @moduledoc """
  Adds an authoritative `metadata_source` provenance column to media_items and
  backfills existing TV shows.

  Provenance cannot be inferred from `tvdb_id`/`tmdb_id` presence alone: a
  TMDB-matched show can carry a back-filled `tvdb_id`. The true signal is which
  id actually fetched the stored metadata, recorded as `metadata.provider_id`.
  The backfill compares `provider_id` against the id columns and only falls back
  to id presence when `provider_id` is absent or unparseable.
  """

  def up do
    alter table(:media_items) do
      add :metadata_source, :string
    end

    flush()

    rows =
      repo().all(
        from(m in "media_items",
          where: m.type == "tv_show",
          select: %{id: m.id, tvdb_id: m.tvdb_id, tmdb_id: m.tmdb_id, metadata: m.metadata}
        )
      )

    # Partition rows by derived source, skipping any that resolve to nil.
    # Chunking at 900 keeps us inside SQLite's 999 bound-parameter ceiling
    # (Postgres is unaffected by this limit but benefits from fewer round-trips too).
    rows
    |> Enum.reduce(%{"tvdb" => [], "tmdb" => []}, fn row, acc ->
      case derive_source(row) do
        nil -> acc
        source -> Map.update!(acc, source, &[row.id | &1])
      end
    end)
    |> Enum.each(fn {source, ids} ->
      ids
      |> Enum.chunk_every(900)
      |> Enum.each(fn chunk ->
        repo().update_all(
          from(m in "media_items", where: m.id in ^chunk),
          set: [metadata_source: source]
        )
      end)
    end)
  end

  def down do
    alter table(:media_items) do
      remove :metadata_source
    end
  end

  @doc false
  def derive_source(%{tvdb_id: tvdb_id, tmdb_id: tmdb_id, metadata: metadata}) do
    provider_id = provider_id_from_metadata(metadata)

    cond do
      provider_id && tvdb_id && provider_id == to_string(tvdb_id) -> "tvdb"
      provider_id && tmdb_id && provider_id == to_string(tmdb_id) -> "tmdb"
      not is_nil(tvdb_id) -> "tvdb"
      not is_nil(tmdb_id) -> "tmdb"
      true -> nil
    end
  end

  @doc false
  def provider_id_from_metadata(metadata) when is_binary(metadata) and metadata != "" do
    case Jason.decode(metadata) do
      {:ok, %{"provider_id" => provider_id}} when not is_nil(provider_id) ->
        to_string(provider_id)

      _ ->
        nil
    end
  end

  @doc false
  def provider_id_from_metadata(_), do: nil
end
