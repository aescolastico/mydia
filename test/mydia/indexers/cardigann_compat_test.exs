defmodule Mydia.Indexers.CardigannCompatTest do
  use ExUnit.Case, async: true

  alias Mydia.Indexers.CardigannCompat

  describe "implemented_filters/0" do
    test "returns a list of strings" do
      filters = CardigannCompat.implemented_filters()
      assert is_list(filters)
      assert Enum.all?(filters, &is_binary/1)
    end

    test "includes known implemented filters" do
      filters = CardigannCompat.implemented_filters()
      assert "replace" in filters
      assert "re_replace" in filters
      assert "append" in filters
      assert "prepend" in filters
      assert "trim" in filters
      assert "split" in filters
      assert "urldecode" in filters
    end
  end

  describe "analyze_definition/2" do
    test "reports fully compatible definition with no filters" do
      yaml = minimal_definition()
      result = CardigannCompat.analyze_definition(yaml, "test.yml")

      assert result.status == :fully_compatible
      assert result.filters_used == []
      assert result.missing_filters == []
      assert result.error == nil
    end

    test "reports fully compatible definition with implemented filters" do
      yaml =
        definition_with_filters([
          %{"name" => "trim"},
          %{"name" => "replace", "args" => ["foo", "bar"]}
        ])

      result = CardigannCompat.analyze_definition(yaml, "test.yml")

      assert result.status == :fully_compatible
      assert "trim" in result.filters_used
      assert "replace" in result.filters_used
      assert result.missing_filters == []
    end

    test "reports partially compatible definition with missing filters" do
      yaml =
        definition_with_filters([
          %{"name" => "trim"},
          %{"name" => "validfilename"},
          %{"name" => "diacritics"}
        ])

      result = CardigannCompat.analyze_definition(yaml, "test.yml")

      assert result.status == :partially_compatible
      assert "trim" in result.filters_used
      assert "validfilename" in result.filters_used
      assert "diacritics" in result.filters_used
      assert "validfilename" in result.missing_filters
      assert "diacritics" in result.missing_filters
      refute "trim" in result.missing_filters
    end

    test "reports parse_failed for invalid YAML" do
      result = CardigannCompat.analyze_definition("not: valid: yaml: [", "broken.yml")

      assert result.status == :parse_failed
      assert result.error != nil
    end

    test "reports parse_failed for YAML missing required fields" do
      yaml = """
      id: test
      name: Test
      """

      result = CardigannCompat.analyze_definition(yaml, "incomplete.yml")

      assert result.status == :parse_failed
      assert result.error != nil
    end

    test "extracts definition name and id" do
      yaml = minimal_definition()
      result = CardigannCompat.analyze_definition(yaml, "test.yml")

      assert result.name == "Test Indexer"
      assert result.id == "testindexer"
    end
  end

  describe "extract_filters_from_parsed/1" do
    test "extracts filters from search fields" do
      parsed = %{
        search: %{
          fields: %{
            title: %{
              selector: "td:nth-child(1)",
              filters: [
                %{name: "trim"},
                %{name: "replace", args: [" ", "-"]}
              ]
            },
            size: %{
              selector: "td:nth-child(2)",
              filters: [%{name: "append", args: [" MB"]}]
            }
          }
        }
      }

      filters = CardigannCompat.extract_filters_from_parsed(parsed)

      assert length(filters) == 3
      assert Enum.any?(filters, &(&1.name == "trim" and &1.field == "title"))
      assert Enum.any?(filters, &(&1.name == "replace" and &1.field == "title"))
      assert Enum.any?(filters, &(&1.name == "append" and &1.field == "size"))
    end

    test "handles fields with no filters" do
      parsed = %{
        search: %{
          fields: %{
            title: %{selector: "td:nth-child(1)"},
            size: %{selector: "td:nth-child(2)", filters: []}
          }
        }
      }

      filters = CardigannCompat.extract_filters_from_parsed(parsed)
      assert filters == []
    end

    test "handles string-keyed filters" do
      parsed = %{
        search: %{
          fields: %{
            title: Map.merge(%{selector: "td"}, %{"filters" => [%{"name" => "trim"}]})
          }
        }
      }

      filters = CardigannCompat.extract_filters_from_parsed(parsed)
      assert length(filters) == 1
      assert hd(filters).name == "trim"
    end
  end

  describe "extract_filters_from_yaml/1" do
    test "extracts filter names from raw YAML string" do
      yaml =
        definition_with_filters([
          %{"name" => "trim"},
          %{"name" => "dateparse", "args" => ["Mon, 02 Jan 2006 15:04:05 -0700"]},
          %{"name" => "regexp", "args" => ["(\\d+)"]}
        ])

      filters = CardigannCompat.extract_filters_from_yaml(yaml)

      assert "trim" in filters
      assert "dateparse" in filters
      assert "regexp" in filters
    end

    test "returns empty list for invalid YAML" do
      assert CardigannCompat.extract_filters_from_yaml("invalid: [yaml: broken") == []
    end

    test "returns empty list for YAML with no search section" do
      yaml = """
      id: test
      name: Test
      """

      assert CardigannCompat.extract_filters_from_yaml(yaml) == []
    end
  end

  # Helper to generate a minimal valid Cardigann definition YAML
  defp minimal_definition do
    """
    id: testindexer
    name: Test Indexer
    description: A test indexer for compatibility analysis
    language: en-US
    type: public
    encoding: UTF-8
    links:
      - https://example.com
    caps:
      modes:
        search: [q]
      categories:
        TV:
          - 5000
    search:
      path: /search
      rows:
        selector: table > tbody > tr
      fields:
        title:
          selector: td:nth-child(1)
        size:
          selector: td:nth-child(2)
        seeders:
          selector: td:nth-child(3)
        leechers:
          selector: td:nth-child(4)
        download:
          selector: td:nth-child(1) a
          attribute: href
    """
  end

  # Helper to generate a definition with specific filters on the title field
  defp definition_with_filters(filters) do
    filters_yaml =
      Enum.map_join(filters, "\n", fn filter ->
        args = Map.get(filter, "args")

        if args do
          args_yaml = Enum.map_join(args, ", ", &inspect/1)
          "          - name: #{filter["name"]}\n            args: [#{args_yaml}]"
        else
          "          - name: #{filter["name"]}"
        end
      end)

    """
    id: testindexer
    name: Test Indexer
    description: A test indexer for compatibility analysis
    language: en-US
    type: public
    encoding: UTF-8
    links:
      - https://example.com
    caps:
      modes:
        search: [q]
      categories:
        TV:
          - 5000
    search:
      path: /search
      rows:
        selector: table > tbody > tr
      fields:
        title:
          selector: td:nth-child(1)
          filters:
    #{filters_yaml}
        size:
          selector: td:nth-child(2)
        seeders:
          selector: td:nth-child(3)
        leechers:
          selector: td:nth-child(4)
        download:
          selector: td:nth-child(1) a
          attribute: href
    """
  end
end
