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
    * `:boolean`  — equality with `is_boolean` guard.

  Unknown option keys fall through the catch-all and are ignored, so callers
  can pass extra opts like `:preload`, `:limit`, etc. alongside filter opts.

  ## Binding constraint

  Generated filters always reference the **first positional binding** of the
  query (`[r]`). This is safe for queries with a single source, but will
  target the wrong binding if the caller composes the filter with a query
  that has joins or reordered bindings. For such queries, keep the filter
  function hand-written.

  Likewise, complex filters (joins, subqueries, multi-field search) should
  remain as manual `defp` functions alongside the generated one.

  ## Nil handling

  Unlike naive `Enum.reduce/3` reducers, the generated clauses carry
  `when not is_nil(val)` guards for `:eq`, and `when is_boolean(val)` for
  `:boolean`. Passing `nil` leaves the query unchanged (returns all rows)
  rather than producing `WHERE col = NULL` (which matches no rows). Callers
  that relied on the latter must guard at the call site.

  ## Extending

  Additional filter types (`:ilike`, `:gte`, `:lte`, etc.) can be added by
  extending `normalize_spec/1` and `build_clause/3`. Only types with actual
  callers are implemented today.
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
  def normalize_spec(:boolean), do: %{type: :boolean}

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

  def build_clause(clause_name, field, %{type: :boolean}) do
    [
      quote do
        defp unquote(clause_name)({unquote(field), val}, query) when is_boolean(val) do
          where(query, [r], field(r, unquote(field)) == ^val)
        end
      end
    ]
  end
end
