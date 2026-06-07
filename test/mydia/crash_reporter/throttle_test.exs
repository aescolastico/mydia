defmodule Mydia.CrashReporter.ThrottleTest do
  use ExUnit.Case, async: true

  alias Mydia.CrashReporter.Throttle

  # Each test starts its own isolated instance with a unique name so the
  # app-wide singleton's state is never shared across tests.
  defp start_throttle(opts) do
    name = :"throttle_#{System.unique_integer([:positive])}"
    start_supervised!({Throttle, Keyword.put(opts, :name, name)})
    name
  end

  test "allows up to the cap within a window" do
    t = start_throttle(window_ms: 60_000, max: 10)
    assert Enum.all?(1..10, fn _ -> Throttle.allow?(t) end)
  end

  test "denies once the cap is reached within a window" do
    t = start_throttle(window_ms: 60_000, max: 10)
    for _ <- 1..10, do: Throttle.allow?(t)
    refute Throttle.allow?(t)
    refute Throttle.allow?(t)
  end

  test "resets and allows again after the window elapses" do
    t = start_throttle(window_ms: 50, max: 2)
    assert Throttle.allow?(t)
    assert Throttle.allow?(t)
    refute Throttle.allow?(t)

    # Comfortably past the 50ms window so a loaded CI scheduler can't return
    # from sleep before the window has actually elapsed.
    Process.sleep(120)

    assert Throttle.allow?(t)
  end

  test "concurrent callers never exceed the cap in a window" do
    t = start_throttle(window_ms: 60_000, max: 10)

    grants =
      1..50
      |> Task.async_stream(fn _ -> Throttle.allow?(t) end,
        max_concurrency: 20,
        timeout: :infinity
      )
      |> Enum.count(fn {:ok, allowed} -> allowed end)

    assert grants == 10
  end
end
