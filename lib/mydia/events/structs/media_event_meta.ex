defmodule Mydia.Events.Structs.MediaEventMeta do
  @moduledoc "Metadata for media-related events."

  @derive Jason.Encoder

  defstruct [
    :title,
    :media_type,
    :year,
    :tmdb_id,
    :reason,
    :changes,
    :monitored,
    :file_path,
    :resolution,
    :codec,
    :size,
    :media_title,
    :episode_count,
    :episode_id,
    :season_number,
    :episode_number,
    :description
  ]

  @type t :: %__MODULE__{
          title: String.t() | nil,
          media_type: String.t() | nil,
          year: integer() | nil,
          tmdb_id: String.t() | integer() | nil,
          reason: String.t() | nil,
          changes: map() | nil,
          monitored: boolean() | nil,
          file_path: String.t() | nil,
          resolution: String.t() | nil,
          codec: String.t() | nil,
          size: integer() | nil,
          media_title: String.t() | nil,
          episode_count: integer() | nil,
          episode_id: String.t() | integer() | nil,
          season_number: integer() | nil,
          episode_number: integer() | nil,
          description: String.t() | nil
        }

  @known_keys %{
    "title" => :title,
    "media_type" => :media_type,
    "year" => :year,
    "tmdb_id" => :tmdb_id,
    "reason" => :reason,
    "changes" => :changes,
    "monitored" => :monitored,
    "file_path" => :file_path,
    "resolution" => :resolution,
    "codec" => :codec,
    "size" => :size,
    "media_title" => :media_title,
    "episode_count" => :episode_count,
    "episode_id" => :episode_id,
    "season_number" => :season_number,
    "episode_number" => :episode_number,
    "description" => :description
  }

  @doc """
  Converts a string-key map to a `MediaEventMeta` struct.

  Unknown keys are silently ignored.

  ## Examples

      iex> MediaEventMeta.from_map(%{"title" => "Breaking Bad", "media_type" => "tv_show"})
      %MediaEventMeta{title: "Breaking Bad", media_type: "tv_show"}
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    attrs =
      for {k, v} <- map,
          atom_key = Map.get(@known_keys, to_string(k)),
          into: %{},
          do: {atom_key, v}

    struct(__MODULE__, attrs)
  end
end
