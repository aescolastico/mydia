defmodule Mydia.Plugins.Logs do
  @moduledoc """
  Context for per-invocation plugin debug logs (U1).

  Writes are fire-and-forget on hot paths (`create_async/1`) and broadcast on a
  per-plugin PubSub topic so the admin detail view can live-tail. Reads
  (`recent/2`) back the detail timeline. Retention (`prune/1`) is driven by the
  `Mydia.Jobs.PluginLogCleanup` cron (U5).

  The async insert split (sync under the SQL sandbox, `Task.Supervisor` in prod)
  and the broadcast shape mirror `Mydia.Events` so the two activity surfaces
  behave identically.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Mydia.Repo
  alias Mydia.Plugins.Log
  alias Phoenix.PubSub

  @pubsub_name Mydia.PubSub

  @doc "PubSub topic carrying `{:plugin_log, %Log{}}` for a single plugin."
  @spec topic(String.t()) :: String.t()
  def topic(slug) when is_binary(slug), do: "plugin_logs:" <> slug

  @doc """
  Inserts a log row and broadcasts it. Synchronous; returns the insert result.
  """
  @spec create(map()) :: {:ok, Log.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %Log{}
    |> Log.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, log} = result ->
        broadcast(log)
        result

      error ->
        error
    end
  end

  @doc """
  Inserts a log row without blocking the caller (fire-and-forget).

  Under the SQL sandbox (test) this runs synchronously to avoid cross-process
  connection-ownership issues; in production it runs in a supervised Task.
  """
  @spec create_async(map()) :: :ok
  def create_async(attrs) do
    if Repo.config()[:pool] == Ecto.Adapters.SQL.Sandbox do
      # Under the sandbox, insert synchronously. Guard against a missing
      # connection ownership (e.g. a caller with no checked-out sandbox conn, or
      # the instance process running a guest `log` call): logging must never
      # crash the invocation it is observing.
      try do
        insert_logged(attrs)
      rescue
        e -> Logger.debug("plugin log skipped: #{Exception.message(e)}")
      end
    else
      Task.Supervisor.start_child(Mydia.TaskSupervisor, fn -> insert_logged(attrs) end)
    end

    :ok
  end

  defp insert_logged(attrs) do
    case create(attrs) do
      {:ok, _log} ->
        :ok

      {:error, changeset} ->
        Logger.error("plugin log insert failed: #{inspect(changeset.errors)}")
    end
  end

  @doc """
  Lists recent log rows for `slug`, newest first.

  ## Options

    * `:min_level` - only return rows at or above this level
      (`:debug`/`:info`/`:warn`/`:error`); defaults to `:debug` (all rows). The
      threshold is uniform across sources, so an `error`-level host trap marker
      always surfaces.
    * `:limit` - maximum rows to return (default 200)
  """
  @spec recent(String.t(), keyword()) :: [Log.t()]
  def recent(slug, opts \\ []) when is_binary(slug) do
    limit = Keyword.get(opts, :limit, 200)

    Log
    |> where([l], l.slug == ^slug)
    |> maybe_filter_level(Keyword.get(opts, :min_level))
    |> order_by([l], desc: l.inserted_at, desc: l.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_filter_level(query, nil), do: query
  defp maybe_filter_level(query, :debug), do: query

  defp maybe_filter_level(query, level) when level in [:info, :warn, :error] do
    keep = for l <- Log.levels(), Log.level_rank(l) >= Log.level_rank(level), do: l
    where(query, [l], l.level in ^keep)
  end

  @doc """
  Prunes log rows by retention policy. Returns `{:ok, deleted_count}`.

  ## Options

    * `:max_age_days` - delete rows older than this many days (default 7)
    * `:max_invocations_per_plugin` - per plugin, keep only the most recent N
      invocations' rows (default 200)

  Both policies apply. Set logic (which invocations exceed the cap) runs in
  Elixir so the delete query stays portable across SQLite and Postgres.
  """
  @spec prune(keyword()) :: {:ok, non_neg_integer()}
  def prune(opts \\ []) do
    max_age_days = Keyword.get(opts, :max_age_days, 7)
    max_invocations = Keyword.get(opts, :max_invocations_per_plugin, 200)

    aged = prune_by_age(max_age_days)
    capped = prune_by_invocation_cap(max_invocations)

    {:ok, aged + capped}
  end

  defp prune_by_age(days) when is_integer(days) and days > 0 do
    cutoff = DateTime.add(DateTime.utc_now(), -days, :day)

    {count, _} =
      Log
      |> where([l], l.inserted_at < ^cutoff)
      |> Repo.delete_all()

    count
  end

  defp prune_by_age(_), do: 0

  defp prune_by_invocation_cap(max) when is_integer(max) and max > 0 do
    # For each plugin, rank invocations by their most-recent line; the
    # invocations beyond the cap are deleted. Ranking happens in Elixir to keep
    # the query engine-agnostic (no window functions).
    stale_invocations =
      Log
      |> group_by([l], [l.slug, l.invocation_id])
      |> select([l], {l.slug, l.invocation_id, max(l.inserted_at)})
      |> Repo.all()
      |> Enum.group_by(fn {slug, _inv, _ts} -> slug end)
      |> Enum.flat_map(fn {_slug, invs} ->
        invs
        |> Enum.sort_by(fn {_slug, _inv, ts} -> ts end, {:desc, DateTime})
        |> Enum.drop(max)
        |> Enum.map(fn {_slug, inv, _ts} -> inv end)
      end)

    case stale_invocations do
      [] ->
        0

      ids ->
        {count, _} =
          Log
          |> where([l], l.invocation_id in ^ids)
          |> Repo.delete_all()

        count
    end
  end

  defp prune_by_invocation_cap(_), do: 0

  defp broadcast(%Log{} = log) do
    PubSub.broadcast(@pubsub_name, topic(log.slug), {:plugin_log, log})
  end
end
