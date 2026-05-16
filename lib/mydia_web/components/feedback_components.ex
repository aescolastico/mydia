defmodule MydiaWeb.FeedbackComponents do
  @moduledoc """
  Components for the global in-app feedback modal.
  """

  use MydiaWeb, :html

  @github_discussions_url "https://github.com/getmydia/mydia/discussions/new/choose"
  @message_limit_bytes 4096

  attr :id, :string, required: true
  attr :form, :any, required: true
  attr :show, :boolean, default: false

  def feedback_modal(assigns) do
    assigns =
      assigns
      |> assign(:message_size_bytes, message_size_bytes(assigns.form))
      |> assign(:message_too_long?, message_size_bytes(assigns.form) > @message_limit_bytes)
      |> assign(:message_limit_bytes, @message_limit_bytes)
      |> assign(:github_discussions_url, @github_discussions_url)

    ~H"""
    <.modal id={@id} show={@show} on_cancel={JS.push("close_feedback_modal")}>
      <:title>Send feedback</:title>

      <p class="text-sm text-base-content/75 mb-3">
        You can either
        <a
          href={@github_discussions_url}
          target="_blank"
          rel="noopener noreferrer"
          class="link link-primary font-medium"
        >
          start a GitHub discussion
        </a>
        or send feedback directly through this form.
      </p>

      <p class="text-sm text-base-content/75 mb-4">
        Your message and optional contact info are sent to the Mydia developer along with this instance's UUID and Mydia version. Your library, file paths, account, and request history are NOT sent.
      </p>

      <.form
        for={@form}
        id="feedback-form"
        phx-change="validate_feedback"
        phx-submit="submit_feedback"
        class="space-y-3"
      >
        <.input
          field={@form[:type]}
          type="select"
          label="Type"
          prompt="Choose one..."
          options={[{"Bug report", "bug"}, {"Idea", "idea"}, {"Question", "question"}]}
        />

        <.input
          field={@form[:message]}
          type="textarea"
          label="Message"
          rows="6"
          placeholder="What happened, what did you expect, or what would make Mydia better?"
        />

        <div class={[
          "min-h-5 text-right text-xs",
          @message_too_long? && "text-error",
          !@message_too_long? && "text-base-content/60"
        ]}>
          {@message_size_bytes} / {@message_limit_bytes} bytes
        </div>

        <.input
          field={@form[:contact]}
          type="text"
          label="Contact (optional)"
          placeholder="Email, GitHub handle, Discord, or anything you prefer"
        />
      </.form>

      <:actions>
        <button type="button" class="btn btn-ghost" phx-click="close_feedback_modal">Cancel</button>
        <button
          type="submit"
          form="feedback-form"
          class="btn btn-primary"
          disabled={@message_too_long?}
        >
          Send feedback
        </button>
      </:actions>
    </.modal>
    """
  end

  defp message_size_bytes(form) do
    form
    |> Phoenix.HTML.Form.input_value(:message)
    |> to_string()
    |> byte_size()
  end
end
