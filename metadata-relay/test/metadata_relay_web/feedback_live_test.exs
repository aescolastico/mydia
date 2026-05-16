defmodule MetadataRelayWeb.FeedbackLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Ecto.Query
  import Plug.Conn

  alias MetadataRelay.Feedback
  alias MetadataRelay.Feedback.Submission
  alias MetadataRelay.Repo

  @endpoint MetadataRelayWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Repo.delete_all(Submission)
    :ok
  end

  test "lists unread rows by default newest first" do
    {:ok, unread_old} = Feedback.create_submission(%{type: "bug", message: "Unread old"})
    {:ok, read} = Feedback.create_submission(%{type: "idea", message: "Already handled"})
    {:ok, archived} = Feedback.create_submission(%{type: "question", message: "Stored away"})
    {:ok, unread_new} = Feedback.create_submission(%{type: "bug", message: "Unread new"})

    Repo.update_all(from(s in Submission, where: s.id == ^unread_old.id),
      set: [inserted_at: ~U[2026-01-01 00:00:00Z]]
    )

    Repo.update_all(from(s in Submission, where: s.id == ^unread_new.id),
      set: [inserted_at: ~U[2026-01-02 00:00:00Z]]
    )

    {:ok, _read} = Feedback.update_state(read, "read")
    {:ok, _archived} = Feedback.update_state(archived, "archived")

    {:ok, _view, html} = live(authed_conn(), "/feedback")

    assert html =~ "Unread new"
    assert html =~ "Unread old"
    refute html =~ read.message
    refute html =~ archived.message

    assert html =~ "feedback-#{unread_new.id}"
    assert html =~ "feedback-#{unread_old.id}"
  end

  test "switching state filter to all surfaces all rows" do
    {:ok, unread} = Feedback.create_submission(%{type: "bug", message: "Unread"})
    {:ok, read} = Feedback.create_submission(%{type: "idea", message: "Read"})
    {:ok, archived} = Feedback.create_submission(%{type: "question", message: "Archived"})
    {:ok, _read} = Feedback.update_state(read, "read")
    {:ok, _archived} = Feedback.update_state(archived, "archived")

    {:ok, view, _html} = live(authed_conn(), "/feedback")

    html =
      view
      |> form("#feedback-filters", %{"filters" => %{"state" => "all", "type" => "all"}})
      |> render_change()

    assert html =~ unread.message
    assert html =~ read.message
    assert html =~ archived.message
  end

  test "mark read transitions an unread row" do
    {:ok, submission} = Feedback.create_submission(%{type: "bug", message: "Unread"})

    {:ok, view, _html} = live(authed_conn(), "/feedback")

    view
    |> element("button[phx-click='mark_read'][phx-value-id='#{submission.id}']")
    |> render_click()

    assert Feedback.get_submission!(submission.id).state == "read"
  end

  test "archive transitions a read row" do
    {:ok, submission} = Feedback.create_submission(%{type: "bug", message: "Read"})
    {:ok, submission} = Feedback.update_state(submission, "read")

    {:ok, view, _html} = live(authed_conn(), "/feedback")

    view
    |> form("#feedback-filters", %{"filters" => %{"state" => "all", "type" => "all"}})
    |> render_change()

    view
    |> element("button[phx-click='archive'][phx-value-id='#{submission.id}']")
    |> render_click()

    assert Feedback.get_submission!(submission.id).state == "archived"
  end

  test "saving github_ref persists the tag" do
    {:ok, submission} = Feedback.create_submission(%{type: "bug", message: "Unread"})

    {:ok, view, _html} = live(authed_conn(), "/feedback")

    html =
      view
      |> form("form[phx-submit='save_github_ref'][phx-value-id='#{submission.id}']", %{
        "github_ref" => "gh#123"
      })
      |> render_submit()

    assert Feedback.get_submission!(submission.id).github_ref == "gh#123"
    assert html =~ "gh#123"
  end

  test "saving github_ref for a missing row shows an error" do
    {:ok, view, _html} = live(authed_conn(), "/feedback")

    html =
      render_hook(view, "save_github_ref", %{
        "id" => Ecto.UUID.generate(),
        "github_ref" => "gh#1"
      })

    assert html =~ "Feedback no longer exists."
  end

  test "saving github_ref with an invalid id shows an error" do
    {:ok, view, _html} = live(authed_conn(), "/feedback")

    html =
      render_hook(view, "save_github_ref", %{
        "id" => "not-a-uuid",
        "github_ref" => "gh#1"
      })

    assert html =~ "Feedback no longer exists."
  end

  defp authed_conn do
    build_conn()
    |> put_req_header("authorization", "Basic " <> Base.encode64("admin:admin"))
  end
end
