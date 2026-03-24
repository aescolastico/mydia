defmodule Mydia.Metadata.Access do
  @moduledoc "Unified access for metadata that may be a struct or a map."

  @doc "Gets a metadata field from a parent struct that has a :metadata field."
  @spec get_field(map() | nil, atom()) :: term()
  def get_field(%{metadata: nil}, _field), do: nil
  def get_field(%{metadata: metadata}, field), do: get(metadata, field)
  def get_field(_, _), do: nil

  @doc "Gets a field from metadata, handling both struct and map access."
  @spec get(map() | struct() | nil, atom()) :: term()
  def get(nil, _field), do: nil
  def get(metadata, field) when is_struct(metadata), do: Map.get(metadata, field)

  def get(metadata, field) when is_map(metadata),
    do: Map.get(metadata, field) || Map.get(metadata, to_string(field))

  def get(_, _), do: nil
end
