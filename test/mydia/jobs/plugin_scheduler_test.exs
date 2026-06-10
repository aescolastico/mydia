defmodule Mydia.Jobs.PluginSchedulerTest do
  use Mydia.DataCase, async: true

  import Mydia.AccountsFixtures

  alias Mydia.Jobs.PluginScheduler
  alias Mydia.Plugins.Connections
  alias Mydia.Plugins.Error
  alias Mydia.Repo
  alias Mydia.Settings
  alias Mydia.Settings.PluginConfig

  # Creates a plugin config. opts: :interval (manifest schedule), :granted
  # (whether schedule:interval is granted), :last (last_scheduled_at), :failures.
  defp install!(slug, opts) do
    interval = Keyword.get(opts, :interval, 5)
    granted? = Keyword.get(opts, :granted, true)

    manifest = %{
      "slug" => slug,
      "name" => slug,
      "version" => "1.0.0",
      "capabilities" => %{
        "events:subscribe" => ["media_item.added"],
        "schedule:interval" => [],
        "users:connections" => []
      },
      "schedule" => %{"interval_minutes" => interval}
    }

    granted =
      if granted?,
        do: %{"schedule:interval" => [], "users:connections" => []},
        else: %{"users:connections" => []}

    {:ok, config} =
      Settings.create_plugin_config(%{
        slug: slug,
        name: slug,
        version: "1.0.0",
        source_url: "test",
        manifest: manifest,
        granted_capabilities: granted,
        enabled: true
      })

    attrs =
      [last_scheduled_at: opts[:last], consecutive_schedule_failures: opts[:failures] || 0]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    config |> Ecto.Changeset.change(Map.new(attrs)) |> Repo.update!()
  end

  defp reload(slug), do: Repo.get_by!(PluginConfig, slug: slug)

  # An invoker that records the slugs it was asked to run and returns `result`.
  defp recording_invoker(test_pid, result) do
    fn slug ->
      send(test_pid, {:invoked, slug})
      result
    end
  end

  test "effective_interval doubles with failures up to a cap" do
    assert PluginScheduler.effective_interval(5, 0) == 5
    assert PluginScheduler.effective_interval(5, 1) == 10
    assert PluginScheduler.effective_interval(5, 2) == 20
    # Capped at 2^4.
    assert PluginScheduler.effective_interval(5, 99) == 5 * 16
  end

  test "a never-run plugin is due and gets invoked" do
    install!("p", last: nil)
    PluginScheduler.tick(DateTime.utc_now(), recording_invoker(self(), {:ok, %{}}))
    assert_received {:invoked, "p"}
  end

  test "a recently-run plugin is not due" do
    recent = DateTime.utc_now() |> DateTime.add(-1, :minute)
    install!("p", interval: 30, last: recent)

    PluginScheduler.tick(DateTime.utc_now(), recording_invoker(self(), {:ok, %{}}))
    refute_received {:invoked, "p"}
  end

  test "a plugin without the schedule:interval grant never ticks (deny-by-default)" do
    install!("p", granted: false, last: nil)
    PluginScheduler.tick(DateTime.utc_now(), recording_invoker(self(), {:ok, %{}}))
    refute_received {:invoked, "p"}
  end

  test "success writes last_scheduled_at and resets the failure counter" do
    install!("p", last: nil, failures: 3)
    now = DateTime.utc_now()

    PluginScheduler.tick(now, recording_invoker(self(), {:ok, %{}}))

    config = reload("p")
    assert config.consecutive_schedule_failures == 0
    refute is_nil(config.last_scheduled_at)
  end

  test "failure increments the backoff counter" do
    install!("p", last: nil, failures: 1)

    PluginScheduler.tick(DateTime.utc_now(), fn _ -> {:error, :boom} end)

    assert reload("p").consecutive_schedule_failures == 2
  end

  test "a busy plugin is skipped, leaving its bookkeeping untouched" do
    install!("p", last: nil, failures: 2)

    PluginScheduler.tick(DateTime.utc_now(), fn _ ->
      {:error, %Error{type: :busy, message: "in flight"}}
    end)

    config = reload("p")
    # Untouched: no last_scheduled_at write, no failure bump.
    assert is_nil(config.last_scheduled_at)
    assert config.consecutive_schedule_failures == 2
  end

  test "backoff delays the next tick for a failing plugin" do
    # 5-min base, 2 failures -> effective 20 min. Last run 10 min ago: not due.
    ten_ago = DateTime.utc_now() |> DateTime.add(-10, :minute)
    install!("p", interval: 5, last: ten_ago, failures: 2)

    PluginScheduler.tick(DateTime.utc_now(), recording_invoker(self(), {:ok, %{}}))
    refute_received {:invoked, "p"}

    # 25 min ago: past the 20-min backoff window -> due.
    twentyfive_ago = DateTime.utc_now() |> DateTime.add(-25, :minute)
    reload("p") |> Ecto.Changeset.change(last_scheduled_at: twentyfive_ago) |> Repo.update!()

    PluginScheduler.tick(DateTime.utc_now(), recording_invoker(self(), {:ok, %{}}))
    assert_received {:invoked, "p"}
  end

  test "connections_invalid in a result errors only active connections" do
    install!("p", last: nil)
    user = user_fixture()
    {:ok, _} = Connections.connect("p", user.id, %{access_token: "t"})

    result = {:ok, %{"connections_invalid" => [user.id, "bogus-not-connected"]}}
    PluginScheduler.tick(DateTime.utc_now(), recording_invoker(self(), result))

    assert Connections.get("p", user.id).status == "error"
  end

  test "a disabled plugin never ticks" do
    config = install!("p", last: nil)
    config |> Ecto.Changeset.change(enabled: false) |> Repo.update!()

    PluginScheduler.tick(DateTime.utc_now(), recording_invoker(self(), {:ok, %{}}))
    refute_received {:invoked, "p"}
  end
end
