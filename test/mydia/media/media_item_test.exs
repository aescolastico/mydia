defmodule Mydia.Media.MediaItemTest do
  use ExUnit.Case, async: true

  alias Mydia.Media.MediaItem

  describe "changeset/2 metadata_source" do
    test "casts :tvdb" do
      changeset =
        MediaItem.changeset(%MediaItem{}, %{
          type: "tv_show",
          title: "Breaking Bad",
          metadata_source: :tvdb
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :metadata_source) == :tvdb
    end

    test "casts :tmdb" do
      changeset =
        MediaItem.changeset(%MediaItem{}, %{
          type: "tv_show",
          title: "Ghost in the Shell",
          metadata_source: :tmdb
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :metadata_source) == :tmdb
    end

    test "rejects an unknown metadata_source" do
      changeset =
        MediaItem.changeset(%MediaItem{}, %{
          type: "tv_show",
          title: "Breaking Bad",
          metadata_source: "imdb"
        })

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :metadata_source)
    end

    test "is optional (nil for movies)" do
      changeset =
        MediaItem.changeset(%MediaItem{}, %{type: "movie", title: "The Matrix", year: 1999})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :metadata_source) == nil
    end
  end
end
