defmodule Mydia.IndexerMock do
  @moduledoc """
  Test helper for mocking indexer API responses using Bypass.

  This module provides utilities to set up mock Prowlarr and other indexer
  responses in tests, preventing real API calls that consume quotas.
  """

  @doc """
  Sets up a Bypass server to mock Prowlarr search endpoint.

  Returns a basic successful search response with configurable results.

  ## Options

    - `:results` - List of result maps to return (default: [])
    - `:status` - HTTP status code to return (default: 200)

  ## Example

      bypass = Bypass.open()
      IndexerMock.mock_prowlarr_search(bypass, results: [
        %{title: "Test Movie", size: 1_000_000, seeders: 10}
      ])

      config = %{
        base_url: "http://localhost:\#{bypass.port}",
        api_key: "test-key"
      }
  """
  def mock_prowlarr_search(bypass, opts \\ []) do
    results = Keyword.get(opts, :results, [])
    status = Keyword.get(opts, :status, 200)

    Bypass.stub(bypass, "GET", "/api/v1/search", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, Jason.encode!(build_search_results(results)))
    end)
  end

  @doc """
  Sets up a Bypass server to mock Prowlarr system status endpoint.
  """
  def mock_prowlarr_status(bypass, opts \\ []) do
    status = Keyword.get(opts, :status, 200)
    version = Keyword.get(opts, :version, "1.0.0")

    Bypass.stub(bypass, "GET", "/api/v1/system/status", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        status,
        Jason.encode!(%{
          "appName" => "Prowlarr",
          "version" => version
        })
      )
    end)
  end

  @doc """
  Sets up a Bypass server to mock both search and status endpoints.

  This is useful for tests that may call either endpoint.
  """
  def mock_prowlarr_all(bypass, opts \\ []) do
    mock_prowlarr_status(bypass, opts)
    mock_prowlarr_search(bypass, opts)
  end

  @doc """
  Builds search result maps in Prowlarr's response format.
  """
  def build_search_results(results) when is_list(results) do
    Enum.map(results, &build_search_result/1)
  end

  defp build_search_result(result) when is_map(result) do
    %{
      "title" => Map.get(result, :title, "Test Release"),
      "size" => Map.get(result, :size, 1_000_000_000),
      "seeders" => Map.get(result, :seeders, 10),
      "leechers" => Map.get(result, :leechers, 5),
      "peers" => Map.get(result, :peers, 5),
      "magnetUrl" => Map.get(result, :magnet_url, build_magnet_url()),
      "downloadUrl" => Map.get(result, :download_url),
      "infoUrl" => Map.get(result, :info_url, "https://example.com"),
      "guid" => Map.get(result, :guid),
      "indexer" => Map.get(result, :indexer, "Test Indexer"),
      "categoryId" => Map.get(result, :category, 2000),
      "publishDate" =>
        Map.get(result, :published_at, DateTime.utc_now() |> DateTime.to_iso8601()),
      "tmdbId" => Map.get(result, :tmdb_id),
      "imdbId" => Map.get(result, :imdb_id),
      "downloadProtocol" => Map.get(result, :protocol, "torrent")
    }
  end

  defp build_magnet_url do
    hash = :crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)
    "magnet:?xt=urn:btih:#{hash}"
  end

  @doc """
  Creates a test indexer config pointing to a Bypass server.

  ## Example

      bypass = Bypass.open()
      config = IndexerMock.test_indexer_config(bypass, name: "Test Indexer")
  """
  def test_indexer_config(bypass, opts \\ []) do
    %{
      name: Keyword.get(opts, :name, "Test Indexer"),
      type: Keyword.get(opts, :type, :prowlarr),
      base_url: "http://localhost:#{bypass.port}",
      api_key: Keyword.get(opts, :api_key, "test-api-key"),
      enabled: Keyword.get(opts, :enabled, true),
      indexer_ids: Keyword.get(opts, :indexer_ids, []),
      categories: Keyword.get(opts, :categories, []),
      rate_limit: Keyword.get(opts, :rate_limit, 10),
      connection_settings: %{
        "timeout" => Keyword.get(opts, :timeout, 30_000)
      }
    }
  end

  @doc """
  Creates movie search results for testing.
  """
  def movie_results(movies) when is_list(movies) do
    Enum.map(movies, &movie_result/1)
  end

  def movie_result(attrs) when is_map(attrs) do
    title = Map.get(attrs, :title, "Unknown Movie")
    year = Map.get(attrs, :year, 2020)
    quality = Map.get(attrs, :quality, "1080p")

    %{
      title: "#{title}.#{year}.#{quality}.BluRay.x264-GROUP",
      size: 4_000_000_000,
      seeders: Map.get(attrs, :seeders, 50),
      leechers: 10,
      magnet_url: build_magnet_url(),
      indexer: "Test Indexer",
      category: 2000,
      tmdb_id: Map.get(attrs, :tmdb_id),
      imdb_id: Map.get(attrs, :imdb_id),
      protocol: "torrent",
      guid: Map.get(attrs, :guid)
    }
  end

  @doc """
  Creates TV show episode search results for testing.
  """
  def tv_episode_results(episodes) when is_list(episodes) do
    Enum.map(episodes, &tv_episode_result/1)
  end

  def tv_episode_result(attrs) when is_map(attrs) do
    title = Map.get(attrs, :title, "Unknown Show")
    season = Map.get(attrs, :season, 1)
    episode = Map.get(attrs, :episode, 1)
    quality = Map.get(attrs, :quality, "1080p")

    season_str = String.pad_leading("#{season}", 2, "0")
    episode_str = String.pad_leading("#{episode}", 2, "0")

    %{
      title: "#{title}.S#{season_str}E#{episode_str}.#{quality}.WEB-DL.x264-GROUP",
      size: 1_500_000_000,
      seeders: Map.get(attrs, :seeders, 30),
      leechers: 5,
      magnet_url: build_magnet_url(),
      indexer: "Test Indexer",
      category: 5000,
      tmdb_id: Map.get(attrs, :tmdb_id),
      imdb_id: Map.get(attrs, :imdb_id),
      protocol: "torrent"
    }
  end

  @doc """
  Creates season pack search results for testing.
  """
  def season_pack_result(attrs) when is_map(attrs) do
    title = Map.get(attrs, :title, "Unknown Show")
    season = Map.get(attrs, :season, 1)
    quality = Map.get(attrs, :quality, "1080p")

    season_str = String.pad_leading("#{season}", 2, "0")

    %{
      title: "#{title}.S#{season_str}.COMPLETE.#{quality}.WEB-DL.x264-GROUP",
      size: 15_000_000_000,
      seeders: Map.get(attrs, :seeders, 100),
      leechers: 20,
      magnet_url: build_magnet_url(),
      indexer: "Test Indexer",
      category: 5000,
      tmdb_id: Map.get(attrs, :tmdb_id),
      imdb_id: Map.get(attrs, :imdb_id),
      protocol: "torrent"
    }
  end
end
