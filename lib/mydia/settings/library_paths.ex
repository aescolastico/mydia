defmodule Mydia.Settings.LibraryPaths do
  @moduledoc false

  import Ecto.Query, warn: false
  import Mydia.QueryHelpers
  require Logger

  alias Mydia.Repo
  alias Mydia.Settings.LibraryPath
  alias Mydia.Settings.RuntimeConfig, as: RC

  def list_library_paths(opts \\ []) do
    # Get database library paths (exclude disabled paths)
    db_paths =
      LibraryPath
      |> where([l], l.disabled == false or is_nil(l.disabled))
      |> maybe_preload(opts[:preload])
      |> order_by([l], desc: l.monitored, asc: l.path)
      |> Repo.all()

    # Merge with runtime config (database takes precedence by path)
    RC.merge_with_runtime_config(db_paths, &RC.get_runtime_library_paths/0, :path)
  end

  def get_library_path!(id, opts \\ [])

  def get_library_path!(id, opts) when is_binary(id) do
    if RC.runtime_id?(id) do
      case RC.parse_runtime_id(id) do
        {:ok, {:library_path, path}} ->
          # Find the runtime library path by matching the path
          runtime_paths = RC.get_runtime_library_paths()

          case Enum.find(runtime_paths, &(&1.path == path)) do
            nil ->
              raise "Runtime library path not found: #{path}"

            library_path ->
              library_path
          end

        _ ->
          raise "Invalid runtime library path ID: #{id}"
      end
    else
      # Try to parse as integer ID for database lookup, or use directly as UUID
      case Integer.parse(id) do
        {int_id, ""} ->
          get_library_path!(int_id, opts)

        _ ->
          # Assume it's a UUID string and try to fetch directly
          LibraryPath
          |> maybe_preload(opts[:preload])
          |> Repo.get!(id)
      end
    end
  end

  def get_library_path!(id, opts) when is_integer(id) do
    LibraryPath
    |> maybe_preload(opts[:preload])
    |> Repo.get!(id)
  end

  def create_library_path(attrs) do
    %LibraryPath{}
    |> LibraryPath.changeset(attrs)
    |> Repo.insert()
  end

  def update_library_path(%LibraryPath{} = library_path, attrs) do
    changeset = LibraryPath.changeset(library_path, attrs)

    # Check if path is being changed
    case Ecto.Changeset.get_change(changeset, :path) do
      nil ->
        # No path change, proceed normally
        Repo.update(changeset)

      new_path ->
        # Path is changing, validate accessibility
        case validate_new_library_path(library_path, new_path) do
          :ok ->
            result = Repo.update(changeset)

            # Log the path change if successful
            if match?({:ok, _}, result) do
              Logger.info(
                "Library path updated: #{library_path.path} -> #{new_path}",
                library_path_id: library_path.id,
                old_path: library_path.path,
                new_path: new_path
              )
            end

            result

          {:error, reason} ->
            # Add validation error to changeset
            changeset_with_error =
              Ecto.Changeset.add_error(changeset, :path, reason)

            {:error, changeset_with_error}
        end
    end
  end

  def validate_new_library_path(%LibraryPath{} = library_path, new_path) do
    alias Mydia.Library.MediaFile

    # Get sample of media files (up to 10)
    sample_files =
      MediaFile
      |> where([mf], mf.library_path_id == ^library_path.id)
      |> where([mf], not is_nil(mf.relative_path))
      |> limit(10)
      |> Repo.all()

    # If no files exist, allow the change
    if Enum.empty?(sample_files) do
      Logger.debug("No files to validate for library path change",
        library_path_id: library_path.id,
        old_path: library_path.path,
        new_path: new_path
      )

      :ok
    else
      # Check how many files are accessible at new location
      accessible_count =
        Enum.count(sample_files, fn file ->
          new_absolute_path = Path.join(new_path, file.relative_path)
          File.exists?(new_absolute_path)
        end)

      total_checked = length(sample_files)

      if accessible_count == total_checked do
        Logger.info("Library path validation passed",
          library_path_id: library_path.id,
          old_path: library_path.path,
          new_path: new_path,
          files_checked: total_checked
        )

        :ok
      else
        error_message =
          "Files not accessible at new location. " <>
            "Checked #{total_checked} files, #{accessible_count} found. " <>
            "Ensure files have been moved to the new location before updating the path."

        Logger.warning("Library path validation failed",
          library_path_id: library_path.id,
          old_path: library_path.path,
          new_path: new_path,
          files_checked: total_checked,
          files_found: accessible_count
        )

        {:error, error_message}
      end
    end
  end

  def delete_library_path(%LibraryPath{} = library_path) do
    Repo.delete(library_path)
  end
end
