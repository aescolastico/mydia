defmodule Mydia.Plugins.Registry do
  @moduledoc """
  Runtime registry of installed/active plugins.

  Mirrors `Mydia.Downloads.Client.Registry` (`use Agent`) but is keyed by plugin
  slug and stores the full `%Mydia.Plugins.Plugin{}` descriptor rather than an
  adapter module. Populated post-boot from persisted config (see
  `Mydia.Plugins.register_plugins/0`) and mutated by the install lifecycle (U8).

  Not to be confused with `Mydia.Plugins.PoolRegistry`, the `Registry` process
  that addresses each plugin's wasmex pool.
  """

  use Agent

  alias Mydia.Plugins.Error
  alias Mydia.Plugins.Plugin

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(opts \\ []) do
    Agent.start_link(fn -> %{} end, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  Registers (or replaces) a plugin descriptor under `slug`.

  Re-registering an existing slug updates the descriptor.
  """
  @spec register(String.t(), Plugin.t()) :: {:ok, Plugin.t()}
  def register(slug, %Plugin{} = plugin) when is_binary(slug) do
    plugin = %Plugin{plugin | slug: slug}
    Agent.update(__MODULE__, &Map.put(&1, slug, plugin))
    {:ok, plugin}
  end

  @doc "Looks up a plugin by slug."
  @spec lookup(String.t()) :: {:ok, Plugin.t()} | {:error, Error.t()}
  def lookup(slug) when is_binary(slug) do
    case Agent.get(__MODULE__, &Map.get(&1, slug)) do
      %Plugin{} = plugin -> {:ok, plugin}
      nil -> {:error, Error.new(:not_found, "no plugin registered for slug #{slug}")}
    end
  end

  @doc "Returns all registered plugin descriptors."
  @spec list() :: [Plugin.t()]
  def list do
    Agent.get(__MODULE__, &Map.values/1)
  end

  @doc "Removes a plugin from the registry."
  @spec unregister(String.t()) :: :ok
  def unregister(slug) when is_binary(slug) do
    Agent.update(__MODULE__, &Map.delete(&1, slug))
  end

  @doc "True when a plugin is registered under `slug`."
  @spec registered?(String.t()) :: boolean()
  def registered?(slug) when is_binary(slug) do
    Agent.get(__MODULE__, &Map.has_key?(&1, slug))
  end

  @doc "Removes all plugins (test helper)."
  @spec clear() :: :ok
  def clear do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end
end
