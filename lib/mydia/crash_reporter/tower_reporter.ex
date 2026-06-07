defmodule Mydia.CrashReporter.TowerReporter do
  @moduledoc """
  Tower reporter that forwards genuine crashes to the metadata relay.

  Tower captures exceptions, exits, and throws across Phoenix, Bandit, Oban, and
  OTP process crashes and invokes `report_event/1` for each. This reporter:

  - forwards only `:error`/`:exit`/`:throw` events (plain `Logger` messages,
    `kind: :message`, are dropped — belt-and-suspenders with
    `config :tower, log_level: :none`),
  - applies the per-window throttle,
  - normalizes the event into the shape `Mydia.CrashReporter.report/3` expects,
    and offloads the actual reporting to a supervised task.

  `report_event/1` runs synchronously in the process that crashed (Tower 0.8+),
  so the work done inline is kept cheap and the report itself is sent from a
  separate task to avoid stalling crash handling.
  """

  @behaviour Tower.Reporter

  alias Mydia.CrashReporter
  alias Mydia.CrashReporter.{ExitError, Throttle, ThrowError}

  @impl Tower.Reporter
  def report_event(%Tower.Event{kind: kind} = event)
      when kind in [:error, :exit, :throw] do
    if Throttle.allow?(throttle_server()) do
      {error, stacktrace, metadata} = normalize(event)

      Task.Supervisor.start_child(Mydia.TaskSupervisor, fn ->
        CrashReporter.report(error, stacktrace, metadata)
      end)
    end

    :ok
  end

  def report_event(%Tower.Event{kind: :message}), do: :ok

  # The throttle server is injectable so tests can drive it deterministically
  # without sharing the application-wide singleton's state.
  defp throttle_server do
    Application.get_env(:mydia, :crash_reporter_throttle, Throttle)
  end

  defp normalize(%Tower.Event{kind: :error, reason: reason, stacktrace: stack} = event) do
    {reason, stack || [], build_metadata(event, stack)}
  end

  defp normalize(%Tower.Event{kind: :exit, reason: reason, stacktrace: stack} = event) do
    {%ExitError{reason: reason}, stack || [], build_metadata(event, stack)}
  end

  defp normalize(%Tower.Event{kind: :throw, reason: value, stacktrace: stack} = event) do
    {%ThrowError{value: value}, stack || [], build_metadata(event, stack)}
  end

  # Derive a small, JSON-safe metadata map from the event. Tower's raw
  # `event.metadata`/`event.plug_conn` can hold pids, structs, and a Plug.Conn,
  # so we extract only the crash-site fields the relay's fingerprint depends on
  # plus the request id.
  defp build_metadata(event, stack) do
    {file, line, function, module} = top_frame(stack)

    %{
      file: file,
      line: line,
      function: function,
      module: module,
      request_id: request_id(event)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp request_id(%Tower.Event{metadata: metadata}) when is_map(metadata),
    do: Map.get(metadata, :request_id)

  defp request_id(_), do: nil

  defp top_frame([{module, function, arity_or_args, location} | _]) do
    arity = if is_list(arity_or_args), do: length(arity_or_args), else: arity_or_args
    file = location |> Keyword.get(:file) |> normalize_file()
    {file, Keyword.get(location, :line), "#{function}/#{arity}", inspect(module)}
  end

  defp top_frame(_), do: {nil, nil, nil, nil}

  defp normalize_file(nil), do: nil
  defp normalize_file(file) when is_binary(file), do: file
  defp normalize_file(file) when is_list(file), do: to_string(file)
  defp normalize_file(file), do: inspect(file)
end
