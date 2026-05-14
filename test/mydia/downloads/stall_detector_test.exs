defmodule Mydia.Downloads.StallDetectorTest do
  use ExUnit.Case, async: true

  alias Mydia.Downloads.StallDetector

  @grace_minutes 60
  @base_time ~U[2026-01-01 12:00:00.000000Z]

  describe "evaluate/5 — first observation" do
    test "initializes last_progress_at when it is nil" do
      assert {:initialize, @base_time} =
               StallDetector.evaluate(nil, 0, 0, @grace_minutes, @base_time)
    end

    test "initializes even when bytes are already non-zero (fresh row mid-download)" do
      assert {:initialize, @base_time} =
               StallDetector.evaluate(nil, nil, 1_000_000, @grace_minutes, @base_time)
    end

    test "treats nil last_known_bytes the same as 0" do
      one_minute_later = DateTime.add(@base_time, 60, :second)

      assert {:progress, 500, ^one_minute_later} =
               StallDetector.evaluate(@base_time, nil, 500, @grace_minutes, one_minute_later)
    end
  end

  describe "evaluate/5 — progress" do
    test "returns :progress when bytes increased" do
      one_minute_later = DateTime.add(@base_time, 60, :second)

      assert {:progress, 200_000_000, ^one_minute_later} =
               StallDetector.evaluate(
                 @base_time,
                 100_000_000,
                 200_000_000,
                 @grace_minutes,
                 one_minute_later
               )
    end

    test "returns :progress even after a long pause if bytes finally increased" do
      two_hours_later = DateTime.add(@base_time, 2 * 60 * 60, :second)

      assert {:progress, 250, ^two_hours_later} =
               StallDetector.evaluate(@base_time, 100, 250, @grace_minutes, two_hours_later)
    end

    test "treats a byte regression as progress (resets the clock, never stalls)" do
      one_minute_later = DateTime.add(@base_time, 60, :second)

      # Bytes went DOWN (client restart, file replaced). We never want this to
      # be misread as a stall — reset the progress clock so the new lower
      # baseline is what we measure against.
      assert {:progress, 50, ^one_minute_later} =
               StallDetector.evaluate(@base_time, 100, 50, @grace_minutes, one_minute_later)
    end
  end

  describe "evaluate/5 — stall window" do
    test "no change when bytes unchanged within grace window" do
      five_minutes_later = DateTime.add(@base_time, 5 * 60, :second)

      assert :no_change =
               StallDetector.evaluate(
                 @base_time,
                 200_000_000,
                 200_000_000,
                 @grace_minutes,
                 five_minutes_later
               )
    end

    test "no change at the exact grace boundary (strict >, not >=)" do
      # Exactly @grace_minutes elapsed — not yet stalled.
      exactly_grace = DateTime.add(@base_time, @grace_minutes * 60, :second)

      assert :no_change =
               StallDetector.evaluate(
                 @base_time,
                 200_000_000,
                 200_000_000,
                 @grace_minutes,
                 exactly_grace
               )
    end

    test "stalled one second past the grace boundary" do
      just_past_grace = DateTime.add(@base_time, @grace_minutes * 60 + 1, :second)

      assert {:stalled, msg, ^just_past_grace} =
               StallDetector.evaluate(
                 @base_time,
                 200_000_000,
                 200_000_000,
                 @grace_minutes,
                 just_past_grace
               )

      assert msg == "stalled after 60m without progress"
    end

    test "stalled message reflects the configured grace window" do
      grace = 15
      past_grace = DateTime.add(@base_time, grace * 60 + 1, :second)

      assert {:stalled, "stalled after 15m without progress", ^past_grace} =
               StallDetector.evaluate(@base_time, 500, 500, grace, past_grace)
    end
  end

  describe "stalled?/1" do
    test "true for the canonical error message" do
      assert StallDetector.stalled?("stalled after 60m without progress")
    end

    test "true for any message starting with 'stalled'" do
      assert StallDetector.stalled?("stalled after 15m without progress")
    end

    test "false for unrelated error messages" do
      refute StallDetector.stalled?("Import failed: bad path")
      refute StallDetector.stalled?("Removed from download client 'qBit'")
    end

    test "false for nil" do
      refute StallDetector.stalled?(nil)
    end
  end

  describe "stalled_message/1" do
    test "interpolates the grace minutes" do
      assert StallDetector.stalled_message(60) == "stalled after 60m without progress"
      assert StallDetector.stalled_message(5) == "stalled after 5m without progress"
    end
  end
end
