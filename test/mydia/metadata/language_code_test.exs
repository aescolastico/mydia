defmodule Mydia.Metadata.LanguageCodeTest do
  use ExUnit.Case, async: true

  alias Mydia.Metadata.LanguageCode

  describe "to_tvdb_code/1" do
    test "maps supported ISO 639-1 codes to ISO 639-2/T" do
      assert LanguageCode.to_tvdb_code("en-US") == "eng"
      assert LanguageCode.to_tvdb_code("de") == "deu"
      assert LanguageCode.to_tvdb_code("ja-JP") == "jpn"
      assert LanguageCode.to_tvdb_code("es") == "spa"
      assert LanguageCode.to_tvdb_code("zh") == "zho"
    end

    test "is case-insensitive and tolerates underscore separators" do
      assert LanguageCode.to_tvdb_code("EN-us") == "eng"
      assert LanguageCode.to_tvdb_code("pt_BR") == "por"
    end

    test "returns nil for blank, nil, and unknown codes" do
      assert LanguageCode.to_tvdb_code("") == nil
      assert LanguageCode.to_tvdb_code(nil) == nil
      assert LanguageCode.to_tvdb_code("xx") == nil
      assert LanguageCode.to_tvdb_code(123) == nil
    end
  end

  describe "tvdb_candidates/1" do
    test "expands Portuguese to both por and pt (TVDB uses both inconsistently)" do
      assert LanguageCode.tvdb_candidates("pt-BR") == ["por", "pt"]
      assert LanguageCode.tvdb_candidates("pt") == ["por", "pt"]
    end

    test "expands a 2-letter code to its 3-letter form plus the 2-letter form" do
      assert LanguageCode.tvdb_candidates("de") == ["deu", "de"]
      assert LanguageCode.tvdb_candidates("ja") == ["jpn", "ja"]
      assert LanguageCode.tvdb_candidates("en-US") == ["eng", "en"]
    end

    test "passes an already-3-letter code through as the only candidate" do
      assert LanguageCode.tvdb_candidates("jpn") == ["jpn"]
      assert LanguageCode.tvdb_candidates("ENG") == ["eng"]
    end

    test "returns empty for blank/nil; passes an unknown code through harmlessly" do
      assert LanguageCode.tvdb_candidates("") == []
      assert LanguageCode.tvdb_candidates(nil) == []
      # Unknown 2-letter code isn't mapped but is still offered as a candidate;
      # it simply never matches a TVDB translation key.
      assert LanguageCode.tvdb_candidates("xx") == ["xx"]
    end
  end

  describe "original_language_from/1" do
    test "extracts a non-empty original_language" do
      assert LanguageCode.original_language_from(%{original_language: "jpn"}) == "jpn"
    end

    test "extracts from a string-key map too" do
      assert LanguageCode.original_language_from(%{"original_language" => "jpn"}) == "jpn"
      assert LanguageCode.original_language_from(%{"original_language" => ""}) == nil
    end

    test "returns nil for absent, empty, or non-binary values" do
      assert LanguageCode.original_language_from(%{original_language: nil}) == nil
      assert LanguageCode.original_language_from(%{original_language: ""}) == nil
      assert LanguageCode.original_language_from(%{}) == nil
      assert LanguageCode.original_language_from(nil) == nil
    end
  end

  describe "select_translation/3" do
    setup do
      translations = [
        %{"language" => "eng", "name" => "The Show", "overview" => "English overview"},
        %{"language" => "spa", "name" => "El Show", "overview" => "Resumen en español"},
        %{"language" => "fra", "name" => "", "overview" => "Résumé"}
      ]

      {:ok, translations: translations}
    end

    test "returns the first matching code's field in preference order", %{
      translations: translations
    } do
      assert LanguageCode.select_translation(translations, "name", ["spa", "eng"]) == "El Show"
      assert LanguageCode.select_translation(translations, "name", ["eng", "spa"]) == "The Show"
    end

    test "skips a requested code that is absent and falls to the next", %{
      translations: translations
    } do
      assert LanguageCode.select_translation(translations, "name", ["deu", "eng"]) == "The Show"
    end

    test "returns nil when no preferred code matches", %{translations: translations} do
      assert LanguageCode.select_translation(translations, "name", ["deu", "ita"]) == nil
    end

    test "treats an empty-string field as no match and continues", %{translations: translations} do
      # French name is "" — should fall through to English rather than return ""
      assert LanguageCode.select_translation(translations, "name", ["fra", "eng"]) == "The Show"
      # but French overview is present
      assert LanguageCode.select_translation(translations, "overview", ["fra", "eng"]) == "Résumé"
    end

    test "returns nil for nil or non-list translations" do
      assert LanguageCode.select_translation(nil, "name", ["eng"]) == nil
      assert LanguageCode.select_translation(%{}, "name", ["eng"]) == nil
    end
  end
end
