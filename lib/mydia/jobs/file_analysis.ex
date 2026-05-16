defmodule Mydia.Jobs.FileAnalysis do
  @moduledoc """
  Recurring worker that fills in tech metadata for `MediaFile` rows the
  import path leaves at `analyzed_at IS NULL`.

  Selection is by row state, so the worker is naturally idempotent: every
  tick pulls a bounded batch of un-analyzed rows whose `analysis_attempts`
  is below the ceiling, runs ffprobe, and routes the write through
  `Mydia.Library.apply_analysis/2`. The write is guarded by
  `WHERE analyzed_at IS NULL`, so concurrent writers (this worker, the
  lazy on-play fallback, the operator retry) never clobber a fresher
  result.

  ## Configuration

      config :mydia, :file_analysis_batch_size, 50
      config :mydia, :file_analysis_max_attempts, 3

  Both default to the module attributes below. The Oban queue concurrency
  is configured separately via `config :mydia, Oban`.
  """

  use Oban.Worker,
    queue: :analysis,
    max_attempts: 3,
    # Prevent cron pileup when a batch overruns the 1-minute tick. Two ticks
    # concurrently selecting the same `analyzed_at IS NULL` rows would run
    # ffprobe twice on the same files; the apply_analysis WHERE guard
    # protects the write but not the wasted work.
    unique: [
      period: 60,
      fields: [:worker],
      states: [:available, :scheduled, :executing]
    ]

  import Ecto.Query

  require Logger

  alias Mydia.Library
  alias Mydia.Library.{FileAnalyzer, MediaFile}
  alias Mydia.Repo

  @default_batch_size 50
  @default_max_attempts 3

  @spec perform(Oban.Job.t()) :: :ok
  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    batch_size = Application.get_env(:mydia, :file_analysis_batch_size, @default_batch_size)
    max_attempts = Application.get_env(:mydia, :file_analysis_max_attempts, @default_max_attempts)

    rows =
      from(mf in MediaFile,
        where: is_nil(mf.analyzed_at) and mf.analysis_attempts < ^max_attempts,
        order_by: [asc: mf.inserted_at],
        limit: ^batch_size,
        preload: :library_path
      )
      |> Repo.all()

    case rows do
      [] ->
        :ok

      rows ->
        Logger.debug("FileAnalysis worker processing batch", count: length(rows))

        Enum.each(rows, &analyze_one/1)

        :ok
    end
  end

  defp analyze_one(%MediaFile{} = media_file) do
    case MediaFile.absolute_path(media_file) do
      nil ->
        Library.apply_analysis(media_file, {:error, :path_not_resolved})

        Logger.warning("Skipping analysis: media file path could not be resolved",
          file_id: media_file.id
        )

      absolute_path ->
        result = FileAnalyzer.analyze(absolute_path)
        outcome = Library.apply_analysis(media_file, result)
        log_outcome(media_file, absolute_path, result, outcome)
    end

    :ok
  end

  defp log_outcome(media_file, path, {:ok, _}, :ok) do
    Logger.info("Analyzed media file",
      file_id: media_file.id,
      path: path
    )
  end

  defp log_outcome(_media_file, _path, {:ok, _}, :already_analyzed), do: :ok

  defp log_outcome(media_file, path, {:error, reason}, _outcome) do
    Logger.warning("Failed to analyze media file",
      file_id: media_file.id,
      path: path,
      reason: inspect(reason)
    )
  end
end
