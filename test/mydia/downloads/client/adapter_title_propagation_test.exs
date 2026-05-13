defmodule Mydia.Downloads.Client.AdapterTitlePropagationTest do
  use ExUnit.Case, async: true

  alias Mydia.Downloads.Client.{Sabnzbd, Nzbget}

  describe "SABnzbd title propagation" do
    setup do
      bypass = Bypass.open()

      config = %{
        type: :sabnzbd,
        host: "localhost",
        port: bypass.port,
        api_key: "test-api-key",
        use_ssl: false,
        url_base: nil,
        options: %{}
      }

      {:ok, bypass: bypass, config: config}
    end

    test "file upload: multipart filename uses title and nzbname param is set",
         %{bypass: bypass, config: config} do
      nzb_content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><nzb></nzb>"

      Bypass.expect(bypass, "POST", "/api", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["nzbname"] == "My Movie"

        {:ok, body, conn} = Plug.Conn.read_body(conn, length: 1_000_000)
        assert body =~ "My Movie.nzb"
        refute body =~ "upload.nzb"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status": true, "nzo_ids": ["SABnzbd_nzo_title1"]}))
      end)

      assert {:ok, _} = Sabnzbd.add_torrent(config, {:file, nzb_content}, title: "My Movie")
    end

    test "file upload: no title falls back to upload.nzb with no nzbname param",
         %{bypass: bypass, config: config} do
      nzb_content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><nzb></nzb>"

      Bypass.expect(bypass, "POST", "/api", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        refute Map.has_key?(conn.query_params, "nzbname")

        {:ok, body, conn} = Plug.Conn.read_body(conn, length: 1_000_000)
        assert body =~ "upload.nzb"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status": true, "nzo_ids": ["SABnzbd_nzo_fallback1"]}))
      end)

      assert {:ok, _} = Sabnzbd.add_torrent(config, {:file, nzb_content})
    end

    test "URL addition: nzbname param is set",
         %{bypass: bypass, config: config} do
      Bypass.expect(bypass, "GET", "/api", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["nzbname"] == "My Movie"
        assert conn.query_params["mode"] == "addurl"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status": true, "nzo_ids": ["SABnzbd_nzo_url1"]}))
      end)

      assert {:ok, _} =
               Sabnzbd.add_torrent(config, {:url, "https://example.com/test.nzb"},
                 title: "My Movie"
               )
    end

    test "URL addition: no title means no nzbname param",
         %{bypass: bypass, config: config} do
      Bypass.expect(bypass, "GET", "/api", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        refute Map.has_key?(conn.query_params, "nzbname")

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status": true, "nzo_ids": ["SABnzbd_nzo_url2"]}))
      end)

      assert {:ok, _} =
               Sabnzbd.add_torrent(config, {:url, "https://example.com/test.nzb"})
    end
  end

  describe "NZBGet title propagation" do
    setup do
      bypass = Bypass.open()

      config = %{
        type: :nzbget,
        host: "localhost",
        port: bypass.port,
        username: "nzbget",
        password: "tegbzn6789",
        use_ssl: false,
        url_base: nil,
        options: %{}
      }

      {:ok, bypass: bypass, config: config}
    end

    test "file upload: uses title as filename in append RPC call",
         %{bypass: bypass, config: config} do
      nzb_content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><nzb></nzb>"

      Bypass.expect(bypass, "POST", "/jsonrpc", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"method" => "append", "params" => params} = Jason.decode!(body)
        [filename | _] = params
        assert filename == "My Movie.nzb"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"jsonrpc" => "2.0", "result" => 42, "id" => 1}))
      end)

      assert {:ok, "42"} = Nzbget.add_torrent(config, {:file, nzb_content}, title: "My Movie")
    end

    test "file upload: no title falls back to upload.nzb",
         %{bypass: bypass, config: config} do
      nzb_content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><nzb></nzb>"

      Bypass.expect(bypass, "POST", "/jsonrpc", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"method" => "append", "params" => params} = Jason.decode!(body)
        [filename | _] = params
        assert filename == "upload.nzb"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"jsonrpc" => "2.0", "result" => 43, "id" => 1}))
      end)

      assert {:ok, "43"} = Nzbget.add_torrent(config, {:file, nzb_content})
    end
  end
end
