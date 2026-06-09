defmodule Mydia.Plugins.Error do
  @moduledoc """
  Error types for the WASM plugin platform.

  Mirrors `Mydia.Downloads.Client.Error`: a consistent `{type, message, details}`
  struct returned across the plugin host, manifest parsing, capability gating,
  the network gate, and the index/install lifecycle.

  ## Error Types

    * `:not_found` - Plugin/slug not registered or not running
    * `:compile_failed` - WASM module failed to compile
    * `:instantiate_failed` - Could not instantiate the module in a fresh store
    * `:timeout` - Invocation exceeded the configured deadline
    * `:trap` - Guest trapped (fuel exhausted, memory limit, unreachable, etc.)
    * `:invalid_output` - Guest returned a payload the host could not decode
    * `:invalid_manifest` - Manifest failed to parse or validate
    * `:capability_denied` - Plugin used a capability it was not granted
    * `:capability_unavailable` - Capability declared but not implemented in this version
    * `:network_error` - Outbound HTTP gate rejected or failed the request
    * `:integrity_mismatch` - Package hash did not match the declared value
    * `:invalid_config` - Invalid configuration provided
    * `:unknown` - Unknown or unexpected error
  """

  @type error_type ::
          :not_found
          | :compile_failed
          | :instantiate_failed
          | :timeout
          | :trap
          | :invalid_output
          | :invalid_manifest
          | :capability_denied
          | :capability_unavailable
          | :network_error
          | :integrity_mismatch
          | :invalid_config
          | :unknown

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          details: map() | nil
        }

  defexception [:type, :message, :details]

  @doc """
  Creates a new plugin error struct.

  ## Examples

      iex> Mydia.Plugins.Error.new(:not_found, "no such plugin")
      %Mydia.Plugins.Error{type: :not_found, message: "no such plugin", details: nil}
  """
  @spec new(error_type(), String.t(), map() | nil) :: t()
  def new(type, message, details \\ nil) do
    %__MODULE__{type: type, message: message, details: details}
  end

  @impl true
  @spec message(t()) :: String.t()
  def message(%__MODULE__{type: type, message: msg}) do
    label =
      type
      |> Atom.to_string()
      |> String.replace("_", " ")
      |> String.capitalize()

    "#{label}: #{msg}"
  end
end
