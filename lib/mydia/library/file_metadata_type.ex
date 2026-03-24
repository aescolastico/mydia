defmodule Mydia.Library.FileMetadataType do
  @moduledoc """
  Custom Ecto type for FileMetadata that provides full type safety.

  Automatically converts between FileMetadata structs and JSON strings
  during database operations. Handles legacy string-key maps transparently.

  ## Usage

  In your schema:

      schema "media_files" do
        field :metadata, Mydia.Library.FileMetadataType
      end

  When you load a media file from the database, metadata will automatically
  be a `%FileMetadata{}` struct instead of a plain map.
  """

  use Ecto.Type

  alias Mydia.Library.Structs.FileMetadata

  def type, do: :string

  def cast(%FileMetadata{} = metadata), do: {:ok, metadata}
  def cast(nil), do: {:ok, FileMetadata.empty()}

  def cast(map) when is_map(map) do
    {:ok, FileMetadata.from_map(map)}
  end

  def cast(_), do: :error

  def load(nil), do: {:ok, FileMetadata.empty()}
  def load(""), do: {:ok, FileMetadata.empty()}
  def load("{}"), do: {:ok, FileMetadata.empty()}

  def load(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, map} when is_map(map) -> {:ok, FileMetadata.from_map(map)}
      {:ok, _} -> :error
      {:error, _} -> :error
    end
  end

  # Handle case where data is already a map (some adapters may do this)
  def load(data) when is_map(data), do: {:ok, FileMetadata.from_map(data)}
  def load(_), do: :error

  def dump(%FileMetadata{} = metadata) do
    {:ok, Jason.encode!(FileMetadata.to_map(metadata))}
  end

  def dump(nil), do: {:ok, "{}"}
  def dump(map) when map == %{}, do: {:ok, "{}"}

  def dump(map) when is_map(map) do
    {:ok, Jason.encode!(map)}
  end

  def dump(_), do: :error

  def equal?(%FileMetadata{} = a, %FileMetadata{} = b), do: a == b
  def equal?(a, b), do: a == b

  def embed_as(_), do: :dump
end
