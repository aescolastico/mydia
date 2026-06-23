defmodule Mydia.Library.FileNamer do
  @moduledoc """
  Generates TRaSH Guides-compatible filenames for media imports.

  This module creates filenames that preserve quality metadata and follow
  TRaSH Guides naming conventions to prevent download loops and ensure
  proper quality tracking.

  ## TRaSH Naming Formats

  **Movies:**
  ```
  {Movie CleanTitle} ({Release Year}) [Edition]{[Quality Full]}{[Audio]}{[HDR]}{[Codec]}{-Release Group}
  ```
  Example: `The Movie Title (2010) [IMAX][Bluray-1080p Proper][DTS 5.1][DV HDR10][x264]-RlsGrp`

  **TV Shows:**
  ```
  {Series Title} ({Year}) - S{season:00}E{episode:00} - {Episode Title} {[Quality Full]}{[Audio]}{[HDR]}{[Codec]}{-Release Group}
  ```
  Example: `Show Title (2020) - S01E01 - Episode Title [WEB-1080p][DTS 5.1][HDR10][x264]-RlsGrp`
  """

  alias Mydia.Library.NamingTemplate
  alias Mydia.Settings.RuntimeConfig

  @doc """
  Generates a filename for a movie.

  ## Parameters
    - `media_item` - The movie media item (must have title and year)
    - `quality_info` - Quality information map with keys: resolution, source, codec, audio, hdr, proper, repack
    - `original_filename` - Original filename (for extension and release group)

  ## Examples

      iex> media_item = %{title: "The Matrix", year: 1999}
      iex> quality = %{resolution: "1080p", source: "BluRay", codec: "x264", audio: "DTS", hdr: false, proper: false, repack: false}
      iex> FileNamer.generate_movie_filename(media_item, quality, "The.Matrix.1999.1080p.BluRay.x264.DTS-GROUP.mkv")
      "The Matrix (1999) [BluRay-1080p] [DTS] [x264]-GROUP.mkv"
  """
  @spec generate_movie_filename(map(), map(), String.t()) :: String.t()
  def generate_movie_filename(media_item, quality_info, original_filename) do
    extension = Path.extname(original_filename)
    base_name = Path.basename(original_filename, extension)
    release_group = extract_release_group(base_name)

    context =
      media_item
      |> base_context(quality_info, release_group)

    NamingTemplate.render(naming().movie_file, context) <> extension
  end

  @doc """
  Generates a filename for a TV episode.

  ## Parameters
    - `media_item` - The TV show media item (must have title)
    - `episode` - The episode record (must have season_number, episode_number, title)
    - `quality_info` - Quality information map with keys: resolution, source, codec, audio, hdr, proper, repack
    - `original_filename` - Original filename (for extension and release group)

  ## Examples

      iex> media_item = %{title: "Breaking Bad", year: 2008}
      iex> episode = %{season_number: 1, episode_number: 1, title: "Pilot"}
      iex> quality = %{resolution: "1080p", source: "BluRay", codec: "x264", audio: nil, hdr: false, proper: false, repack: false}
      iex> FileNamer.generate_episode_filename(media_item, episode, quality, "Breaking.Bad.S01E01.1080p.BluRay.x264-GROUP.mkv")
      "Breaking Bad (2008) - S01E01 - Pilot [BluRay-1080p] [x264]-GROUP.mkv"
  """
  @spec generate_episode_filename(map(), map(), map(), String.t()) :: String.t()
  def generate_episode_filename(media_item, episode, quality_info, original_filename) do
    extension = Path.extname(original_filename)
    base_name = Path.basename(original_filename, extension)
    release_group = extract_release_group(base_name)

    season = String.pad_leading("#{episode.season_number}", 2, "0")
    ep_num = String.pad_leading("#{episode.episode_number}", 2, "0")

    context =
      media_item
      |> base_context(quality_info, release_group)
      |> Map.merge(%{
        "season" => season,
        "episode" => ep_num,
        "sxxeyy" => "S#{season}E#{ep_num}",
        "episode_title" => sanitize_title(episode.title || "")
      })

    NamingTemplate.render(naming().episode_file, context) <> extension
  end

  @doc """
  Sanitizes a title for use in a filename.

  Removes or replaces characters that are problematic in filenames.

  ## Examples

      iex> FileNamer.sanitize_title("The Matrix: Reloaded")
      "The Matrix - Reloaded"

      iex> FileNamer.sanitize_title("Law & Order")
      "Law and Order"
  """
  @spec sanitize_title(String.t()) :: String.t()
  def sanitize_title(title) when is_binary(title) do
    title
    |> String.replace(":", " -")
    |> String.replace("/", "-")
    |> String.replace("\\", "-")
    |> String.replace("<", "")
    |> String.replace(">", "")
    |> String.replace("\"", "'")
    |> String.replace("|", "-")
    |> String.replace("?", "")
    |> String.replace("*", "")
    |> String.replace("&", "and")
    # Remove multiple spaces
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc """
  Returns whether episodes should be placed in per-season sub-folders.
  """
  @spec season_folders_enabled?() :: boolean()
  def season_folders_enabled?, do: naming().season_folders

  @doc """
  Generates the library folder name for a movie from the configured template.

  ## Examples

      iex> FileNamer.generate_movie_folder(%{title: "The Matrix", year: 1999})
      "The Matrix (1999)"
  """
  @spec generate_movie_folder(map()) :: String.t()
  def generate_movie_folder(media_item) do
    render_folder(naming().movie_folder, media_item)
  end

  @doc """
  Generates the library folder name for a TV show from the configured template.

  ## Examples

      iex> FileNamer.generate_tv_folder(%{title: "Breaking Bad", year: 2008})
      "Breaking Bad"
  """
  @spec generate_tv_folder(map()) :: String.t()
  def generate_tv_folder(media_item) do
    render_folder(naming().tv_folder, media_item)
  end

  @doc """
  Generates the per-season sub-folder name from the configured template.

  ## Examples

      iex> FileNamer.generate_season_folder(1)
      "Season 01"
  """
  @spec generate_season_folder(integer() | String.t()) :: String.t()
  def generate_season_folder(season_number) do
    context = %{"season" => String.pad_leading("#{season_number}", 2, "0")}

    naming().season_folder
    |> NamingTemplate.render(context)
    |> sanitize_path_component()
  end

  ## Private Functions

  # Renders a folder template and sanitizes the result for use as a single path
  # component. Falls back to "Unknown" if the result is blank.
  defp render_folder(template, media_item) do
    case template
         |> NamingTemplate.render(folder_context(media_item))
         |> sanitize_path_component() do
      "" -> "Unknown"
      name -> name
    end
  end

  # Folder context uses the *raw* title (the whole rendered name is sanitized as
  # a path component afterwards), matching the legacy folder-naming behavior.
  defp folder_context(media_item) do
    %{
      "title" => Map.get(media_item, :title) || "",
      "year" => year_value(Map.get(media_item, :year)),
      "tmdb" => provider_tag("tmdb", Map.get(media_item, :tmdb_id)),
      "tvdb" => provider_tag("tvdb", Map.get(media_item, :tvdb_id)),
      "imdb" => provider_tag("imdb", Map.get(media_item, :imdb_id))
    }
  end

  defp sanitize_path_component(name) do
    name
    |> String.replace(~r/[<>:"\/\\|?*]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # Builds the token context shared by movie and episode templates.
  defp base_context(media_item, quality_info, release_group) do
    %{
      "title" => sanitize_title(media_item.title),
      "year" => year_value(Map.get(media_item, :year)),
      "quality" => build_quality_tag(quality_info),
      "audio" => build_audio_tag(quality_info.audio),
      "hdr" => build_hdr_tag(quality_info),
      "codec" => build_codec_tag(quality_info.codec),
      "release_group" => release_group_tag(release_group),
      "tmdb" => provider_tag("tmdb", Map.get(media_item, :tmdb_id)),
      "tvdb" => provider_tag("tvdb", Map.get(media_item, :tvdb_id)),
      "imdb" => provider_tag("imdb", Map.get(media_item, :imdb_id))
    }
  end

  defp year_value(nil), do: ""
  defp year_value(year), do: to_string(year)

  defp release_group_tag(nil), do: ""
  defp release_group_tag(""), do: ""
  defp release_group_tag(group) when is_binary(group), do: "-#{group}"

  defp provider_tag(_prefix, nil), do: ""
  defp provider_tag(_prefix, ""), do: ""
  defp provider_tag(prefix, id), do: "#{prefix}-#{id}"

  # Resolved naming templates (DB/UI > YAML > schema defaults). Falls back to
  # schema defaults if the runtime config is unavailable.
  defp naming do
    RuntimeConfig.get_naming_config()
  rescue
    _ -> %Mydia.Config.Schema.Naming{}
  end

  defp build_quality_tag(%{
         source: source,
         resolution: resolution,
         proper: proper,
         repack: repack
       }) do
    parts = [
      source,
      resolution,
      if(proper, do: "Proper", else: nil),
      if(repack, do: "Repack", else: nil)
    ]

    tag =
      parts
      |> Enum.reject(&is_nil/1)
      |> Enum.join("-")

    if tag != "", do: "[#{tag}]", else: nil
  end

  defp build_audio_tag(nil), do: nil

  defp build_audio_tag(audio) when is_binary(audio) do
    # Audio format already clean from parser
    "[#{audio}]"
  end

  defp build_hdr_tag(%{hdr: false}), do: nil

  defp build_hdr_tag(%{hdr: true}) do
    # Just tag as HDR - specific HDR format detection can be added later
    "[HDR]"
  end

  defp build_codec_tag(nil), do: nil

  defp build_codec_tag(codec) when is_binary(codec) do
    "[#{codec}]"
  end

  defp extract_release_group(filename) do
    # Release group is usually after the last hyphen
    # Example: "Movie.1080p.BluRay.x264-GROUP" -> "GROUP"
    case String.split(filename, "-") do
      parts when length(parts) > 1 ->
        parts
        |> List.last()
        |> String.trim()
        # Remove common extensions that might be included
        |> String.replace(~r/\.(mkv|mp4|avi)$/i, "")

      _ ->
        nil
    end
  end
end
