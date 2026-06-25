defmodule Mydia.Library.NamingTemplateTest do
  use ExUnit.Case, async: true

  alias Mydia.Library.NamingTemplate

  doctest NamingTemplate

  describe "render/2 literal braces" do
    test "a single brace is a literal character" do
      assert NamingTemplate.render("a { b } c", %{}) == "a { b } c"
    end

    test "literal provider prefix plus ID token renders a detectable tag" do
      ctx = %{"tmdb" => "2316"}
      assert NamingTemplate.render("{tmdb-{{tmdb}}}", ctx) == "{tmdb-2316}"
    end

    test "full convention example" do
      ctx = %{"title" => "The Office", "year" => "2005", "tmdb" => "2316"}

      assert NamingTemplate.render("{{title}} ({{year}}) {tmdb-{{tmdb}}}", ctx) ==
               "The Office (2005) {tmdb-2316}"
    end

    test "missing provider id collapses the empty provider tag and trailing space" do
      ctx = %{"title" => "The Office", "year" => "2005"}

      assert NamingTemplate.render("{{title}} ({{year}}) {tmdb-{{tmdb}}}", ctx) ==
               "The Office (2005)"
    end

    test "missing provider id collapses supported id tag aliases" do
      assert NamingTemplate.render("{tmdbid-{{tmdb}}}", %{}) == ""
      assert NamingTemplate.render("[tvdb-{{tvdb}}]", %{}) == ""
      assert NamingTemplate.render("[tvdbid-{{tvdb}}]", %{}) == ""
      assert NamingTemplate.render("{imdb-{{imdb}}}", %{}) == ""
      assert NamingTemplate.render("{imdbid-{{imdb}}}", %{}) == ""
    end
  end

  describe "render/2 substitution" do
    test "unknown token renders empty" do
      assert NamingTemplate.render("{{title}}{{bogus}}", %{"title" => "X"}) == "X"
    end

    test "nil value renders empty" do
      assert NamingTemplate.render("{{title}}", %{"title" => nil}) == ""
    end

    test "non-string values are stringified" do
      assert NamingTemplate.render("S{{season}}E{{episode}}", %{"season" => 1, "episode" => 4}) ==
               "S1E4"
    end

    test "padding whitespace inside braces is allowed" do
      assert NamingTemplate.render("{{ title }}", %{"title" => "X"}) == "X"
    end

    test "adjacent bracket tags render without inserted spaces" do
      ctx = %{"quality" => "[Bluray-1080p]", "audio" => "[DTS]", "codec" => "[x264]"}

      assert NamingTemplate.render("{{quality}}{{audio}}{{codec}}", ctx) ==
               "[Bluray-1080p][DTS][x264]"
    end

    test "empty episode title does not leave a doubled separator" do
      ctx = %{
        "title" => "Breaking Bad",
        "year" => "2008",
        "sxxeyy" => "S01E01",
        "episode_title" => "",
        "quality" => "[Bluray-1080p]"
      }

      template = "{{title}} ({{year}}) - {{sxxeyy}} - {{episode_title}} {{quality}}"

      assert NamingTemplate.render(template, ctx) ==
               "Breaking Bad (2008) - S01E01 - [Bluray-1080p]"
    end
  end

  describe "tokens_in/1" do
    test "returns unique token names" do
      assert NamingTemplate.tokens_in("{{title}} ({{year}}) {{title}}") == ["title", "year"]
    end

    test "ignores single braces" do
      assert NamingTemplate.tokens_in("a { b } {{title}}") == ["title"]
    end
  end

  describe "validate/2" do
    test "returns :ok when all tokens are allowed" do
      assert NamingTemplate.validate("{{title}} ({{year}})", ["title", "year"]) == :ok
    end

    test "returns unknown tokens" do
      assert NamingTemplate.validate("{{title}} {{bogus}}", ["title", "year"]) ==
               {:error, ["bogus"]}
    end
  end
end
