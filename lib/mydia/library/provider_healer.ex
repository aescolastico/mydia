defmodule Mydia.Library.ProviderHealer do
  @moduledoc """
  Backfills missing provider ids on a media item by parsing provider id tags
  embedded in its on-disk path.

  When a show/movie was matched via one provider (e.g. TVDB) but the on-disk path
  carries a different provider's id tag, the missing association is migrated onto
  the record ("auto heal") so naming templates can resolve that provider's token.
  Supported tag forms are `{tmdb-...}`, `{tmdbid-...}`, `[tmdb-...]`,
  `[tmdbid-...]`, `{tvdb-...}`, `{tvdbid-...}`, `[tvdb-...]`, `[tvdbid-...]`,
  `{imdb-...}`, `{imdbid-...}`, `[imdb-...]`, and `[imdbid-...]`.
  Runs during rename preview generation and scheduled library scans.

  Existing provider ids are never overwritten — only missing (`nil`/blank) ids
  are filled in. When multiple tags for the same provider appear, deeper path
  tags such as filename-level tags win over outer folder tags.
  """

  alias Mydia.Library.PathParser
  alias Mydia.Media.MediaItem

  require Logger

  @doc """
  Heals a media item's provider associations from a file path.

  Returns the (possibly updated) media item. When no provider tags are present in
  the path, or the relevant provider id is already set, the media item is
  returned unchanged.
  """
  @spec heal_from_path(MediaItem.t(), String.t()) :: MediaItem.t()
  def heal_from_path(%MediaItem{} = media_item, path) when is_binary(path) do
    path
    |> PathParser.extract_external_id_tags()
    |> Enum.reverse()
    |> Enum.reduce(media_item, fn {id, provider}, current_item ->
      heal_provider_id(current_item, provider, id)
    end)
  end

  def heal_from_path(media_item, _path), do: media_item

  defp heal_provider_id(%MediaItem{} = media_item, provider, raw_id) do
    field = provider_field(provider)

    with field when not is_nil(field) <- field,
         true <- blank_provider_id?(Map.get(media_item, field)),
         value when not is_nil(value) <- cast_provider_id(provider, raw_id),
         {:ok, updated} <-
           Mydia.Media.update_media_item(media_item, %{field => value},
             reason: "Healed #{provider} id from file path"
           ) do
      Logger.info("Healed provider association from file path",
        media_item_id: media_item.id,
        field: field,
        value: value
      )

      updated
    else
      _ -> media_item
    end
  end

  defp provider_field(:tmdb), do: :tmdb_id
  defp provider_field(:tvdb), do: :tvdb_id
  defp provider_field(:imdb), do: :imdb_id
  defp provider_field(_), do: nil

  defp blank_provider_id?(nil), do: true
  defp blank_provider_id?(""), do: true
  defp blank_provider_id?(_), do: false

  defp cast_provider_id(:imdb, id), do: id

  defp cast_provider_id(_provider, id) do
    case Integer.parse(id) do
      {int, ""} -> int
      :error -> nil
      {_int, _rest} -> nil
    end
  end
end
