defmodule Mydia.Indexers.Adapter.ProwlarrTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Mydia.Indexers.Adapter.Prowlarr
  alias Mydia.Indexers.Adapter.Error

  @moduletag :external

  defp build_config(bypass) do
    %{
      type: :prowlarr,
      name: "Test Prowlarr",
      host: "localhost",
      port: bypass.port,
      api_key: "test-api-key",
      use_ssl: false,
      options: %{timeout: 5_000}
    }
  end

  describe "test_connection/1" do
    @tag :skip
    test "successfully connects to Prowlarr" do
      config = %{
        type: :prowlarr,
        name: "Test Prowlarr",
        host: "localhost",
        port: 9696,
        api_key: System.get_env("PROWLARR_API_KEY", "test-api-key"),
        use_ssl: false,
        options: %{}
      }

      assert {:ok, info} = Prowlarr.test_connection(config)
      assert info.name == "Prowlarr"
      assert is_binary(info.version)
    end

    @tag :skip
    test "fails with invalid API key" do
      config = %{
        type: :prowlarr,
        name: "Test Prowlarr",
        host: "localhost",
        port: 9696,
        api_key: "invalid-key",
        use_ssl: false,
        options: %{}
      }

      assert {:error, %Error{type: :connection_failed}} = Prowlarr.test_connection(config)
    end

    @tag :skip
    test "fails with invalid host" do
      config = %{
        type: :prowlarr,
        name: "Test Prowlarr",
        host: "nonexistent.local",
        port: 9696,
        api_key: "test-api-key",
        use_ssl: false,
        options: %{}
      }

      assert {:error, %Error{type: :connection_failed}} = Prowlarr.test_connection(config)
    end
  end

  describe "search/3" do
    @tag :skip
    test "successfully searches Prowlarr" do
      config = %{
        type: :prowlarr,
        name: "Test Prowlarr",
        host: "localhost",
        port: 9696,
        api_key: System.get_env("PROWLARR_API_KEY", "test-api-key"),
        use_ssl: false,
        options: %{
          timeout: 30_000
        }
      }

      assert {:ok, results} = Prowlarr.search(config, "ubuntu", limit: 5)
      assert is_list(results)
      assert length(results) > 0

      # Check first result has required fields
      result = hd(results)
      assert is_binary(result.title)
      assert is_integer(result.size)
      assert is_integer(result.seeders)
      assert is_integer(result.leechers)
      assert is_binary(result.download_url)
      assert is_binary(result.indexer)
    end

    @tag :skip
    test "searches with category filter" do
      config = %{
        type: :prowlarr,
        name: "Test Prowlarr",
        host: "localhost",
        port: 9696,
        api_key: System.get_env("PROWLARR_API_KEY", "test-api-key"),
        use_ssl: false,
        options: %{
          timeout: 30_000,
          categories: [2000]
        }
      }

      assert {:ok, results} = Prowlarr.search(config, "movie", limit: 5)
      assert is_list(results)
    end

    @tag :skip
    test "handles invalid API key" do
      config = %{
        type: :prowlarr,
        name: "Test Prowlarr",
        host: "localhost",
        port: 9696,
        api_key: "invalid-key",
        use_ssl: false,
        options: %{}
      }

      assert {:error, %Error{type: error_type}} = Prowlarr.search(config, "test")
      assert error_type in [:connection_failed, :search_failed]
    end

    @tag :skip
    test "handles search with empty query" do
      config = %{
        type: :prowlarr,
        name: "Test Prowlarr",
        host: "localhost",
        port: 9696,
        api_key: System.get_env("PROWLARR_API_KEY", "test-api-key"),
        use_ssl: false,
        options: %{}
      }

      # Empty queries should still work
      assert {:ok, _results} = Prowlarr.search(config, "")
    end
  end

  describe "get_capabilities/1" do
    test "returns static capabilities" do
      config = %{
        type: :prowlarr,
        name: "Test Prowlarr",
        host: "localhost",
        port: 9696,
        api_key: "test-api-key",
        use_ssl: false,
        options: %{}
      }

      assert {:ok, capabilities} = Prowlarr.get_capabilities(config)
      assert %{searching: searching, categories: categories} = capabilities
      assert is_map(searching)
      assert is_list(categories)
      assert length(categories) > 0

      # Check standard search capabilities
      assert searching.search.available == true
      assert searching.tv_search.available == true
      assert searching.movie_search.available == true
    end
  end

  describe "result parsing" do
    test "parses quality from title" do
      _config = %{
        type: :prowlarr,
        name: "Test Prowlarr",
        host: "localhost",
        port: 9696,
        api_key: "test-api-key",
        use_ssl: false,
        options: %{}
      }

      # Mock response with quality indicators in title
      # This test would need to be expanded with actual response mocking
      # For now, we verify the adapter is properly structured
      assert function_exported?(Prowlarr, :search, 3)
      assert function_exported?(Prowlarr, :test_connection, 1)
      assert function_exported?(Prowlarr, :get_capabilities, 1)
    end
  end

  describe "Usenet-aware parsing (#121, #125)" do
    @moduletag :indexers
    @describetag external: false

    test "NZB results carry usenet_date from publishDate and grabs into nzb_grabs" do
      bypass = Bypass.open()

      body =
        Jason.encode!([
          %{
            "title" => "Show.S01E01.1080p.WEB-DL",
            "size" => 1_073_741_824,
            "downloadUrl" => "http://example.com/release.nzb",
            "downloadProtocol" => "usenet",
            "publishDate" => "2024-11-25T10:30:00Z",
            "grabs" => 42,
            "indexer" => "Prowlarr"
          }
        ])

      Bypass.expect_once(bypass, "GET", "/api/v1/search", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, body)
      end)

      config = build_config(bypass)
      assert {:ok, [result]} = Prowlarr.search(config, "test")

      assert result.download_protocol == :nzb
      assert result.seeders == nil
      assert result.leechers == nil
      assert result.nzb_grabs == 42
      assert %DateTime{year: 2024, month: 11, day: 25} = result.usenet_date
    end

    test "torrent results keep seeders/leechers and have nil NZB fields" do
      bypass = Bypass.open()

      body =
        Jason.encode!([
          %{
            "title" => "Movie.2024.1080p.BluRay.x264",
            "size" => 5_368_709_120,
            "downloadUrl" => "http://example.com/release.torrent",
            "downloadProtocol" => "torrent",
            "publishDate" => "2024-11-25T10:30:00Z",
            "seeders" => 120,
            "leechers" => 10,
            "indexer" => "Prowlarr"
          }
        ])

      Bypass.expect_once(bypass, "GET", "/api/v1/search", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, body)
      end)

      config = build_config(bypass)
      assert {:ok, [result]} = Prowlarr.search(config, "test")

      assert result.download_protocol == :torrent
      assert result.seeders == 120
      assert result.leechers == 10
      assert result.nzb_grabs == nil
      assert result.usenet_date == nil
    end

    test "emits zero info-level log lines for routine result parsing (#125)" do
      bypass = Bypass.open()

      body =
        Jason.encode!([
          %{
            "title" => "Show.S01E01.1080p.WEB-DL",
            "size" => 1_073_741_824,
            "downloadUrl" => "http://example.com/release.nzb",
            "downloadProtocol" => "usenet",
            "publishDate" => "2024-11-25T10:30:00Z",
            "grabs" => 42,
            "indexer" => "Prowlarr"
          },
          %{
            "title" => "Movie.2024.1080p.BluRay.x264",
            "size" => 5_368_709_120,
            "downloadUrl" => "http://example.com/release.torrent",
            "downloadProtocol" => "torrent",
            "seeders" => 50,
            "leechers" => 5,
            "indexer" => "Prowlarr"
          }
        ])

      Bypass.expect_once(bypass, "GET", "/api/v1/search", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, body)
      end)

      config = build_config(bypass)

      log =
        capture_log([level: :info], fn ->
          assert {:ok, _results} = Prowlarr.search(config, "test")
        end)

      # The four previously info-level lines about protocol detection and item
      # keys must no longer fire at :info level.
      refute log =~ "Prowlarr item keys"
      refute log =~ "Protocol field value"
      refute log =~ "Detected protocol"
    end
  end

  describe "use_ssl defaults (GitHub issue #28)" do
    test "get_capabilities works without use_ssl key in config" do
      # Config WITHOUT use_ssl key - simulates web UI config
      config = %{
        type: :prowlarr,
        name: "Test Prowlarr",
        host: "localhost",
        port: 9696,
        api_key: "test-api-key",
        options: %{}
      }

      # get_capabilities returns static data and doesn't make HTTP calls,
      # so we can test that it doesn't crash when use_ssl is missing
      assert {:ok, capabilities} = Prowlarr.get_capabilities(config)
      assert is_map(capabilities.searching)
      assert is_list(capabilities.categories)
    end
  end
end
