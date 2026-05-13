defmodule Mydia.Library.ReleaseParser.Candidate do
  @moduledoc """
  A single classifier hypothesis for a token: a candidate label with a
  confidence score and the zone (title/metadata) in which the token sits.

  The classifier emits zero or more candidates per token; the resolver
  picks a globally consistent assignment.
  """

  @enforce_keys [:label, :confidence]
  defstruct [:label, :value, :confidence, :zone]

  @type label ::
          :title_candidate
          | :year
          | :resolution
          | :source
          | :codec
          | :audio
          | :hdr
          | :language
          | :streaming_service
          | :release_group
          | :episode_marker
          | :season_marker
          | :container
          | :proper
          | :repack
          | atom()

  @type zone :: :title | :metadata | :anywhere

  @type t :: %__MODULE__{
          label: label(),
          value: term() | nil,
          confidence: float(),
          zone: zone() | nil
        }

  @doc "Build a candidate. `value` defaults to nil and is filled when the candidate carries structured data (e.g. an episode marker resolving to a season+episode tuple)."
  @spec new(label(), float(), keyword()) :: t()
  def new(label, confidence, opts \\ []) do
    %__MODULE__{
      label: label,
      confidence: confidence,
      value: Keyword.get(opts, :value),
      zone: Keyword.get(opts, :zone)
    }
  end
end
