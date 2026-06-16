defmodule Mydia.Jobs.UsenetImportIntegrationTest do
  use Mydia.DataCase, async: true
  use Oban.Testing, repo: Mydia.Repo

  alias Mydia.Jobs.{DownloadMonitor, MediaImport}
  alias Mydia.{Downloads, Library, Settings}
  import Mydia.MediaFixtures
  import Mydia.DownloadsFixtures

  @moduletag :tmp_dir

  describe "SABnzbd full pipeline" do
    setup %{tmp_dir: tmp_dir} do
      bypass = Bypass.open()

      {:ok, client_config} =
        Settings.create_download_client_config(%{
          name: "SABnzbd-Test-#{System.unique_integer([:positive])}",
          type: :sabnzbd,
          host: "localhost",
          port: bypass.port,
          api_key: "test-api-key",
          enabled: true,
          priority: 1
        })

      library_path = create_test_library_path(tmp_dir, :movies)

      {:ok, bypass: bypass, client_config: client_config, library_path: library_path}
    end

    test "imports movie via client-reported save_path", %{
      bypass: bypass,
      client_config: client_config,
      tmp_dir: tmp_dir
    } do
      download_dir = Path.join(tmp_dir, "sabnzbd_downloads")
      File.mkdir_p!(download_dir)
      movie_file = Path.join(download_dir, "Integration.Movie.2024.1080p.mkv")
      File.write!(movie_file, "fake video content for integration test")

      nzo_id = "SABnzbd_nzo_int001"

      Bypass.expect(bypass, "GET", "/api", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        case conn.query_params["mode"] do
          "history" ->
            history_slots = [
              %{
                "nzo_id" => nzo_id,
                "filename" => "Integration.Movie.2024.1080p.mkv",
                "status" => "Completed",
                "bytes" => 1_000_000,
                "storage" => download_dir,
                "completed" => System.system_time(:second)
              }
            ]

            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(
              200,
              Jason.encode!(%{"history" => %{"slots" => history_slots}})
            )

          "queue" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, Jason.encode!(%{"queue" => %{"slots" => []}}))
        end
      end)

      media_item = media_item_fixture(%{type: "movie", title: "Integration Movie", year: 2024})

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          status: "completed",
          completed_at: DateTime.utc_now(),
          download_client: client_config.name,
          download_client_id: nzo_id
        })

      assert {:ok, :imported} =
               perform_job(MediaImport, %{"download_id" => download.id})

      updated = Downloads.get_download!(download.id)
      assert updated.imported_at != nil

      media_files = Library.list_media_files()
      assert Enum.any?(media_files, &String.ends_with?(&1.relative_path, ".mkv"))
    end
  end

  describe "save_path fallback pipeline" do
    setup %{tmp_dir: tmp_dir} do
      bypass = Bypass.open()

      {:ok, client_config} =
        Settings.create_download_client_config(%{
          name: "NZBGet-Fallback-#{System.unique_integer([:positive])}",
          type: :nzbget,
          host: "localhost",
          port: bypass.port,
          username: "nzbget",
          password: "tegbzn6789",
          enabled: true,
          priority: 1
        })

      library_path = create_test_library_path(tmp_dir, :movies)

      {:ok, bypass: bypass, client_config: client_config, library_path: library_path}
    end

    test "imports via save_path when client purged from history", %{
      bypass: bypass,
      client_config: client_config,
      tmp_dir: tmp_dir
    } do
      download_dir = Path.join(tmp_dir, "nzbget_downloads")
      File.mkdir_p!(download_dir)
      movie_file = Path.join(download_dir, "Fallback.Movie.2024.1080p.mkv")
      File.write!(movie_file, "fake video content for fallback test")

      nzb_id = "999"

      Bypass.expect(bypass, "POST", "/jsonrpc", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"method" => method} = Jason.decode!(body)

        case method do
          "listgroups" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(
              200,
              Jason.encode!(%{"jsonrpc" => "2.0", "result" => [], "id" => 1})
            )

          "history" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(
              200,
              Jason.encode!(%{"jsonrpc" => "2.0", "result" => [], "id" => 1})
            )

          _ ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(
              200,
              Jason.encode!(%{
                "jsonrpc" => "2.0",
                "result" => nil,
                "error" => %{"code" => -1, "message" => "Unknown method"},
                "id" => 1
              })
            )
        end
      end)

      media_item =
        media_item_fixture(%{type: "movie", title: "Fallback Movie", year: 2024})

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          status: "completed",
          completed_at: DateTime.utc_now(),
          download_client: client_config.name,
          download_client_id: nzb_id
        })

      assert {:ok, :imported} =
               perform_job(MediaImport, %{
                 "download_id" => download.id,
                 "save_path" => download_dir
               })

      updated = Downloads.get_download!(download.id)
      assert updated.imported_at != nil
    end

    test "returns error when client purged and no save_path", %{
      bypass: bypass,
      client_config: client_config
    } do
      Bypass.expect(bypass, "POST", "/jsonrpc", fn conn ->
        {:ok, _body, conn} = Plug.Conn.read_body(conn)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"jsonrpc" => "2.0", "result" => [], "id" => 1})
        )
      end)

      media_item =
        media_item_fixture(%{type: "movie", title: "No SavePath Movie", year: 2024})

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          status: "completed",
          completed_at: DateTime.utc_now(),
          download_client: client_config.name,
          download_client_id: "888"
        })

      assert {:error, :client_error} =
               perform_job(MediaImport, %{"download_id" => download.id})
    end

    test "classifies a save_path with no visible parent as a mapping mismatch", %{
      bypass: bypass,
      client_config: client_config
    } do
      Bypass.expect(bypass, "POST", "/jsonrpc", fn conn ->
        {:ok, _body, conn} = Plug.Conn.read_body(conn)

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{"jsonrpc" => "2.0", "result" => [], "id" => 1})
        )
      end)

      media_item =
        media_item_fixture(%{type: "movie", title: "Bad Path Movie", year: 2024})

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          status: "completed",
          completed_at: DateTime.utc_now(),
          download_client: client_config.name,
          download_client_id: "777"
        })

      # Neither the leaf nor its immediate parent is visible inside Mydia's
      # filesystem view — the container volume mount-mismatch signature. This is
      # classified as a path-mapping mismatch and goes terminal on the first
      # attempt (returns :cancel, not :error).
      assert {:cancel, {:path_mapping_mismatch, "/nonexistent/path/that/does/not/exist"}} =
               perform_job(MediaImport, %{
                 "download_id" => download.id,
                 "save_path" => "/nonexistent/path/that/does/not/exist"
               })
    end
  end

  describe "stalled NZB pipeline (DownloadMonitor + StallDetector)" do
    setup do
      bypass = Bypass.open()

      {:ok, client_config} =
        Settings.create_download_client_config(%{
          name: "SABnzbd-Stalled-#{System.unique_integer([:positive])}",
          type: :sabnzbd,
          host: "localhost",
          port: bypass.port,
          api_key: "test-api-key",
          enabled: true,
          priority: 1,
          incomplete_grace_minutes: 15
        })

      {:ok, bypass: bypass, client_config: client_config}
    end

    test "DownloadMonitor flags an NZB whose bytes haven't moved past the grace window",
         %{bypass: bypass, client_config: client_config} do
      nzo_id = "SABnzbd_nzo_stalled001"

      # The client keeps reporting the same byte count poll after poll —
      # exactly the scenario described in #126. Both queue and history are
      # consulted by `list_torrents`, so we serve both.
      Bypass.expect(bypass, "GET", "/api", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        case conn.query_params["mode"] do
          "queue" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(
              200,
              Jason.encode!(%{
                "queue" => %{
                  "slots" => [
                    %{
                      "nzo_id" => nzo_id,
                      "filename" => "Stalled.Show.S01E01.mkv",
                      "status" => "Downloading",
                      "mb" => 100.0,
                      "mbleft" => 75.0,
                      "kbpersec" => 0.0,
                      "timeleft" => "0:00:00",
                      "storage" => "/downloads",
                      "added" => System.system_time(:second)
                    }
                  ]
                }
              })
            )

          "history" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, Jason.encode!(%{"history" => %{"slots" => []}}))

          _ ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, "{}")
        end
      end)

      media_item = media_item_fixture(%{type: "movie"})
      first_seen = ~U[2026-05-14 10:00:00.000000Z]
      same_bytes = round(25.0 * 1024 * 1024)

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: client_config.name,
          download_client_id: nzo_id,
          last_progress_at: first_seen,
          last_known_bytes: same_bytes
        })

      # 16 minutes after `first_seen` — past the 15-minute grace window.
      now = ~U[2026-05-14 10:16:00.000000Z]

      assert :ok = perform_job(DownloadMonitor, %{"now" => DateTime.to_iso8601(now)})

      updated = Downloads.get_download!(download.id)
      assert updated.import_failed_at != nil
      assert DateTime.diff(updated.import_failed_at, now, :second) == 0
      assert updated.import_last_error == "stalled after 15m without progress"
    end

    test "DownloadMonitor clears no progress when bytes finally move past the grace window",
         %{bypass: bypass, client_config: client_config} do
      nzo_id = "SABnzbd_nzo_recovers001"

      # The mocked queue reports bytes that have moved up by 5MB since the
      # previous observation — even though more than the grace window has
      # elapsed, this is forward progress, not a stall.
      Bypass.expect(bypass, "GET", "/api", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        case conn.query_params["mode"] do
          "queue" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(
              200,
              Jason.encode!(%{
                "queue" => %{
                  "slots" => [
                    %{
                      "nzo_id" => nzo_id,
                      "filename" => "Recovers.Show.S01E01.mkv",
                      "status" => "Downloading",
                      "mb" => 100.0,
                      "mbleft" => 70.0,
                      "kbpersec" => 50.0,
                      "timeleft" => "0:30:00",
                      "storage" => "/downloads",
                      "added" => System.system_time(:second)
                    }
                  ]
                }
              })
            )

          "history" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, Jason.encode!(%{"history" => %{"slots" => []}}))

          _ ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.resp(200, "{}")
        end
      end)

      media_item = media_item_fixture(%{type: "movie"})
      first_seen = ~U[2026-05-14 10:00:00.000000Z]
      previous_bytes = round(25.0 * 1024 * 1024)

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: client_config.name,
          download_client_id: nzo_id,
          last_progress_at: first_seen,
          last_known_bytes: previous_bytes
        })

      # 20 minutes later — past the 15-min grace, but bytes increased.
      now = ~U[2026-05-14 10:20:00.000000Z]

      assert :ok = perform_job(DownloadMonitor, %{"now" => DateTime.to_iso8601(now)})

      updated = Downloads.get_download!(download.id)
      assert is_nil(updated.import_failed_at)
      assert updated.last_progress_at != first_seen
      assert updated.last_known_bytes > previous_bytes
    end
  end

  defp create_test_library_path(base_path, type) do
    library_path = Path.join(base_path, "library")
    File.mkdir_p!(library_path)

    {:ok, path_record} =
      Settings.create_library_path(%{
        path: library_path,
        type: type,
        monitored: true
      })

    path_record
  end
end
