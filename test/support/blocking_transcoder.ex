defmodule Mydia.Downloads.BlockingTranscoder do
  @moduledoc """
  Deterministic stand-in for `Mydia.Downloads.FfmpegMp4Transcoder` used by
  `JobManager` tests.

  A started job stays alive (occupying a capacity slot) until it is explicitly
  stopped via `stop_transcoding/1` or told to finish via `finish/1`. This lets
  capacity and queueing assertions hold without racing real FFmpeg timing —
  a 1-second test clip otherwise transcodes faster than a test can fill
  capacity, intermittently freeing the slot the test expects to be occupied.

  Implements the same surface `JobManager` calls on the transcoder:
  `start_transcoding/1` and `stop_transcoding/1`.
  """

  use GenServer

  @doc "Starts a blocking transcoder process that stays alive until stopped."
  @spec start_transcoding(keyword()) :: GenServer.on_start()
  def start_transcoding(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Stops the transcoder process (simulates a cancelled job)."
  @spec stop_transcoding(pid()) :: :ok
  def stop_transcoding(pid) do
    GenServer.stop(pid, :normal)
  end

  @doc """
  Simulates a finished transcode: invokes the `:on_complete` callback (if any)
  and exits normally, so `JobManager` frees the slot and starts the next
  queued job.
  """
  @spec finish(pid()) :: :ok
  def finish(pid) do
    GenServer.cast(pid, :finish)
  end

  @impl true
  def init(opts) do
    {:ok, %{on_complete: Keyword.get(opts, :on_complete)}}
  end

  @impl true
  def handle_cast(:finish, %{on_complete: on_complete} = state) do
    if is_function(on_complete, 0), do: on_complete.()
    {:stop, :normal, state}
  end
end
