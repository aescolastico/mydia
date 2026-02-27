defmodule Mydia.Indexers.CardigannBulkParseTest do
  @moduledoc """
  Bulk parse test that downloads ALL upstream Cardigann definitions
  and validates our parser handles them.

  Tagged as :external since it requires GitHub API access.
  Definitions are cached locally for 24 hours to speed up repeated runs.
  """
  use ExUnit.Case

  @moduletag :external

  @cache_dir Path.join([System.tmp_dir!(), "mydia_test_cache", "cardigann_definitions"])

  alias Mydia.Indexers.DefinitionSync
  alias Mydia.Indexers.CardigannParser

  setup_all do
    File.mkdir_p!(@cache_dir)

    case DefinitionSync.list_definition_files() do
      {:ok, files} ->
        definitions =
          files
          |> Task.async_stream(
            fn file -> fetch_cached(file) end,
            max_concurrency: 5,
            timeout: 60_000,
            on_timeout: :kill_task
          )
          |> Enum.flat_map(fn
            {:ok, {:ok, item}} -> [item]
            _ -> []
          end)

        {:ok, %{definitions: definitions}}

      {:error, reason} ->
        {:ok, %{definitions: [], skip_reason: reason}}
    end
  end

  test "parses at least 95% of upstream definitions successfully", %{definitions: definitions} do
    if definitions == [] do
      IO.puts("Skipping: no definitions fetched (rate limited?)")
    else
      total = length(definitions)
      assert total > 100, "Expected to fetch >100 definitions, got #{total}"

      results =
        Enum.map(definitions, fn {filename, yaml} ->
          case CardigannParser.parse_definition(yaml) do
            {:ok, _parsed} -> {:ok, filename}
            {:error, reason} -> {:error, filename, reason}
          end
        end)

      successes = Enum.count(results, &match?({:ok, _}, &1))
      failures = Enum.filter(results, &match?({:error, _, _}, &1))
      parse_rate = successes / total * 100

      IO.puts("\nBulk Parse Results:")
      IO.puts("  Total:     #{total}")
      IO.puts("  Parsed:    #{successes}")
      IO.puts("  Failed:    #{length(failures)}")
      IO.puts("  Rate:      #{Float.round(parse_rate, 1)}%")

      if failures != [] do
        IO.puts("\n  Top failures:")

        failures
        |> Enum.take(20)
        |> Enum.each(fn {:error, filename, reason} ->
          IO.puts("    #{filename}: #{inspect(reason)}")
        end)
      end

      assert parse_rate >= 95.0,
             "Parse rate #{Float.round(parse_rate, 1)}% is below 95% threshold. " <>
               "#{length(failures)} definitions failed."
    end
  end

  test "all successfully parsed definitions have required search fields", %{
    definitions: definitions
  } do
    if definitions == [] do
      IO.puts("Skipping: no definitions fetched")
    else
      parsed =
        definitions
        |> Enum.flat_map(fn {filename, yaml} ->
          case CardigannParser.parse_definition(yaml) do
            {:ok, p} -> [{filename, p}]
            _ -> []
          end
        end)

      missing_title =
        Enum.filter(parsed, fn {_f, p} ->
          not Map.has_key?(p.search.fields, :title)
        end)

      assert missing_title == [],
             "#{length(missing_title)} definitions missing :title field"
    end
  end

  defp fetch_cached(file) do
    filename = Map.get(file, "name")
    cache_path = Path.join(@cache_dir, filename)

    if File.exists?(cache_path) and cache_fresh?(cache_path) do
      case File.read(cache_path) do
        {:ok, content} -> {:ok, {filename, content}}
        _ -> fetch_and_cache(file, cache_path)
      end
    else
      fetch_and_cache(file, cache_path)
    end
  end

  defp fetch_and_cache(file, cache_path) do
    download_url = Map.get(file, "download_url")
    filename = Map.get(file, "name")

    case DefinitionSync.fetch_definition_file(download_url) do
      {:ok, content} ->
        File.write!(cache_path, content)
        {:ok, {filename, content}}

      error ->
        error
    end
  end

  defp cache_fresh?(path) do
    case File.stat(path) do
      {:ok, %{mtime: mtime}} ->
        cache_age =
          :calendar.datetime_to_gregorian_seconds(:calendar.local_time()) -
            :calendar.datetime_to_gregorian_seconds(mtime)

        cache_age < 86_400

      _ ->
        false
    end
  end
end
