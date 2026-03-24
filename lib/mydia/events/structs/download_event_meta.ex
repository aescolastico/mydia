defmodule Mydia.Events.Structs.DownloadEventMeta do
  @moduledoc "Metadata for download-related events."

  @derive Jason.Encoder

  defstruct [
    :title,
    :indexer,
    :download_client,
    :download_id,
    :error_message,
    :error_reason,
    :selected_release,
    :description,
    :media_item_id,
    :media_title,
    :media_type,
    :episode_id,
    :season_number,
    :episode_number
  ]

  @type t :: %__MODULE__{
          title: String.t() | nil,
          indexer: String.t() | nil,
          download_client: String.t() | nil,
          download_id: String.t() | integer() | nil,
          error_message: String.t() | nil,
          error_reason: String.t() | nil,
          selected_release: String.t() | nil,
          description: String.t() | nil,
          media_item_id: String.t() | integer() | nil,
          media_title: String.t() | nil,
          media_type: String.t() | nil,
          episode_id: String.t() | integer() | nil,
          season_number: integer() | nil,
          episode_number: integer() | nil
        }

  @known_keys %{
    "title" => :title,
    "indexer" => :indexer,
    "download_client" => :download_client,
    "download_id" => :download_id,
    "error_message" => :error_message,
    "error_reason" => :error_reason,
    "selected_release" => :selected_release,
    "description" => :description,
    "media_item_id" => :media_item_id,
    "media_title" => :media_title,
    "media_type" => :media_type,
    "episode_id" => :episode_id,
    "season_number" => :season_number,
    "episode_number" => :episode_number
  }

  @doc """
  Converts a string-key map to a `DownloadEventMeta` struct.

  Unknown keys are silently ignored.

  ## Examples

      iex> DownloadEventMeta.from_map(%{"title" => "Movie.2024.1080p", "download_client" => "qbittorrent"})
      %DownloadEventMeta{title: "Movie.2024.1080p", download_client: "qbittorrent"}
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
