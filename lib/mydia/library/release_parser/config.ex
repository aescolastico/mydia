defmodule Mydia.Library.ReleaseParser.Config do
  @moduledoc """
  Named thresholds used by the V3 release parser.

  Downstream code (resolver, import gating, search-to-add UX) references
  these functions rather than literal numbers. This satisfies R3a from
  the plan ("named thresholds") and gives operators a single knob to
  tighten or loosen gating without code changes.

  Application configuration shape:

      config :mydia, :release_parser,
        commit_threshold: 0.75,
        suggest_threshold: 0.50

  Defaults match the plan's "Decision matrix" table.
  """

  @default_commit_threshold 0.75
  @default_suggest_threshold 0.50

  @doc """
  Confidence floor for "commit this parse without user review".

  Bound import flows (and any other automatic application) should only
  apply a field when `field_confidence.<field> >= commit_threshold/0`.
  """
  @spec commit_threshold() :: float()
  def commit_threshold do
    fetch(:commit_threshold, @default_commit_threshold)
  end

  @doc """
  Confidence floor for "show this parse as a UX suggestion".

  Below this floor the parser's output should be considered too weak to
  surface to a user.
  """
  @spec suggest_threshold() :: float()
  def suggest_threshold do
    fetch(:suggest_threshold, @default_suggest_threshold)
  end

  defp fetch(key, default) do
    :mydia
    |> Application.get_env(:release_parser, [])
    |> Keyword.get(key, default)
  end
end
