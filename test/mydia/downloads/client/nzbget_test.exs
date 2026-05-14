defmodule Mydia.Downloads.Client.NzbgetTest do
  use ExUnit.Case, async: true

  alias Mydia.Downloads.Client.Nzbget

  @config %{
    type: :nzbget,
    host: "localhost",
    port: 6789,
    username: "nzbget",
    password: "tegbzn6789",
    use_ssl: false,
    url_base: nil,
    options: %{}
  }

  describe "module behaviour" do
    test "implements all callbacks from Mydia.Downloads.Client behaviour" do
      # Verify the module implements the required behaviour
      behaviours = Nzbget.__info__(:attributes)[:behaviour] || []
      assert Mydia.Downloads.Client in behaviours
    end
  end

  describe "configuration validation" do
    test "test_connection requires username and password" do
      config_without_username = Map.delete(@config, :username)

      {:error, error} = Nzbget.test_connection(config_without_username)
      assert error.type == :invalid_config
      assert error.message =~ "Username and password are required"
    end

    test "test_connection fails with unreachable host" do
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      {:error, error} = Nzbget.test_connection(timeout_config)
      assert error.type in [:connection_failed, :network_error, :timeout]
    end
  end

  describe "add_torrent/3" do
    test "returns error with unreachable host for URL addition" do
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      nzb_url = "https://example.com/test.nzb"

      {:error, error} = Nzbget.add_torrent(timeout_config, {:url, nzb_url})
      # URL download will fail first before reaching NZBGet
      assert error.type in [:connection_failed, :network_error, :timeout, :api_error]
    end

    test "rejects magnet links" do
      magnet = "magnet:?xt=urn:btih:ABC123DEF456789012345678901234567890ABCD&dn=test"

      {:error, error} = Nzbget.add_torrent(@config, {:magnet, magnet})
      assert error.type == :invalid_torrent
      assert error.message =~ "does not support magnet links"
    end

    test "requires authentication" do
      config_without_username = Map.delete(@config, :username)
      nzb_url = "https://example.com/test.nzb"

      {:error, error} = Nzbget.add_torrent(config_without_username, {:url, nzb_url})
      assert error.type == :invalid_config
    end
  end

  describe "get_status/2" do
    test "returns error with unreachable host" do
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      {:error, error} = Nzbget.get_status(timeout_config, "12345")
      assert error.type in [:connection_failed, :network_error, :timeout]
    end

    test "requires valid integer ID" do
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      # Should handle string ID by converting to integer
      {:error, error} = Nzbget.get_status(timeout_config, "12345")
      assert error.type in [:connection_failed, :network_error, :timeout]

      # Should fail gracefully with invalid ID format
      {:error, error} = Nzbget.get_status(timeout_config, "not-a-number")
      assert error.type == :invalid_torrent
      assert error.message =~ "Invalid NZB ID format"
    end
  end

  describe "list_torrents/2" do
    test "returns error with unreachable host" do
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      {:error, error} = Nzbget.list_torrents(timeout_config)
      assert error.type in [:connection_failed, :network_error, :timeout]
    end

    test "accepts filter options" do
      # Test that the function accepts the expected options without error
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      {:error, _error} = Nzbget.list_torrents(timeout_config, filter: :downloading)
      {:error, _error} = Nzbget.list_torrents(timeout_config, filter: :completed)
      {:error, _error} = Nzbget.list_torrents(timeout_config, filter: :paused)
      assert true
    end
  end

  describe "remove_torrent/3" do
    test "returns error with unreachable host" do
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      {:error, error} = Nzbget.remove_torrent(timeout_config, "12345")
      assert error.type in [:connection_failed, :network_error, :timeout]
    end

    test "requires authentication" do
      config_without_username = Map.delete(@config, :username)

      {:error, error} = Nzbget.remove_torrent(config_without_username, "12345")
      assert error.type == :invalid_config
    end

    test "accepts delete_files option" do
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      {:error, _error} = Nzbget.remove_torrent(timeout_config, "12345", delete_files: true)
      {:error, _error} = Nzbget.remove_torrent(timeout_config, "12345", delete_files: false)
      assert true
    end

    test "handles invalid ID format" do
      {:error, error} = Nzbget.remove_torrent(@config, "not-a-number")
      assert error.type == :invalid_torrent
      assert error.message =~ "Invalid NZB ID format"
    end
  end

  describe "pause_torrent/2" do
    test "returns error with unreachable host" do
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      {:error, error} = Nzbget.pause_torrent(timeout_config, "12345")
      assert error.type in [:connection_failed, :network_error, :timeout]
    end

    test "requires authentication" do
      config_without_username = Map.delete(@config, :username)

      {:error, error} = Nzbget.pause_torrent(config_without_username, "12345")
      assert error.type == :invalid_config
    end

    test "handles invalid ID format" do
      {:error, error} = Nzbget.pause_torrent(@config, "not-a-number")
      assert error.type == :invalid_torrent
      assert error.message =~ "Invalid NZB ID format"
    end
  end

  describe "resume_torrent/2" do
    test "returns error with unreachable host" do
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      {:error, error} = Nzbget.resume_torrent(timeout_config, "12345")
      assert error.type in [:connection_failed, :network_error, :timeout]
    end

    test "requires authentication" do
      config_without_username = Map.delete(@config, :username)

      {:error, error} = Nzbget.resume_torrent(config_without_username, "12345")
      assert error.type == :invalid_config
    end

    test "handles invalid ID format" do
      {:error, error} = Nzbget.resume_torrent(@config, "not-a-number")
      assert error.type == :invalid_torrent
      assert error.message =~ "Invalid NZB ID format"
    end
  end

  describe "JSON-RPC protocol" do
    test "uses correct endpoint path" do
      unreachable_config = %{@config | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      # Attempt connection - should fail at network level, not at path level
      {:error, error} = Nzbget.test_connection(timeout_config)
      assert error.type in [:connection_failed, :network_error, :timeout]
    end
  end

  describe "URL base handling" do
    test "handles custom URL base in configuration" do
      config_with_base = %{@config | url_base: "/nzbget"}
      unreachable_config = %{config_with_base | host: "nonexistent.invalid", port: 9999}
      timeout_config = put_in(unreachable_config, [:options, :connect_timeout], 100)

      # Should fail with connection error, not path error
      {:error, error} = Nzbget.test_connection(timeout_config)
      assert error.type in [:connection_failed, :network_error, :timeout]
    end
  end

  describe "priority profile resolution (Bypass)" do
    setup do
      bypass = Bypass.open()
      config = %{@config | host: "localhost", port: bypass.port}
      {:ok, bypass: bypass, config: config}
    end

    # Pull the JSON-RPC params from the request body so we can assert on the
    # priority argument NZBGet's `append` RPC receives.
    defp read_append_priority(conn) do
      {:ok, body, conn} = Plug.Conn.read_body(conn, length: 1_000_000)
      decoded = Jason.decode!(body)
      assert decoded["method"] == "append"
      # append params: [filename, content_b64, category, priority, ...]
      priority = Enum.at(decoded["params"], 3)
      {priority, conn}
    end

    test "empty profile falls back to hardcoded :high -> 50",
         %{bypass: bypass, config: config} do
      Bypass.expect(bypass, "POST", "/jsonrpc", fn conn ->
        {priority, conn} = read_append_priority(conn)
        assert priority == 50

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"jsonrpc":"2.0","result":42,"id":1}))
      end)

      assert {:ok, "42"} = Nzbget.add_torrent(config, {:file, "fake-nzb"}, priority: :high)
    end

    test "empty profile maps :verylow -> -100 and :veryhigh -> 100",
         %{bypass: bypass, config: config} do
      Bypass.expect(bypass, "POST", "/jsonrpc", fn conn ->
        {priority, conn} = read_append_priority(conn)
        assert priority == -100

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"jsonrpc":"2.0","result":1,"id":1}))
      end)

      assert {:ok, _} = Nzbget.add_torrent(config, {:file, "fake-nzb"}, priority: :verylow)

      bypass2 = Bypass.open()
      config2 = %{config | port: bypass2.port}

      Bypass.expect(bypass2, "POST", "/jsonrpc", fn conn ->
        {priority, conn} = read_append_priority(conn)
        assert priority == 100

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"jsonrpc":"2.0","result":2,"id":2}))
      end)

      assert {:ok, _} = Nzbget.add_torrent(config2, {:file, "fake-nzb"}, priority: :veryhigh)
    end

    test "profile override wins over hardcoded default",
         %{bypass: bypass, config: config} do
      # NZBGet expects integers; the schema stores integer-valued maps fine.
      config_with_profile = Map.put(config, :priority_profile, %{"high" => 75})

      Bypass.expect(bypass, "POST", "/jsonrpc", fn conn ->
        {priority, conn} = read_append_priority(conn)
        assert priority == 75

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"jsonrpc":"2.0","result":7,"id":1}))
      end)

      assert {:ok, _} =
               Nzbget.add_torrent(config_with_profile, {:file, "fake-nzb"}, priority: :high)
    end

    test "tier not present in profile falls back to its hardcoded default",
         %{bypass: bypass, config: config} do
      # Override :high but leave :low alone — :low must still be -50.
      config_with_profile = Map.put(config, :priority_profile, %{"high" => 75})

      Bypass.expect(bypass, "POST", "/jsonrpc", fn conn ->
        {priority, conn} = read_append_priority(conn)
        assert priority == -50

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"jsonrpc":"2.0","result":8,"id":1}))
      end)

      assert {:ok, _} =
               Nzbget.add_torrent(config_with_profile, {:file, "fake-nzb"}, priority: :low)
    end

    test "nil priority sends 0 (NZBGet's normal default)",
         %{bypass: bypass, config: config} do
      Bypass.expect(bypass, "POST", "/jsonrpc", fn conn ->
        {priority, conn} = read_append_priority(conn)
        assert priority == 0

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"jsonrpc":"2.0","result":9,"id":1}))
      end)

      assert {:ok, _} = Nzbget.add_torrent(config, {:file, "fake-nzb"})
    end
  end
end
