defmodule Mydia.Events.Structs.BackoffEventMeta do
  @moduledoc "Metadata for search backoff events."

  @derive Jason.Encoder

  defstruct [
    :title,
    :media_type,
    :failure_count,
    :reason,
    :next_eligible_at,
    :backoff_duration_seconds,
    :previous_failure_count,
    :episode_id,
    :season_number,
    :episode_number
  ]

  @type t :: %__MODULE__{
          title: String.t() | nil,
          media_type: String.t() | nil,
          failure_count: integer() | nil,
          reason: String.t() | nil,
          next_eligible_at: String.t() | nil,
          backoff_duration_seconds: integer() | nil,
          previous_failure_count: integer() | nil,
          episode_id: String.t() | integer() | nil,
          season_number: integer() | nil,
          episode_number: integer() | nil
        }

  @known_keys %{
    "title" => :title,
    "media_type" => :media_type,
    "failure_count" => :failure_count,
    "reason" => :reason,
    "next_eligible_at" => :next_eligible_at,
    "backoff_duration_seconds" => :backoff_duration_seconds,
    "previous_failure_count" => :previous_failure_count,
    "episode_id" => :episode_id,
    "season_number" => :season_number,
    "episode_number" => :episode_number
  }

  @doc """
  Converts a string-key map to a `BackoffEventMeta` struct.

  Unknown keys are silently ignored.

  ## Examples

      iex> BackoffEventMeta.from_map(%{"title" => "Breaking Bad", "failure_count" => 3, "reason" => "no_results"})
      %BackoffEventMeta{title: "Breaking Bad", failure_count: 3, reason: "no_results"}
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
