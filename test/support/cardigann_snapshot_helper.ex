defmodule Mydia.CardigannSnapshotHelper do
  @moduledoc """
  Helper for running snapshot tests against Cardigann indexer definitions.

  Loads a YAML definition and saved HTML/JSON fixture, parses results through
  the Cardigann engine, and asserts on the output.

  ## Usage

      use ExUnit.Case
      import Mydia.CardigannSnapshotHelper

      test "1337x parses correctly" do
        run_snapshot("test/fixtures/cardigann/1337x", min_results: 10, assertions: fn results ->
          first = hd(results)
          assert first.title != ""
          assert first.seeders >= 0
        end)
      end
  """

  alias Mydia.Indexers.CardigannParser
  alias Mydia.Indexers.CardigannResultParser

  @doc """
  Runs a snapshot test for a fixture directory.

  The directory must contain:
  - `definition.yml` - The Cardigann YAML definition
  - `response.html` or `response.json` - The saved search response

  Optionally:
  - `metadata.json` - Query metadata (keywords, expected count, etc.)

  ## Options

  - `:min_results` - Minimum expected result count (default: 1)
  - `:assertions` - Function receiving the results list for custom assertions
  - `:template_context` - Template context for rendering (default: builds from metadata)
  """
  def run_snapshot(fixture_dir, opts \\ []) do
    min_results = Keyword.get(opts, :min_results, 1)
    assertions_fn = Keyword.get(opts, :assertions)
    extra_context = Keyword.get(opts, :template_context)

    # Load definition
    definition_path = Path.join(fixture_dir, "definition.yml")

    unless File.exists?(definition_path) do
      raise "Missing definition file: #{definition_path}"
    end

    yaml_content = File.read!(definition_path)

    {:ok, definition} = CardigannParser.parse_definition(yaml_content)

    # Load response fixture
    {response_body, _type} = load_response_fixture(fixture_dir)

    # Load metadata if available
    metadata = load_metadata(fixture_dir)

    # Build template context
    template_context =
      extra_context ||
        build_template_context(metadata, definition)

    # Build base URL from definition
    base_url =
      case definition.links do
        [url | _] when is_binary(url) -> url
        _ -> ""
      end

    indexer_name = definition.name || definition.id

    # Parse results
    response = %{status: 200, body: response_body}

    result =
      CardigannResultParser.parse_results(definition, response, indexer_name,
        template_context: template_context,
        base_url: base_url
      )

    case result do
      {:ok, results} ->
        # Assert minimum result count
        if length(results) < min_results do
          raise ExUnit.AssertionError,
            message:
              "Expected at least #{min_results} results from #{indexer_name}, got #{length(results)}"
        end

        # Run custom assertions if provided
        if assertions_fn do
          assertions_fn.(results)
        end

        {:ok, results}

      {:error, error} ->
        raise ExUnit.AssertionError,
          message: "Parsing failed for #{indexer_name}: #{inspect(error)}"
    end
  end

  @doc """
  Lists all available fixture directories.
  """
  def list_fixture_dirs(base_path \\ "test/fixtures/cardigann") do
    if File.dir?(base_path) do
      base_path
      |> File.ls!()
      |> Enum.map(&Path.join(base_path, &1))
      |> Enum.filter(&File.dir?/1)
      |> Enum.filter(fn dir ->
        File.exists?(Path.join(dir, "definition.yml"))
      end)
      |> Enum.sort()
    else
      []
    end
  end

  @doc """
  Validates basic field expectations on a list of search results.
  """
  def assert_basic_fields(results) do
    for result <- results do
      # Title should be non-empty
      assert_field_present(result, :title, "title")

      # Download URL should be non-empty
      assert_field_present(result, :download_url, "download_url")

      # Seeders should be non-negative
      if result.seeders do
        unless result.seeders >= 0 do
          raise ExUnit.AssertionError,
            message: "Expected seeders >= 0, got #{result.seeders} for '#{result.title}'"
        end
      end
    end
  end

  defp assert_field_present(result, field, name) do
    value = Map.get(result, field)

    if is_nil(value) or value == "" do
      raise ExUnit.AssertionError,
        message: "Expected #{name} to be present, got #{inspect(value)}"
    end
  end

  defp load_response_fixture(fixture_dir) do
    html_path = Path.join(fixture_dir, "response.html")
    json_path = Path.join(fixture_dir, "response.json")

    cond do
      File.exists?(html_path) -> {File.read!(html_path), :html}
      File.exists?(json_path) -> {File.read!(json_path), :json}
      true -> raise "No response fixture found in #{fixture_dir}"
    end
  end

  defp load_metadata(fixture_dir) do
    metadata_path = Path.join(fixture_dir, "metadata.json")

    if File.exists?(metadata_path) do
      case Jason.decode(File.read!(metadata_path)) do
        {:ok, metadata} -> metadata
        _ -> %{}
      end
    else
      %{}
    end
  end

  defp build_template_context(metadata, definition) do
    keywords = Map.get(metadata, "query", "test")

    # Build config from definition settings defaults
    config =
      (definition.settings || [])
      |> Enum.reduce(%{}, fn setting, acc ->
        name = setting[:name] || setting["name"]
        default = setting[:default] || setting["default"]
        if name && default, do: Map.put(acc, name, to_string(default)), else: acc
      end)

    %{
      keywords: keywords,
      config: config,
      categories: [],
      settings: definition.settings || [],
      query: %{}
    }
  end
end
