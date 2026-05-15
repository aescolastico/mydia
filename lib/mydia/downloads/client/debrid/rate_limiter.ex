defmodule Mydia.Downloads.Client.Debrid.RateLimiter do
  @moduledoc """
  Sliding-window rate limiter for outbound calls to debrid providers.

  Keyed by `{provider :: atom, api_key :: String.t()}` so that two operators
  configured against the same provider with different API tokens don't share
  a budget, and a single operator's two-provider setup (e.g., RD + AD) has
  isolated budgets.

  Mirrors the shape of `Mydia.Indexers.RateLimiter` — ETS-backed sliding
  window, volatile across restarts. Burst-after-restart mitigation lives
  in the `Fetcher` (each fetcher jitters its first call by 0-30s); the
  limiter itself starts with an empty window after a restart.

  Each provider exposes its budget via the `rate_limit_budget/0` callback
  on `Mydia.Downloads.Client.Debrid.Provider` (RD `{250, 60}`,
  AD `{600, 60}`, PM `{30, 60}` conservative, TB `{300, 60}` per endpoint).
  """

  use GenServer
  require Logger

  @table_name :debrid_rate_limits
  @cleanup_interval :timer.minutes(5)

  @typedoc "Provider key (`:real_debrid | :all_debrid | :premiumize | :tor_box`)"
  @type provider :: atom()

  @typedoc "Tuple form of `{requests, per_seconds}` returned by `Provider.rate_limit_budget/0`"
  @type budget :: {pos_integer(), pos_integer()}

  ## Client API

  @doc "Starts the limiter GenServer."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Attempts to acquire a slot for the `{provider, api_key}` tuple against
  the supplied budget. Returns `:ok` if the slot is taken; `{:error,
  :rate_limited}` otherwise.

  Records the slot immediately on success — callers do not need a separate
  `record/2` call. This is the conservative ordering: the alternative
  (acquire-then-call-then-record) creates a race where two concurrent
  callers both acquire under-budget.
  """
  @spec acquire(provider(), String.t() | nil, budget()) ::
          :ok | {:error, :rate_limited}
  def acquire(provider, api_key, {requests, window_seconds} = budget)
      when is_atom(provider) and is_integer(requests) and requests > 0 and
             is_integer(window_seconds) and window_seconds > 0 do
    GenServer.call(__MODULE__, {:acquire, provider, api_key, budget})
  rescue
    # GenServer not running (e.g., during boot or in tests that haven't
    # started the GenServer). Fail open — better to over-permit briefly
    # than to block the entire pipeline.
    _ -> :ok
  catch
    # `GenServer.call/2` to a non-existent process emits an `:exit` signal,
    # not an Elixir exception, so `rescue` alone won't catch it. Same
    # fail-open posture as the rescue clause.
    :exit, _ -> :ok
  end

  @doc """
  Returns the number of slots currently used in the window. Diagnostic;
  not used by production code paths.
  """
  @spec usage(provider(), String.t() | nil, pos_integer()) :: non_neg_integer()
  def usage(provider, api_key, window_seconds) do
    key = key(provider, api_key)
    now = System.monotonic_time(:millisecond)
    window_start = now - window_seconds * 1_000
    count(key, window_start)
  rescue
    ArgumentError -> 0
  end

  @doc """
  Clears all slot records for a given key. Used in tests; not safe to
  expose to operators (would let one operator wipe another's budget).
  """
  @spec clear(provider(), String.t() | nil) :: :ok
  def clear(provider, api_key) do
    key = key(provider, api_key)

    match_spec = [
      {{{:"$1", :_, :_}, :_}, [{:==, :"$1", {:const, key}}], [true]}
    ]

    :ets.select_delete(@table_name, match_spec)
    :ok
  rescue
    ArgumentError -> :ok
  end

  ## GenServer

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    schedule_cleanup()
    Logger.info("Debrid rate limiter started")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:acquire, provider, api_key, {requests, window_seconds}}, _from, state) do
    key = key(provider, api_key)
    now = System.monotonic_time(:millisecond)
    window_start = now - window_seconds * 1_000

    result =
      if count(key, window_start) < requests do
        slot_id = System.unique_integer([:monotonic, :positive])
        :ets.insert(@table_name, {{key, now, slot_id}, true})
        :ok
      else
        {:error, :rate_limited}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_records()
    schedule_cleanup()
    {:noreply, state}
  end

  ## Helpers

  defp key(provider, api_key) when is_atom(provider) do
    {provider, api_key || ""}
  end

  defp count(key, window_start) do
    match_spec = [
      {{{:"$1", :"$2", :_}, :_},
       [{:andalso, {:==, :"$1", {:const, key}}, {:>=, :"$2", window_start}}], [true]}
    ]

    :ets.select_count(@table_name, match_spec)
  end

  defp cleanup_old_records do
    # 10-minute cutoff comfortably outranks any provider's window
    # (RD/AD/PM/TB are all 60s today).
    cutoff = System.monotonic_time(:millisecond) - :timer.minutes(10)

    match_spec = [
      {{{:_, :"$1", :_}, :_}, [{:<, :"$1", cutoff}], [true]}
    ]

    :ets.select_delete(@table_name, match_spec)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
