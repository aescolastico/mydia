#!/usr/bin/env elixir
#
# Sample release-name strings from a local Bitmagnet instance via GraphQL.
#
# Bitmagnet (https://github.com/bitmagnet-io/bitmagnet) is a self-hosted BitTorrent
# DHT crawler that exposes a GraphQL API over the torrents it has indexed. Its
# `torrent.name` field is exactly the raw release-name string mydia's parser
# consumes, so a sample is useful supplementary corpus material.
#
# The `classified_title`, `content_type`, and `video_resolution` Bitmagnet reports
# are SOFT ground-truth only — Bitmagnet itself uses regex classifiers that may
# be wrong. Use these for direction/sanity checks, not strict assertions.
#
# Usage:
#   ./dev mix run scripts/sample_bitmagnet_corpus.exs
#   ./dev mix run scripts/sample_bitmagnet_corpus.exs --endpoint http://localhost:3333/graphql --limit 2000
#   ./dev mix run scripts/sample_bitmagnet_corpus.exs --mock-response  # for CI determinism
#
# If Bitmagnet is unreachable, the script writes an empty fixture with a note —
# this is best-effort sampling, not a hard dependency. The Sonarr/Radarr corpus
# is the load-bearing regression set; Bitmagnet just adds DHT-sourced breadth.

