defmodule Mydia.Library.NamingTemplateTest do
  use ExUnit.Case, async: true

  alias Mydia.Library.NamingTemplate

  test "renders provider IDs as raw values inside chosen tag conventions" do
    template = "{{title}} ({{year}}) {tmdb-{{tmdb}}} [tvdbid-{{tvdb}}]"

    assert NamingTemplate.render(template, %{
             "title" => "The Office",
             "year" => 2005,
             "tmdb" => 2316,
             "tvdb" => nil
           }) == "The Office (2005) {tmdb-2316}"
  end

  test "rejects templates that would break scanning or escape a directory" do
    assert {:error, _} = NamingTemplate.validate_for("{{title}}/../other", :movie_folder)
    assert {:error, _} = NamingTemplate.validate_for("{{title}} - {{episode}}", :episode_file)
    assert {:error, _} = NamingTemplate.validate_for("Series {{season}}", :season_folder)
    assert :ok = NamingTemplate.validate_for("S{{season}}", :season_folder)
  end
end
