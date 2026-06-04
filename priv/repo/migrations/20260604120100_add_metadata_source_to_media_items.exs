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

    repo().all(
      from(m in "media_items",
        where: m.type == "tv_show",
        select: %{id: m.id, tvdb_id: m.tvdb_id, tmdb_id: m.tmdb_id, metadata: m.metadata}
      )
    )
    |> Enum.each(fn row ->
      case derive_source(row) do
        nil ->
          :ok

        source ->
          repo().update_all(
            from(m in "media_items", where: m.id == ^row.id),
            set: [metadata_source: source]
          )
      end
    end)
  end

  def down do
    alter table(:media_items) do
      remove :metadata_source
    end
  end

  defp derive_source(%{tvdb_id: tvdb_id, tmdb_id: tmdb_id, metadata: metadata}) do
    provider_id = provider_id_from_metadata(metadata)

    cond do
      provider_id && tvdb_id && provider_id == to_string(tvdb_id) -> "tvdb"
      provider_id && tmdb_id && provider_id == to_string(tmdb_id) -> "tmdb"
      not is_nil(tvdb_id) -> "tvdb"
      not is_nil(tmdb_id) -> "tmdb"
      true -> nil
    end
  end

  defp provider_id_from_metadata(metadata) when is_binary(metadata) and metadata != "" do
    case Jason.decode(metadata) do
      {:ok, %{"provider_id" => provider_id}} when not is_nil(provider_id) ->
        to_string(provider_id)

      _ ->
        nil
    end
  end

  defp provider_id_from_metadata(_), do: nil
end
