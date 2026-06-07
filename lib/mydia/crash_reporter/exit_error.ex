defmodule Mydia.CrashReporter.ExitError do
  @moduledoc """
  Wraps a Tower `:exit` reason (a raw term) in an exception struct.

  `build_report/3` and `ErrorTracker.report/3` both require an exception, but
  Tower's `:exit` events carry an arbitrary term. Wrapping keeps the downstream
  pipeline unchanged and gives exits a distinct `error_type` for relay
  fingerprinting.
  """
  defexception [:reason]

  @impl Exception
  def message(%__MODULE__{reason: reason}), do: "(exit) " <> inspect(reason)
end
