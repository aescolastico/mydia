defmodule Mydia.Jobs.PluginLogCleanupTest do
  use Mydia.DataCase, async: true

  alias Mydia.Plugins.Log
  alias Mydia.Plugins.Logs
  alias Mydia.Jobs.PluginLogCleanup

  defp log(overrides) do
    {:ok, l} =
      Logs.create(
        Map.merge(
          %{
            slug: "webhook_notifier",
            invocation_id: "inv-#{System.unique_integer([:positive])}",
            source: :host,
            level: :info,
            message: "marker"
          },
          overrides
        )
      )

    l
  end

  test "perform/1 prunes rows older than the configured age" do
    fresh = log(%{message: "fresh"})
    old = log(%{message: "old"})

    old_ts = DateTime.add(DateTime.utc_now(), -30, :day) |> DateTime.truncate(:second)
    Repo.update_all(from(l in Log, where: l.id == ^old.id), set: [inserted_at: old_ts])

    assert :ok = PluginLogCleanup.perform(%Oban.Job{args: %{"max_age_days" => 7}})

    ids = "webhook_notifier" |> Logs.recent() |> Enum.map(& &1.id)
    assert fresh.id in ids
    refute old.id in ids
  end

  test "perform/1 runs cleanly on an empty table" do
    assert :ok = PluginLogCleanup.perform(%Oban.Job{args: %{}})
  end
end
