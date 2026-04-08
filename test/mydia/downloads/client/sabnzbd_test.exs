defmodule Mydia.Downloads.Client.SabnzbdTest do
  use ExUnit.Case, async: true

  alias Mydia.Downloads.Client.Sabnzbd

  @config %{
    type: :sabnzbd,
    host: "localhost",
    port: 8080,
    api_key: "test-api-key",
    use_ssl: false,
    url_base: nil,
    options: %{}
  }

  describe "module behaviour" do
    test "implements all callbacks from Mydia.Downloads.Client behaviour" do
      # Verify the module implements the required behaviour
      behaviours = Sabnzbd.__info__(:attributes)[:behaviour] || []
      assert Mydia.Downloads.Client in behaviours
    end
  end

  describe "configuration validation" do
    test "test_connection requires API key" do
      config_without_api_key = Map.delete(@config, :api_key)

      {:error, error} = Sabnzbd.test_connection(config_without_api_key)
      assert error.type == :invalid_config
      assert error.message =~ "API key is required"
    end

    test "test_connection fails with unreachable host" do
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      {:error, error} = Sabnzbd.test_connection(timeout_config)
      assert error.type in [:connection_failed, :network_error, :timeout]
    end
  end

  describe "add_torrent/3" do
    test "returns error with unreachable host for URL addition" do
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      nzb_url = "https://example.com/test.nzb"

      {:error, error} = Sabnzbd.add_torrent(timeout_config, {:url, nzb_url})
      assert error.type in [:connection_failed, :network_error, :timeout]
    end

    test "rejects magnet links" do
      magnet = "magnet:?xt=urn:btih:ABC123DEF456789012345678901234567890ABCD&dn=test"

      {:error, error} = Sabnzbd.add_torrent(@config, {:magnet, magnet})
      assert error.type == :invalid_torrent
      assert error.message =~ "does not support magnet links"
    end

    test "requires API key" do
      config_without_api_key = Map.delete(@config, :api_key)
      nzb_url = "https://example.com/test.nzb"

      {:error, error} = Sabnzbd.add_torrent(config_without_api_key, {:url, nzb_url})
      assert error.type == :invalid_config
    end
  end

  describe "get_status/2" do
    test "returns error with unreachable host" do
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      {:error, error} = Sabnzbd.get_status(timeout_config, "SABnzbd_nzo_test123")
      assert error.type in [:connection_failed, :network_error, :timeout]
    end
  end

  describe "list_torrents/2" do
    test "returns error with unreachable host" do
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      {:error, error} = Sabnzbd.list_torrents(timeout_config)
      assert error.type in [:connection_failed, :network_error, :timeout]
    end

    test "accepts filter options" do
      # Test that the function accepts the expected options without error
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      {:error, _error} = Sabnzbd.list_torrents(timeout_config, filter: :downloading)
      {:error, _error} = Sabnzbd.list_torrents(timeout_config, filter: :completed)
      {:error, _error} = Sabnzbd.list_torrents(timeout_config, filter: :paused)
      assert true
    end
  end

  describe "remove_torrent/3" do
    test "returns error with unreachable host" do
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      {:error, error} = Sabnzbd.remove_torrent(timeout_config, "SABnzbd_nzo_test123")
      assert error.type in [:connection_failed, :network_error, :timeout]
    end

    test "requires API key" do
      config_without_api_key = Map.delete(@config, :api_key)

      {:error, error} = Sabnzbd.remove_torrent(config_without_api_key, "SABnzbd_nzo_test123")
      assert error.type == :invalid_config
    end

    test "accepts delete_files option" do
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      {:error, _error} = Sabnzbd.remove_torrent(timeout_config, "test", delete_files: true)
      {:error, _error} = Sabnzbd.remove_torrent(timeout_config, "test", delete_files: false)
      assert true
    end
  end

  describe "pause_torrent/2" do
    test "returns error with unreachable host" do
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      {:error, error} = Sabnzbd.pause_torrent(timeout_config, "SABnzbd_nzo_test123")
      assert error.type in [:connection_failed, :network_error, :timeout]
    end

    test "requires API key" do
      config_without_api_key = Map.delete(@config, :api_key)

      {:error, error} = Sabnzbd.pause_torrent(config_without_api_key, "SABnzbd_nzo_test123")
      assert error.type == :invalid_config
    end
  end

  describe "resume_torrent/2" do
    test "returns error with unreachable host" do
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      {:error, error} = Sabnzbd.resume_torrent(timeout_config, "SABnzbd_nzo_test123")
      assert error.type in [:connection_failed, :network_error, :timeout]
    end

    test "requires API key" do
      config_without_api_key = Map.delete(@config, :api_key)

      {:error, error} = Sabnzbd.resume_torrent(config_without_api_key, "SABnzbd_nzo_test123")
      assert error.type == :invalid_config
    end
  end

  describe "state mapping" do
    # These tests verify the state parsing logic works correctly
    # We can't easily test this without mocking, so we'll add integration tests instead
    # The state mapping is tested indirectly through integration tests
  end

  describe "URL base handling" do
    test "handles custom URL base in configuration" do
      config_with_base = %{@config | url_base: "/sabnzbd"}
      unreachable_config = %{config_with_base | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      # Should fail with connection error, not path error
      {:error, error} = Sabnzbd.test_connection(timeout_config)
      assert error.type in [:connection_failed, :network_error, :timeout]
    end
  end

  describe "add_torrent/3 with Bypass" do
    setup do
      bypass = Bypass.open()
      config = %{@config | host: "localhost", port: bypass.port}
      {:ok, bypass: bypass, config: config}
    end

    test "sends title-based multipart filename and nzbname param for file upload",
         %{bypass: bypass, config: config} do
      nzb_content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><nzb></nzb>"

      Bypass.expect(bypass, "POST", "/api", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["nzbname"] == "Movie Name (2024)"

        {:ok, body, conn} = Plug.Conn.read_body(conn, length: 1_000_000)
        assert body =~ "Movie Name (2024).nzb"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status": true, "nzo_ids": ["SABnzbd_nzo_test123"]}))
      end)

      assert {:ok, "SABnzbd_nzo_test123"} =
               Sabnzbd.add_torrent(config, {:file, nzb_content}, title: "Movie Name (2024)")
    end

    test "sends nzbname param for URL addition", %{bypass: bypass, config: config} do
      Bypass.expect(bypass, "GET", "/api", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["nzbname"] == "Show S01E01"
        assert conn.query_params["mode"] == "addurl"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status": true, "nzo_ids": ["SABnzbd_nzo_test456"]}))
      end)

      assert {:ok, "SABnzbd_nzo_test456"} =
               Sabnzbd.add_torrent(config, {:url, "https://example.com/test.nzb"},
                 title: "Show S01E01"
               )
    end

    test "falls back to upload.nzb when no title provided for file upload",
         %{bypass: bypass, config: config} do
      nzb_content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><nzb></nzb>"

      Bypass.expect(bypass, "POST", "/api", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        refute Map.has_key?(conn.query_params, "nzbname")

        {:ok, body, conn} = Plug.Conn.read_body(conn, length: 1_000_000)
        assert body =~ "upload.nzb"
        refute body =~ "nil"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status": true, "nzo_ids": ["SABnzbd_nzo_test789"]}))
      end)

      assert {:ok, "SABnzbd_nzo_test789"} =
               Sabnzbd.add_torrent(config, {:file, nzb_content})
    end

    test "falls back to upload.nzb when title is nil for file upload",
         %{bypass: bypass, config: config} do
      nzb_content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><nzb></nzb>"

      Bypass.expect(bypass, "POST", "/api", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        refute Map.has_key?(conn.query_params, "nzbname")

        {:ok, body, conn} = Plug.Conn.read_body(conn, length: 1_000_000)
        assert body =~ "upload.nzb"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status": true, "nzo_ids": ["SABnzbd_nzo_nil"]}))
      end)

      assert {:ok, "SABnzbd_nzo_nil"} =
               Sabnzbd.add_torrent(config, {:file, nzb_content}, title: nil)
    end

    test "no nzbname param when no title for URL addition",
         %{bypass: bypass, config: config} do
      Bypass.expect(bypass, "GET", "/api", fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        refute Map.has_key?(conn.query_params, "nzbname")
        assert conn.query_params["mode"] == "addurl"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status": true, "nzo_ids": ["SABnzbd_nzo_url"]}))
      end)

      assert {:ok, "SABnzbd_nzo_url"} =
               Sabnzbd.add_torrent(config, {:url, "https://example.com/test.nzb"})
    end
  end
end
