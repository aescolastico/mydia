defmodule Mix.Tasks.Mydia.CardigannCompat do
  @moduledoc """
  Analyzes Cardigann indexer compatibility with our native engine.

  Downloads all v11 definitions from Prowlarr/Indexers GitHub repository,
  parses each one, and generates a compatibility report showing filter usage,
  missing filters, and per-definition compatibility status.

  ## Usage

      mix mydia.cardigann_compat [options]

  ## Options

      --limit N       Analyze only the first N definitions (useful for testing)
      --cache         Cache downloaded definitions to speed up repeated runs
      --verbose       Show per-definition details
      --json          Output report as JSON

  ## Examples

      mix mydia.cardigann_compat
      mix mydia.cardigann_compat --limit 50
      mix mydia.cardigann_compat --cache --verbose
  """

  use Mix.Task

  @shortdoc "Analyzes Cardigann indexer definition compatibility"

  @impl Mix.Task
  def run(args) do
    {opts, _} =
      OptionParser.parse!(args,
        strict: [limit: :integer, cache: :boolean, verbose: :boolean, json: :boolean]
      )

    Mix.Task.run("app.start")

    limit = opts[:limit]
    verbose = opts[:verbose] || false
    json = opts[:json] || false

    cache_dir =
      if opts[:cache] do
        Path.join([Mix.Project.build_path(), "cardigann_compat_cache"])
      else
        nil
      end

    analyze_opts =
      [limit: limit, cache_dir: cache_dir]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    Mix.shell().info("Analyzing Cardigann definitions...")

    case Mydia.Indexers.CardigannCompat.analyze(analyze_opts) do
      {:ok, report} ->
        if json do
          print_json_report(report)
        else
          print_report(report, verbose)
        end

      {:error, reason} ->
        Mix.shell().error("Analysis failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp print_report(report, verbose) do
    Mix.shell().info("")
    Mix.shell().info("=== Cardigann Compatibility Report ===")
    Mix.shell().info("")

    # Summary
    Mix.shell().info("Summary:")
    Mix.shell().info("  Total definitions:      #{report.total}")
    Mix.shell().info("  Successfully parsed:    #{report.parsed}")
    Mix.shell().info("  Parse failures:         #{report.parse_failed}")
    Mix.shell().info("  Fully compatible:       #{report.fully_compatible}")
    Mix.shell().info("  Partially compatible:   #{report.partially_compatible}")
    Mix.shell().info("")

    parse_rate =
      if report.total > 0,
        do: Float.round(report.parsed / report.total * 100, 1),
        else: 0.0

    compat_rate =
      if report.parsed > 0,
        do: Float.round(report.fully_compatible / report.parsed * 100, 1),
        else: 0.0

    Mix.shell().info("  Parse success rate:     #{parse_rate}%")
    Mix.shell().info("  Compatibility rate:     #{compat_rate}% (of parsed)")
    Mix.shell().info("")

    # Filter usage
    Mix.shell().info("Filter Usage (all definitions):")
    Mix.shell().info(String.duplicate("-", 50))

    implemented = Mydia.Indexers.CardigannCompat.implemented_filters()

    Enum.each(report.filter_usage, fn {name, count} ->
      status = if name in implemented, do: "[OK]", else: "[MISSING]"

      Mix.shell().info(
        "  #{String.pad_trailing(name, 20)} #{String.pad_leading(to_string(count), 5)}  #{status}"
      )
    end)

    Mix.shell().info("")

    # Missing filters
    if report.missing_filters != [] do
      Mix.shell().info("Missing Filters (priority order by usage):")
      Mix.shell().info(String.duplicate("-", 50))

      Enum.each(report.missing_filters, fn {name, count} ->
        Mix.shell().info("  #{String.pad_trailing(name, 20)} used by #{count} definitions")
      end)

      Mix.shell().info("")
    end

    # Parse failures
    if report.parse_failures != [] do
      failures_to_show =
        if verbose, do: report.parse_failures, else: Enum.take(report.parse_failures, 10)

      Mix.shell().info("Parse Failures#{unless verbose, do: " (top 10)"}:")
      Mix.shell().info(String.duplicate("-", 50))

      Enum.each(failures_to_show, fn {name, reason} ->
        Mix.shell().info("  #{name}: #{format_error(reason)}")
      end)

      if not verbose and length(report.parse_failures) > 10 do
        Mix.shell().info(
          "  ... and #{length(report.parse_failures) - 10} more (use --verbose to see all)"
        )
      end

      Mix.shell().info("")
    end

    # Per-definition details (verbose only)
    if verbose do
      Mix.shell().info("Per-Definition Details:")
      Mix.shell().info(String.duplicate("-", 80))

      report.definitions
      |> Enum.sort_by(& &1.name)
      |> Enum.each(fn defn ->
        status_str =
          case defn.status do
            :fully_compatible -> "OK"
            :partially_compatible -> "PARTIAL"
            :parse_failed -> "FAILED"
          end

        missing_str =
          if defn.missing_filters != [] do
            " missing: #{Enum.join(defn.missing_filters, ", ")}"
          else
            ""
          end

        Mix.shell().info("  [#{status_str}] #{defn.name}#{missing_str}")
      end)

      Mix.shell().info("")
    end
  end

  defp print_json_report(report) do
    json_data = %{
      summary: %{
        total: report.total,
        parsed: report.parsed,
        parse_failed: report.parse_failed,
        fully_compatible: report.fully_compatible,
        partially_compatible: report.partially_compatible
      },
      filter_usage: Map.new(report.filter_usage),
      missing_filters: Map.new(report.missing_filters),
      definitions:
        Enum.map(report.definitions, fn defn ->
          %{
            name: defn.name,
            id: defn.id,
            status: defn.status,
            filters_used: defn.filters_used,
            missing_filters: defn.missing_filters,
            error: if(defn.error, do: format_error(defn.error))
          }
        end)
    }

    Mix.shell().info(Jason.encode!(json_data, pretty: true))
  end

  defp format_error({:missing_required_field, field}), do: "missing required field: #{field}"
  defp format_error({:missing_required_fields, fields}), do: "missing fields: #{inspect(fields)}"
  defp format_error({:parse_error, msg}), do: "parse error: #{msg}"
  defp format_error({:yaml_parse_error, _} = err), do: "YAML error: #{inspect(err)}"
  defp format_error(:missing_search_path), do: "missing search path"
  defp format_error(:missing_rows_selector), do: "missing rows selector"
  defp format_error(:missing_fields), do: "missing search fields"
  defp format_error(:missing_capabilities), do: "missing capabilities"
  defp format_error(other), do: inspect(other)
end
