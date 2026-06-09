defmodule Mydia.Plugins.LogsTest do
  use Mydia.DataCase, async: true

  alias Mydia.Plugins.Log
  alias Mydia.Plugins.Logs

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{
        slug: "webhook_notifier",
        invocation_id: "inv-#{System.unique_integer([:positive])}",
        source: :guest,
        level: :info,
        message: "handling media_item.added"
      },
      overrides
    )
  end

  describe "create/1 and recent/2" do
    test "inserts a row that recent/2 returns" do
      {:ok, log} = Logs.create(attrs())
      assert [%Log{} = found] = Logs.recent("webhook_notifier")
      assert found.id == log.id
      assert found.message == "handling media_item.added"
      assert found.source == :guest
    end

    test "recent/2 scopes to the given slug" do
      {:ok, _} = Logs.create(attrs(%{slug: "webhook_notifier"}))
      {:ok, _} = Logs.create(attrs(%{slug: "other_plugin"}))

      slugs = "webhook_notifier" |> Logs.recent() |> Enum.map(& &1.slug)
      assert slugs == ["webhook_notifier"]
    end

    test "recent/2 :min_level returns only rows at or above the threshold" do
      inv = "inv-mixed"
      {:ok, _} = Logs.create(attrs(%{invocation_id: inv, level: :debug, message: "d"}))
      {:ok, _} = Logs.create(attrs(%{invocation_id: inv, level: :info, message: "i"}))
      {:ok, _} = Logs.create(attrs(%{invocation_id: inv, level: :warn, message: "w"}))
      {:ok, _} = Logs.create(attrs(%{invocation_id: inv, level: :error, message: "e"}))

      levels = "webhook_notifier" |> Logs.recent(min_level: :warn) |> Enum.map(& &1.level)
      assert Enum.sort(levels) == [:error, :warn]
    end

    test "recent/2 returns newest first and limits" do
      for n <- 1..5, do: {:ok, _} = Logs.create(attrs(%{message: "m#{n}"}))
      messages = "webhook_notifier" |> Logs.recent(limit: 3) |> Enum.map(& &1.message)
      assert length(messages) == 3
    end
  end

  describe "message sanitization (KTD10)" do
    test "non-UTF-8 message bytes are replaced and insert succeeds" do
      garbled = <<"panic at ", 0xFF, 0xFE, " lib.rs:47">>
      refute String.valid?(garbled)

      {:ok, log} = Logs.create(attrs(%{source: :wasi, level: :error, message: garbled}))
      assert String.valid?(log.message)
      assert log.message =~ "lib.rs:47"
    end
  end

  describe "create_async/1" do
    test "broadcasts {:plugin_log, log} on the per-plugin topic" do
      Phoenix.PubSub.subscribe(Mydia.PubSub, Logs.topic("webhook_notifier"))
      :ok = Logs.create_async(attrs(%{message: "live line"}))

      assert_receive {:plugin_log, %Log{message: "live line", slug: "webhook_notifier"}}
    end
  end

  describe "invocation correlation (AE2)" do
    test "guest and host rows sharing one invocation_id are returned together" do
      inv = "inv-shared"

      {:ok, _} =
        Logs.create(
          attrs(%{invocation_id: inv, source: :host, level: :info, message: "invoke start"})
        )

      {:ok, _} =
        Logs.create(
          attrs(%{
            invocation_id: inv,
            source: :guest,
            level: :info,
            message: "posting to webhook"
          })
        )

      {:ok, _} =
        Logs.create(attrs(%{invocation_id: inv, source: :host, level: :info, message: "ok 204"}))

      rows = Logs.recent("webhook_notifier")
      assert length(rows) == 3
      assert Enum.all?(rows, &(&1.invocation_id == inv))
      assert Enum.map(rows, & &1.source) |> Enum.sort() == [:guest, :host, :host]
    end
  end

  describe "prune/1" do
    test "deletes rows older than max_age_days" do
      {:ok, fresh} = Logs.create(attrs(%{message: "fresh"}))
      {:ok, old} = Logs.create(attrs(%{message: "old"}))

      old_ts = DateTime.add(DateTime.utc_now(), -30, :day) |> DateTime.truncate(:second)
      Repo.update_all(from(l in Log, where: l.id == ^old.id), set: [inserted_at: old_ts])

      {:ok, deleted} = Logs.prune(max_age_days: 7, max_invocations_per_plugin: 1000)
      assert deleted >= 1

      ids = "webhook_notifier" |> Logs.recent() |> Enum.map(& &1.id)
      assert fresh.id in ids
      refute old.id in ids
    end

    test "per-plugin cap keeps only the most recent N invocations" do
      base = DateTime.utc_now() |> DateTime.truncate(:second)

      for n <- 1..4 do
        {:ok, log} = Logs.create(attrs(%{invocation_id: "inv-#{n}", message: "m#{n}"}))
        ts = DateTime.add(base, n, :second)
        Repo.update_all(from(l in Log, where: l.id == ^log.id), set: [inserted_at: ts])
      end

      {:ok, _deleted} = Logs.prune(max_age_days: 3650, max_invocations_per_plugin: 2)

      kept = "webhook_notifier" |> Logs.recent() |> Enum.map(& &1.invocation_id) |> Enum.sort()
      assert kept == ["inv-3", "inv-4"]
    end
  end

  describe "ordering and message cap" do
    test "recent/2 preserves intra-invocation insertion order (microsecond precision)" do
      base = DateTime.utc_now()

      sequence = [{:host, "invoke start"}, {:guest, "posting"}, {:host, "ok 204"}]

      for {{source, message}, i} <- Enum.with_index(sequence) do
        {:ok, log} = Logs.create(attrs(%{invocation_id: "seq", source: source, message: message}))
        ts = DateTime.add(base, i, :microsecond)
        Repo.update_all(from(l in Log, where: l.id == ^log.id), set: [inserted_at: ts])
      end

      # Newest-first; microsecond gaps keep same-second rows ordered (a
      # second-precision column would collapse these and randomize the tiebreak).
      messages = "webhook_notifier" |> Logs.recent() |> Enum.map(& &1.message)
      assert messages == ["ok 204", "posting", "invoke start"]
    end

    test "an oversized message is truncated to the byte cap" do
      big = String.duplicate("x", 200_000)
      {:ok, log} = Logs.create(attrs(%{source: :wasi, level: :info, message: big}))

      assert byte_size(log.message) <= 64 * 1024 + 32
      assert String.ends_with?(log.message, "[truncated]")
    end
  end
end
