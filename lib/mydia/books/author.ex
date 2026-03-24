defmodule Mydia.Books.Author do
  @moduledoc """
  Schema for book authors.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: binary(),
          name: String.t() | nil,
          sort_name: String.t() | nil,
          openlibrary_id: String.t() | nil,
          goodreads_id: String.t() | nil,
          biography: String.t() | nil,
          image_url: String.t() | nil,
          books: [Mydia.Books.Book.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "authors" do
    field :name, :string
    field :sort_name, :string
    field :openlibrary_id, :string
    field :goodreads_id, :string
    field :biography, :string
    field :image_url, :string

    has_many :books, Mydia.Books.Book

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating an author.
  """
  def changeset(author, attrs) do
    author
    |> cast(attrs, [:name, :sort_name, :openlibrary_id, :goodreads_id, :biography, :image_url])
    |> validate_required([:name])
    |> unique_constraint(:openlibrary_id)
    |> unique_constraint(:goodreads_id)
  end
end
