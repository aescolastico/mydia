defmodule Mydia.Indexers.CardigannCompat do
  @moduledoc """
  Analyzes Cardigann indexer definitions for compatibility with our native engine.

  Downloads all v11 definitions from the Prowlarr/Indexers GitHub repository,
  parses each one, scans for filter usage, and produces a compatibility report.
  """

  require Logger

  alias Mydia.Indexers.CardigannParser
  alias Mydia.Indexers.DefinitionSync

  @implemented_filters ~w(
    replace re_replace append prepend trim split urldecode
    regexp dateparse timeparse timeago reltime fuzzytime
    tolower toupper urlencode htmldecode querystring
  )

  @doc """
  Returns the list of currently implemented filter names.
  """
  def implemented_filters, do: @implemented_filters

  @doc """
  Runs a full compatibility analysis against all upstream definitions.

  ## Options

  - `:limit` - Maximum number of definitions to analyze (default: all)
  - `:cache_dir` - Directory to cache downloaded definitions (default: nil, no caching)

  ## Returns

  `{:ok, report}` where report is a map with:
  - `:total` - Total definitions found
  - `:parsed` - Successfully parsed count
  - `:parse_failed` - Failed to parse count
  - `:fully_compatible` - Use only implemented filters
  - `:partially_compatible` - Use some unimplemented filters
  - `:incompatible` - Cannot parse at all
  - `:filter_usage` - Map of filter name => usage count (sorted descending)
  - `:missing_filters` - Filter names we don't implement, with usage counts
  - `:definitions` - List of per-definition analysis results
  - `:parse_failures` - List of `{filename, reason}` tuples
  """
  def analyze(opts \\ []) do
    limit = Keyword.get(opts, :limit)
    cache_dir = Keyword.get(opts, :cache_dir)

    with {:ok, files} <- list_definitions(),
         files <- maybe_limit(files, limit),
         {:ok, yamls} <- fetch_all_definitions(files, cache_dir) do
      results = analyze_definitions(yamls)
      {:ok, build_report(results)}
    end
  end

  @doc """
  Analyzes a single YAML definition string and returns its compatibility status.

  ## Returns

  A map with:
  - `:name` - Definition name or filename
  - `:status` - `:fully_compatible`, `:partially_compatible`, or `:parse_failed`
  - `:filters_used` - List of all filter names used
  - `:missing_filters` - List of filter names not implemented
  - `:error` - Error reason if parse failed
  """
  def analyze_definition(yaml_content, filename \\ "unknown") do
    case CardigannParser.parse_definition(yaml_content) do
      {:ok, parsed} ->
        filters = extract_filters_from_parsed(parsed)
        filter_names = filters |> Enum.map(& &1.name) |> Enum.uniq()
        missing = Enum.reject(filter_names, &(&1 in @implemented_filters))

        status =
          cond do
            missing == [] -> :fully_compatible
            true -> :partially_compatible
          end

        %{
          name: parsed.name || filename,
          id: parsed.id,
          status: status,
          filters_used: filter_names,
          missing_filters: missing,
          error: nil
        }

      {:error, reason} ->
        %{
          name: filename,
          id: nil,
          status: :parse_failed,
          filters_used: [],
          missing_filters: [],
          error: reason
        }
    end
  end

  @doc """
  Extracts all filter references from a parsed Cardigann definition.

  Returns a list of `%{name: filter_name, field: field_name}` maps.
  """
  def extract_filters_from_parsed(%{search: search}) do
    fields = Map.get(search, :fields, %{})

    Enum.flat_map(fields, fn {field_name, field_config} ->
      filters = get_filters(field_config)

      Enum.map(filters, fn filter ->
        name = Map.get(filter, "name") || Map.get(filter, :name, "unknown")
        %{name: to_string(name), field: to_string(field_name)}
      end)
    end)
  end

  def extract_filters_from_parsed(_), do: []

  @doc """
  Extracts all filter names from raw YAML data (before full parsing).

  This is a fallback for definitions that fail to parse - we can still
  scan the raw YAML map for filter references.
  """
  def extract_filters_from_yaml(yaml_string) when is_binary(yaml_string) do
    case YamlElixir.read_from_string(yaml_string) do
      {:ok, data} -> extract_filters_from_yaml_data(data)
      {:error, _} -> []
    end
  end

  # Private implementation

  defp list_definitions do
    DefinitionSync.list_definition_files()
  end

  defp maybe_limit(files, nil), do: files
  defp maybe_limit(files, limit), do: Enum.take(files, limit)

  defp fetch_all_definitions(files, cache_dir) do
    if cache_dir do
      File.mkdir_p!(cache_dir)
    end

    results =
      Task.async_stream(
        files,
        fn file -> fetch_single_definition(file, cache_dir) end,
        max_concurrency: 5,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    yamls =
      Enum.flat_map(results, fn
        {:ok, {:ok, yaml}} ->
          [yaml]

        {:ok, {:error, reason}} ->
          Logger.warning("[CardigannCompat] Failed to fetch: #{inspect(reason)}")
          []

        {:exit, reason} ->
          Logger.warning("[CardigannCompat] Task failed: #{inspect(reason)}")
          []
      end)

    {:ok, yamls}
  end

  defp fetch_single_definition(file, cache_dir) do
    filename = Map.get(file, "name")
    download_url = Map.get(file, "download_url")

    # Check cache first
    cached = if cache_dir, do: read_cache(cache_dir, filename), else: nil

    case cached do
      {:ok, content} ->
        {:ok, {filename, content}}

      _ ->
        case DefinitionSync.fetch_definition_file(download_url) do
          {:ok, content} ->
            if cache_dir, do: write_cache(cache_dir, filename, content)
            {:ok, {filename, content}}

          error ->
            error
        end
    end
  end

  defp read_cache(cache_dir, filename) do
    path = Path.join(cache_dir, filename)

    if File.exists?(path) do
      # Check if cache is less than 24 hours old
      case File.stat(path) do
        {:ok, %{mtime: mtime}} ->
          cache_age_seconds =
            :calendar.datetime_to_gregorian_seconds(:calendar.local_time()) -
              :calendar.datetime_to_gregorian_seconds(mtime)

          if cache_age_seconds < 86_400 do
            File.read(path)
          else
            nil
          end

        _ ->
          nil
      end
    else
      nil
    end
  end

  defp write_cache(cache_dir, filename, content) do
    path = Path.join(cache_dir, filename)
    File.write(path, content)
  end

  defp analyze_definitions(yamls) do
    Enum.map(yamls, fn {filename, yaml_content} ->
      result = analyze_definition(yaml_content, filename)

      # If parsing failed, try to extract filters from raw YAML as a fallback
      if result.status == :parse_failed do
        raw_filters = extract_filters_from_yaml(yaml_content)
        Map.put(result, :raw_filters, raw_filters)
      else
        result
      end
    end)
  end

  defp build_report(results) do
    total = length(results)
    parsed = Enum.count(results, &(&1.status != :parse_failed))
    parse_failed = total - parsed
    fully_compatible = Enum.count(results, &(&1.status == :fully_compatible))
    partially_compatible = Enum.count(results, &(&1.status == :partially_compatible))

    # Count filter usage across all definitions
    filter_usage =
      results
      |> Enum.flat_map(& &1.filters_used)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_name, count} -> -count end)

    # Missing filters with usage counts
    missing_filters =
      results
      |> Enum.flat_map(& &1.missing_filters)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_name, count} -> -count end)

    # Parse failures
    parse_failures =
      results
      |> Enum.filter(&(&1.status == :parse_failed))
      |> Enum.map(&{&1.name, &1.error})

    %{
      total: total,
      parsed: parsed,
      parse_failed: parse_failed,
      fully_compatible: fully_compatible,
      partially_compatible: partially_compatible,
      filter_usage: filter_usage,
      missing_filters: missing_filters,
      definitions: results,
      parse_failures: parse_failures
    }
  end

  defp get_filters(field_config) when is_map(field_config) do
    Map.get(field_config, :filters, []) ++ Map.get(field_config, "filters", [])
  end

  defp get_filters(_), do: []

  defp extract_filters_from_yaml_data(data) when is_map(data) do
    search = Map.get(data, "search", %{})
    fields = Map.get(search, "fields", %{})

    Enum.flat_map(fields, fn
      {_field_name, %{"filters" => filters}} when is_list(filters) ->
        Enum.map(filters, fn
          %{"name" => name} -> name
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end)
    |> Enum.uniq()
  end

  defp extract_filters_from_yaml_data(_), do: []
end
