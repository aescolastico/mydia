defmodule Mydia.Indexers.CardigannResultParser do
  @moduledoc """
  Parser for Cardigann search results from HTML or JSON responses.

  This module handles parsing search results from HTTP responses using
  Cardigann selector definitions. It supports both HTML and JSON parsing
  with filters, transformations, and conversion to SearchResult structs.

  ## HTML Parsing

  Uses Floki for HTML parsing with CSS selector support:
  - Row selectors to identify result elements
  - Field selectors to extract data from each row
  - Attribute extraction (href, data-*, etc.)
  - Text content extraction

  ## JSON Parsing

  Supports JSONPath-style selectors for navigating JSON structures:
  - Object property access
  - Array indexing and iteration
  - Nested structure traversal

  ## Cardigann Filters

  Applies transformation filters defined in the Cardigann spec:
  - `replace` - String replacement
  - `re_replace` - Regex replacement
  - `append` - Append string
  - `prepend` - Prepend string
  - `trim` - Trim whitespace
  - `split` - Split string and return part at index
  - `urldecode` - URL-decode strings
  - `regexp` - Regex extraction (first capture group)
  - `dateparse`/`timeparse` - Parse date with Go format layout
  - `timeago`/`reltime` - Parse relative time ("2 hours ago")
  - `fuzzytime` - Parse various date formats (Today, Yesterday, timestamps)
  - `tolower`/`toupper` - Case conversion
  - `urlencode` - URL-encode strings
  - `htmldecode` - Decode HTML entities
  - `querystring` - Extract URL query parameter value

  ## Examples

      # Parse HTML response
      definition = %Parsed{search: %{rows: %{selector: "tr.result"}, fields: ...}}
      response = %{status: 200, body: "<html>...</html>"}
      {:ok, results} = CardigannResultParser.parse_results(definition, response)

      # Parse JSON response
      definition = %Parsed{search: %{rows: %{selector: "$.results[*]"}, fields: ...}}
      response = %{status: 200, body: "{...}"}
      {:ok, results} = CardigannResultParser.parse_results(definition, response)
  """

  alias Mydia.Indexers.CardigannDefinition.Parsed
  alias Mydia.Indexers.SearchResult
  alias Mydia.Indexers.QualityParser
  alias Mydia.Indexers.CategoryMapping
  alias Mydia.Indexers.Adapter.Error
  alias Mydia.Indexers.CardigannTemplate

  require Logger

  @type parse_result :: {:ok, [SearchResult.t()]} | {:error, Error.t()}
  @type http_response :: %{status: integer(), body: String.t()}

  @doc """
  Parses search results from an HTTP response using Cardigann definition.

  Automatically detects whether the response is HTML or JSON based on the
  response body and selectors defined in the definition.

  ## Parameters

  - `definition` - Parsed Cardigann definition with search configuration
  - `response` - HTTP response with status and body
  - `indexer_name` - Name of the indexer for result attribution
  - `opts` - Optional keyword list with:
    - `:template_context` - Template context for rendering filter arguments

  ## Returns

  - `{:ok, results}` - List of SearchResult structs
  - `{:error, reason}` - Parsing error

  ## Examples

      iex> parse_results(definition, response, "1337x")
      {:ok, [%SearchResult{}, ...]}

      iex> parse_results(definition, response, "1337x", template_context: %{config: %{"sort" => "seeders"}})
      {:ok, [%SearchResult{}, ...]}
  """
  @spec parse_results(Parsed.t(), http_response(), String.t(), keyword()) :: parse_result()
  def parse_results(%Parsed{} = definition, response, indexer_name, opts \\ []) do
    body = response.body
    template_context = Keyword.get(opts, :template_context, %{})
    base_url = Keyword.get(opts, :base_url, "")

    # Extract category mappings from definition capabilities
    category_mappings = get_in(definition.capabilities, [:categorymappings]) || []

    # Guard against nil or non-string bodies
    cond do
      is_nil(body) ->
        {:error, Error.search_failed("Empty response body")}

      is_map(body) ->
        # Req auto-decoded JSON response - parse directly
        parse_json_results_from_map(
          definition,
          body,
          indexer_name,
          template_context,
          base_url,
          category_mappings
        )

      not is_binary(body) ->
        {:error, Error.search_failed("Invalid response body type: #{inspect(body)}")}

      String.trim(body) == "" ->
        {:ok, []}

      true ->
        case detect_response_type(body) do
          :html ->
            parse_html_results(
              definition,
              body,
              indexer_name,
              template_context,
              base_url,
              category_mappings
            )

          :json ->
            parse_json_results(
              definition,
              body,
              indexer_name,
              template_context,
              base_url,
              category_mappings
            )
        end
    end
  end

  @doc """
  Parses HTML response body using Cardigann selectors.

  ## Process

  1. Parse HTML with Floki
  2. Extract rows using row selector
  3. For each row, extract fields using field selectors
  4. Apply filters to field values (with template rendering)
  5. Transform to SearchResult structs

  ## Parameters

  - `definition` - Parsed Cardigann definition
  - `html_body` - HTML response body
  - `indexer_name` - Name of the indexer
  - `template_context` - Template context for rendering filter arguments
  - `base_url` - Base URL for resolving relative URLs
  - `category_mappings` - Category mappings from the definition for site-to-Torznab conversion

  ## Returns

  - `{:ok, results}` - List of SearchResult structs
  - `{:error, reason}` - Parsing error
  """
  @spec parse_html_results(Parsed.t(), String.t(), String.t(), map(), String.t(), list()) ::
          parse_result()
  def parse_html_results(
        %Parsed{} = definition,
        html_body,
        indexer_name,
        template_context \\ %{},
        base_url \\ "",
        category_mappings \\ []
      ) do
    with {:ok, document} <- parse_html_document(html_body),
         {:ok, rows} <- extract_rows(document, definition.search, template_context) do
      Logger.info("[#{indexer_name}] Extracted #{length(rows)} rows from HTML")

      case parse_row_fields(rows, definition.search, document, template_context) do
        {:ok, parsed_rows} ->
          Logger.info("[#{indexer_name}] Parsed #{length(parsed_rows)} rows successfully")

          results =
            transform_to_search_results(parsed_rows, indexer_name, base_url, category_mappings)

          Logger.info("[#{indexer_name}] Transformed to #{length(results)} search results")
          {:ok, results}

        error ->
          error
      end
    end
  rescue
    error ->
      Logger.error("HTML parsing error for #{indexer_name}: #{inspect(error)}")
      {:error, Error.search_failed("Failed to parse HTML response: #{inspect(error)}")}
  end

  @doc """
  Parses JSON response body using Cardigann selectors.

  ## Parameters

  - `definition` - Parsed Cardigann definition
  - `json_body` - JSON response body
  - `indexer_name` - Name of the indexer
  - `template_context` - Template context for rendering filter arguments
  - `base_url` - Base URL for resolving relative URLs
  - `category_mappings` - Category mappings from the definition for site-to-Torznab conversion

  ## Returns

  - `{:ok, results}` - List of SearchResult structs
  - `{:error, reason}` - Parsing error
  """
  @spec parse_json_results(Parsed.t(), String.t(), String.t(), map(), String.t(), list()) ::
          parse_result()
  def parse_json_results(
        %Parsed{} = definition,
        json_body,
        indexer_name,
        template_context \\ %{},
        base_url \\ "",
        category_mappings \\ []
      ) do
    with {:ok, json} <- Jason.decode(json_body),
         {:ok, rows} <- extract_json_rows(json, definition.search) do
      Logger.info("[#{indexer_name}] Extracted #{length(rows)} rows from JSON")

      case parse_json_row_fields(rows, definition.search, template_context) do
        {:ok, parsed_rows} ->
          Logger.info("[#{indexer_name}] Parsed #{length(parsed_rows)} JSON rows successfully")

          results =
            transform_to_search_results(parsed_rows, indexer_name, base_url, category_mappings)

          Logger.info("[#{indexer_name}] Transformed to #{length(results)} search results")
          {:ok, results}

        error ->
          error
      end
    else
      {:error, %Jason.DecodeError{} = error} ->
        {:error, Error.search_failed("Invalid JSON: #{inspect(error)}")}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("JSON parsing error for #{indexer_name}: #{inspect(error)}")
      {:error, Error.search_failed("Failed to parse JSON response: #{inspect(error)}")}
  end

  @doc """
  Parses pre-decoded JSON response (when Req auto-decodes JSON).

  ## Parameters

  - `definition` - Parsed Cardigann definition
  - `json` - Already decoded JSON map
  - `indexer_name` - Name of the indexer
  - `template_context` - Template context for rendering filter arguments
  - `base_url` - Base URL for resolving relative URLs
  - `category_mappings` - Category mappings from the definition for site-to-Torznab conversion

  ## Returns

  - `{:ok, results}` - List of SearchResult structs
  - `{:error, reason}` - Parsing error
  """
  @spec parse_json_results_from_map(Parsed.t(), map(), String.t(), map(), String.t(), list()) ::
          parse_result()
  def parse_json_results_from_map(
        %Parsed{} = definition,
        json,
        indexer_name,
        template_context \\ %{},
        base_url \\ "",
        category_mappings \\ []
      )
      when is_map(json) do
    with {:ok, rows} <- extract_json_rows(json, definition.search),
         {:ok, parsed_rows} <- parse_json_row_fields(rows, definition.search, template_context) do
      results =
        transform_to_search_results(parsed_rows, indexer_name, base_url, category_mappings)

      {:ok, results}
    end
  rescue
    error ->
      Logger.error("JSON map parsing error: #{inspect(error)}")
      {:error, Error.search_failed("Failed to parse JSON response: #{inspect(error)}")}
  end

  # HTML Parsing Functions

  defp parse_html_document(html_body) do
    case Floki.parse_document(html_body) do
      {:ok, document} -> {:ok, document}
      {:error, reason} -> {:error, Error.search_failed("HTML parse error: #{inspect(reason)}")}
    end
  end

  defp extract_rows(document, %{rows: %{selector: selector} = row_config}, template_context) do
    # Render Go templates in the row selector
    rendered_selector = render_selector_template(selector, template_context)
    Logger.info("Extracting rows with selector: #{inspect(rendered_selector)}")
    # Use enhanced find that supports :contains() pseudo-selector
    rows = floki_find_with_contains(document, rendered_selector)
    Logger.info("Found #{length(rows)} rows before filtering")

    # Debug: if no rows found, log some HTML structure info
    if rows == [] do
      # Try to find any tr elements to understand the structure
      all_trs = Floki.find(document, "tr")
      all_tables = Floki.find(document, "table")

      Logger.info(
        "Debug: Found #{length(all_trs)} tr elements and #{length(all_tables)} tables in document"
      )

      # Check for common row patterns
      torrent_links = Floki.find(document, "a[href*=\"torrent\"]")
      Logger.info("Debug: Found #{length(torrent_links)} links containing 'torrent' in href")

      # Log first 500 chars of HTML to understand structure
      html_preview = document |> Floki.raw_html() |> String.slice(0, 1000)
      Logger.info("Debug: HTML preview: #{html_preview}")
    end

    # Apply 'after' filter to skip header rows if configured
    rows_after_skip =
      case Map.get(row_config, :after) do
        nil ->
          rows

        skip_count when is_integer(skip_count) ->
          Logger.info("Skipping first #{skip_count} rows")
          Enum.drop(rows, skip_count)
      end

    {:ok, rows_after_skip}
  end

  defp extract_rows(_document, _search_config, _template_context) do
    {:error, Error.search_failed("No row selector configured")}
  end

  # Renders Go templates in a selector string
  defp render_selector_template(selector, template_context)
       when is_binary(selector) and map_size(template_context) > 0 do
    if String.contains?(selector, "{{") do
      case CardigannTemplate.render(selector, template_context, url_encode: false) do
        {:ok, rendered} -> rendered
        {:error, _} -> selector
      end
    else
      selector
    end
  end

  defp render_selector_template(selector, _template_context), do: selector

  # Enhanced Floki.find that supports :contains() pseudo-selector
  # Floki doesn't support :contains(), so we handle it manually
  defp floki_find_with_contains(document, selector) do
    # Handle comma-separated selectors (OR)
    if String.contains?(selector, ",") do
      selector
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.flat_map(&floki_find_with_contains(document, &1))
      |> Enum.uniq()
    else
      floki_find_single_selector(document, selector)
    end
  end

  defp floki_find_single_selector(document, selector) do
    # Check if selector contains :contains()
    case Regex.run(~r/:contains\(['"]([^'"]+)['"]\)/, selector) do
      [full_match, text_to_find] ->
        # Split selector at :contains() and process
        [before_contains | rest] = String.split(selector, full_match, parts: 2)
        after_contains = Enum.join(rest, "")

        # Find elements matching the part before :contains
        before_selector = String.trim(before_contains)

        elements =
          if before_selector == "" do
            # :contains at the start - search all elements
            [document]
          else
            Floki.find(document, before_selector)
          end

        # Filter to only elements containing the text
        matching_elements =
          Enum.filter(elements, fn el ->
            text = Floki.text(el)
            String.contains?(text, text_to_find)
          end)

        # If there's more selector after :contains, apply it
        if String.trim(after_contains) == "" do
          matching_elements
        else
          # Apply the rest of the selector within matching elements
          Enum.flat_map(matching_elements, fn el ->
            floki_find_with_contains(el, String.trim(after_contains))
          end)
        end

      nil ->
        # No :contains(), use normal Floki.find
        Floki.find(document, selector)
    end
  end

  defp parse_row_fields(rows, %{fields: fields}, _document, template_context) do
    parsed_rows =
      rows
      |> Enum.map(fn row ->
        parse_single_row(row, fields, template_context)
      end)
      |> Enum.filter(&(&1 != nil))

    {:ok, parsed_rows}
  end

  defp parse_single_row(row, fields, template_context) do
    # Separate fields into selector-based and text-based (computed) fields
    # A field is text-based if it has a non-empty :text or "text" key
    {selector_fields, text_fields} =
      Enum.split_with(fields, fn {_name, config} ->
        # Ensure config is a map before accessing it
        if is_map(config) do
          text_value = Map.get(config, :text) || Map.get(config, "text")
          is_nil(text_value) || text_value == ""
        else
          # Non-map configs are treated as selector-based
          true
        end
      end)

    # First pass: Extract all selector-based fields from HTML/JSON
    field_values =
      Enum.reduce(selector_fields, %{}, fn {field_name, field_config}, acc ->
        # Skip non-map configs
        if is_map(field_config) do
          is_optional =
            Map.get(field_config, :optional) || Map.get(field_config, "optional", false)

          case extract_field_value(row, field_config, template_context) do
            {:ok, value} ->
              Map.put(acc, field_name, value)

            {:error, reason} ->
              # Field extraction failed
              if is_optional do
                # Optional field - just skip it, don't log as error
                acc
              else
                Logger.debug("Field #{field_name} extraction failed: #{inspect(reason)}")
                acc
              end
          end
        else
          Logger.debug("Skipping field #{field_name}: config is not a map")
          acc
        end
      end)

    # Second pass: Compute text-based fields using templates
    # These can reference previously extracted values via {{ .Result.fieldname }}
    field_values =
      Enum.reduce(text_fields, field_values, fn {field_name, field_config}, acc ->
        # Skip non-map configs
        if is_map(field_config) do
          case compute_text_field(field_config, acc, template_context) do
            {:ok, value} ->
              Map.put(acc, field_name, value)

            {:error, _reason} ->
              acc
          end
        else
          Logger.debug("Skipping text field #{field_name}: config is not a map")
          acc
        end
      end)

    # Handle compound title fields (title_default, title_optional -> title)
    field_values = combine_compound_fields(field_values)

    # Only return row if we got at least title and download
    has_title = Map.has_key?(field_values, "title") || Map.has_key?(field_values, :title)
    has_download = Map.has_key?(field_values, "download") || Map.has_key?(field_values, :download)

    if has_title && has_download do
      field_values
    else
      Logger.info(
        "Row filtered out - title: #{has_title}, download: #{has_download}, fields: #{inspect(Map.keys(field_values))}"
      )

      nil
    end
  end

  # Computes a text-based field value using template rendering
  # The template can reference previously extracted values via {{ .Result.fieldname }}
  defp compute_text_field(field_config, extracted_values, template_context)
       when is_map(field_config) do
    text_template = Map.get(field_config, :text) || Map.get(field_config, "text")
    filters = Map.get(field_config, :filters) || Map.get(field_config, "filters", [])

    # Guard against nil or non-string text templates
    if is_nil(text_template) or not is_binary(text_template) do
      {:error, :invalid_text_template}
    else
      # Build a context that includes the extracted result values
      # Cardigann templates use .Result.fieldname to access extracted values
      result_context =
        extracted_values
        |> Enum.map(fn {key, value} ->
          # Ensure keys are strings for template lookup
          key_str = if is_atom(key), do: Atom.to_string(key), else: key
          {key_str, value}
        end)
        |> Map.new()

      # Merge result context into template context
      full_context = Map.put(template_context, :result, result_context)

      # Render the template
      try do
        case CardigannTemplate.render(text_template, full_context, url_encode: false) do
          {:ok, rendered_value} ->
            # Apply any filters to the rendered value
            apply_filters(String.trim(rendered_value), filters, template_context)

          {:error, reason} ->
            Logger.debug("Text field template render failed: #{inspect(reason)}")
            {:error, reason}
        end
      rescue
        e ->
          Logger.warning(
            "Template render exception: #{inspect(e)}, template: #{inspect(text_template)}"
          )

          {:error, {:template_exception, e}}
      end
    end
  end

  # Fallback for non-map configs
  defp compute_text_field(_field_config, _extracted_values, _template_context) do
    {:error, :invalid_field_config}
  end

  # Combine compound fields like title_default/title_optional into a single title field
  # This handles Cardigann definitions that use field variants for fallback logic
  defp combine_compound_fields(field_values) do
    field_values
    |> combine_title_fields()
    |> combine_download_fields()
  end

  defp combine_title_fields(field_values) do
    title_default = field_values[:title_default] || field_values["title_default"]
    title_optional = field_values[:title_optional] || field_values["title_optional"]
    existing_title = field_values[:title] || field_values["title"]

    # If we already have a title, don't override
    if existing_title && existing_title != "" do
      field_values
    else
      # Use title_optional if default contains "..." (truncated), otherwise use default
      title =
        cond do
          title_optional && title_optional != "" && title_default &&
              String.contains?(title_default || "", "...") ->
            title_optional

          title_default && title_default != "" ->
            title_default

          title_optional && title_optional != "" ->
            title_optional

          true ->
            nil
        end

      if title do
        field_values
        |> Map.put(:title, title)
        |> Map.delete(:title_default)
        |> Map.delete(:title_optional)
        |> Map.delete("title_default")
        |> Map.delete("title_optional")
      else
        field_values
      end
    end
  end

  defp combine_download_fields(field_values) do
    # Handle download/download2 fallback pattern
    download = field_values[:download] || field_values["download"]
    download2 = field_values[:download2] || field_values["download2"]

    cond do
      download && download != "" ->
        field_values

      download2 && download2 != "" ->
        field_values
        |> Map.put(:download, download2)
        |> Map.delete(:download2)
        |> Map.delete("download2")

      true ->
        field_values
    end
  end

  defp extract_field_value(row, field_config, template_context) when is_map(field_config) do
    selector = Map.get(field_config, :selector) || Map.get(field_config, "selector")
    attribute = Map.get(field_config, :attribute) || Map.get(field_config, "attribute")
    filters = Map.get(field_config, :filters) || Map.get(field_config, "filters", [])

    with {:ok, raw_value} <- extract_raw_value(row, selector, attribute) do
      apply_filters(raw_value, filters, template_context)
    end
  end

  # Fallback for non-map field configs
  defp extract_field_value(_row, _field_config, _template_context) do
    {:error, :invalid_field_config}
  end

  defp extract_raw_value(row, selector, nil) do
    # Extract text content
    case Floki.find(row, selector) do
      [] ->
        {:error, :not_found}

      elements ->
        text =
          elements
          |> Floki.text()
          |> String.trim()

        {:ok, text}
    end
  end

  defp extract_raw_value(row, selector, attribute) do
    # Extract attribute value
    case Floki.find(row, selector) do
      [] ->
        {:error, :not_found}

      elements ->
        case Floki.attribute(elements, attribute) do
          [value | _] -> {:ok, String.trim(value)}
          [] -> {:error, :not_found}
        end
    end
  end

  @doc """
  Applies Cardigann filters to a field value.

  Filters are applied in sequence, with each filter transforming
  the value before passing to the next filter. Filter arguments
  containing Go template syntax will be rendered using the provided
  template context before application.

  ## Supported Filters

  - `replace` - String replacement: `{name: "replace", args: ["old", "new"]}`
  - `re_replace` - Regex replacement: `{name: "re_replace", args: ["pattern", "replacement"]}`
  - `append` - Append string: `{name: "append", args: ["suffix"]}`
  - `prepend` - Prepend string: `{name: "prepend", args: ["prefix"]}`
  - `trim` - Trim whitespace: `{name: "trim"}`
  - `dateparse` - Parse date: `{name: "dateparse", args: ["format"]}`

  ## Examples

      iex> apply_filters("  test  ", [%{name: "trim"}], %{})
      {:ok, "test"}

      iex> apply_filters("1.5 GB", [%{name: "replace", args: [" GB", ""]}], %{})
      {:ok, "1.5"}

      iex> apply_filters("text", [%{name: "append", args: ["{{ if .Config.flag }} suffix{{ else }}{{ end }}"]}], %{config: %{"flag" => true}})
      {:ok, "text suffix"}
  """
  @spec apply_filters(String.t(), list(), map()) :: {:ok, String.t()} | {:error, term()}
  def apply_filters(value, [], _template_context), do: {:ok, value}

  def apply_filters(value, [filter | rest], template_context) do
    # Render templates in filter arguments
    rendered_filter = render_filter_templates(filter, template_context)

    case apply_single_filter(value, rendered_filter) do
      {:ok, new_value} -> apply_filters(new_value, rest, template_context)
      error -> error
    end
  end

  # Backward compatibility - allow calling without template_context
  def apply_filters(value, filters) when is_list(filters) do
    apply_filters(value, filters, %{})
  end

  # Renders Go templates in filter arguments using the provided template context
  defp render_filter_templates(filter, template_context) when is_map(filter) do
    # Get args from filter (support both atom and string keys)
    args = Map.get(filter, :args) || Map.get(filter, "args")
    args_key = if Map.has_key?(filter, :args), do: :args, else: "args"

    case args do
      nil ->
        filter

      args when is_list(args) ->
        # Render each arg that contains template syntax (if template_context available)
        rendered_args =
          if template_context == %{} or template_context == nil do
            args
          else
            Enum.map(args, fn arg ->
              render_template_in_string(arg, template_context)
            end)
          end

        Map.put(filter, args_key, rendered_args)

      args when is_binary(args) ->
        # Single string arg - render template (if context available) and wrap in list for consistency
        rendered_arg =
          if template_context == %{} or template_context == nil do
            args
          else
            render_template_in_string(args, template_context)
          end

        Map.put(filter, args_key, [rendered_arg])

      _ ->
        filter
    end
  end

  defp render_filter_templates(filter, _template_context), do: filter

  # Helper to render template in a string if it contains template syntax
  defp render_template_in_string(value, template_context) when is_binary(value) do
    if String.contains?(value, "{{") do
      case CardigannTemplate.render(value, template_context, url_encode: false) do
        {:ok, rendered} -> rendered
        {:error, _} -> value
      end
    else
      value
    end
  end

  defp render_template_in_string(value, _template_context), do: value

  # Delegate all filter application to the CardigannFilters module
  defp apply_single_filter(value, filter) do
    Mydia.Indexers.CardigannFilters.apply(filter, value)
  end

  # JSON Parsing Functions

  defp extract_json_rows(json, %{rows: row_config}) do
    selector = Map.get(row_config, :selector) || Map.get(row_config, "selector")
    attribute = Map.get(row_config, :attribute) || Map.get(row_config, "attribute")

    case navigate_json_path(json, selector) do
      {:ok, rows} when is_list(rows) ->
        # If attribute is set (e.g., "torrents"), expand sub-arrays within each row.
        # Each sub-item becomes its own row with a "__parent" key for ".." prefix access.
        expanded = maybe_expand_attribute(rows, attribute)
        {:ok, expanded}

      {:ok, single_value} ->
        {:ok, [single_value]}

      {:error, :path_not_found} ->
        available_keys = if is_map(json), do: Map.keys(json), else: []

        Logger.warning(
          "JSON path not found: #{selector}. Available top-level keys: #{inspect(available_keys)}"
        )

        {:ok, []}

      error ->
        error
    end
  end

  defp extract_json_rows(_json, _search_config) do
    {:error, Error.search_failed("No row selector configured for JSON")}
  end

  defp maybe_expand_attribute(rows, nil), do: rows
  defp maybe_expand_attribute(rows, ""), do: rows

  defp maybe_expand_attribute(rows, attribute) when is_binary(attribute) do
    Enum.flat_map(rows, fn parent_row when is_map(parent_row) ->
      case Map.get(parent_row, attribute) do
        sub_items when is_list(sub_items) ->
          Enum.map(sub_items, fn sub_item when is_map(sub_item) ->
            Map.put(sub_item, "__parent", parent_row)
          end)

        _ ->
          # No sub-array, keep parent as-is
          [parent_row]
      end
    end)
  end

  defp navigate_json_path(json, "$") do
    {:ok, json}
  end

  defp navigate_json_path(json, "$.") do
    {:ok, json}
  end

  defp navigate_json_path(json, "$." <> path) do
    navigate_json_path_parts(json, String.split(path, "."))
  end

  defp navigate_json_path(json, path) do
    # Split dotted paths (e.g., "data.movies" → ["data", "movies"])
    parts = String.split(path, ".")
    navigate_json_path_parts(json, parts)
  end

  defp navigate_json_path_parts(value, []) do
    {:ok, value}
  end

  defp navigate_json_path_parts(map, [key | rest]) when is_map(map) do
    case Map.get(map, key) do
      nil -> {:error, :path_not_found}
      value -> navigate_json_path_parts(value, rest)
    end
  end

  defp navigate_json_path_parts(_value, _path) do
    {:error, :invalid_path}
  end

  defp parse_json_row_fields(rows, %{fields: fields}, template_context) do
    parsed_rows =
      rows
      |> Enum.map(fn row ->
        parse_single_json_row(row, fields, template_context)
      end)
      |> Enum.filter(&(&1 != nil))

    {:ok, parsed_rows}
  end

  defp parse_single_json_row(row, fields, template_context) when is_map(row) do
    # First pass: extract raw values without applying filters that need .Result context
    raw_values =
      Enum.reduce(fields, %{}, fn {field_name, field_config}, acc ->
        case extract_json_raw_value(row, field_config) do
          {:ok, value} ->
            Map.put(acc, field_name, value)

          {:error, _reason} ->
            acc
        end
      end)

    # Build a result context for template rendering (e.g., {{ .Result._quality }})
    result_context =
      raw_values
      |> Enum.map(fn {key, value} ->
        key_str = if is_atom(key), do: Atom.to_string(key), else: key
        {key_str, value}
      end)
      |> Map.new()

    full_context = Map.put(template_context, :result, result_context)

    # Second pass: apply filters with the full template context
    field_values =
      Enum.reduce(fields, %{}, fn {field_name, field_config}, acc ->
        case extract_json_field_value(row, field_config, full_context) do
          {:ok, value} ->
            Map.put(acc, field_name, value)

          {:error, _reason} ->
            acc
        end
      end)

    # Handle compound fields (title_default + title_optional → title)
    field_values = combine_compound_fields(field_values)

    # Only return row if we got at least title and download
    has_title = Map.has_key?(field_values, :title) || Map.has_key?(field_values, "title")
    has_download = Map.has_key?(field_values, :download) || Map.has_key?(field_values, "download")

    if has_title && has_download do
      field_values
    else
      nil
    end
  end

  defp extract_json_raw_value(row, field_config) when is_map(field_config) do
    selector = Map.get(field_config, :selector) || Map.get(field_config, "selector")

    with {:ok, raw_value} <- get_json_value_by_selector(row, selector),
         {:ok, str_value} <- ensure_string(raw_value) do
      {:ok, str_value}
    end
  end

  defp extract_json_field_value(row, field_config, template_context) when is_map(field_config) do
    selector = Map.get(field_config, :selector) || Map.get(field_config, "selector")
    filters = Map.get(field_config, :filters) || Map.get(field_config, "filters", [])
    text_template = Map.get(field_config, :text) || Map.get(field_config, "text")

    cond do
      # Text-based field: render template with .Result context
      is_binary(text_template) and text_template != "" ->
        compute_text_field(field_config, %{}, template_context)

      # Selector-based field: extract value then apply filters
      true ->
        with {:ok, raw_value} <- get_json_value_by_selector(row, selector),
             {:ok, str_value} <- ensure_string(raw_value) do
          apply_filters(str_value, filters, template_context)
        end
    end
  end

  defp get_json_value_by_selector(row, ".." <> parent_selector) when is_binary(parent_selector) do
    # ".." prefix means access parent object's field (set via rows.attribute expansion)
    case Map.get(row, "__parent") do
      parent when is_map(parent) ->
        case Map.get(parent, parent_selector) do
          nil -> {:error, :not_found}
          value -> {:ok, value}
        end

      _ ->
        {:error, :no_parent}
    end
  end

  defp get_json_value_by_selector(row, selector) when is_binary(selector) do
    # Simple property access - try direct key first, then dotted path
    case Map.get(row, selector) do
      nil ->
        if String.contains?(selector, ".") do
          navigate_json_path(row, selector)
        else
          {:error, :not_found}
        end

      value ->
        {:ok, value}
    end
  end

  defp ensure_string(value) when is_binary(value), do: {:ok, value}
  defp ensure_string(value) when is_integer(value), do: {:ok, Integer.to_string(value)}
  defp ensure_string(value) when is_float(value), do: {:ok, Float.to_string(value)}
  defp ensure_string(nil), do: {:error, :not_found}
  defp ensure_string(_), do: {:error, :invalid_type}

  # Result Transformation

  defp transform_to_search_results(parsed_rows, indexer_name, base_url, category_mappings) do
    parsed_rows
    |> Enum.map(fn row ->
      transform_to_search_result(row, indexer_name, base_url, category_mappings)
    end)
    |> Enum.filter(&(&1 != nil))
  end

  defp transform_to_search_result(row, indexer_name, base_url, category_mappings) do
    raw_size = get_field(row, "size", "0")

    with {:ok, title} <- get_required_field(row, "title"),
         {:ok, download_url} <- get_required_field(row, "download"),
         size <- parse_size_with_title_fallback(raw_size, title),
         seeders <- parse_integer(get_field(row, "seeders", "0")),
         leechers <- parse_integer(get_field(row, "leechers", "0")) do
      # Parse quality from title
      quality = QualityParser.parse(title)

      # Resolve relative URLs to absolute
      resolved_download_url = resolve_url(download_url, base_url)
      resolved_info_url = resolve_url(get_field(row, "details"), base_url)

      # Detect download protocol from URL
      download_protocol = detect_download_protocol(resolved_download_url)

      # Map site-specific category to Torznab category
      raw_category = get_field(row, "category")
      torznab_category = map_category(raw_category, category_mappings)

      # Build SearchResult
      %SearchResult{
        title: title,
        size: size,
        seeders: seeders,
        leechers: leechers,
        download_url: resolved_download_url,
        info_url: resolved_info_url,
        indexer: indexer_name,
        category: torznab_category,
        published_at: parse_date(get_field(row, "date")),
        quality: quality,
        tmdb_id: parse_integer(get_field(row, "tmdbid")),
        imdb_id: get_field(row, "imdbid"),
        download_protocol: download_protocol
      }
    else
      _ -> nil
    end
  end

  # Maps a site-specific category to a Torznab category ID
  defp map_category(nil, _category_mappings), do: nil
  defp map_category("", _category_mappings), do: nil

  defp map_category(raw_category, category_mappings)
       when is_list(category_mappings) and length(category_mappings) > 0 do
    # Try to map using the category mappings from the definition
    case CategoryMapping.map_site_category_to_torznab(raw_category, category_mappings) do
      nil ->
        # Fallback: check if raw_category is already a Torznab ID
        parse_integer(raw_category)

      torznab_id ->
        torznab_id
    end
  end

  defp map_category(raw_category, _category_mappings) do
    # No mappings available, just parse as integer (might already be Torznab ID)
    parse_integer(raw_category)
  end

  # Resolve a URL relative to a base URL
  defp resolve_url(nil, _base_url), do: nil
  defp resolve_url("", _base_url), do: nil

  defp resolve_url(url, base_url) when is_binary(url) do
    cond do
      # Already absolute (http, https, magnet, etc.)
      String.match?(url, ~r/^[a-zA-Z][a-zA-Z0-9+.-]*:/) ->
        url

      # Protocol-relative URL (//example.com/path)
      String.starts_with?(url, "//") ->
        "https:" <> url

      # Absolute path (/path/to/file)
      String.starts_with?(url, "/") ->
        case URI.parse(base_url) do
          %URI{scheme: scheme, host: host, port: port} when not is_nil(host) ->
            port_str = if port && port not in [80, 443], do: ":#{port}", else: ""
            "#{scheme || "https"}://#{host}#{port_str}#{url}"

          _ ->
            # Can't resolve, return as-is
            url
        end

      # Relative path (path/to/file or file.ext)
      true ->
        case base_url do
          "" ->
            url

          base when is_binary(base) ->
            # Ensure base URL doesn't end with a slash for clean joining
            base_trimmed = String.trim_trailing(base, "/")
            "#{base_trimmed}/#{url}"
        end
    end
  end

  defp get_required_field(row, field) do
    # Check both string and atom keys since parser may use either
    value = Map.get(row, field) || Map.get(row, String.to_atom(field))

    case value do
      nil -> {:error, :missing_field}
      "" -> {:error, :empty_field}
      value -> {:ok, value}
    end
  end

  defp get_field(row, field, default \\ nil) do
    # Check both string and atom keys since parser may use either
    Map.get(row, field) || Map.get(row, String.to_atom(field), default)
  end

  @doc """
  Parses size with fallback to extracting from title.

  When the size field is empty or parses to 0, attempts to extract size
  from the title text using patterns like "(3.05Gb)" or "500MB".
  """
  @spec parse_size_with_title_fallback(String.t() | nil, String.t()) :: non_neg_integer()
  def parse_size_with_title_fallback(raw_size, title) do
    size = parse_size(raw_size)

    if size == 0 do
      # Try to extract size from title
      extract_size_from_text(title)
    else
      size
    end
  end

  # Extracts size from text containing embedded size like "(3.05Gb)" or "500MB"
  defp extract_size_from_text(text) when is_binary(text) do
    # Match patterns like (3.05Gb), 500MB, 1.2 GB, etc.
    case Regex.run(~r/([\d.]+)\s*(gb|gib|mb|mib|kb|kib|tb|tib)/i, text) do
      [_, num_str, unit] ->
        case Float.parse(num_str) do
          {num, _} ->
            multiplier = size_unit_multiplier(String.downcase(unit))
            trunc(num * multiplier)

          :error ->
            0
        end

      nil ->
        0
    end
  end

  defp extract_size_from_text(_), do: 0

  defp size_unit_multiplier("tb"), do: 1024 * 1024 * 1024 * 1024
  defp size_unit_multiplier("tib"), do: 1024 * 1024 * 1024 * 1024
  defp size_unit_multiplier("gb"), do: 1024 * 1024 * 1024
  defp size_unit_multiplier("gib"), do: 1024 * 1024 * 1024
  defp size_unit_multiplier("mb"), do: 1024 * 1024
  defp size_unit_multiplier("mib"), do: 1024 * 1024
  defp size_unit_multiplier("kb"), do: 1024
  defp size_unit_multiplier("kib"), do: 1024
  defp size_unit_multiplier(_), do: 1

  @doc """
  Parses size strings to bytes.

  Supports various formats (case-insensitive):
  - "1.5 GB" → 1_610_612_736 bytes
  - "500 MB" → 524_288_000 bytes
  - "1024 KB" → 1_048_576 bytes
  - "1024" → 1024 bytes
  - "3.05Gb" → (lowercase units supported)

  ## Examples

      iex> parse_size("1.5 GB")
      1_610_612_736

      iex> parse_size("500 MB")
      524_288_000
  """
  @spec parse_size(String.t() | nil) :: non_neg_integer()
  def parse_size(nil), do: 0
  def parse_size(""), do: 0

  def parse_size(size_str) when is_binary(size_str) do
    size_str = String.trim(size_str)
    size_str_lower = String.downcase(size_str)

    cond do
      String.contains?(size_str_lower, "gb") || String.contains?(size_str_lower, "gib") ->
        parse_size_value(size_str, 1024 * 1024 * 1024)

      String.contains?(size_str_lower, "mb") || String.contains?(size_str_lower, "mib") ->
        parse_size_value(size_str, 1024 * 1024)

      String.contains?(size_str_lower, "kb") || String.contains?(size_str_lower, "kib") ->
        parse_size_value(size_str, 1024)

      String.contains?(size_str_lower, "tb") || String.contains?(size_str_lower, "tib") ->
        parse_size_value(size_str, 1024 * 1024 * 1024 * 1024)

      true ->
        # Assume it's already in bytes
        parse_integer(size_str)
    end
  end

  defp parse_size_value(size_str, multiplier) do
    # Extract numeric value from string, looking for patterns like "3.05Gb" or "500 MB"
    # First try to find a number immediately before or after the unit
    numeric_part =
      case Regex.run(~r/([\d.]+)\s*(?:gb|gib|mb|mib|kb|kib|tb|tib)/i, size_str) do
        [_, num] ->
          num

        nil ->
          # Fallback: just extract all digits and periods
          size_str
          |> String.replace(~r/[^\d.]/, "")
          |> String.trim()
      end

    case Float.parse(numeric_part) do
      {value, _} -> trunc(value * multiplier)
      :error -> 0
    end
  end

  defp parse_integer(nil), do: 0
  defp parse_integer(""), do: 0

  defp parse_integer(str) when is_binary(str) do
    # Remove any non-digit characters
    clean_str = String.replace(str, ~r/[^\d]/, "")

    case Integer.parse(clean_str) do
      {num, _} -> num
      :error -> 0
    end
  end

  defp parse_integer(num) when is_integer(num), do: num
  defp parse_integer(_), do: 0

  @doc """
  Parses date strings to DateTime.

  Attempts to parse various date formats:
  - ISO 8601: "2024-01-15T12:30:00Z"
  - Relative: "2 hours ago", "yesterday"
  - Custom formats based on common patterns

  ## Examples

      iex> parse_date("2024-01-15T12:30:00Z")
      ~U[2024-01-15 12:30:00Z]

      iex> parse_date(nil)
      nil
  """
  @spec parse_date(String.t() | nil) :: DateTime.t() | nil
  def parse_date(nil), do: nil
  def parse_date(""), do: nil

  def parse_date(date_str) when is_binary(date_str) do
    # Try ISO 8601 format first
    case DateTime.from_iso8601(date_str) do
      {:ok, datetime, _offset} ->
        datetime

      _ ->
        # Try other common formats using Timex
        case Timex.parse(date_str, "{ISO:Extended}") do
          {:ok, datetime} -> datetime
          _ -> nil
        end
    end
  rescue
    _ -> nil
  end

  # Download Protocol Detection
  # Detects protocol from URL: magnet/.torrent → :torrent, .nzb → :nzb
  # Defaults to :torrent as most Cardigann indexers are torrent sites
  defp detect_download_protocol(url) when is_binary(url) do
    cond do
      String.starts_with?(url, "magnet:") -> :torrent
      String.contains?(url, ".torrent") -> :torrent
      String.contains?(url, ".nzb") -> :nzb
      String.contains?(url, "nzb") -> :nzb
      true -> :torrent
    end
  end

  defp detect_download_protocol(_), do: :torrent

  # Response Type Detection

  defp detect_response_type(body) when is_binary(body) do
    trimmed = String.trim(body)

    cond do
      # Check if it looks like JSON (starts with { or [)
      String.starts_with?(trimmed, "{") || String.starts_with?(trimmed, "[") ->
        # Verify it's actually valid JSON before treating as JSON
        case Jason.decode(trimmed) do
          {:ok, _} -> :json
          {:error, _} -> :html
        end

      String.starts_with?(trimmed, "<") ->
        :html

      true ->
        # Default to HTML for ambiguous cases
        :html
    end
  end

  defp detect_response_type(_), do: :html
end
