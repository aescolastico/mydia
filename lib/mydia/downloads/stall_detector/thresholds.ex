defmodule Mydia.Downloads.StallDetector.Thresholds do
  @moduledoc """
  Config thresholds for `Mydia.Downloads.StallDetector.evaluate/7`.

  Bundles the three per-poll tuning knobs so the evaluator keeps a small arity
  and callers pass an explicit, self-documenting config value:

    * `grace_minutes` — per-client incomplete grace window before a continuously
      observed, byte-stalled download enters a recoverable soft-stall.
    * `escalation_minutes` — how long a soft-stall may persist before escalating
      to a terminal failure (larger than `grace_minutes`).
    * `gap_threshold_seconds` — an observation gap larger than this resets the
      stall clock (outage / restart / paused torrent).
  """

  @enforce_keys [:grace_minutes, :escalation_minutes, :gap_threshold_seconds]
  defstruct [:grace_minutes, :escalation_minutes, :gap_threshold_seconds]

  @type t :: %__MODULE__{
          grace_minutes: pos_integer(),
          escalation_minutes: pos_integer(),
          gap_threshold_seconds: pos_integer()
        }
end
