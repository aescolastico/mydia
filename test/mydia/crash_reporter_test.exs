defmodule Mydia.CrashReporterTest do
  use Mydia.DataCase, async: false

  alias Mydia.CrashReporter

  describe "stats/0" do
    test "tracked_errors counts errors stored locally by ErrorTracker" do
      assert CrashReporter.stats().tracked_errors == 0

      insert_error()
      insert_error()

      assert CrashReporter.stats().tracked_errors == 2
    end

    test "tracked_errors is 0 when no errors are stored" do
      assert CrashReporter.stats().tracked_errors == 0
    end

    test "does not expose a :sent_reports key" do
      refute Map.has_key?(CrashReporter.stats(), :sent_reports)
    end

    test "still returns enabled, queued_reports, and metadata_relay_url" do
      stats = CrashReporter.stats()

      assert is_boolean(stats.enabled)
      assert is_integer(stats.queued_reports)
      assert is_binary(stats.metadata_relay_url)
    end
  end

  defp insert_error do
    Mydia.Repo.insert!(%ErrorTracker.Error{
      kind: "RuntimeError",
      reason: "boom #{System.unique_integer([:positive])}",
      source_line: "lib/foo.ex:1",
      source_function: "Foo.bar/0",
      status: :unresolved,
      # ErrorTracker stores the fingerprint as a Base16 string (the column is a
      # NOT NULL unique string); raw bytes break Postgres' UTF-8 encoding.
      fingerprint: Base.encode16(:crypto.strong_rand_bytes(8)),
      last_occurrence_at: DateTime.utc_now()
    })
  end
end
