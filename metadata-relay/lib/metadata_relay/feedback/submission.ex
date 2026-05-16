defmodule MetadataRelay.Feedback.Submission do
  @moduledoc """
  Persisted in-app feedback sent from Mydia instances.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @types ["bug", "idea", "question"]
  @states ["unread", "read", "archived"]

  schema "feedback_submissions" do
    field :type, :string
    field :message, :string
    field :contact, :string
    field :instance_id, :string
    field :mydia_version, :string
    field :source_ip, :string
    field :state, :string, default: "unread"
    field :github_ref, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(submission, attrs) do
    submission
    |> cast(attrs, [
      :type,
      :message,
      :contact,
      :instance_id,
      :mydia_version,
      :source_ip,
      :state,
      :github_ref
    ])
    |> validate_required([:type, :message])
    |> validate_inclusion(:type, @types)
    |> validate_inclusion(:state, @states)
  end

  def state_changeset(submission, state) do
    submission
    |> cast(%{state: state}, [:state])
    |> validate_required([:state])
    |> validate_inclusion(:state, @states)
  end

  def github_ref_changeset(submission, github_ref) do
    cast(submission, %{github_ref: github_ref}, [:github_ref])
  end
end
