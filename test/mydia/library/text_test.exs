defmodule Mydia.Library.TextTest do
  use ExUnit.Case, async: true

  alias Mydia.Library.Text

  describe "normalize_title/1 — backward compatibility" do
    test "downcases the title" do
      assert Text.normalize_title("MATRIX") == "matrix"
      assert Text.normalize_title("MiXeD CaSe") == "mixed case"
    end

    test "rotates leading articles to the end" do
      assert Text.normalize_title("The Matrix") == "matrix the"
      assert Text.normalize_title("A Bug's Life") == "bugs life a"
      assert Text.normalize_title("An Inconvenient Truth") == "inconvenient truth an"
    end

    test "converts trailing roman numerals to arabic numbers" do
      assert Text.normalize_title("Rocky II") == "rocky 2"
      assert Text.normalize_title("Spider-Man II") == "spiderman 2"
      assert Text.normalize_title("Rocky III") == "rocky 3"
      assert Text.normalize_title("Rocky IV") == "rocky 4"
      assert Text.normalize_title("Rocky V") == "rocky 5"
      assert Text.normalize_title("Rocky VI") == "rocky 6"
      assert Text.normalize_title("Rocky VII") == "rocky 7"
      assert Text.normalize_title("Rocky VIII") == "rocky 8"
      assert Text.normalize_title("Rocky IX") == "rocky 9"
      assert Text.normalize_title("Rocky X") == "rocky 10"
    end

    test "leaves single 'I' alone (ambiguous with the pronoun)" do
      assert Text.normalize_title("Rocky I") =~ "rocky"
      # Single I is not converted to 1.
      refute Text.normalize_title("Rocky I") =~ "1"
    end

    test "strips punctuation" do
      # Existing behavior: punctuation is removed without leaving a
      # space — `"Spider-Man"` collapses to `"spiderman"`. This matches
      # the original `MetadataMatcher.normalize_title/1`.
      assert Text.normalize_title("Spider-Man: Far From Home") == "spiderman far from home"
      assert Text.normalize_title("Mr. & Mrs. Smith") == "mr and mrs smith"
      assert Text.normalize_title("Wall-E") == "walle"
    end

    test "collapses whitespace" do
      assert Text.normalize_title("  too    many   spaces  ") == "too many spaces"
    end

    test "normalizes & to 'and'" do
      assert Text.normalize_title("Mr & Mrs Smith") == "mr and mrs smith"
    end
  end

  describe "normalize_title/1 — NFKD + accent folding" do
    test "folds composed accents (Pokémon → pokemon)" do
      assert Text.normalize_title("Pokémon") == "pokemon"
    end

    test "composed and decomposed forms normalize to the same string" do
      composed = "Café"
      decomposed = :unicode.characters_to_nfd_binary(composed)

      # Sanity-check the fixtures: they must differ as bytes but
      # normalize identically.
      refute composed == decomposed
      assert Text.normalize_title(composed) == "cafe"
      assert Text.normalize_title(decomposed) == "cafe"
    end

    test "handles multiple accented characters" do
      assert Text.normalize_title("Amélie Poulain") == "amelie poulain"
      assert Text.normalize_title("Volver à Vingt Ans") == "volver a vingt ans"
    end
  end

  describe "normalize_title/1 — combined transforms" do
    test "article rotation + roman numeral + accent fold" do
      assert Text.normalize_title("The Pokémon Movie II") == "pokemon movie 2 the"
    end

    test "ampersand + accent" do
      assert Text.normalize_title("Mr & Mrs Café") == "mr and mrs cafe"
    end
  end

  describe "title_similarity/2" do
    test "identical strings return 1.0" do
      assert Text.title_similarity("Matrix", "Matrix") == 1.0
    end

    test "case-insensitive returns 1.0 after light normalization" do
      assert Text.title_similarity("The Matrix", "the matrix") == 1.0
    end

    test "normalized equivalents return 1.0" do
      # "Pokemon" and "Pokémon" normalize to the same canonical form.
      assert Text.title_similarity("Pokemon", "Pokémon") == 1.0
    end

    test "substring on light normalization returns 0.8" do
      score = Text.title_similarity("Matrix", "Matrix Reloaded")
      assert score == 0.8
    end

    test "obviously-different titles score low" do
      score = Text.title_similarity("Matrix", "Zzzzzz")
      assert is_float(score)
      assert score < 0.5
    end

    test "empty strings score 0.0" do
      assert Text.title_similarity("", "anything") == 0.0
      assert Text.title_similarity("anything", "") == 0.0
    end

    test "non-binary input returns 0.0" do
      assert Text.title_similarity(nil, "Matrix") == 0.0
      assert Text.title_similarity("Matrix", nil) == 0.0
    end

    test "all scores are bounded in [0.0, 1.0]" do
      pairs = [
        {"Frieren", "Severance"},
        {"The Matrix", "Matrix Reloaded"},
        {"Pokemon", "Pokémon"},
        {"abcdef", "ghijkl"},
        {"a", "ab"}
      ]

      for {a, b} <- pairs do
        score = Text.title_similarity(a, b)
        assert score >= 0.0
        assert score <= 1.0
      end
    end
  end
end
