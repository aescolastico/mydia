defmodule Mydia.Jobs.MediaServerWatchedSyncTest do
  use Mydia.DataCase
  use Oban.Testing, repo: Mydia.Repo

  alias Mydia.Jobs.MediaServerWatchedSync
  alias Mydia.Settings

  import Mydia.AccountsFixtures

  describe "perform/1 with mode all_enabled" do
    test "skips when no servers have watched sync enabled" do
      {:ok, _server} =
        Settings.create_media_server_config(%{
          name: "Test Plex",
          type: :plex,
          url: "http://localhost:32400",
          token: "test-token",
          enabled: true,
          connection_settings: %{}
        })

      assert :ok = perform_job(MediaServerWatchedSync, %{"mode" => "all_enabled"})
    end

    test "enqueues individual jobs for enabled servers with sync_watched" do
      user = user_fixture()

      {:ok, server} =
        Settings.create_media_server_config(%{
          name: "Sync Plex",
          type: :plex,
          url: "http://localhost:32400",
          token: "test-token",
          enabled: true,
          connection_settings: %{"sync_watched" => true}
        })

      assert :ok = perform_job(MediaServerWatchedSync, %{"mode" => "all_enabled"})

      assert_enqueued(
        worker: MediaServerWatchedSync,
        args: %{"config_id" => server.id, "user_id" => user.id}
      )
    end
  end

  describe "perform/1 with individual config" do
    test "skips when server is disabled" do
      user = user_fixture()

      {:ok, server} =
        Settings.create_media_server_config(%{
          name: "Disabled Plex",
          type: :plex,
          url: "http://localhost:32400",
          token: "test-token",
          enabled: false,
          connection_settings: %{"sync_watched" => true}
        })

      assert {:ok, :skipped} =
               perform_job(MediaServerWatchedSync, %{
                 "config_id" => server.id,
                 "user_id" => user.id
               })
    end

    test "skips when sync_watched is not enabled" do
      user = user_fixture()

      {:ok, server} =
        Settings.create_media_server_config(%{
          name: "No Sync Plex",
          type: :plex,
          url: "http://localhost:32400",
          token: "test-token",
          enabled: true,
          connection_settings: %{}
        })

      assert {:ok, :skipped} =
               perform_job(MediaServerWatchedSync, %{
                 "config_id" => server.id,
                 "user_id" => user.id
               })
    end
  end
end
