defmodule Mydia.LibraryTest do
  use Mydia.DataCase

  alias Mydia.Library

  import Mydia.SettingsFixtures

  describe "list_media_files/1 with library_path_type filter" do
    test "filters media files by library path type" do
      # Create library paths of different types
      movies_path = library_path_fixture(%{path: "/movies", type: "movies"})
      adult_path = library_path_fixture(%{path: "/adult", type: "adult"})

      # Create media files in each library
      {:ok, movies_file} =
        Library.create_scanned_media_file(%{
          relative_path: "movie.mp4",
          library_path_id: movies_path.id,
          size: 1_000_000
        })

      {:ok, adult_file} =
        Library.create_scanned_media_file(%{
          relative_path: "video.mp4",
          library_path_id: adult_path.id,
          size: 2_000_000
        })

      # Filter by adult type
      adult_files = Library.list_media_files(library_path_type: :adult)
      assert length(adult_files) == 1
      assert hd(adult_files).id == adult_file.id

      # Filter by movies type
      movie_files = Library.list_media_files(library_path_type: :movies)
      assert length(movie_files) == 1
      assert hd(movie_files).id == movies_file.id
    end

    test "returns empty list when no files match type" do
      # Create a library path of one type
      movies_path = library_path_fixture(%{path: "/movies2", type: "movies"})

      {:ok, _movies_file} =
        Library.create_scanned_media_file(%{
          relative_path: "movie2.mp4",
          library_path_id: movies_path.id,
          size: 1_000_000
        })

      # Query for a different type
      adult_files = Library.list_media_files(library_path_type: :adult)
      assert Enum.empty?(adult_files)
    end

    test "can combine library_path_type with preload" do
      adult_path = library_path_fixture(%{path: "/adult2", type: "adult"})

      {:ok, _adult_file} =
        Library.create_scanned_media_file(%{
          relative_path: "video2.mp4",
          library_path_id: adult_path.id,
          size: 2_000_000
        })

      files = Library.list_media_files(library_path_type: :adult, preload: [:library_path])
      assert length(files) == 1
      assert hd(files).library_path.type == :adult
    end
  end

  describe "update_media_file_scan/2" do
    test "updates orphaned media file without validation errors" do
      library_path = library_path_fixture(%{type: "movies"})

      # Create an orphaned file (no media_item_id or episode_id)
      {:ok, media_file} =
        Library.create_scanned_media_file(%{
          relative_path: "orphaned/file.mp4",
          library_path_id: library_path.id,
          size: 1_000_000
        })

      assert is_nil(media_file.media_item_id)
      assert is_nil(media_file.episode_id)

      # Update using scan function should succeed
      {:ok, updated} =
        Library.update_media_file_scan(media_file, %{
          size: 2_000_000,
          verified_at: DateTime.utc_now()
        })

      assert updated.size == 2_000_000
      assert updated.verified_at != nil
    end

    test "regular update_media_file fails on orphaned files" do
      library_path = library_path_fixture(%{type: "movies"})

      # Create an orphaned file
      {:ok, media_file} =
        Library.create_scanned_media_file(%{
          relative_path: "orphaned/file2.mp4",
          library_path_id: library_path.id,
          size: 1_000_000
        })

      # Regular update should fail due to missing parent
      {:error, changeset} =
        Library.update_media_file(media_file, %{
          size: 2_000_000,
          verified_at: DateTime.utc_now()
        })

      assert %{media_item_id: ["either media_item_id or episode_id must be set"]} =
               errors_on(changeset)
    end
  end

  describe "list_media_ids_in_library_path/1" do
    test "returns unique media item IDs from files in library path" do
      unique_path = "/media/movies_#{System.unique_integer([:positive])}"
      library_path = library_path_fixture(%{path: unique_path, type: "movies"})

      # Create a media item
      {:ok, media_item} =
        Mydia.Media.create_media_item(%{
          type: "movie",
          title: "Test Movie",
          year: 2024
        })

      # Create media files for this media item
      {:ok, _file1} =
        Library.create_media_file(%{
          relative_path: "Test Movie/movie.mp4",
          library_path_id: library_path.id,
          media_item_id: media_item.id,
          size: 1_000_000
        })

      {:ok, _file2} =
        Library.create_media_file(%{
          relative_path: "Test Movie/movie.srt",
          library_path_id: library_path.id,
          media_item_id: media_item.id,
          size: 50_000
        })

      # Get media IDs for this library path
      media_ids = Library.list_media_ids_in_library_path(library_path)

      # Should return the media item ID once (not duplicated)
      assert length(media_ids) == 1
      assert hd(media_ids) == media_item.id
    end

    test "returns empty list when no files in library path" do
      unique_path = "/media/empty_#{System.unique_integer([:positive])}"
      library_path = library_path_fixture(%{path: unique_path, type: "movies"})

      media_ids = Library.list_media_ids_in_library_path(library_path)

      assert media_ids == []
    end

    test "excludes files without media_item_id" do
      unique_path = "/media/orphaned_#{System.unique_integer([:positive])}"
      library_path = library_path_fixture(%{path: unique_path, type: "movies"})

      # Create orphaned file (no media_item_id)
      {:ok, _orphaned_file} =
        Library.create_scanned_media_file(%{
          relative_path: "orphaned.mp4",
          library_path_id: library_path.id,
          size: 1_000_000
        })

      media_ids = Library.list_media_ids_in_library_path(library_path)

      assert media_ids == []
    end
  end

  describe "trash_media_file/1" do
    test "sets trashed_at timestamp" do
      library_path = library_path_fixture(%{type: "movies"})

      {:ok, media_file} =
        Library.create_scanned_media_file(%{
          relative_path: "trash_test.mp4",
          library_path_id: library_path.id,
          size: 1_000_000
        })

      assert is_nil(media_file.trashed_at)

      {:ok, trashed} = Library.trash_media_file(media_file)
      assert not is_nil(trashed.trashed_at)
    end
  end

  describe "restore_media_file/1" do
    test "clears trashed_at timestamp" do
      library_path = library_path_fixture(%{type: "movies"})

      {:ok, media_file} =
        Library.create_scanned_media_file(%{
          relative_path: "restore_test.mp4",
          library_path_id: library_path.id,
          size: 1_000_000
        })

      {:ok, trashed} = Library.trash_media_file(media_file)
      assert not is_nil(trashed.trashed_at)

      {:ok, restored} = Library.restore_media_file(trashed)
      assert is_nil(restored.trashed_at)
    end
  end

  describe "list_media_files/1 with trashed files" do
    test "excludes trashed files by default" do
      library_path =
        library_path_fixture(%{
          path: "/trash_filter_#{System.unique_integer([:positive])}",
          type: "movies"
        })

      {:ok, file1} =
        Library.create_scanned_media_file(%{
          relative_path: "active.mp4",
          library_path_id: library_path.id,
          size: 1_000_000
        })

      {:ok, file2} =
        Library.create_scanned_media_file(%{
          relative_path: "trashed.mp4",
          library_path_id: library_path.id,
          size: 2_000_000
        })

      {:ok, _trashed} = Library.trash_media_file(file2)

      files = Library.list_media_files(library_path_id: library_path.id)
      assert length(files) == 1
      assert hd(files).id == file1.id
    end

    test "includes trashed files when include_trashed: true" do
      library_path =
        library_path_fixture(%{
          path: "/trash_include_#{System.unique_integer([:positive])}",
          type: "movies"
        })

      {:ok, _file1} =
        Library.create_scanned_media_file(%{
          relative_path: "active2.mp4",
          library_path_id: library_path.id,
          size: 1_000_000
        })

      {:ok, file2} =
        Library.create_scanned_media_file(%{
          relative_path: "trashed2.mp4",
          library_path_id: library_path.id,
          size: 2_000_000
        })

      {:ok, _trashed} = Library.trash_media_file(file2)

      files = Library.list_media_files(library_path_id: library_path.id, include_trashed: true)
      assert length(files) == 2
    end
  end

  describe "purge_old_trashed_media_files/1" do
    test "only deletes files trashed beyond retention period" do
      library_path =
        library_path_fixture(%{
          path: "/purge_test_#{System.unique_integer([:positive])}",
          type: "movies"
        })

      # Create two files
      {:ok, old_file} =
        Library.create_scanned_media_file(%{
          relative_path: "old_trashed.mp4",
          library_path_id: library_path.id,
          size: 1_000_000
        })

      {:ok, recent_file} =
        Library.create_scanned_media_file(%{
          relative_path: "recent_trashed.mp4",
          library_path_id: library_path.id,
          size: 2_000_000
        })

      # Trash both files
      {:ok, _} = Library.trash_media_file(old_file)
      {:ok, _} = Library.trash_media_file(recent_file)

      # Manually backdate the old file's trashed_at to 31 days ago
      old_trashed_at = DateTime.utc_now() |> DateTime.add(-31, :day) |> DateTime.truncate(:second)

      old_file
      |> Ecto.Changeset.change(trashed_at: old_trashed_at)
      |> Mydia.Repo.update!()

      # Purge with 30 day retention
      {:ok, count} = Library.purge_old_trashed_media_files(30)
      assert count == 1

      # Old file should be gone, recent file should still exist
      assert is_nil(Library.get_media_file(old_file.id))
      assert not is_nil(Library.get_media_file(recent_file.id))
    end

    test "does not delete non-trashed files" do
      library_path =
        library_path_fixture(%{
          path: "/purge_safe_#{System.unique_integer([:positive])}",
          type: "movies"
        })

      {:ok, active_file} =
        Library.create_scanned_media_file(%{
          relative_path: "active_purge.mp4",
          library_path_id: library_path.id,
          size: 1_000_000
        })

      {:ok, count} = Library.purge_old_trashed_media_files(0)
      assert count == 0

      assert not is_nil(Library.get_media_file(active_file.id))
    end
  end

  describe "get_media_file_by_relative_path/3 with trashed files" do
    test "excludes trashed files by default" do
      library_path =
        library_path_fixture(%{
          path: "/rel_path_trash_#{System.unique_integer([:positive])}",
          type: "movies"
        })

      {:ok, media_file} =
        Library.create_scanned_media_file(%{
          relative_path: "trashable.mp4",
          library_path_id: library_path.id,
          size: 1_000_000
        })

      {:ok, _trashed} = Library.trash_media_file(media_file)

      assert is_nil(Library.get_media_file_by_relative_path(library_path.id, "trashable.mp4"))
    end

    test "includes trashed files when include_trashed: true" do
      library_path =
        library_path_fixture(%{
          path: "/rel_path_include_#{System.unique_integer([:positive])}",
          type: "movies"
        })

      {:ok, media_file} =
        Library.create_scanned_media_file(%{
          relative_path: "trashable2.mp4",
          library_path_id: library_path.id,
          size: 1_000_000
        })

      {:ok, _trashed} = Library.trash_media_file(media_file)

      found =
        Library.get_media_file_by_relative_path(library_path.id, "trashable2.mp4",
          include_trashed: true
        )

      assert not is_nil(found)
      assert found.id == media_file.id
    end
  end

  describe "total_storage_bytes/0 with trashed files" do
    test "excludes trashed files from total" do
      library_path =
        library_path_fixture(%{
          path: "/storage_trash_#{System.unique_integer([:positive])}",
          type: "movies"
        })

      {:ok, _active} =
        Library.create_scanned_media_file(%{
          relative_path: "counted.mp4",
          library_path_id: library_path.id,
          size: 500
        })

      {:ok, trashable} =
        Library.create_scanned_media_file(%{
          relative_path: "not_counted.mp4",
          library_path_id: library_path.id,
          size: 300
        })

      total_before = Library.total_storage_bytes()

      {:ok, _} = Library.trash_media_file(trashable)

      total_after = Library.total_storage_bytes()
      assert total_after == total_before - 300
    end
  end
end
