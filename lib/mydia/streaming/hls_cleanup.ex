defmodule Mydia.Streaming.HlsCleanup do
  @moduledoc """
  Cleanup utilities for HLS transcoding temporary files.

  This module handles cleanup of stale HLS session directories in /tmp/mydia-hls.
  Cleanup runs on application startup and can be triggered manually.

  Directories are considered stale if:
  - They're older than 24 hours
  - No corresponding active session exists
  """

  require Logger

  @temp_base_dir "/tmp/mydia-hls"
  @stale_threshold_hours 24

  @doc """
  Performs cleanup of stale HLS session directories.

  This function should be called during application startup to clean up
  any leftover directories from previous runs.

  ## Options

    * `:force` - If true, removes all directories regardless of age (default: false)
    * `:dry_run` - If true, logs what would be deleted without actually deleting (default: false)

  ## Returns

    * `{:ok, count}` - Number of directories cleaned up
    * `{:error, reason}` - If cleanup failed
  """
  def cleanup_stale_sessions(opts \\ []) do
    force = Keyword.get(opts, :force, false)
    dry_run = Keyword.get(opts, :dry_run, false)

    Logger.info("Starting HLS session cleanup (force: #{force}, dry_run: #{dry_run})")

    if File.exists?(@temp_base_dir) do
      case File.ls(@temp_base_dir) do
        {:ok, session_dirs} ->
          stale_dirs =
            session_dirs
            |> Enum.map(&Path.join(@temp_base_dir, &1))
            |> Enum.filter(fn dir ->
              File.dir?(dir) and is_stale?(dir, force)
            end)

          if dry_run do
            Logger.info("DRY RUN: Would remove #{length(stale_dirs)} stale directories")
            Enum.each(stale_dirs, fn dir -> Logger.info("  Would remove: #{dir}") end)
            {:ok, length(stale_dirs)}
          else
            removed_count =
              Enum.reduce(stale_dirs, 0, fn dir, count ->
                case File.rm_rf(dir) do
                  {:ok, _files} ->
                    Logger.info("Removed stale HLS directory: #{dir}")
                    count + 1

                  {:error, reason, file} ->
                    Logger.warning(
                      "Failed to remove directory #{dir} (file: #{file}): #{inspect(reason)}"
                    )

                    count
                end
              end)

            Logger.info("Cleaned up #{removed_count} stale HLS session directories")
            {:ok, removed_count}
          end

        {:error, reason} ->
          Logger.error("Failed to list temp directory #{@temp_base_dir}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.debug("Temp directory #{@temp_base_dir} does not exist, nothing to clean")
      {:ok, 0}
    end
  end

  @doc """
  Cleans up a specific session directory by session ID.

  This is useful for manual cleanup or when a session terminates unexpectedly.
  """
  def cleanup_session(session_id) do
    session_dir = Path.join(@temp_base_dir, session_id)

    if File.exists?(session_dir) do
      case File.rm_rf(session_dir) do
        {:ok, files} ->
          Logger.info("Cleaned up session directory for #{session_id} (#{length(files)} files)")
          {:ok, length(files)}

        {:error, reason, file} ->
          Logger.error(
            "Failed to cleanup session #{session_id} (file: #{file}): #{inspect(reason)}"
          )

          {:error, reason}
      end
    else
      Logger.debug("Session directory for #{session_id} does not exist")
      {:ok, 0}
    end
  end

  @doc """
  Returns the size of all HLS temp directories in bytes.
  """
  def get_temp_size do
    if File.exists?(@temp_base_dir) do
      case File.ls(@temp_base_dir) do
        {:ok, session_dirs} ->
          total_size =
            session_dirs
            |> Enum.map(&Path.join(@temp_base_dir, &1))
            |> Enum.filter(&File.dir?/1)
            |> Enum.reduce(0, fn dir, acc ->
              acc + calculate_dir_size(dir)
            end)

          {:ok, total_size}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, 0}
    end
  end

  ## Private Functions

  defp is_stale?(dir, force) do
    if force do
      true
    else
      case File.stat(dir) do
        {:ok, stat} ->
          # Check if directory is older than threshold
          # Convert erlang datetime tuple to unix timestamp
          mtime_gregorian = :calendar.datetime_to_gregorian_seconds(stat.mtime)
          # Unix epoch in gregorian seconds
          unix_epoch = :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})
          mtime_unix = mtime_gregorian - unix_epoch

          age_seconds = System.system_time(:second) - mtime_unix
          age_hours = age_seconds / 3600

          age_hours > @stale_threshold_hours

        {:error, _reason} ->
          # If we can't stat it, consider it stale
          true
      end
    end
  end

  defp calculate_dir_size(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.map(&Path.join(dir, &1))
        |> Enum.reduce(0, fn path, acc ->
          cond do
            File.dir?(path) ->
              acc + calculate_dir_size(path)

            File.regular?(path) ->
              case File.stat(path) do
                {:ok, stat} -> acc + stat.size
                {:error, _} -> acc
              end

            true ->
              acc
          end
        end)

      {:error, _reason} ->
        0
    end
  end
end
