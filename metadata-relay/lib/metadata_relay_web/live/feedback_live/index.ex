defmodule MetadataRelayWeb.FeedbackLive.Index do
  @moduledoc """
  Maintainer dashboard for reading and triaging Mydia feedback.
  """

  use Phoenix.LiveView

  alias MetadataRelay.Feedback

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:state_filter, "unread")
     |> assign(:type_filter, "all")
     |> assign(:expanded_ids, MapSet.new())
     |> assign(:page_title, "Feedback")
     |> load_submissions()}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply,
     socket
     |> assign(:state_filter, Map.get(filters, "state", "unread"))
     |> assign(:type_filter, Map.get(filters, "type", "all"))
     |> load_submissions()}
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
         |> load_submissions()}

      submission ->
        case updater.(submission) do
          {:ok, _submission} ->
            {:noreply, load_submissions(socket)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not update feedback.")}
        end
    end
  end

  defp load_submissions(socket) do
    opts =
      []
      |> maybe_filter(:state, socket.assigns.state_filter)
      |> maybe_filter(:type, socket.assigns.type_filter)

    assign(socket, :submissions, Feedback.list_submissions(opts))
  end

  defp maybe_filter(opts, _key, "all"), do: opts
  defp maybe_filter(opts, key, value), do: Keyword.put(opts, key, value)

  def expanded?(expanded_ids, id), do: MapSet.member?(expanded_ids, id)

  def short_instance_id(nil), do: "anonymous"

  def short_instance_id(instance_id) do
    String.slice(instance_id, 0, 8)
  end

  def format_time(nil), do: ""

  def format_time(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  def truncate_message(message) when byte_size(message) <= 220, do: message
  def truncate_message(message), do: String.slice(message, 0, 220) <> "..."
end
