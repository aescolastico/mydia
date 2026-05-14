defmodule Mydia.CrashReporter.LoggerBackendTest do
  use ExUnit.Case, async: false

  require Logger

  alias Mydia.CrashReporter.{LoggerBackend, Queue}

  setup do
    # Re-enable the backend for this module; config/test.exs sets
    # :crash_reporter_disabled? to true to protect other test files.
    # This module is async: false so no other test file is affected.
    Application.put_env(:mydia, :crash_reporter_disabled?, false)
    System.put_env("CRASH_REPORTING_ENABLED", "true")
    original_relay = System.get_env("METADATA_RELAY_URL")
    # Point at an unreachable address so the Sender fails fast and reports
    # stay in the queue long enough to assert on. Port 1 is "tcpmux" and
    # typically refused immediately.
    System.put_env("METADATA_RELAY_URL", "http://127.0.0.1:1")

    Queue.clear_all()

    on_exit(fn ->
      Application.put_env(:mydia, :crash_reporter_disabled?, true)
      Queue.clear_all()
      System.delete_env("CRASH_REPORTING_ENABLED")

      case original_relay do
        nil -> System.delete_env("METADATA_RELAY_URL")
        url -> System.put_env("METADATA_RELAY_URL", url)
      end
    end)

    :ok
  end

  test "an error logged via Logger reaches the crash report queue" do
    Logger.error("integration smoke test",
      crash_reason: {%RuntimeError{message: "boom"}, []},
      file: "lib/mydia/synthetic.ex"
    )

    assert wait_until(fn -> Queue.count() >= 1 end)

    [%{report: report} | _] = Queue.list_all()
    assert report.error_type == "RuntimeError"
    assert report.error_message =~ "boom"
  end

  test "the backend is installed at application start" do
    # If this fails, Mydia.Application.start/2 stopped calling
    # LoggerBackends.add/1, or the :logger_backends dep was removed.
    assert LoggerBackend in :gen_event.which_handlers(LoggerBackends)
  end

  defp wait_until(fun, deadline_ms \\ 2_000, step_ms \\ 25)
  defp wait_until(_fun, deadline_ms, _step) when deadline_ms <= 0, do: false

  defp wait_until(fun, deadline_ms, step_ms) do
    if fun.() do
      true
    else
      Process.sleep(step_ms)
      wait_until(fun, deadline_ms - step_ms, step_ms)
    end
  end
end
