defmodule Mydia.MediaServer.WatchedSync.PlexTest do
  use ExUnit.Case, async: true

  alias Mydia.MediaServer.WatchedSync.Plex

  describe "behaviour implementation" do
    test "implements WatchedSync behaviour" do
      # Ensure the module is loaded
      Code.ensure_loaded!(Plex)

      assert function_exported?(Plex, :fetch_watched, 1)
      assert function_exported?(Plex, :mark_watched, 2)
      assert function_exported?(Plex, :mark_unwatched, 2)
      assert function_exported?(Plex, :build_server_index, 1)
    end
  end
end
