defmodule Mydia.Music.Artist do
  @moduledoc """
  Schema for music artists.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: binary(),
          name: String.t() | nil,
          sort_name: String.t() | nil,
          musicbrainz_id: String.t() | nil,
          biography: String.t() | nil,
          image_url: String.t() | nil,
          genres: [String.t()],
          albums: [Mydia.Music.Album.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "artists" do
    field :name, :string
    field :sort_name, :string
    field :musicbrainz_id, :string
    field :biography, :string
    field :image_url, :string
    field :genres, {:array, :string}, default: []

    has_many :albums, Mydia.Music.Album

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating an artist.
  """
  def changeset(artist, attrs) do
    artist
    |> cast(attrs, [:name, :sort_name, :musicbrainz_id, :biography, :image_url, :genres])
    |> validate_required([:name])
    |> unique_constraint(:musicbrainz_id)
  end
end
