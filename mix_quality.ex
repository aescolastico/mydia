defmodule MydiaQuality do
  @moduledoc """
  Build-time helpers for the code-quality gates.

  Used by `mix.exs` to configure `mix_unused`. Lives outside `lib/` so it is
  not shipped in the release and is not itself analysed for dead code.
  """

  @doc """
  True when `{module, fun, arity}` is a behaviour callback implemented by
  `module` - that is, `module` declares `@behaviour B` and `{fun, arity}` is
  one of `B`'s callbacks.

  Behaviour callbacks are dispatched by the framework that owns the behaviour
  (Guardian, Plug, telemetry, the app's own `@behaviour`s), so static export
  analysis cannot see the call site and flags them as unused. This predicate is
  a *rule about tool blindness*: it auto-covers every current and future
  callback implementation rather than enumerating individual findings.
  """
  @spec behaviour_callback?({module(), atom(), arity()}) :: boolean()
  def behaviour_callback?({module, fun, arity}) do
    module
    |> implemented_behaviours()
    |> Enum.any?(&callback?(&1, fun, arity))
  end

  defp implemented_behaviours(module) do
    if Code.ensure_loaded?(module) do
      module.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()
    else
      []
    end
  rescue
    _ -> []
  end

  defp callback?(behaviour, fun, arity) do
    Code.ensure_loaded?(behaviour) and
      function_exported?(behaviour, :behaviour_info, 1) and
      {fun, arity} in behaviour.behaviour_info(:callbacks)
  rescue
    _ -> false
  end
end
