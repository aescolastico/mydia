defmodule MetadataRelay.Feedback.Notifier do
  @moduledoc """
  Sends maintainer notifications for new feedback submissions.
  """

  import Swoosh.Email

  alias MetadataRelay.Feedback.Submission
  alias MetadataRelay.Mailer

  @config_key __MODULE__

  def deliver_new_submission(%Submission{} = submission) do
    case recipient() do
      nil ->
        :ok

      recipient ->
        submission
        |> new_submission_email(recipient)
        |> Mailer.deliver()
    end
  end

  defp new_submission_email(submission, recipient) do
    subject = "[Mydia feedback] #{submission.type}: #{subject_preview(submission.message)}"

    new()
    |> to(recipient)
    |> from(from_address())
    |> subject(subject)
    |> text_body(text_body(submission))
  end

  defp text_body(submission) do
    """
    New Mydia feedback received.

    Type: #{submission.type}
    Contact: #{optional_value(submission.contact)}
    Instance: #{optional_value(submission.instance_id)}
    Mydia version: #{optional_value(submission.mydia_version)}
    Source IP: #{optional_value(submission.source_ip)}
    Submitted at: #{DateTime.to_iso8601(submission.inserted_at)}

    Message:
    #{submission.message}
    #{dashboard_line(submission)}
    """
    |> String.trim()
  end

  defp recipient do
    @config_key
    |> config()
    |> Keyword.get(:recipient)
    |> normalize_optional_string()
  end

  defp from_address do
    @config_key
    |> config()
    |> Keyword.get(:from, "metadata-relay@localhost")
  end

  defp dashboard_line(submission) do
    case dashboard_url() do
      nil -> ""
      dashboard_url -> "\n\nDashboard: #{dashboard_url}/feedback#feedback-#{submission.id}"
    end
  end

  defp dashboard_url do
    @config_key
    |> config()
    |> Keyword.get(:dashboard_url)
    |> normalize_optional_string()
    |> case do
      nil -> nil
      url -> String.trim_trailing(url, "/")
    end
  end

  defp config(key), do: Application.get_env(:metadata_relay, key, [])

  defp subject_preview(message) do
    message
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 80)
  end

  defp optional_value(value) do
    case normalize_optional_string(value) do
      nil -> "-"
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_optional_string(_), do: nil
end
