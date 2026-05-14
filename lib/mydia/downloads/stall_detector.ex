defmodule Mydia.Downloads.StallDetector do
  @moduledoc """
  Pure progress-tracking logic for the `DownloadMonitor` stall-detection circuit
  breaker (see issue #126).

  On each poll cycle the monitor compares the bytes-downloaded reported by the
  client against the `last_known_bytes` stored on the `Download` row:

    * If the client reports MORE bytes, the download made progress — bump
      `last_progress_at` and `last_known_bytes`.
    * If the client reports the SAME bytes AND `(now - last_progress_at)` has
      exceeded the per-client `incomplete_grace_minutes`, the download is
      considered stalled. We flag it with `import_failed_at` + a
      `"stalled after Nm without progress"` error message. The `:status` column
      is intentionally NOT updated — that field is not cast on
      `Download.changeset/2` (known bug, out of scope for #126).
    * If `last_progress_at` is `nil` (a fresh download we have not observed
      yet), initialize it to `now`. We never flag a download as stalled on
      first sight; the grace window has to elapse.

  This module is deliberately decoupled from Ecto / Oban so it can be unit
  tested with pure data.
  """

  @type decision ::
          :no_change
          | {:progress, new_bytes :: non_neg_integer(), now :: DateTime.t()}
          | {:initialize, now :: DateTime.t()}
          | {:stalled, error_message :: String.t(), now :: DateTime.t()}

  @doc """
  Decide what to do with a download whose progress we just observed.

  ## Parameters

    * `last_progress_at` — timestamp of the last bytes-downloaded increment, or
      `nil` for a download we have not tracked yet.
    * `last_known_bytes` — bytes-downloaded count at `last_progress_at`. May be
      `nil` if the row was created before the column existed; treated as `0`.
    * `observed_bytes` — bytes-downloaded reported by the client right now.
    * `grace_minutes` — per-client incomplete grace window (positive integer).
    * `now` — the current `DateTime` (injected for test determinism).

  ## Returned decisions

    * `:no_change` — bytes unchanged and within grace window. Caller should do
      nothing.
    * `{:initialize, now}` — first observation of this download. Caller should
      set `last_progress_at = now` and `last_known_bytes = observed_bytes`.
    * `{:progress, observed_bytes, now}` — bytes increased. Caller should set
      `last_progress_at = now` and `last_known_bytes = observed_bytes`.
    * `{:stalled, error_message, now}` — bytes unchanged AND
      `now - last_progress_at > grace_minutes`. Caller should set
      `import_failed_at = now` and `import_last_error = error_message`.

  Boundary semantics: a download whose `last_progress_at` is EXACTLY
  `grace_minutes` old is *not yet* stalled. The check uses strict `>`.
  """
  @spec evaluate(
          DateTime.t() | nil,
          non_neg_integer() | nil,
          non_neg_integer(),
          pos_integer(),
          DateTime.t()
        ) :: decision()
  def evaluate(last_progress_at, last_known_bytes, observed_bytes, grace_minutes, now)
      when is_integer(observed_bytes) and observed_bytes >= 0 and
             is_integer(grace_minutes) and grace_minutes > 0 do
    known = last_known_bytes || 0

    cond do
      is_nil(last_progress_at) ->
        {:initialize, now}

      observed_bytes > known ->
        {:progress, observed_bytes, now}

      observed_bytes < known ->
        # Bytes regressed (rare: client restart, file replaced). Treat as fresh
        # progress so we don't false-trip the stall window.
        {:progress, observed_bytes, now}

      true ->
        elapsed_seconds = DateTime.diff(now, last_progress_at, :second)
        grace_seconds = grace_minutes * 60

        if elapsed_seconds > grace_seconds do
          {:stalled, stalled_message(grace_minutes), now}
        else
          :no_change
        end
    end
  end

  @doc """
  Build the standardised stalled error message. Other modules (notably the
  Downloads LiveView) match on the leading `"stalled "` substring to surface
  the badge.
  """
  @spec stalled_message(pos_integer()) :: String.t()
  def stalled_message(grace_minutes) when is_integer(grace_minutes) and grace_minutes > 0 do
    "stalled after #{grace_minutes}m without progress"
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
