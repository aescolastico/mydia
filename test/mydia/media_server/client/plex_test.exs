defmodule Mydia.MediaServer.Client.PlexTest do
  use ExUnit.Case, async: true

  alias Mydia.MediaServer.Client.Plex

  describe "parse_guids/1" do
    test "parses TMDB, IMDB, and TVDB GUIDs" do
      guids = [
        %{"id" => "tmdb://12345"},
        %{"id" => "imdb://tt1234567"},
        %{"id" => "tvdb://67890"}
      ]

      assert Plex.parse_guids(guids) == %{
               tmdb: "12345",
               imdb: "tt1234567",
               tvdb: "67890"
             }
    end

    test "handles partial GUIDs" do
      guids = [%{"id" => "tmdb://555"}]
      assert Plex.parse_guids(guids) == %{tmdb: "555"}
    end

    test "handles nil" do
      assert Plex.parse_guids(nil) == %{}
    end

    test "handles empty list" do
      assert Plex.parse_guids([]) == %{}
    end

    test "ignores unknown GUID providers" do
      guids = [
        %{"id" => "tmdb://123"},
        %{"id" => "unknown://456"}
      ]

      assert Plex.parse_guids(guids) == %{tmdb: "123"}
    end

    test "handles non-list value" do
      assert Plex.parse_guids("not a list") == %{}
    end

    test "last GUID wins when duplicates exist" do
      guids = [
        %{"id" => "tmdb://111"},
        %{"id" => "tmdb://222"}
      ]

      assert Plex.parse_guids(guids) == %{tmdb: "222"}
    end
  end
end
