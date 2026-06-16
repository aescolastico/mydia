defmodule Mydia.CrashReporter.ThrowError do
  @moduledoc """
  Wraps a Tower `:throw` value (a raw term) in an exception struct.

  See `Mydia.CrashReporter.ExitError` for the rationale; this gives throws a
  distinct `error_type` for relay fingerprinting.
  """
  defexception [:value]

  @impl Exception
  def message(%__MODULE__{value: value}),
    do: "(throw) " <> inspect(value, limit: 50, printable_limit: 4096)
end
