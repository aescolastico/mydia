defmodule Mydia.Indexers.CardigannFilterCoverageTest do
  @moduledoc """
  Scans all upstream Cardigann definitions for filter usage and verifies
  every discovered filter is implemented in our CardigannFilters module.

  Tagged as :external since it requires GitHub API access.
  """
  use ExUnit.Case

  @moduletag :external

  @cache_dir Path.join([System.tmp_dir!(), "mydia_test_cache", "cardigann_definitions"])

  alias Mydia.Indexers.DefinitionSync
  alias Mydia.Indexers.CardigannFilters
  alias Mydia.Indexers.CardigannCompat

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

  test "every filter used in upstream definitions is implemented", %{definitions: definitions} do
    if definitions == [] do
      IO.puts("Skipping: no definitions fetched")
    else
      # Extract all filter names from all definitions
      all_filters =
        Enum.flat_map(definitions, fn {_filename, yaml} ->
          CardigannCompat.extract_filters_from_yaml(yaml)
        end)
        |> Enum.uniq()
        |> Enum.sort()

      implemented = CardigannFilters.implemented_filters()

      # Special filters that are handled differently (row-level, not value-level)
      # andmatch and validate are row-level filters with different semantics
      special_filters = ["andmatch", "validate"]

      unimplemented =
        Enum.reject(all_filters, fn f ->
          f in implemented or f in special_filters
        end)

      IO.puts("\nFilter Coverage Report:")
      IO.puts("  Total unique filters found: #{length(all_filters)}")
      IO.puts("  Implemented: #{length(implemented)}")
      IO.puts("  Unimplemented: #{length(unimplemented)}")

      if unimplemented != [] do
        IO.puts("\n  Unimplemented filters:")
        Enum.each(unimplemented, &IO.puts("    - #{&1}"))
      end

      IO.puts("\n  All discovered filters: #{Enum.join(all_filters, ", ")}")

      assert unimplemented == [],
             "Found #{length(unimplemented)} unimplemented filters: #{Enum.join(unimplemented, ", ")}"
    end
  end

  test "filter usage frequency report", %{definitions: definitions} do
    if definitions == [] do
      IO.puts("Skipping: no definitions fetched")
    else
      filter_counts =
        Enum.flat_map(definitions, fn {_filename, yaml} ->
          CardigannCompat.extract_filters_from_yaml(yaml)
        end)
        |> Enum.frequencies()
        |> Enum.sort_by(fn {_name, count} -> -count end)

      IO.puts("\nFilter Usage Frequency:")
      IO.puts(String.duplicate("-", 40))

      Enum.each(filter_counts, fn {name, count} ->
        status = if CardigannFilters.implemented?(name), do: "OK", else: "MISSING"

        IO.puts(
          "  #{String.pad_trailing(name, 20)} #{String.pad_leading(to_string(count), 5)}  [#{status}]"
        )
      end)
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
