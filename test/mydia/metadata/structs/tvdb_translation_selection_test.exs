defmodule Mydia.Metadata.Structs.TvdbTranslationSelectionTest do
  use ExUnit.Case, async: true

  alias Mydia.Metadata.Structs.{EpisodeData, SeasonData}

  defp season_translations do
    %{
      "nameTranslations" => [
        %{"language" => "eng", "name" => "Season 1"},
        %{"language" => "spa", "name" => "Temporada 1"}
      ],
      "overviewTranslations" => [
        %{"language" => "eng", "overview" => "English season overview"},
        %{"language" => "spa", "overview" => "Resumen de la temporada"}
      ]
    }
  end

  defp episode_translations do
    %{
      "nameTranslations" => [
        %{"language" => "eng", "name" => "Pilot"},
        %{"language" => "fra", "name" => "Pilote"}
      ],
      "overviewTranslations" => [
        %{"language" => "eng", "overview" => "English episode overview"},
        %{"language" => "fra", "overview" => "Résumé de l'épisode"}
      ]
    }
  end

  describe "SeasonData.from_tvdb_response/2" do
    test "selects the configured language when present" do
      data = %{"number" => 1, "translations" => season_translations(), "episodes" => []}

      season = SeasonData.from_tvdb_response(data, ["spa", "eng"])

      assert season.name == "Temporada 1"
      assert season.overview == "Resumen de la temporada"
    end

    test "falls back to English then raw when configured language absent" do
      data = %{"number" => 2, "translations" => season_translations(), "episodes" => []}

      season = SeasonData.from_tvdb_response(data, ["deu", "eng"])

      assert season.name == "Season 1"
      assert season.overview == "English season overview"
    end

    test "default arity preserves English-only behavior" do
      data = %{"number" => 1, "translations" => season_translations(), "episodes" => []}

      season = SeasonData.from_tvdb_response(data)

      assert season.name == "Season 1"
    end

    test "forwards preferred codes to nested episodes" do
      data = %{
        "number" => 1,
        "translations" => season_translations(),
        "episodes" => [
          %{
            "seasonNumber" => 1,
            "number" => 1,
            "name" => "raw",
            "translations" => episode_translations()
          }
        ]
      }

      season = SeasonData.from_tvdb_response(data, ["fra", "eng"])
      [episode] = season.episodes

      assert episode.name == "Pilote"
    end

    test "falls back to raw season name when no translations present" do
      data = %{"number" => 3, "name" => "Specials", "episodes" => []}

      season = SeasonData.from_tvdb_response(data, ["spa", "eng"])

      assert season.name == "Specials"
    end
  end

  describe "EpisodeData.from_tvdb_response/2" do
    test "selects the configured language when present" do
      data = %{
        "seasonNumber" => 1,
        "number" => 1,
        "name" => "raw name",
        "translations" => episode_translations()
      }

      episode = EpisodeData.from_tvdb_response(data, ["fra", "eng"])

      assert episode.name == "Pilote"
      assert episode.overview == "Résumé de l'épisode"
    end

    test "falls back through English to raw when configured language absent" do
      data = %{
        "seasonNumber" => 1,
        "number" => 1,
        "name" => "raw name",
        "translations" => episode_translations()
      }

      episode = EpisodeData.from_tvdb_response(data, ["spa", "eng"])

      assert episode.name == "Pilot"
    end

    test "falls back to raw fields when episode has no translations" do
      data = %{"seasonNumber" => 1, "number" => 2, "name" => "Raw Episode"}

      episode = EpisodeData.from_tvdb_response(data, ["fra", "eng"])

      assert episode.name == "Raw Episode"
    end
  end
end
