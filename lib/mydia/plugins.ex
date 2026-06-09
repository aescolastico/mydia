defmodule Mydia.Plugins do
  @moduledoc """
  Context for the WASM plugin platform.

  This is the public surface for listing and resolving installed plugins. The
  install/approval/remove lifecycle (U8) and config persistence (U4) extend this
  module; for now it wraps the runtime `Mydia.Plugins.Registry`.
  """

  require Logger

  alias Mydia.Plugins.Error
  alias Mydia.Plugins.Plugin
  alias Mydia.Plugins.Registry

  @doc "Lists all registered plugin descriptors."
  @spec list_plugins() :: [Plugin.t()]
  def list_plugins, do: Registry.list()

  @doc "Fetches a plugin descriptor by slug."
  @spec get_plugin(String.t()) :: {:ok, Plugin.t()} | {:error, Error.t()}
  def get_plugin(slug), do: Registry.lookup(slug)

  @doc "True when a plugin is registered under `slug`."
  @spec plugin_registered?(String.t()) :: boolean()
  def plugin_registered?(slug), do: Registry.registered?(slug)

  @doc """
  Rehydrates installed plugins into the runtime registry post-boot.

  Called from `Mydia.Application` after the supervision tree starts, mirroring
  `Mydia.Downloads.register_clients/0`. The install lifecycle (U8) fills this in
  by loading persisted `PluginConfig` rows, compiling their artifacts, and
  starting their pools. Until then it is a safe no-op.
  """
  @spec register_plugins() :: :ok
  def register_plugins do
    :ok
  end
end
