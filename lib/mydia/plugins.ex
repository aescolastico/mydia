defmodule Mydia.Plugins do
  @moduledoc """
  Context for the WASM plugin platform.

  This is the public surface for listing and resolving installed plugins. The
  install/approval/remove lifecycle (U8) and config persistence (U4) extend this
  module; for now it wraps the runtime `Mydia.Plugins.Registry`.
  """

  require Logger

  alias Mydia.Plugins.Error
  alias Mydia.Plugins.Host
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

  ## Event dispatch (U5)

  @doc """
  Returns the enabled plugins subscribed to `event_type`.

  A plugin subscribes by listing the event in its manifest `events:subscribe`
  capability; only enabled plugins are returned (deny-by-default).
  """
  @spec subscribers(String.t()) :: [Plugin.t()]
  def subscribers(event_type) when is_binary(event_type) do
    Registry.list()
    |> Enum.filter(fn %Plugin{} = p -> p.enabled and event_type in p.events end)
  end

  @doc """
  Invokes a plugin for an event, routing by the plugin's delivery mode.

  This is the dispatcher's default invoker. `:inline` plugins run their guest
  handler synchronously through `Mydia.Plugins.Host`. `:durable` plugins (the
  bundled notifier — U10) enqueue a durable Oban delivery job; that branch is
  wired in U10, so until then every plugin is dispatched inline.
  """
  @spec invoke_plugin(Plugin.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def invoke_plugin(%Plugin{} = plugin, event) do
    Host.call(plugin.slug, plugin.entrypoint, build_payload(event), force_fuel: true)
  end

  @doc """
  Builds the JSON-encodable payload handed to a guest for an event.

  Atoms (`actor_type`) are stringified so the boundary stays language-agnostic.
  """
  @spec build_payload(map()) :: map()
  def build_payload(event) do
    %{
      "event" => Map.get(event, :type),
      "category" => Map.get(event, :category),
      "severity" => to_string_or_nil(Map.get(event, :severity)),
      "actor_type" => to_string_or_nil(Map.get(event, :actor_type)),
      "actor_id" => Map.get(event, :actor_id),
      "resource_type" => Map.get(event, :resource_type),
      "resource_id" => Map.get(event, :resource_id),
      "metadata" => Map.get(event, :metadata) || %{}
    }
  end

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value), do: to_string(value)

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
