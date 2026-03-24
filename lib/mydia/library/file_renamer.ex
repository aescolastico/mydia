defmodule Mydia.Library.FileRenamer do
  @moduledoc """
  Handles renaming media files to follow a consistent naming convention.
  """

  import Ecto.Query, warn: false

  alias Mydia.Library.MediaFile
  alias Mydia.Media.{MediaItem, Episode}
  alias Mydia.Repo

  require Logger

  @doc """
  Generates a proposed filename for a media file based on its metadata.

  Returns a map with:
  - `:current_path` - The current full path
  - `:proposed_path` - The proposed full path
  - `:current_filename` - Just the current filename
  - `:proposed_filename` - Just the proposed filename
  - `:directory` - The directory path
  - `:extension` - The file extension
  """
  def generate_rename_preview(%MediaFile{} = file) do
    # Load associations if needed - force reload to ensure we have fresh data
    file = Repo.preload(file, [:library_path, :media_item, episode: :media_item], force: true)

    # Get the file details - use absolute_path for filesystem operations
    current_path = MediaFile.absolute_path(file)
    directory = Path.dirname(current_path)
    extension = Path.extname(current_path)
    current_filename = Path.basename(current_path)

    # Generate proposed filename based on media type
    proposed_filename =
      cond do
        # TV Show Episode (associated with episode)
        file.episode_id && file.episode ->
          media_item = file.episode.media_item
          generate_episode_filename(file.episode, media_item, file, extension)

        # TV Show file not associated with episode (parse from filename)
        file.media_item_id && file.media_item && file.media_item.type == "tv_show" ->
          generate_filename_from_path(file, extension)

        # Movie
        file.media_item_id && file.media_item && file.media_item.type == "movie" ->
          generate_movie_filename(file.media_item, file, extension)

        # Fallback to current filename if we can't determine
        true ->
          current_filename
      end

    proposed_path = Path.join(directory, proposed_filename)

    %{
      current_path: current_path,
      proposed_path: proposed_path,
      current_filename: current_filename,
      proposed_filename: proposed_filename,
      directory: directory,
      extension: extension,
      file_id: file.id
    }
  end

  @doc """
  Generates rename previews for all files associated with a media item.

  Returns a list of preview maps.
  """
  def generate_rename_previews_for_media_item(%MediaItem{} = media_item) do
    active_files_query = from(mf in MediaFile, where: is_nil(mf.trashed_at))

    media_item =
      Repo.preload(media_item,
        media_files: active_files_query,
        episodes: [media_files: active_files_query]
      )

    # Get all media file IDs (both movie files and episode files)
    file_ids =
      if media_item.type == "tv_show" do
        # For TV shows, get all episode file IDs
        media_item.episodes
        |> Enum.flat_map(& &1.media_files)
        |> Enum.map(& &1.id)
      else
        # For movies, get media item file IDs
        media_item.media_files
        |> Enum.map(& &1.id)
      end

    # Reload each file fresh from database to ensure we have current data
    file_ids
    |> Enum.map(&Mydia.Library.get_media_file!/1)
    |> Enum.map(&generate_rename_preview/1)
  end

  @doc """
  Renames a media file on the filesystem and updates the database.

  Returns `{:ok, updated_file}` on success, or `{:error, reason}` on failure.
  """
  def rename_file(%MediaFile{} = file, new_path) when is_binary(new_path) do
    # Preload library_path to resolve absolute path
    file = Repo.preload(file, :library_path)
    current_path = MediaFile.absolute_path(file)

    cond do
      # Check if file exists
      not File.exists?(current_path) ->
        {:error, :file_not_found}

      # Check if target already exists
      File.exists?(new_path) and new_path != current_path ->
        {:error, :target_exists}

      # Check if paths are the same (nothing to do)
      current_path == new_path ->
        {:ok, file}

      # Perform the rename
      true ->
        # Ensure target directory exists
        target_dir = Path.dirname(new_path)
        File.mkdir_p!(target_dir)

        case File.rename(current_path, new_path) do
          :ok ->
            # Calculate the new relative path
            library_path_root = file.library_path.path
            new_relative_path = Path.relative_to(new_path, library_path_root)

            # Update the database with the new relative path
            case Mydia.Library.update_media_file(file, %{relative_path: new_relative_path}) do
              {:ok, updated_file} ->
                Logger.info("Successfully renamed file",
                  file_id: file.id,
                  old_path: current_path,
                  new_path: new_path,
                  new_relative_path: new_relative_path
                )

                {:ok, updated_file}

              {:error, changeset} ->
                # Rollback: rename file back
                File.rename(new_path, current_path)

                Logger.error("Failed to update database after rename, rolled back",
                  file_id: file.id,
                  errors: inspect(changeset.errors)
                )

                {:error, :database_update_failed}
            end

          {:error, reason} ->
            Logger.error("Failed to rename file",
              file_id: file.id,
              reason: inspect(reason)
            )

            {:error, reason}
        end
    end
  end

  @doc """
  Renames multiple media files in a batch operation.

  Accepts a list of maps with `:file_id` and `:new_path` keys.

  Returns `{:ok, results}` where results is a list of `{:ok, file}` or `{:error, reason}` tuples.
  """
  def rename_files_batch(rename_specs) when is_list(rename_specs) do
    results =
      Enum.map(rename_specs, fn %{file_id: file_id, new_path: new_path} ->
        file = Mydia.Library.get_media_file!(file_id)
        rename_file(file, new_path)
      end)

    success_count = Enum.count(results, &match?({:ok, _}, &1))
    error_count = Enum.count(results, &match?({:error, _}, &1))

    Logger.info("Batch rename completed",
      total: length(results),
      success: success_count,
      errors: error_count
    )

    {:ok, results}
  end

  ## Private Functions

  defp generate_movie_filename(%MediaItem{} = media_item, %MediaFile{} = file, extension) do
    # Format: {Title} ({Year}) [{Quality} {Source}].{ext}
    # Example: The Matrix (1999) [1080p BluRay].mkv

    title = sanitize_filename(media_item.title)
    year = media_item.year || ""

    # Build quality string
    quality_parts = [
      get_quality_for_file(file),
      get_source_from_metadata(file)
    ]

    quality_str =
      quality_parts
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    # Build filename
    filename_parts = [
      "#{title} (#{year})",
      if(quality_str != "", do: "[#{quality_str}]", else: nil)
    ]

    filename_parts
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> Kernel.<>(extension)
  end

  defp generate_episode_filename(
         %Episode{} = episode,
         %MediaItem{} = media_item,
         %MediaFile{} = file,
         extension
       ) do
    # Format: {Show Title} - S{Season}E{Episode} - {Episode Title} [{Quality}].{ext}
    # Example: Breaking Bad - S01E01 - Pilot [720p].mkv

    show_title = sanitize_filename(media_item.title)
    season = String.pad_leading(to_string(episode.season_number), 2, "0")
    episode_num = String.pad_leading(to_string(episode.episode_number), 2, "0")
    episode_title = if episode.title, do: sanitize_filename(episode.title), else: "TBA"

    # Get quality info - try to parse from filename if DB value seems wrong or missing
    quality = get_quality_for_file(file)

    # Build filename
    "#{show_title} - S#{season}E#{episode_num} - #{episode_title} [#{quality}]#{extension}"
  end

  defp generate_filename_from_path(%MediaFile{} = file, extension) do
    # For TV show files not associated with episodes, parse the filename
    # to extract season/episode info
    absolute_path = MediaFile.absolute_path(file)
    basename = Path.basename(absolute_path, extension)
    media_item = file.media_item

    # Try to extract S##E## or similar pattern from filename
    case Regex.run(~r/[Ss](\d+)[Ee](\d+)/, basename) do
      [_, season_str, episode_str] ->
        season = String.pad_leading(season_str, 2, "0")
        episode_num = String.pad_leading(episode_str, 2, "0")

        # Try to extract episode title (text between episode number and quality)
        episode_title =
          case Regex.run(~r/[Ee]\d+[.\s]+([^.\d]+?)(?:\d{3,4}p|\.mkv|\.mp4)/i, basename) do
            [_, title] ->
              title
              |> String.replace([".", "_"], " ")
              |> String.trim()
              |> sanitize_filename()

            _ ->
              "Episode #{episode_num}"
          end

        show_title = sanitize_filename(media_item.title)
        quality = get_quality_for_file(file)

        "#{show_title} - S#{season}E#{episode_num} - #{episode_title} [#{quality}]#{extension}"

      _ ->
        # Can't parse, keep original filename
        Path.basename(absolute_path)
    end
  end

  defp get_quality_for_file(%MediaFile{} = file) do
    # Try to parse resolution from the current filename first
    # This handles cases where DB has wrong/stale data
    absolute_path = MediaFile.absolute_path(file)
    basename = Path.basename(absolute_path)

    parsed_resolution =
      case Regex.run(~r/\b(\d{3,4}p)\b/i, basename) do
        [_, res] -> String.downcase(res)
        _ -> nil
      end

    # Prefer parsed resolution from filename, fallback to DB value
    parsed_resolution || file.resolution || "Unknown"
  end

  defp sanitize_filename(name) when is_binary(name) do
    name
    # Remove or replace invalid filesystem characters
    |> String.replace(~r/[<>:"|?*]/, "")
    # Replace forward and back slashes with dashes
    |> String.replace(~r/[\/\\]/, "-")
    # Replace multiple spaces with single space
    |> String.replace(~r/\s+/, " ")
    # Trim whitespace
    |> String.trim()
  end

  defp get_source_from_metadata(%MediaFile{} = file) do
    # Try to determine source from codec or metadata
    cond do
      # Check metadata for source
      file.metadata && file.metadata.source ->
        file.metadata.source

      # Infer from codec
      file.codec && String.contains?(String.downcase(file.codec), "bluray") ->
        "BluRay"

      file.codec && String.contains?(String.downcase(file.codec), "web") ->
        "WEB-DL"

      # Default
      true ->
        "WEB-DL"
    end
  end
end
