defmodule Mydia.Events.Structs.SearchEventMeta do
  @moduledoc "Metadata for search-related events."

  @derive Jason.Encoder

  defstruct [
    :title,
    :media_type,
    :query,
    :results_count,
    :indexers_searched,
    :filter_stats,
    :breakdown,
    :score,
    :selected_release,
    :all_results,
    :error_message,
    :episode_id,
    :season_number,
    :episode_number,
    :mode,
    :description
  ]

  @type t :: %__MODULE__{
          title: String.t() | nil,
          media_type: String.t() | nil,
          query: String.t() | nil,
          results_count: integer() | nil,
          indexers_searched: integer() | nil,
          filter_stats: map() | nil,
          breakdown: map() | nil,
          score: number() | nil,
          selected_release: String.t() | nil,
          all_results: map() | nil,
          error_message: String.t() | nil,
          episode_id: String.t() | integer() | nil,
          season_number: integer() | nil,
          episode_number: integer() | nil,
          mode: String.t() | nil,
          description: String.t() | nil
        }

  @known_keys %{
    "title" => :title,
    "media_type" => :media_type,
    "query" => :query,
    "results_count" => :results_count,
    "indexers_searched" => :indexers_searched,
    "filter_stats" => :filter_stats,
    "breakdown" => :breakdown,
    "score" => :score,
    "selected_release" => :selected_release,
    "all_results" => :all_results,
    "error_message" => :error_message,
    "episode_id" => :episode_id,
    "season_number" => :season_number,
    "episode_number" => :episode_number,
    "mode" => :mode,
    "description" => :description
  }

  @doc """
  Converts a string-key map to a `SearchEventMeta` struct.

  Unknown keys are silently ignored. Nested structures like `filter_stats`,
  `breakdown`, and `all_results` are preserved as-is (maps/lists).

  ## Examples

      iex> SearchEventMeta.from_map(%{"title" => "Breaking Bad", "query" => "Breaking Bad S01E01", "results_count" => 15})
      %SearchEventMeta{title: "Breaking Bad", query: "Breaking Bad S01E01", results_count: 15}
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    attrs =
      for {k, v} <- map,
          atom_key = Map.get(@known_keys, to_string(k)),
          into: %{},
          do: {atom_key, v}

    struct(__MODULE__, attrs)
  end
end
