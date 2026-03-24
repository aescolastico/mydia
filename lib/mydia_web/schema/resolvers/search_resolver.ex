defmodule MydiaWeb.Schema.Resolvers.SearchResolver do
  @moduledoc """
  Resolvers for search-related GraphQL queries.
  """

  alias Mydia.Media

  alias Mydia.Metadata.Access, as: MetadataAccess
  alias Mydia.Metadata.ImageUrl

  @spec search(map(), map(), Absinthe.Resolution.t()) :: {:ok, term()} | {:error, term()}
  def search(_parent, %{query: query} = args, _info) when byte_size(query) > 0 do
    first = Map.get(args, :first, 20)
    types = Map.get(args, :types)

    # Build query options with search term
    opts = [search: query]

    opts =
      if types do
        type_filter =
          cond do
            :movie in types and :tv_show in types -> nil
            :movie in types -> "movie"
            :tv_show in types -> "tv_show"
            true -> nil
          end

        if type_filter, do: Keyword.put(opts, :type, type_filter), else: opts
      else
        opts
      end

    # Perform search
    results =
      Media.list_media_items(opts)
      |> Enum.take(first)
      |> Enum.map(&build_search_result/1)

    {:ok,
     %{
       results: results,
       total_count: length(results)
     }}
  end

  def search(_parent, _args, _info) do
    {:ok, %{results: [], total_count: 0}}
  end

  defp build_search_result(media_item) do
    %{
      id: media_item.id,
      type: String.to_existing_atom(media_item.type),
      title: media_item.title,
      year: media_item.year,
      artwork: build_artwork(media_item),
      score: nil
    }
  end

  defp build_artwork(%{metadata: nil}), do: nil

  defp build_artwork(%{metadata: metadata}) do
    poster_path = MetadataAccess.get(metadata, :poster_path)
    backdrop_path = MetadataAccess.get(metadata, :backdrop_path)

    %{
      poster_url: ImageUrl.poster_url(poster_path),
      backdrop_url: ImageUrl.backdrop_url(backdrop_path),
      thumbnail_url: nil
    }
  end

  defp build_artwork(_), do: nil
end
