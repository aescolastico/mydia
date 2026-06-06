defmodule Mydia.Hooks.Manager do
  @moduledoc """
  Manages hook discovery, registration, and metadata storage.

  Hooks are discovered from a configurable external directory (default: `/config/hooks`)
  on startup and cached in an ETS table for fast lookup. The directory can be mounted
  as a Docker volume for user-defined hooks.
  """

  use GenServer
  require Logger

  @table_name :mydia_hooks

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  List all hooks registered for a given event.
  """
  def list_hooks(event) do
    case :ets.lookup(@table_name, event) do
      [{^event, hooks}] -> hooks
      [] -> []
    end
  end

  @doc """
  List all available hook events.
  """
  def list_events do
    :ets.tab2list(@table_name)
    |> Enum.map(fn {event, _hooks} -> event end)
    |> Enum.sort()
  end

  @doc """
  Reload hooks from disk.
  """
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for hook metadata
    :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])

    # Discover and register hooks
    discover_hooks()

    {:ok, %{}}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    discover_hooks()
    {:reply, :ok, state}
  end

  # Private Functions

  defp discover_hooks do
    config = Application.get_env(:mydia, :runtime_config)
    hooks_enabled = config.hooks.enabled

    if hooks_enabled do
      hooks_path = resolve_hooks_path(config)
      Logger.info("Discovering hooks from #{hooks_path}")

      if File.dir?(hooks_path) do
        hooks_path
        |> File.ls!()
        |> Enum.each(&discover_event_hooks(hooks_path, &1))
      else
        Logger.info("Hooks directory not found: #{hooks_path} (will be created on first use)")
      end
    else
      Logger.info("Hooks system is disabled")
      :ok
    end
  end

  defp resolve_hooks_path(config) do
    hooks_dir = config.hooks.directory
    db_path = config.database.path

    # If hooks_dir is absolute, use it as-is
    # Otherwise, resolve it relative to the database directory
    if Path.type(hooks_dir) == :absolute do
      hooks_dir
    else
      db_dir = Path.dirname(db_path)
      Path.join(db_dir, hooks_dir)
    end
  end

  defp discover_event_hooks(base_path, event_name) do
    event_path = Path.join(base_path, event_name)

    if File.dir?(event_path) do
      hooks =
        event_path
        |> File.ls!()
        |> Enum.filter(&hook_file?/1)
        |> Enum.map(&build_hook_metadata(event_path, event_name, &1))
        |> Enum.sort_by(& &1.priority)

      :ets.insert(@table_name, {event_name, hooks})
      Logger.info("Registered #{length(hooks)} hook(s) for event: #{event_name}")
    end
  end

  defp hook_file?(filename) do
    String.ends_with?(filename, ".lua") or
      (String.ends_with?(filename, ".sh") and File.stat!(filename).mode |> executable?())
  end

  defp executable?(mode) do
    # Check if file has execute permission (owner, group, or others)
    Bitwise.band(mode, 0o111) != 0
  end

  defp build_hook_metadata(event_path, event_name, filename) do
    file_path = Path.join(event_path, filename)
    priority = extract_priority(filename)

    %{
      event: event_name,
      name: filename,
      path: file_path,
      type: hook_type(filename),
      priority: priority,
      enabled: true
    }
  end

  defp hook_type(filename) do
    cond do
      String.ends_with?(filename, ".lua") -> :lua
      String.ends_with?(filename, ".sh") -> :external
      true -> :unknown
    end
  end

  defp extract_priority(filename) do
    case Regex.run(~r/^(\d+)_/, filename) do
      [_, priority_str] ->
        String.to_integer(priority_str)

      nil ->
        # No prefix, assign default priority
        999
    end
  end
end
