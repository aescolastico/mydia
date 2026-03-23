defmodule Mydia.QueryHelpers do
  @moduledoc """
  Shared query helper functions used across context modules.
  """

  import Ecto.Query, warn: false

  @doc """
  Conditionally applies preloads to a query.

  Returns the query unchanged if preloads is `nil` or `[]`.
  """
  def maybe_preload(query, nil), do: query
  def maybe_preload(query, []), do: query
  def maybe_preload(query, preloads), do: preload(query, ^preloads)
end
