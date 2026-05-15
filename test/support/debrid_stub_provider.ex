defmodule Mydia.Downloads.Client.Debrid.StubProvider do
  @moduledoc """
  Hand-rolled stub `Provider` used by debrid Fetcher and dispatch tests.

  The repo does NOT use Mox or a `Mydia.Downloads.ClientMock` (verified by
  the comment in `test/mydia/jobs/download_monitor_test.exs:1019`). This
  stub is the test seam.

  Responses are stored in a public ETS table so the Fetcher GenServer
  (a different process from the test) can read them. Tests call `set/2`
  in `setup` and `reset/0` in `on_exit`.
  """

  @behaviour Mydia.Downloads.Client.Debrid.Provider

  alias Mydia.Downloads.Client.Debrid.ProviderJob
  alias Mydia.Downloads.Client.Error
  alias Mydia.Downloads.Structs.ClientInfo

  @table :debrid_stub_provider

  @doc "Ensures the backing ETS table exists. Idempotent."
  def ensure_started! do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
        :ok

      _ ->
        :ok
    end
  end

  @doc "Sets the stub's response for a given operation."
  def set(op, response) do
    ensure_started!()
    :ets.insert(@table, {op, response})
    :ok
  end

  @doc "Resets the stub state."
  def reset do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(@table)
    end

    :ok
  end

  defp get(op, default) do
    case :ets.whereis(@table) do
      :undefined ->
        default

      _ ->
        case :ets.lookup(@table, op) do
          [{^op, response}] -> response
          [] -> default
        end
    end
  end

  @impl true
  def validate_credentials(_config),
    do: get(:validate_credentials, {:ok, %ClientInfo{version: "stub"}})

  @impl true
  def submit_torrent(_config, _input), do: get(:submit_torrent, {:ok, "stub-job-id"})

  @impl true
  def post_submission_setup(_config, _id), do: get(:post_submission_setup, :ok)

  @impl true
  def get_job(_config, id),
    do: get(:get_job, {:ok, %ProviderJob{provider_id: id, state: :downloading, progress: 0.0}})

  @impl true
  def list_jobs(_config, ids) do
    case get(:list_jobs, :default) do
      :default ->
        {:ok,
         Map.new(ids, fn id ->
           {id, %ProviderJob{provider_id: id, state: :downloading, progress: 0.0}}
         end)}

      other ->
        other
    end
  end

  @impl true
  def get_download_urls(_config, _job),
    do: get(:get_download_urls, {:error, Error.unknown("stub not configured")})

  @impl true
  def delete_job(_config, _id), do: get(:delete_job, :ok)

  @impl true
  def rate_limit_budget, do: get(:rate_limit_budget, {1000, 60})
end
