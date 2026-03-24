defmodule Mydia.Music.PlaylistTrack do
  @moduledoc """
  Schema for playlist tracks - a join table that tracks the order of tracks in a playlist.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: binary(),
          position: integer() | nil,
          added_at: DateTime.t() | nil,
          playlist: Mydia.Music.Playlist.t() | Ecto.Association.NotLoaded.t(),
          playlist_id: binary() | nil,
          track: Mydia.Music.Track.t() | Ecto.Association.NotLoaded.t(),
          track_id: binary() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "playlist_tracks" do
    field :position, :integer
    field :added_at, :utc_datetime

    belongs_to :playlist, Mydia.Music.Playlist
    belongs_to :track, Mydia.Music.Track

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a playlist track.
  """
  def changeset(playlist_track, attrs) do
    playlist_track
    |> cast(attrs, [:position, :added_at])
    |> validate_required([:position, :added_at])
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:playlist_id)
    |> foreign_key_constraint(:track_id)
  end
end
