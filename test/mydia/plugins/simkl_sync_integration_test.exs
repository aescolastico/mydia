defmodule Mydia.Plugins.SimklSyncIntegrationTest do
  # async: false — starts a real pool under the app-wide PoolRegistry and seeds
  # rows the connected invocation reads (Postgres sandbox rule).
  use Mydia.DataCase, async: false

  import Mydia.AccountsFixtures

  alias Mydia.Media
  alias Mydia.Playback
  alias Mydia.Plugins
  alias Mydia.Plugins.Connections
  alias Mydia.Plugins.Host
  alias Mydia.Plugins.HostFunctions
  alias Mydia.Plugins.Plugin
  alias Mydia.Plugins.Registry
  alias Mydia.Settings

  @slug "simkl_sync"

  # The bundled guest, built by the :plugins compiler into priv/plugins/ (nix
  # toolchain). Read from the app dir like the webhook notifier integration test.
  defp guest_wasm, do: File.read!(Application.app_dir(:mydia, "priv/plugins/simkl_sync.wasm"))

  @grants %{
    "net:http" => ["127.0.0.1"],
    "state:kv" => [],
    "data:read" => ["playback_progress"],
    "surfaces:write" => ["playback:watched"],
    "users:connections" => [],
    "schedule:interval" => []
  }

  setup do
    # Plugin lifecycle replaces the global :runtime_config; restore it.
    original = Application.get_env(:mydia, :runtime_config)

    on_exit(fn ->
      if original,
        do: Application.put_env(:mydia, :runtime_config, original),
        else: Application.delete_env(:mydia, :runtime_config)
    end)

    bypass = Bypass.open()
    api_base = "http://127.0.0.1:#{bypass.port}"

    {:ok, _} =
      Settings.create_plugin_config(%{
        slug: @slug,
        name: "Simkl Sync",
        version: "1.0.0",
        source_url: "test",
        manifest: %{
          "slug" => @slug,
          "name" => "Simkl Sync",
          "version" => "1.0.0",
          "capabilities" => %{"events:subscribe" => ["playback.finished"]}
        },
        settings: %{"api_base" => api_base},
        granted_capabilities: @grants,
        enabled: true
      })

    {:ok, _} =
      Registry.register(@slug, %Plugin{
        slug: @slug,
        name: "Simkl Sync",
        granted_capabilities: @grants,
        enabled: true
      })

    on_exit(fn -> Registry.unregister(@slug) end)

    bytes = guest_wasm()

    imports =
      HostFunctions.imports_for(@slug,
        allow_private: true,
        resolver: fn _ -> {:ok, [{127, 0, 0, 1}]} end
      )

    {:ok, _pid} = Host.start_plugin(@slug, bytes, imports: imports)
    on_exit(fn -> Host.stop_plugin(@slug) end)

    user = user_fixture()
    {:ok, _} = Connections.connect(@slug, user.id, %{access_token: "simkl-token"})

    %{bypass: bypass, user: user}
  end

  defp movie!(imdb) do
    {:ok, item} =
      Media.create_media_item(%{
        title: "Movie #{imdb}",
        type: "movie",
        year: 2024,
        imdb_id: imdb,
        tmdb_id: System.unique_integer([:positive])
      })

    item
  end

  test "pulls Simkl history into mydia and pushes local watches back, with echo guard",
       %{bypass: bypass, user: user} do
    pull_movie = movie!("ttPULL")
    push_movie = movie!("ttPUSH")

    # A local watch to push.
    {:ok, _} =
      Playback.save_progress(user.id, [media_item_id: push_movie.id], %{
        position_seconds: 95,
        duration_seconds: 100
      })

    test_pid = self()

    Bypass.expect(bypass, "GET", "/sync/activities", fn conn ->
      Plug.Conn.resp(conn, 200, ~s({"all":"2024-06-01T00:00:00Z"}))
    end)

    Bypass.expect(bypass, "GET", "/sync/all-items", fn conn ->
      Plug.Conn.resp(conn, 200, ~s({"movies":[{"ids":{"imdb":"ttPULL"}}],"episodes":[]}))
    end)

    Bypass.expect(bypass, "POST", "/sync/history", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:history, body})
      Plug.Conn.resp(conn, 200, ~s({"added":{"movies":1}}))
    end)

    assert {:ok, result} = Plugins.invoke_plugin_schedule(@slug)
    assert result["pulled"] >= 1
    assert result["pushed"] >= 1

    # Pull: the Simkl-watched movie is now watched locally.
    assert Playback.get_progress(user.id, media_item_id: pull_movie.id).watched == true

    # Push: the local watch reached Simkl, and the just-pulled item was NOT
    # echoed back.
    assert_received {:history, body}
    assert body =~ "ttPUSH"
    refute body =~ "ttPULL"
  end

  test "a 401 from Simkl reports the connection as invalid", %{bypass: bypass, user: user} do
    Bypass.expect(bypass, "GET", "/sync/activities", fn conn ->
      Plug.Conn.resp(conn, 401, ~s({"error":"unauthorized"}))
    end)

    assert {:ok, result} = Plugins.invoke_plugin_schedule(@slug)
    assert user.id in result["connections_invalid"]
  end
end
