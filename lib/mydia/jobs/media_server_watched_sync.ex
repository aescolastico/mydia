defmodule Mydia.Jobs.MediaServerWatchedSync do
  @moduledoc """
  Oban worker for syncing watched status between Mydia and media servers.

  Two modes:
  - **Individual**: Sync a specific server for a specific user.
    Args: `%{"config_id" => id, "user_id" => uid}`
  - **Scheduler**: Find all enabled servers with watched sync enabled
    and enqueue individual jobs for each server/user pair.
    Args: `%{"mode" => "all_enabled"}`
  """

  use Oban.Worker, queue: :integrations, max_attempts: 3

  alias Mydia.Accounts
  alias Mydia.MediaServer.WatchedSync
  alias Mydia.MediaServer.WatchedSync.Orchestrator
  alias Mydia.Settings

  require Logger

  defmodule Args do
    @moduledoc false
    defstruct [:mode, :config_id, :user_id]

    @type t :: %__MODULE__{
            mode: String.t() | nil,
            config_id: String.t() | nil,
            user_id: String.t() | nil
          }

    def parse(%{"mode" => "all_enabled"}) do
      %__MODULE__{mode: "all_enabled"}
    end

    def parse(%{"config_id" => config_id, "user_id" => user_id}) do
      %__MODULE__{config_id: config_id, user_id: user_id}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"mode" => "all_enabled"} = raw_args}) do
    _args = Args.parse(raw_args)

    servers =
      Settings.list_media_server_configs()
      |> Enum.filter(fn config ->
        config.enabled && watched_sync_enabled?(config)
      end)

    users = Accounts.list_users()

    Enum.each(servers, fn server ->
      Enum.each(users, fn user ->
        changeset =
          %{"config_id" => server.id, "user_id" => user.id}
          |> __MODULE__.new()

        safe_insert(changeset)
      end)
    end)

    :ok
  end

  def perform(%Oban.Job{args: raw_args}) do
    args = Args.parse(raw_args)
    config_id = args.config_id
    user_id = args.user_id
    config = Settings.get_media_server_config!(config_id)

    unless config.enabled && watched_sync_enabled?(config) do
      Logger.debug(
        "Skipping watched sync for #{config.name}: disabled or sync_watched not enabled"
      )

      {:ok, :skipped}
    else
      direction = get_sync_direction(config)

      Logger.info("Starting watched sync (#{direction}) for #{config.name}, user #{user_id}")

      with {:ok, _adapter} <- WatchedSync.adapter_for(config) do
        result = Orchestrator.sync(config, user_id, direction: direction)

        # Update last sync timestamp
        update_last_sync_timestamp(config)

        case result do
          {:ok, stats} ->
            Logger.info("Watched sync complete for #{config.name}: #{inspect(stats)}")
            :ok

          {:error, reason} ->
            Logger.error("Watched sync failed for #{config.name}: #{inspect(reason)}")
            {:error, reason}
        end
      end
    end
  end

  defp watched_sync_enabled?(config) do
    get_in_connection_settings(config, "sync_watched") in [true, "true"]
  end

  defp get_sync_direction(config) do
    case get_in_connection_settings(config, "sync_watched_direction") do
      "import" -> :import
      "export" -> :export
      _ -> :bidirectional
    end
  end

  defp get_in_connection_settings(config, key) do
    case config.connection_settings do
      %{} = settings -> Map.get(settings, key)
      _ -> nil
    end
  end

  defp safe_insert(changeset) do
    try do
      Oban.insert(changeset)
    rescue
      RuntimeError ->
        Mydia.Repo.insert(changeset)
    end
  end

  defp update_last_sync_timestamp(config) do
    current_settings = config.connection_settings || %{}
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    updated_settings = Map.put(current_settings, "last_watched_sync_at", now)

    Settings.update_media_server_config(config, %{connection_settings: updated_settings})
  end
end
