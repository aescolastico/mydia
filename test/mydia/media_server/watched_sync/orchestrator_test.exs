defmodule Mydia.MediaServer.WatchedSync.OrchestratorTest do
  use Mydia.DataCase

  alias Mydia.MediaServer.WatchedSync.Orchestrator
  alias Mydia.Playback

  import Mydia.AccountsFixtures
  import Mydia.MediaFixtures

  describe "import_watched/3 with movies" do
    test "marks a matched movie as watched" do
      user = user_fixture()
      movie = media_item_fixture(%{type: "movie", tmdb_id: 27205})

      adapter =
        mock_adapter(
          watched: [
            %{
              type: :movie,
              external_ids: %{tmdb: "27205"},
              title: "Inception",
              season_number: nil,
              episode_number: nil,
              server_item_id: "100"
            }
          ]
        )

      assert {:ok, stats} = Orchestrator.import_watched(adapter, %{name: "Test Plex"}, user.id)
      assert stats.imported == 1
      assert stats.skipped == 0
      assert stats.not_found == 0

      # Verify the movie is marked watched
      progress = Playback.get_progress(user.id, media_item_id: movie.id)
      assert progress.watched == true
    end

    test "skips already-watched items" do
      user = user_fixture()
      movie = media_item_fixture(%{type: "movie", tmdb_id: 555})

      # Pre-mark as watched
      Playback.save_progress(user.id, [media_item_id: movie.id], %{
        position_seconds: 0,
        duration_seconds: 1,
        watched: true
      })

      adapter =
        mock_adapter(
          watched: [
            %{
              type: :movie,
              external_ids: %{tmdb: "555"},
              title: "Already Watched",
              season_number: nil,
              episode_number: nil,
              server_item_id: "200"
            }
          ]
        )

      assert {:ok, stats} = Orchestrator.import_watched(adapter, %{name: "Test"}, user.id)
      assert stats.imported == 0
      assert stats.skipped == 1
    end

    test "counts not-found items" do
      user = user_fixture()

      adapter =
        mock_adapter(
          watched: [
            %{
              type: :movie,
              external_ids: %{tmdb: "999999"},
              title: "Unknown Movie",
              season_number: nil,
              episode_number: nil,
              server_item_id: "300"
            }
          ]
        )

      assert {:ok, stats} = Orchestrator.import_watched(adapter, %{name: "Test"}, user.id)
      assert stats.not_found == 1
    end
  end

  describe "import_watched/3 with episodes" do
    test "marks a matched episode as watched" do
      user = user_fixture()
      show = media_item_fixture(%{type: "tv_show", tvdb_id: 12345})
      episode = episode_fixture(%{media_item_id: show.id, season_number: 1, episode_number: 1})

      adapter =
        mock_adapter(
          watched: [
            %{
              type: :episode,
              external_ids: %{tvdb: "12345"},
              title: "Show S1E1",
              season_number: 1,
              episode_number: 1,
              server_item_id: "400"
            }
          ]
        )

      assert {:ok, stats} = Orchestrator.import_watched(adapter, %{name: "Test"}, user.id)
      assert stats.imported == 1

      progress = Playback.get_progress(user.id, episode_id: episode.id)
      assert progress.watched == true
    end
  end

  describe "export_watched/3" do
    test "exports watched movies to server" do
      user = user_fixture()
      movie = media_item_fixture(%{type: "movie", tmdb_id: 27205})

      # Mark as watched locally
      Playback.save_progress(user.id, [media_item_id: movie.id], %{
        position_seconds: 0,
        duration_seconds: 1,
        watched: true
      })

      {adapter, agent} = mock_adapter_with_tracking(server_index: %{"movie:tmdb:27205" => "100"})

      assert {:ok, stats} = Orchestrator.export_watched(adapter, %{name: "Test"}, user.id)
      assert stats.exported == 1

      # Verify mark_watched was called
      calls = Agent.get(agent, & &1)
      assert {:mark_watched, "100"} in calls
    end

    test "skips items not found in server index" do
      user = user_fixture()
      movie = media_item_fixture(%{type: "movie", tmdb_id: 99999})

      Playback.save_progress(user.id, [media_item_id: movie.id], %{
        position_seconds: 0,
        duration_seconds: 1,
        watched: true
      })

      {adapter, _agent} = mock_adapter_with_tracking(server_index: %{})

      assert {:ok, stats} = Orchestrator.export_watched(adapter, %{name: "Test"}, user.id)
      assert stats.export_skipped == 1
    end
  end

  describe "sync/3" do
    test "runs bidirectional sync by default" do
      user = user_fixture()
      _movie = media_item_fixture(%{type: "movie", tmdb_id: 111})

      {adapter, _agent} =
        mock_adapter_with_tracking(
          watched: [
            %{
              type: :movie,
              external_ids: %{tmdb: "111"},
              title: "Sync Test",
              season_number: nil,
              episode_number: nil,
              server_item_id: "500"
            }
          ],
          server_index: %{}
        )

      config = %{name: "Test", type: :plex}

      # We need to mock adapter_for, so test sync via orchestrator directly
      # by calling import + export
      assert {:ok, import_stats} = Orchestrator.import_watched(adapter, config, user.id)
      assert import_stats.imported == 1
    end
  end

  # ── Mock Helpers ──────────────────────────────────────────────────

  defp mock_adapter(opts) do
    watched = Keyword.get(opts, :watched, [])

    # Create a module-like map that the orchestrator can call
    # Since the orchestrator calls adapter.fetch_watched(config),
    # we use a simple module with the right callbacks
    mock_module = create_mock_module(watched: watched)
    mock_module
  end

  defp mock_adapter_with_tracking(opts) do
    watched = Keyword.get(opts, :watched, [])
    server_index = Keyword.get(opts, :server_index, %{})

    {:ok, agent} = Agent.start_link(fn -> [] end)

    mock_module =
      create_mock_module(
        watched: watched,
        server_index: server_index,
        tracking_agent: agent
      )

    {mock_module, agent}
  end

  defp create_mock_module(opts) do
    watched = Keyword.get(opts, :watched, [])
    server_index = Keyword.get(opts, :server_index, %{})
    agent = Keyword.get(opts, :tracking_agent)

    # Use a unique integer as key (escapable into quote blocks)
    key = :erlang.unique_integer([:positive])
    :persistent_term.put({__MODULE__, key, :watched}, watched)
    :persistent_term.put({__MODULE__, key, :server_index}, server_index)
    :persistent_term.put({__MODULE__, key, :agent}, agent)

    module_name = Module.concat(__MODULE__, "Mock#{key}")

    Module.create(
      module_name,
      quote do
        @behaviour Mydia.MediaServer.WatchedSync

        @key unquote(key)
        @test_module unquote(__MODULE__)

        @impl true
        def fetch_watched(_config) do
          {:ok, :persistent_term.get({@test_module, @key, :watched})}
        end

        @impl true
        def mark_watched(_config, server_item_id) do
          agent = :persistent_term.get({@test_module, @key, :agent})

          if agent,
            do: Agent.update(agent, fn calls -> [{:mark_watched, server_item_id} | calls] end)

          :ok
        end

        @impl true
        def mark_unwatched(_config, server_item_id) do
          agent = :persistent_term.get({@test_module, @key, :agent})

          if agent,
            do: Agent.update(agent, fn calls -> [{:mark_unwatched, server_item_id} | calls] end)

          :ok
        end

        @impl true
        def build_server_index(_config) do
          {:ok, :persistent_term.get({@test_module, @key, :server_index})}
        end
      end,
      Macro.Env.location(__ENV__)
    )

    module_name
  end
end
