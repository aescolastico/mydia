defmodule MydiaWeb.Formatters do
  @moduledoc "Shared formatting helpers for LiveViews."

  @doc """
  Formats a byte count into a human-readable file size string.

  ## Examples

      iex> MydiaWeb.Formatters.format_file_size(1024)
      "1.0 KB"

      iex> MydiaWeb.Formatters.format_file_size(1_073_741_824)
      "1.0 GB"

  """
  def format_file_size(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_099_511_627_776 -> "#{Float.round(bytes / 1_099_511_627_776, 2)} TB"
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      true -> "#{bytes} B"
    end
  end

  @doc """
  Formats an Ecto changeset's errors into a human-readable string.

  Traverses all errors in the changeset, interpolating any dynamic values,
  and joins them into a semicolon-separated string.

  ## Examples

      iex> changeset = Ecto.Changeset.add_error(%Ecto.Changeset{}, :name, "can't be blank")
      iex> MydiaWeb.Formatters.format_changeset_errors(changeset)
      "name: can't be blank"

  """
  def format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} ->
      "#{field}: #{Enum.join(errors, ", ")}"
    end)
  end

  @doc """
  Formats a download progress percentage (0.0..100.0) for display.

  Returns a string with one decimal place, guaranteed clean of
  floating-point noise (unlike Float.round/2 + interpolation).

  ## Examples

      iex> MydiaWeb.Formatters.format_progress(45.5)
      "45.5"

      iex> MydiaWeb.Formatters.format_progress(0.899999999999)
      "0.9"

      iex> MydiaWeb.Formatters.format_progress(nil)
      "0.0"

  """
  def format_progress(nil), do: "0.0"

  def format_progress(progress) when is_number(progress),
    do: :erlang.float_to_binary(progress, decimals: 1)
end
