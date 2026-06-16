defmodule Mydia.CrashReporter.Throttle do
  @moduledoc """
  Fixed-window rate limiter for crash reports.

  Caps the number of reports forwarded to the metadata relay during a crash
  storm. The previous Logger backend kept this counter in its `:gen_event`
  state; with capture moved to `Mydia.CrashReporter.TowerReporter`, the limit
  lives here instead.

  Semantics: at most `max` grants per fixed `window_ms` window. The window
  resets the first time `allow?/1` is called after the current window has
  elapsed; reports beyond the cap within a window are dropped.
  """

  use GenServer

  @window_ms 60_000
  @max 10

  defstruct count: 0, window_start: nil, window_ms: @window_ms, max: @max

  # Client API

  def child_spec(opts) do
    # Derive the child id from the name so multiple named instances (e.g. in
    # tests) can run alongside the application-wide singleton.
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns `true` if a report may be sent now, recording the grant. Returns
  `false` once the per-window cap is reached.
  """
  @spec allow?(GenServer.server()) :: boolean()
  def allow?(server \\ __MODULE__) do
    GenServer.call(server, :allow)
  catch
    # Tower runs report_event/1 in the crashing process. If the Throttle is
    # unavailable (not yet started, restarting), fail open rather than letting
    # the GenServer.call exit propagate and amplify the failure: losing a crash
    # report is worse than skipping the rate limit for it.
    :exit, _ -> true
  end

  # Server callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      count: 0,
      window_start: System.monotonic_time(:millisecond),
      window_ms: Keyword.get(opts, :window_ms, @window_ms),
      max: Keyword.get(opts, :max, @max)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:allow, _from, state) do
    now = System.monotonic_time(:millisecond)

    state =
      if now - state.window_start >= state.window_ms do
        %{state | count: 0, window_start: now}
      else
        state
      end

    if state.count < state.max do
      {:reply, true, %{state | count: state.count + 1}}
    else
      {:reply, false, state}
    end
  end
end