defmodule SampleBitmagnetCorpus do
  @default_endpoint "http://localhost:3333/graphql"
  @default_target "test/fixtures/release_parser"
  @default_limit 2000
  @page_size 100

  @query """
  query Search($queryString: String, $facets: TorrentContentFacetsInput, $first: Int, $after: String) {
    torrentContent {
      search(input: { queryString: $queryString, facets: $facets, first: $first, after: $after }) {
        items {
          torrent {
            name
            infoHash
          }
          title
          contentType
          videoResolution
        }
        pageInfo {
          endCursor
          hasNextPage
        }
      }
    }
  }
  """

  def run(argv) do
    {opts, _} =
      OptionParser.parse!(argv,
        strict: [
          target: :string,
          endpoint: :string,
          limit: :integer,
          mock_response: :boolean
        ]
      )

    target = Path.expand(opts[:target] || @default_target)
    File.mkdir_p!(target)
    endpoint = opts[:endpoint] || @default_endpoint
    limit = opts[:limit] || @default_limit

    cond do
      opts[:mock_response] ->
        write_mock_fixture(Path.join(target, "bitmagnet_sample.exs"))

      true ->
        sample_and_write(endpoint, limit, Path.join(target, "bitmagnet_sample.exs"))
    end
  end

  defp sample_and_write(endpoint, limit, out_path) do
    IO.puts("\nSampling Bitmagnet at #{endpoint}")
    IO.puts("  Target: #{limit} TV samples + #{limit} movie samples")

    case sample(endpoint, "tv_show", limit) do
      {:ok, tv} ->
        case sample(endpoint, "movie", limit) do
          {:ok, movies} ->
            IO.puts("  Got #{length(tv)} TV + #{length(movies)} movie samples")
            write_fixture(out_path, endpoint, tv, movies)
            IO.puts("  Wrote #{out_path}")

          {:error, reason} ->
            IO.puts("  Failed to fetch movies: #{inspect(reason)}")
            IO.puts("  Writing TV-only fixture")
            write_fixture(out_path, endpoint, tv, [])
        end

      {:error, reason} ->
        IO.puts("  Could not reach Bitmagnet: #{inspect(reason)}")
        IO.puts("  Writing empty fixture (Bitmagnet sample is best-effort)")
        write_empty_fixture(out_path, endpoint, reason)
    end
  end

  defp sample(endpoint, content_type, target_total) do
    sample_pages(endpoint, content_type, target_total, nil, [])
  end

  defp sample_pages(_endpoint, _content_type, target_total, _cursor, acc)
       when length(acc) >= target_total,
       do: {:ok, Enum.take(Enum.reverse(acc), target_total)}

  defp sample_pages(endpoint, content_type, target_total, cursor, acc) do
    variables = %{
      "queryString" => nil,
      "facets" => %{"contentType" => %{"filter" => [content_type]}},
      "first" => @page_size,
      "after" => cursor
    }

    case post_graphql(endpoint, @query, variables) do
      {:ok, %{"data" => %{"torrentContent" => %{"search" => search}}}} ->
        items = search["items"] || []
        page_info = search["pageInfo"] || %{}
        new_acc = Enum.reverse(items) ++ acc

        cond do
          length(new_acc) >= target_total ->
            {:ok, Enum.take(Enum.reverse(new_acc), target_total)}

          page_info["hasNextPage"] == true ->
            sample_pages(endpoint, content_type, target_total, page_info["endCursor"], new_acc)

          true ->
            {:ok, Enum.reverse(new_acc)}
        end

      {:ok, %{"errors" => errors}} ->
        {:error, {:graphql_errors, errors}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp post_graphql(endpoint, query, variables) do
    body = %{"query" => query, "variables" => variables}

    case Req.post(endpoint, json: body, receive_timeout: 30_000, retry: false) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:http, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_fixture(path, endpoint, tv_items, movie_items) do
    cases =
      (Enum.map(tv_items, &to_case(&1, "tv_show")) ++
         Enum.map(movie_items, &to_case(&1, "movie")))
      |> Enum.reject(&is_nil/1)

    header =
      """
      # Generated by scripts/sample_bitmagnet_corpus.exs.
      # Do not edit by hand — re-run the sampler against a local Bitmagnet to refresh.
      #
      # Source: Bitmagnet GraphQL API (#{endpoint})
      # Classification fields (title, content_type, video_resolution) are SOFT ground truth.
      """

    payload =
      """
      %{
        source: "bitmagnet",
        endpoint: "#{endpoint}",
        sampled_at: "#{DateTime.utc_now() |> DateTime.to_iso8601()}",
        cases: #{inspect(cases, limit: :infinity, printable_limit: :infinity)}
      }
      """

    formatted = payload |> Code.format_string!() |> IO.iodata_to_binary()
    File.write!(path, header <> "\n" <> formatted <> "\n")
  end

  defp write_empty_fixture(path, endpoint, reason) do
    header =
      """
      # Generated by scripts/sample_bitmagnet_corpus.exs.
      # Bitmagnet was unreachable at sample time.
      """

    payload =
      """
      %{
        source: "bitmagnet",
        endpoint: "#{endpoint}",
        sampled_at: "#{DateTime.utc_now() |> DateTime.to_iso8601()}",
        unreachable: true,
        reason: #{inspect(reason)},
        cases: []
      }
      """

    formatted = payload |> Code.format_string!() |> IO.iodata_to_binary()
    File.write!(path, header <> "\n" <> formatted <> "\n")
  end

  defp write_mock_fixture(path) do
    cases = [
      %{
        input: "Mock.Show.S01E01.1080p.WEB-DL.x265-MOCK",
        soft_truth: %{title: "Mock Show", content_type: "tv_show", video_resolution: "1080p"},
        info_hash: "0000000000000000000000000000000000000001"
      },
      %{
        input: "Mock.Movie.2024.2160p.BluRay.x265-MOCK",
        soft_truth: %{title: "Mock Movie", content_type: "movie", video_resolution: "2160p"},
        info_hash: "0000000000000000000000000000000000000002"
      }
    ]

    header = "# Mock Bitmagnet fixture — used when --mock-response is passed.\n"

    payload =
      """
      %{
        source: "bitmagnet-mock",
        sampled_at: "#{DateTime.utc_now() |> DateTime.to_iso8601()}",
        cases: #{inspect(cases, limit: :infinity, printable_limit: :infinity)}
      }
      """

    formatted = payload |> Code.format_string!() |> IO.iodata_to_binary()
    File.write!(path, header <> "\n" <> formatted <> "\n")
  end

  defp to_case(
         %{"torrent" => %{"name" => name, "infoHash" => hash}} = item,
         expected_content_type
       )
       when is_binary(name) do
    %{
      input: name,
      soft_truth: %{
        title: item["title"],
        content_type: item["contentType"] || expected_content_type,
        video_resolution: item["videoResolution"]
      },
      info_hash: hash
    }
  end

  defp to_case(_, _), do: nil
end

SampleBitmagnetCorpus.run(System.argv())
