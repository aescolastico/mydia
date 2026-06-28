defmodule Mydia.Library.Structs.Quality do
  @moduledoc """
  Canonical parsed-quality struct.

  Represents quality information parsed either from a release title
  (indexer search results) or extracted from an on-disk media file.
  Provides compile-time safety for quality data, replacing plain map
  access that can silently return nil.

  Boolean release flags (`hdr`, `proper`, `repack`) default to `false`;
  on-disk files simply leave them at the defaults.

  ## HDR Format Tiers (per TRaSH Guides)

  - "DV" (Dolby Vision) - highest quality, includes fallback layer
  - "HDR10+" - dynamic metadata
  - "HDR10" - static metadata HDR
  - nil (SDR) - standard dynamic range
  """

  defstruct resolution: nil,
            source: nil,
            codec: nil,
            audio: nil,
            hdr: false,
            hdr_format: nil,
            proper: false,
            repack: false

  @type t :: %__MODULE__{
          resolution: String.t() | nil,
          source: String.t() | nil,
          codec: String.t() | nil,
          audio: String.t() | nil,
          hdr: boolean(),
          hdr_format: String.t() | nil,
          proper: boolean(),
          repack: boolean()
        }

  @doc """
  Creates a new Quality struct from a keyword list or map.

  ## Examples

      iex> new(resolution: "1080p", source: "BluRay")
      %Quality{resolution: "1080p", source: "BluRay", hdr: false, proper: false, repack: false}
  """
  def new(attrs \\ []) when is_list(attrs) or is_map(attrs) do
    struct(__MODULE__, attrs)
  end

  @doc """
  Returns an empty Quality struct (all content nil, flags false).
  """
  def empty do
    %__MODULE__{}
  end

  @doc """
  Checks if a Quality struct is empty (all content fields are nil).
  Boolean flags are not considered.
  """
  def empty?(%__MODULE__{} = quality) do
    quality.resolution == nil &&
      quality.source == nil &&
      quality.codec == nil &&
      quality.audio == nil &&
      quality.hdr_format == nil
  end

  @doc """
  Formats a Quality struct as a human-readable string.

  ## Examples

      iex> format(%Quality{resolution: "1080p", source: "BluRay", codec: "x264"})
      "1080p BluRay x264"

      iex> format(%Quality{resolution: "2160p", source: "WEB-DL", hdr: true, hdr_format: "DV"})
      "2160p WEB-DL DV"
  """
  def format(%__MODULE__{} = quality) do
    [
      quality.resolution,
      quality.source,
      quality.codec,
      quality.audio,
      if(quality.hdr && quality.hdr_format, do: quality.hdr_format),
      if(quality.hdr && !quality.hdr_format, do: "HDR"),
      if(quality.proper, do: "PROPER"),
      if(quality.repack, do: "REPACK")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  def format(nil), do: nil

  @doc """
  Creates a Quality struct from a plain map with string or atom keys.

  Used to reconstruct a Quality from database-stored JSON data.
  """
  def from_map(nil), do: nil

  def from_map(map) when is_map(map) do
    new(%{
      resolution: map["resolution"] || map[:resolution],
      source: map["source"] || map[:source],
      codec: map["codec"] || map[:codec],
      audio: map["audio"] || map[:audio],
      hdr: map["hdr"] || map[:hdr] || false,
      hdr_format: map["hdr_format"] || map[:hdr_format],
      proper: map["proper"] || map[:proper] || false,
      repack: map["repack"] || map[:repack] || false
    })
  end
end
