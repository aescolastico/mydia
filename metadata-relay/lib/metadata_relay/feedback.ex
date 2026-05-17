defmodule MetadataRelay.Feedback do
  @moduledoc """
  Stores and triages feedback submissions from Mydia instances.
  """

  import Ecto.Query

  alias MetadataRelay.Feedback.Submission
  alias MetadataRelay.Repo

  def create_submission(attrs) when is_map(attrs) do
    %Submission{}
    |> Submission.changeset(attrs)
    |> Repo.insert()
  end

  def list_submissions(opts \\ []) do
    Submission
    |> maybe_filter(:state, Keyword.get(opts, :state))
    |> maybe_filter(:type, Keyword.get(opts, :type))
    |> order_by([submission], desc: submission.inserted_at)
    |> Repo.all()
  end

  def submission_summary do
    Repo.one(
      from(submission in Submission,
        select: %{
          total: count(submission.id),
          unread:
            fragment(
              "coalesce(sum(case when ? = 'unread' then 1 else 0 end), 0)",
              submission.state
            ),
          read:
            fragment(
              "coalesce(sum(case when ? = 'read' then 1 else 0 end), 0)",
              submission.state
            ),
          archived:
            fragment(
              "coalesce(sum(case when ? = 'archived' then 1 else 0 end), 0)",
              submission.state
            ),
          bug:
            fragment(
              "coalesce(sum(case when ? = 'bug' then 1 else 0 end), 0)",
              submission.type
            ),
          idea:
            fragment(
              "coalesce(sum(case when ? = 'idea' then 1 else 0 end), 0)",
              submission.type
            ),
          question:
            fragment(
              "coalesce(sum(case when ? = 'question' then 1 else 0 end), 0)",
              submission.type
            )
        }
      )
    )
  end

  def get_submission(id) when is_binary(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id) do
      Repo.get(Submission, uuid)
    else
      :error -> nil
    end
  end

  def get_submission!(id), do: Repo.get!(Submission, id)

  def update_state(%Submission{} = submission, state) do
    submission
    |> Submission.state_changeset(state)
    |> Repo.update()
  end

  def set_github_ref(%Submission{} = submission, github_ref) do
    submission
    |> Submission.github_ref_changeset(github_ref)
    |> Repo.update()
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, _field, "all"), do: query
  defp maybe_filter(query, _field, :all), do: query

  defp maybe_filter(query, field, value) do
    where(query, [submission], field(submission, ^field) == ^value)
  end
end
