defmodule Mydia.Downloads.Client.Debrid do
  @moduledoc """
  Debrid download client adapter (placeholder).

  Replaced in U4 with the full provider-dispatching implementation. This
  scaffold exists so the registry, health-check dispatch, and admin UI can
  reference the module before the rest of the unit lands.
  """

  @behaviour Mydia.Downloads.Client

  alias Mydia.Downloads.Client.Error

  @not_yet_implemented "Debrid adapter is not yet implemented"

  @impl true
  def test_connection(_config), do: {:error, Error.unknown(@not_yet_implemented)}

  @impl true
  def add_torrent(_config, _torrent, _opts), do: {:error, Error.unknown(@not_yet_implemented)}

  @impl true
  def get_status(_config, _client_id), do: {:error, Error.unknown(@not_yet_implemented)}

  @impl true
  def list_torrents(_config, _opts), do: {:error, Error.unknown(@not_yet_implemented)}

  @impl true
  def remove_torrent(_config, _client_id, _opts),
    do: {:error, Error.unknown(@not_yet_implemented)}

  @impl true
  def pause_torrent(_config, _client_id), do: {:error, Error.unknown(@not_yet_implemented)}

  @impl true
  def resume_torrent(_config, _client_id), do: {:error, Error.unknown(@not_yet_implemented)}
end
