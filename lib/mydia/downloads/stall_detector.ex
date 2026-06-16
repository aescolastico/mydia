defmodule Mydia.Downloads.StallDetector do
  @moduledoc """
  Pure progress-tracking logic for the `DownloadMonitor` stall-detection circuit
  breaker (see issue #126 and the 2026-06-16 stall-resilience rework).

  The stall clock only accrues over *observed, actively-downloading* time. On
  each poll cycle the monitor passes in the download's persisted progress state
  plus the bytes-downloaded reported by the client, and this module returns a
  decision the monitor persists:

    * **Observation gap → reset.** If too much wall-clock has elapsed since the
      last observation (`last_observed_at`), the download was *not* observed for
      a stretch — a client outage, a Mydia restart, or a paused/queued torrent.
      We can't attribute that gap to a stall, so we reset the baseline
      (`last_progress_at = now`) and clear any in-flight soft-stall. This is the
      single mechanism that makes stall-detection resilient to outages.
    * **Progress → advance.** If the client reports a different byte count
      (more, or a regression from a client restart), the download made progress;
      advance `last_progress_at`/`last_known_bytes` and clear any soft-stall.
    * **Soft-stall.** If bytes are unchanged, the download was observed
      continuously (no gap), and `(now - last_progress_at)` exceeded the
      per-client grace window, we record a *recoverable* soft-stall
      (`stalled_since = now`). A soft-stall keeps occupying its episode — it is
      NOT a terminal `import_failed_at` failure — and auto-clears on resumed
      progress or a gap reset.
    * **Escalate.** A download that stays continuously soft-stalled past a
      separate, longer escalation threshold escalates to a terminal failure
      (the monitor sets `import_failed_at`, releasing the episode for re-search).
    * **Initialize.** First time we see a download (`last_progress_at` nil) we
      set the baseline and never flag stalled on first sight.

  This module is deliberately decoupled from Ecto / Oban so it can be unit
  tested with pure data. Persistence, escalation writes, and event emission stay
  in `Mydia.Jobs.DownloadMonitor`.
  """

  @type decision ::
          :no_change
          | {:initialize, now :: DateTime.t()}
          | {:reset, now :: DateTime.t()}
          | {:progress, new_bytes :: non_neg_integer(), now :: DateTime.t()}
          | {:soft_stall, message :: String.t(), now :: DateTime.t()}
          | {:escalate, message :: String.t(), now :: DateTime.t()}

  @doc """
  Decide what to do with a download whose progress we just observed.

  ## Parameters

    * `last_progress_at` — timestamp of the last bytes-downloaded increment, or
      `nil` for a download we have not tracked yet.
    * `last_known_bytes` — bytes-downloaded count at `last_progress_at`. May be
      `nil` if the row predates the column; treated as `0`.
    * `last_observed_at` — timestamp of the last poll in which this download was
      observed actively downloading, or `nil` for a row that predates the column
      (treated as a gap → reset).
    * `stalled_since` — timestamp the current soft-stall began, or `nil` if not
      soft-stalled.
    * `observed_bytes` — bytes-downloaded reported by the client right now.
    * `grace_minutes` — per-client incomplete grace window (positive integer).
    * `escalation_minutes` — how long a soft-stall may persist before escalating
      to a terminal failure (positive integer, larger than `grace_minutes`).
    * `gap_threshold_seconds` — an observation gap larger than this resets the
      stall clock (positive integer).
    * `now` — the current `DateTime` (injected for test determinism).

  ## Returned decisions

    * `:no_change` — nothing to persist beyond the monitor's unconditional
      `last_observed_at = now` stamp (includes holding an immature soft-stall).
    * `{:initialize, now}` — first observation. Set `last_progress_at = now` and
      `last_known_bytes = observed_bytes`.
    * `{:reset, now}` — observation gap. Set `last_progress_at = now`, clear
      `stalled_since`. The byte baseline is left as-is (bytes were unchanged).
    * `{:progress, observed_bytes, now}` — bytes changed. Set
      `last_progress_at = now`, `last_known_bytes = observed_bytes`, clear
      `stalled_since`.
    * `{:soft_stall, message, now}` — bytes unchanged past the grace window. Set
      `stalled_since = now`; leave `import_failed_at` nil (episode retained).
    * `{:escalate, message, now}` — soft-stalled past the escalation threshold.
      Set `import_failed_at = now` + `import_last_error = message` (terminal).

  Boundary semantics: a download whose baseline is EXACTLY `grace_minutes` old is
  *not yet* soft-stalled, and one stalled EXACTLY `escalation_minutes` is *not
  yet* escalated. Both checks use strict `>`.
  """
  @spec evaluate(
          DateTime.t() | nil,
          non_neg_integer() | nil,
          DateTime.t() | nil,
          DateTime.t() | nil,
          non_neg_integer(),
          pos_integer(),
          pos_integer(),
          pos_integer(),
          DateTime.t()
        ) :: decision()
  def evaluate(
        last_progress_at,
        last_known_bytes,
        last_observed_at,
        stalled_since,
        observed_bytes,
        grace_minutes,
        escalation_minutes,
        gap_threshold_seconds,
        now
      )
      when is_integer(observed_bytes) and observed_bytes >= 0 and
             is_integer(grace_minutes) and grace_minutes > 0 and
             is_integer(escalation_minutes) and escalation_minutes > 0 and
             is_integer(gap_threshold_seconds) and gap_threshold_seconds > 0 do
    known = last_known_bytes || 0

    cond do
      is_nil(last_progress_at) ->
        {:initialize, now}

      # Observation gap — the download was not observed for a stretch (outage,
      # restart, paused/queued). Reset the baseline rather than attribute the
      # gap to a stall, and clear any in-flight soft-stall (R2/R3).
      is_nil(last_observed_at) or
          DateTime.diff(now, last_observed_at, :second) > gap_threshold_seconds ->
        {:reset, now}

      # Bytes changed — progress (or a regression from a client restart). Either
      # way reset the clock so we never false-trip the stall window, and
      # auto-clear an in-flight soft-stall (R7).
      observed_bytes != known ->
        {:progress, observed_bytes, now}

      # Currently soft-stalled and observed continuously: either escalate (past
      # the longer threshold) or hold the soft-stall.
      not is_nil(stalled_since) ->
        if DateTime.diff(now, stalled_since, :second) > escalation_minutes * 60 do
          {:escalate, escalation_message(escalation_minutes), now}
        else
          :no_change
        end

      # Not yet stalled: enter a soft-stall once the grace window has elapsed.
      DateTime.diff(now, last_progress_at, :second) > grace_minutes * 60 ->
        {:soft_stall, stalled_message(grace_minutes), now}

      true ->
        :no_change
    end
  end

  @doc """
  Build the standardised soft-stall error message. The Downloads LiveView matches
  on the leading `"stalled"` substring to surface the badge.
  """
  @spec stalled_message(pos_integer()) :: String.t()
  def stalled_message(grace_minutes) when is_integer(grace_minutes) and grace_minutes > 0 do
    "stalled after #{grace_minutes}m without progress"
  end

  @doc """
  Build the terminal-escalation error message. Kept with a leading `"stalled"`
  prefix so `stalled?/1` and the LiveView badge continue to recognise it.
  """
  @spec escalation_message(pos_integer()) :: String.t()
  def escalation_message(escalation_minutes)
      when is_integer(escalation_minutes) and escalation_minutes > 0 do
    "stalled after #{escalation_minutes}m without progress — escalated to failure"
  end

  @doc """
  Test whether a download's `import_last_error` indicates a stalled state.
  Used by the LiveView badge helper.
  """
  @spec stalled?(String.t() | nil) :: boolean()
  def stalled?(nil), do: false

  def stalled?(error_message) when is_binary(error_message),
    do: String.starts_with?(error_message, "stalled")
end
