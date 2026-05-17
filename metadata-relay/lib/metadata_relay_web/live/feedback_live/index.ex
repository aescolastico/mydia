defmodule MetadataRelayWeb.FeedbackLive.Index do
  @moduledoc """
  Maintainer dashboard for reading and triaging Mydia feedback.
  """

  use Phoenix.LiveView

  alias MetadataRelay.Feedback

  @message_preview_limit 220

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:state_filter, "unread")
     |> assign(:type_filter, "all")
     |> assign(:expanded_ids, MapSet.new())
     |> assign(:page_title, "Feedback Dashboard")
     |> load_dashboard()}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply,
     socket
     |> assign(:state_filter, Map.get(filters, "state", "unread"))
     |> assign(:type_filter, Map.get(filters, "type", "all"))
     |> load_dashboard()}
  end

  def handle_event("toggle_expand", %{"id" => id}, socket) do
    expanded_ids =
      if MapSet.member?(socket.assigns.expanded_ids, id) do
        MapSet.delete(socket.assigns.expanded_ids, id)
      else
        MapSet.put(socket.assigns.expanded_ids, id)
      end

    {:noreply, assign(socket, :expanded_ids, expanded_ids)}
  end

  def handle_event("mark_read", %{"id" => id}, socket) do
    update_submission(socket, id, fn submission -> Feedback.update_state(submission, "read") end)
  end

  def handle_event("archive", %{"id" => id}, socket) do
    update_submission(socket, id, fn submission ->
      Feedback.update_state(submission, "archived")
    end)
  end

  def handle_event("save_github_ref", %{"id" => id, "github_ref" => github_ref}, socket) do
    update_submission(socket, id, fn submission ->
      Feedback.set_github_ref(submission, github_ref)
    end)
  end

  defp update_submission(socket, id, updater) do
    case Feedback.get_submission(id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Feedback no longer exists.")
         |> load_dashboard()}

      submission ->
        case updater.(submission) do
          {:ok, _submission} ->
            {:noreply, load_dashboard(socket)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not update feedback.")}
        end
    end
  end

  defp load_dashboard(socket) do
    opts =
      []
      |> maybe_filter(:state, socket.assigns.state_filter)
      |> maybe_filter(:type, socket.assigns.type_filter)

    all_submissions = Feedback.list_submissions()
    filtered_submissions = Feedback.list_submissions(opts)

    socket
    |> assign(:submissions, filtered_submissions)
    |> assign(:summary, summarize_submissions(all_submissions))
    |> assign(:visible_count, length(filtered_submissions))
  end

  defp maybe_filter(opts, _key, "all"), do: opts
  defp maybe_filter(opts, key, value), do: Keyword.put(opts, key, value)

  defp summarize_submissions(submissions) do
    Enum.reduce(submissions, empty_summary(), fn submission, summary ->
      summary
      |> increment_summary(:total)
      |> increment_summary(state_key(submission.state))
      |> increment_summary(type_key(submission.type))
    end)
  end

  defp empty_summary do
    %{total: 0, unread: 0, read: 0, archived: 0, bug: 0, idea: 0, question: 0}
  end

  defp increment_summary(summary, key), do: Map.update!(summary, key, &(&1 + 1))

  defp state_key("unread"), do: :unread
  defp state_key("read"), do: :read
  defp state_key("archived"), do: :archived

  defp type_key("bug"), do: :bug
  defp type_key("idea"), do: :idea
  defp type_key("question"), do: :question

  def expanded?(expanded_ids, id), do: MapSet.member?(expanded_ids, id)

  def short_instance_id(nil), do: "anonymous"

  def short_instance_id(instance_id) do
    String.slice(instance_id, 0, 8)
  end

  def format_time(nil), do: ""

  def format_time(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  def active_filter_label(state_filter, type_filter, visible_count) do
    "Showing #{visible_count} matching submissions - State: #{label_for_state_filter(state_filter)} - Type: #{label_for_type_filter(type_filter)}"
  end

  def empty_state_copy(state_filter, type_filter) do
    "No #{label_for_state_filter(state_filter)} #{label_for_type_filter(type_filter)} submissions match the current filters."
  end

  def type_label("bug"), do: "Bug"
  def type_label("idea"), do: "Idea"
  def type_label("question"), do: "Question"

  def state_label("unread"), do: "Unread"
  def state_label("read"), do: "Read"
  def state_label("archived"), do: "Archived"

  def type_badge_class("bug"), do: "badge-error"
  def type_badge_class("idea"), do: "badge-info"
  def type_badge_class("question"), do: "badge-warning"

  def state_badge_class("unread"), do: "badge-primary"
  def state_badge_class("read"), do: "badge-ghost"
  def state_badge_class("archived"), do: "badge-neutral"

  def expandable_message?(message), do: byte_size(message) > @message_preview_limit

  def truncate_message(message) when byte_size(message) <= @message_preview_limit, do: message
  def truncate_message(message), do: String.slice(message, 0, @message_preview_limit) <> "..."

  defp label_for_state_filter("all"), do: "all states"
  defp label_for_state_filter("unread"), do: "unread"
  defp label_for_state_filter("read"), do: "read"
  defp label_for_state_filter("archived"), do: "archived"

  defp label_for_type_filter("all"), do: "all types"
  defp label_for_type_filter("bug"), do: "bug"
  defp label_for_type_filter("idea"), do: "idea"
  defp label_for_type_filter("question"), do: "question"
end
