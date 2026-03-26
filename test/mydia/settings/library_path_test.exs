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
  end
end
