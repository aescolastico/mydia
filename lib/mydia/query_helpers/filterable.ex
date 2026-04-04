defmodule Mydia.QueryHelpers.Filterable do
  @moduledoc """
  Macro that generates `apply_filters/2` (or a custom-named function) from a
  declarative filter specification.

  ## Usage

      use Mydia.QueryHelpers.Filterable,
        function_name: :apply_collection_filters,
        filters: [
          type: {:eq, values: ["manual", "smart"]},
          visibility: {:eq, values: ["private", "shared"]}
        ]

  ## Supported filter types

    * `:eq`       — equality (`field == ^val`). Skips nil values.
    * `{:eq, values: list}` — equality with an allowlist guard.
    * `:ilike`    — case-insensitive LIKE (`%term%`). Skips nil and `""`.
    * `:boolean`  — equality with `is_boolean` guard.
    * `:gte`      — greater-than-or-equal (`field >= ^val`). Skips nil.
    * `:lte`      — less-than-or-equal (`field <= ^val`). Skips nil.

  Filters whose value is `nil` (or `""` for `:ilike`) are silently skipped.
  Unknown option keys fall through the catch-all and are ignored.

  Complex filters (joins, subqueries, multi-field search) should remain as
  manual `defp` functions alongside the generated one.
  """

  defmacro __using__(opts) do
    filters = Keyword.fetch!(opts, :filters)
    function_name = Keyword.get(opts, :function_name, :apply_filters)
    clause_name = :"__#{function_name}_clause__"

    filter_clauses =
      Enum.flat_map(filters, fn {field, spec} ->
        normalized = normalize_spec(spec)
        build_clause(clause_name, field, normalized)
      end)

    catch_all =
      quote do
        defp unquote(clause_name)(_other, query), do: query
      end

    main_fn =
      quote do
        defp unquote(function_name)(query, opts) do
          Enum.reduce(opts, query, fn opt, acc ->
            unquote(clause_name)(opt, acc)
          end)
        end
      end

    import_stmt =
      quote do
        import Ecto.Query, warn: false
      end

    [import_stmt | filter_clauses] ++ [catch_all, main_fn]
  end

  @doc false
  def normalize_spec(:eq), do: %{type: :eq, values: nil}
  def normalize_spec(:ilike), do: %{type: :ilike}
  def normalize_spec(:boolean), do: %{type: :boolean}
  def normalize_spec(:gte), do: %{type: :gte}
  def normalize_spec(:lte), do: %{type: :lte}

  def normalize_spec({:eq, kw}) do
    %{type: :eq, values: Keyword.get(kw, :values)}
  end

  @doc false
  def build_clause(clause_name, field, %{type: :eq, values: nil}) do
    [
      quote do
        defp unquote(clause_name)({unquote(field), val}, query) when not is_nil(val) do
          where(query, [r], field(r, unquote(field)) == ^val)
        end
      end
    ]
  end

  def build_clause(clause_name, field, %{type: :eq, values: values}) when is_list(values) do
    [
      quote do
        defp unquote(clause_name)({unquote(field), val}, query)
             when val in unquote(values) do
          where(query, [r], field(r, unquote(field)) == ^val)
        end
      end
    ]
  end

  def build_clause(clause_name, field, %{type: :ilike}) do
    [
      quote do
        defp unquote(clause_name)({unquote(field), val}, query)
             when is_binary(val) and val != "" do
          pattern = "%#{String.downcase(val)}%"
          where(query, [r], like(fragment("lower(?)", field(r, unquote(field))), ^pattern))
        end
      end
    ]
  end

  def build_clause(clause_name, field, %{type: :boolean}) do
    [
      quote do
        defp unquote(clause_name)({unquote(field), val}, query) when is_boolean(val) do
          where(query, [r], field(r, unquote(field)) == ^val)
        end
      end
    ]
  end

  def build_clause(clause_name, field, %{type: :gte}) do
    [
      quote do
        defp unquote(clause_name)({unquote(field), val}, query) when not is_nil(val) do
          where(query, [r], field(r, unquote(field)) >= ^val)
        end
      end
    ]
  end

  def build_clause(clause_name, field, %{type: :lte}) do
    [
      quote do
        defp unquote(clause_name)({unquote(field), val}, query) when not is_nil(val) do
          where(query, [r], field(r, unquote(field)) <= ^val)
        end
      end
    ]
  end
end
