defmodule Mydia.Events.Structs.JobEventMeta do
  @moduledoc "Metadata for job/system-related events."

  @derive Jason.Encoder

  defstruct [
    :job_name,
    :duration_ms,
    :items_processed,
    :error_message,
    :queue,
    :attempt,
    :max_attempts,
    :stacktrace,
    :args
  ]

  @type t :: %__MODULE__{
          job_name: String.t() | nil,
          duration_ms: integer() | nil,
          items_processed: integer() | nil,
          error_message: String.t() | nil,
          queue: String.t() | nil,
          attempt: integer() | nil,
          max_attempts: integer() | nil,
          stacktrace: String.t() | nil,
          args: map() | nil
        }

  @known_keys %{
    "job_name" => :job_name,
    "duration_ms" => :duration_ms,
    "items_processed" => :items_processed,
    "error_message" => :error_message,
    "queue" => :queue,
    "attempt" => :attempt,
    "max_attempts" => :max_attempts,
    "stacktrace" => :stacktrace,
    "args" => :args
  }

  @doc """
  Converts a string-key map to a `JobEventMeta` struct.

  Unknown keys are silently ignored.

  ## Examples

      iex> JobEventMeta.from_map(%{"job_name" => "metadata_refresh", "duration_ms" => 1500})
      %JobEventMeta{job_name: "metadata_refresh", duration_ms: 1500}
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    attrs =
      for {k, v} <- map,
          atom_key = Map.get(@known_keys, to_string(k)),
          into: %{},
          do: {atom_key, v}

    struct(__MODULE__, attrs)
  end
end
