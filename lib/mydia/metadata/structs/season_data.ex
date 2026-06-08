defmodule Mydia.Metadata.Structs.SeasonData do
  @moduledoc """
  Represents TV season data from TMDB via the metadata relay service.

  This struct provides compile-time safety for season data, replacing
  plain map access that can silently return nil.
  """

  alias Mydia.Metadata.LanguageCode
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

  `preferred_codes` is an ordered list of TVDB (ISO 639-2/T) language codes to
  try when selecting the localized name/overview; it is also forwarded to each
  episode. Defaults to `["eng"]` to preserve prior English-only behavior.
  """
  def from_tvdb_response(data, preferred_codes \\ ["eng"]) when is_map(data) do
    episodes = data["episodes"] || []

    {localized_name, localized_overview} =
      select_from_translations(data["translations"], preferred_codes)

    %__MODULE__{
      season_number: data["number"],
      name: localized_name || data["name"] || "Season #{data["number"]}",
      overview: localized_overview || data["overview"],
      air_date: nil,
      poster_path: data["image"],
      episode_count: length(episodes),
      episodes: Enum.map(episodes, &EpisodeData.from_tvdb_response(&1, preferred_codes))
    }
  end

  # Select localized name/overview from TVDB TranslationExtended format:
  #   %{"nameTranslations" => [%{"language" => "eng", "name" => "..."}, ...],
  #     "overviewTranslations" => [%{"language" => "eng", "overview" => "..."}, ...]}
  defp select_from_translations(%{} = t, preferred_codes) do
    name = LanguageCode.select_translation(t["nameTranslations"], "name", preferred_codes)

    overview =
      LanguageCode.select_translation(t["overviewTranslations"], "overview", preferred_codes)

    {name, overview}
  end

  defp select_from_translations(_translations, _preferred_codes), do: {nil, nil}

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
