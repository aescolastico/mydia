defmodule Mydia.Adult.Scene do
  @moduledoc """
  Schema for adult content scenes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: binary(),
          title: String.t() | nil,
          release_date: Date.t() | nil,
          description: String.t() | nil,
          performers: [String.t()],
          tags: [String.t()],
          cover_url: String.t() | nil,
          duration: integer() | nil,
          monitored: boolean(),
          studio: Mydia.Adult.Studio.t() | Ecto.Association.NotLoaded.t(),
          studio_id: binary() | nil,
          adult_files: [Mydia.Adult.AdultFile.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "scenes" do
    field :title, :string
    field :release_date, :date
    field :description, :string
    field :performers, {:array, :string}, default: []
    field :tags, {:array, :string}, default: []
    field :cover_url, :string
    field :duration, :integer
    field :monitored, :boolean, default: true

    belongs_to :studio, Mydia.Adult.Studio
    has_many :adult_files, Mydia.Adult.AdultFile

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a scene.
  """
  def changeset(scene, attrs) do
    scene
    |> cast(attrs, [
      :title,
      :studio_id,
      :release_date,
      :description,
      :performers,
      :tags,
      :cover_url,
      :duration,
      :monitored
    ])
    |> validate_required([:title])
    |> foreign_key_constraint(:studio_id)
  end
end
