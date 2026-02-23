defmodule Mydia.Metadata.Structs.SeasonData do
  @moduledoc """
  Represents TV season data from TMDB via the metadata relay service.

  This struct provides compile-time safety for season data, replacing
  plain map access that can silently return nil.
  """

  alias Mydia.Metadata.Structs.EpisodeData

  @enforce_keys [:season_number]
  defstruct [
    # Required fields
    :season_number,
    # Optional fields
    :name,
    :overview,
    :air_date,
    :poster_path,
    :episode_count,
    :episodes
  ]

  @type t :: %__MODULE__{
          season_number: integer(),
          name: String.t() | nil,
          overview: String.t() | nil,
          air_date: Date.t() | nil,
          poster_path: String.t() | nil,
          episode_count: integer() | nil,
          episodes: [EpisodeData.t()] | nil
        }

  @doc """
  Creates a SeasonData struct from a raw API response map.

  ## Examples

      iex> from_api_response(%{"season_number" => 1, "episodes" => [...], ...})
      %SeasonData{season_number: 1, episodes: [%EpisodeData{}, ...], ...}
  """
  def from_api_response(data) when is_map(data) do
    episodes = data["episodes"] || []

    %__MODULE__{
      season_number: data["season_number"],
      name: data["name"],
      overview: data["overview"],
      air_date: parse_date(data["air_date"]),
      poster_path: data["poster_path"],
      episode_count: length(episodes),
      episodes: Enum.map(episodes, &EpisodeData.from_api_response/1)
    }
  end

  @doc """
  Creates a SeasonData struct from a TVDB extended season response.

  TVDB season extended endpoint returns season details with episodes
  nested under the `"episodes"` key. Translations are in TranslationExtended
  format: `%{"nameTranslations" => [...], "overviewTranslations" => [...]}`.
  """
  def from_tvdb_response(data) when is_map(data) do
    episodes = data["episodes"] || []

    # Extract English translations if available.
    # TVDB season extended returns translations in TranslationExtended format:
    #   %{"nameTranslations" => [%{"language" => "eng", "name" => "..."}, ...],
    #     "overviewTranslations" => [%{"language" => "eng", "overview" => "..."}, ...]}
    {english_name, english_overview} = extract_english_from_translations(data["translations"])

    %__MODULE__{
      season_number: data["number"],
      name: english_name || data["name"] || "Season #{data["number"]}",
      overview: english_overview || data["overview"],
      air_date: nil,
      poster_path: data["image"],
      episode_count: length(episodes),
      episodes: Enum.map(episodes, &EpisodeData.from_tvdb_response/1)
    }
  end

  # Handle TranslationExtended format (TVDB season/series extended):
  #   %{"nameTranslations" => [%{"language" => "eng", "name" => "..."}, ...],
  #     "overviewTranslations" => [%{"language" => "eng", "overview" => "..."}, ...]}
  defp extract_english_from_translations(%{} = t) do
    english_name = find_english_in_list(t["nameTranslations"], "name")
    english_overview = find_english_in_list(t["overviewTranslations"], "overview")
    {english_name, english_overview}
  end

  defp extract_english_from_translations(_), do: {nil, nil}

  defp find_english_in_list(nil, _field), do: nil

  defp find_english_in_list(translations, field) when is_list(translations) do
    case Enum.find(translations, fn t -> t["language"] == "eng" end) do
      nil -> nil
      translation -> translation[field]
    end
  end

  defp find_english_in_list(_, _), do: nil

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
