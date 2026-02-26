defmodule Mydia.MediaServer.WatchedSync do
  @moduledoc """
  Behaviour for media server watched status sync adapters.

  Each adapter (Plex, Jellyfin, etc.) implements this behaviour to:
  - Fetch watched items from the server
  - Mark items as watched/unwatched on the server
  - Build an index of server items for efficient export
  """

  alias Mydia.Settings.MediaServerConfig

  @type watched_item :: %{
          type: :movie | :episode,
          external_ids: %{
            optional(:tmdb) => String.t(),
            optional(:tvdb) => String.t(),
            optional(:imdb) => String.t()
          },
          title: String.t(),
          season_number: integer() | nil,
          episode_number: integer() | nil,
          server_item_id: String.t()
        }

  @doc """
  Fetches all watched items from the media server.

  Returns a list of watched items with external IDs for matching
  and server_item_id for marking back.
  """
  @callback fetch_watched(config :: MediaServerConfig.t()) ::
              {:ok, [watched_item()]} | {:error, term()}

  @doc """
  Marks a specific item as watched on the media server.
  """
  @callback mark_watched(config :: MediaServerConfig.t(), server_item_id :: String.t()) ::
              :ok | {:error, term()}

  @doc """
  Marks a specific item as unwatched on the media server.
  """
  @callback mark_unwatched(config :: MediaServerConfig.t(), server_item_id :: String.t()) ::
              :ok | {:error, term()}

  @doc """
  Builds a lookup map from external ID keys to server_item_ids.

  Used by export to find which server items to mark as watched.
  Keys are in the format `"{type}:{provider}:{id}"` (e.g., `"movie:tmdb:12345"`).
  """
  @callback build_server_index(config :: MediaServerConfig.t()) ::
              {:ok, %{String.t() => String.t()}} | {:error, term()}

  @doc """
  Returns the adapter module for the given media server config.
  """
  def adapter_for(%{type: :plex}), do: {:ok, Mydia.MediaServer.WatchedSync.Plex}
  def adapter_for(%{type: type}), do: {:error, "Watched sync not supported for #{type}"}
end
