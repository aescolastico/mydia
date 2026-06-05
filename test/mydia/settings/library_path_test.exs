defmodule Mydia.Settings.LibraryPathTest do
  use ExUnit.Case, async: true

  alias Mydia.Settings.LibraryPath

  describe "changeset/2" do
    test "auto_rename defaults to true" do
      library_path = %LibraryPath{}
      assert library_path.auto_rename == true
    end

    test "accepts auto_rename in changeset" do
      changeset =
        LibraryPath.changeset(%LibraryPath{}, %{
          path: "/media/movies",
          type: "movies",
          auto_rename: false
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :auto_rename) == false
    end

    test "auto_rename can be toggled back to true" do
      changeset =
        LibraryPath.changeset(%LibraryPath{auto_rename: false}, %{
          path: "/media/movies",
          type: "movies",
          auto_rename: true
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :auto_rename) == true
    end

    test "tv_metadata_source defaults to :tvdb" do
      assert %LibraryPath{}.tv_metadata_source == :tvdb
    end

    test "accepts :tmdb as tv_metadata_source" do
      changeset =
        LibraryPath.changeset(%LibraryPath{}, %{
          path: "/media/anime",
          type: "series",
          tv_metadata_source: :tmdb
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :tv_metadata_source) == :tmdb
    end

    test "accepts :tvdb as tv_metadata_source" do
      changeset =
        LibraryPath.changeset(%LibraryPath{tv_metadata_source: :tmdb}, %{
          path: "/media/series",
          type: "series",
          tv_metadata_source: :tvdb
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :tv_metadata_source) == :tvdb
    end

    test "rejects an unknown tv_metadata_source" do
      changeset =
        LibraryPath.changeset(%LibraryPath{}, %{
          path: "/media/series",
          type: "series",
          tv_metadata_source: "imdb"
        })

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :tv_metadata_source)
    end

    test "defaults to :tvdb when omitted from attrs" do
      changeset =
        LibraryPath.changeset(%LibraryPath{}, %{path: "/media/series", type: "series"})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :tv_metadata_source) == :tvdb
    end
  end
end
