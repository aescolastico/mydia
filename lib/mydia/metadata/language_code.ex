defmodule Mydia.Metadata.LanguageCode do
  @moduledoc """
  Maps configured language codes to the form TVDB uses, and selects a
  translation from a TVDB translation bundle by an ordered preference list.

  The configured metadata language arrives as a BCP-47 / ISO 639-1 value
  (e.g. `"en-US"`, `"de"`, `"ja-JP"`), while TVDB extended endpoints key
  their translation arrays off ISO 639-2/T 3-letter codes (`"eng"`, `"deu"`,
  `"jpn"`). This module bridges the two and centralizes the selection logic
  that was previously duplicated (and hardcoded to English) across the relay
  transform and the season/episode structs.
  """

  # ISO 639-1 (primary subtag) -> ISO 639-2/T, covering the metadata config's
  # supported language set. TVDB v4 uses the /T ("terminological") variant.
  @iso_639_1_to_639_2 %{
    "en" => "eng",
    "es" => "spa",
    "fr" => "fra",
    "de" => "deu",
    "it" => "ita",
    "pt" => "por",
    "ja" => "jpn",
    "zh" => "zho",
    "ko" => "kor",
    "ru" => "rus"
  }

  @doc """
  Maps a BCP-47 / ISO 639-1 language code to its TVDB (ISO 639-2/T) 3-letter
  code, stripping any region suffix. Returns `nil` for unknown or blank input
  so callers can skip that tier of the fallback chain.

  ## Examples

      iex> Mydia.Metadata.LanguageCode.to_tvdb_code("en-US")
      "eng"

      iex> Mydia.Metadata.LanguageCode.to_tvdb_code("de")
      "deu"

      iex> Mydia.Metadata.LanguageCode.to_tvdb_code("xx")
      nil
  """
  def to_tvdb_code(code) when is_binary(code) do
    primary =
      code
      |> String.downcase()
      |> String.split(["-", "_"], parts: 2)
      |> List.first()

    Map.get(@iso_639_1_to_639_2, primary)
  end

  def to_tvdb_code(_), do: nil

  @doc """
  Selects a field value from a TVDB translation list by trying each preferred
  language code in order. TVDB translation entries look like
  `%{"language" => "eng", "name" => "..."}`. Returns the first non-empty match,
  or `nil` when no preferred code has a usable value (callers fall back to the
  raw field).

  `preferred_codes` is an ordered list of 3-letter codes, e.g.
  `["spa", "jpn", "eng"]` for "Spanish, then original, then English".
  """
  def select_translation(translations, field, preferred_codes)
      when is_list(translations) and is_list(preferred_codes) do
    Enum.find_value(preferred_codes, fn code ->
      case Enum.find(translations, fn t -> t["language"] == code end) do
        %{} = translation ->
          value = translation[field]
          if is_binary(value) and value != "", do: value

        _ ->
          nil
      end
    end)
  end

  def select_translation(_translations, _field, _preferred_codes), do: nil
end
