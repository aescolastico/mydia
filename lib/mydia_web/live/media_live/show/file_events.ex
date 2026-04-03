defmodule MydiaWeb.MediaLive.Show.FileEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, start_async: 3]

  alias Mydia.Media
  alias Mydia.Library
  alias Mydia.Downloads
  alias MydiaWeb.Live.Authorization

  import MydiaWeb.MediaLive.Show.Loaders,
    only: [load_media_item: 1, load_transcode_jobs: 1]

  import MydiaWeb.MediaLive.Show.Helpers,
    only: [get_season_media_files: 2, refresh_files: 1]

  require Logger

  def refresh_metadata(_params, socket) do
    media_item = socket.assigns.media_item

    metadata_result = Media.refresh_metadata(media_item)

    case {media_item.type, metadata_result} do
      {"tv_show", {:ok, updated_item}} ->
        case Media.refresh_episodes_for_tv_show(updated_item) do
          {:ok, count} ->
            {:noreply,
             socket
             |> assign(:media_item, load_media_item(media_item.id))
             |> put_flash(:info, "Refreshed metadata: #{count} episodes updated")}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:media_item, load_media_item(media_item.id))
             |> put_flash(
               :warning,
               "Metadata refreshed but episode refresh failed: #{inspect(reason)}"
             )}
        end

      {"movie", {:ok, _updated_item}} ->
        {:noreply,
         socket
         |> assign(:media_item, load_media_item(media_item.id))
         |> put_flash(:info, "Metadata refreshed")}

      {_, {:error, :missing_provider_id}} ->
        {:noreply, put_flash(socket, :error, "Cannot refresh: Missing provider ID (TMDB/TVDB)")}

      {_, {:error, reason}} ->
        {:noreply, put_flash(socket, :error, "Failed to refresh metadata: #{inspect(reason)}")}
    end
  end

  def refresh_all_file_metadata(_params, socket) do
    media_item = socket.assigns.media_item
    media_files = media_item.media_files

    if Enum.empty?(media_files) do
      {:noreply, put_flash(socket, :info, "No media files to refresh")}
    else
      {:noreply,
       socket
       |> assign(:refreshing_file_metadata, true)
       |> start_async(:refresh_files, fn -> refresh_files(media_files) end)}
    end
  end

  def rescan_season_files(%{"season-number" => season_number_str}, socket) do
    media_item = socket.assigns.media_item
    season_num = String.to_integer(season_number_str)
    season_media_files = get_season_media_files(media_item, season_num)

    if Enum.empty?(season_media_files) do
      {:noreply, put_flash(socket, :info, "No media files to refresh for season #{season_num}")}
    else
      {:noreply,
       socket
       |> assign(:rescanning_season, season_num)
       |> start_async(:rescan_season_files, fn ->
         {season_num, refresh_files(season_media_files)}
       end)}
    end
  end

  def rescan_series(_params, socket) do
    media_item = socket.assigns.media_item

    if media_item.type != "tv_show" do
      {:noreply, put_flash(socket, :error, "Re-scan is only available for TV shows")}
    else
      {:noreply,
       socket
       |> put_flash(:info, "Re-scanning series: discovering new files and refreshing metadata...")
       |> start_async(:rescan_series, fn ->
         scan_result = Library.rescan_series(media_item.id)

         case scan_result do
           {:ok, _result} ->
             updated_media_item =
               Media.get_media_item!(media_item.id,
                 preload: [episodes: [media_files: :library_path]]
               )

             all_media_files = Enum.flat_map(updated_media_item.episodes, & &1.media_files)
             refresh_result = refresh_files(all_media_files)
             {scan_result, refresh_result}

           error ->
             {error, {:ok, 0, 0}}
         end
       end)}
    end
  end

  def rescan_season(%{"season-number" => season_number_str}, socket) do
    media_item = socket.assigns.media_item
    season_num = String.to_integer(season_number_str)

    if media_item.type != "tv_show" do
      {:noreply, put_flash(socket, :error, "Re-scan is only available for TV shows")}
    else
      {:noreply,
       socket
       |> assign(:rescanning_season, season_num)
       |> put_flash(
         :info,
         "Re-scanning season #{season_num}: discovering new files and refreshing metadata..."
       )
       |> start_async(:rescan_season, fn ->
         scan_result = Library.rescan_season(media_item.id, season_num)

         case scan_result do
           {:ok, _result} ->
             updated_media_item =
               Media.get_media_item!(media_item.id,
                 preload: [episodes: [media_files: :library_path]]
               )

             season_media_files = get_season_media_files(updated_media_item, season_num)
             refresh_result = refresh_files(season_media_files)
             {season_num, scan_result, refresh_result}

           error ->
             {season_num, error, {:ok, 0, 0}}
         end
       end)}
    end
  end

  def rescan_movie(_params, socket) do
    media_item = socket.assigns.media_item

    if media_item.type != "movie" do
      {:noreply, put_flash(socket, :error, "Re-scan is only available for movies")}
    else
      {:noreply,
       socket
       |> put_flash(:info, "Re-scanning movie: discovering new files and refreshing metadata...")
       |> start_async(:rescan_movie, fn ->
         scan_result = Library.rescan_movie(media_item.id)

         case scan_result do
           {:ok, _result} ->
             updated_media_item =
               Media.get_media_item!(media_item.id, preload: [media_files: :library_path])

             all_media_files = updated_media_item.media_files
             refresh_result = refresh_files(all_media_files)
             {scan_result, refresh_result}

           error ->
             {error, {:ok, 0, 0}}
         end
       end)}
    end
  end

  def show_file_delete_confirm(%{"file-id" => file_id}, socket) do
    file = Library.get_media_file!(file_id, preload: :library_path)

    {:noreply,
     socket
     |> assign(:show_file_delete_confirm, true)
     |> assign(:file_to_delete, file)}
  end

  def hide_file_delete_confirm(_params, socket) do
    {:noreply,
     socket
     |> assign(:show_file_delete_confirm, false)
     |> assign(:file_to_delete, nil)}
  end

  def delete_media_file(_params, socket) do
    with :ok <- Authorization.authorize_delete_media(socket) do
      file = socket.assigns.file_to_delete

      case Library.delete_media_file(file) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:media_item, load_media_item(socket.assigns.media_item.id))
           |> assign(:show_file_delete_confirm, false)
           |> assign(:file_to_delete, nil)
           |> put_flash(:info, "Media file deleted successfully")}

        {:error, _changeset} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to delete media file")
           |> assign(:show_file_delete_confirm, false)
           |> assign(:file_to_delete, nil)}
      end
    else
      {:unauthorized, socket} -> {:noreply, socket}
    end
  end

  def show_file_details(%{"file-id" => file_id}, socket) do
    file = Library.get_media_file!(file_id)

    {:noreply,
     socket
     |> assign(:show_file_details_modal, true)
     |> assign(:file_details, file)}
  end

  def hide_file_details(_params, socket) do
    {:noreply,
     socket
     |> assign(:show_file_details_modal, false)
     |> assign(:file_details, nil)}
  end

  def pre_transcode(
        %{"media-file-id" => media_file_id, "resolution" => resolution},
        socket
      ) do
    media_item = socket.assigns.media_item

    case Downloads.DownloadService.prepare_by_file(media_file_id, resolution) do
      {:ok, _job_info} ->
        {:noreply,
         socket
         |> assign(:transcode_jobs, load_transcode_jobs(media_item))
         |> put_flash(:info, "Pre-transcode started for #{resolution}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start pre-transcode: #{inspect(reason)}")}
    end
  end

  def cancel_transcode(%{"job-id" => job_id}, socket) do
    case Downloads.DownloadService.cancel_job(job_id) do
      {:ok, :cancelled} ->
        media_item = socket.assigns.media_item

        {:noreply,
         socket
         |> assign(:transcode_jobs, load_transcode_jobs(media_item))
         |> put_flash(:info, "Transcode cancelled")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel: #{inspect(reason)}")}
    end
  end

  def show_rename_modal(_params, socket) do
    media_item = load_media_item(socket.assigns.media_item.id)

    rename_previews =
      Mydia.Library.FileRenamer.generate_rename_previews_for_media_item(media_item)

    {:noreply,
     socket
     |> assign(:show_rename_modal, true)
     |> assign(:rename_previews, rename_previews)}
  end

  def hide_rename_modal(_params, socket) do
    {:noreply,
     socket
     |> assign(:show_rename_modal, false)
     |> assign(:rename_previews, [])
     |> assign(:renaming_files, false)}
  end

  def confirm_rename_files(_params, socket) do
    rename_previews = socket.assigns.rename_previews

    rename_specs =
      Enum.map(rename_previews, fn preview ->
        %{file_id: preview.file_id, new_path: preview.proposed_path}
      end)

    {:noreply,
     socket
     |> assign(:renaming_files, true)
     |> start_async(:rename_files, fn ->
       Mydia.Library.FileRenamer.rename_files_batch(rename_specs)
     end)}
  end

  def mark_file_preferred(%{"file-id" => file_id}, socket) do
    file = Library.get_media_file!(file_id)
    media_item = socket.assigns.media_item

    case Library.update_media_file(file, %{quality_profile_id: media_item.quality_profile_id}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:media_item, load_media_item(socket.assigns.media_item.id))
         |> put_flash(:info, "Marked as preferred version")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to mark file as preferred")}
    end
  end

  # handle_async dispatches

  def handle_refresh_files_async({:ok, {:ok, success_count, error_count}}, socket) do
    message =
      if error_count > 0 do
        "Refreshed #{success_count} file(s), #{error_count} failed"
      else
        "Successfully refreshed #{success_count} file(s)"
      end

    {:noreply,
     socket
     |> assign(:refreshing_file_metadata, false)
     |> assign(:media_item, load_media_item(socket.assigns.media_item.id))
     |> put_flash(:info, message)}
  end

  def handle_refresh_files_async({:ok, {:error, reason}}, socket) do
    Logger.error("File metadata refresh failed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:refreshing_file_metadata, false)
     |> put_flash(:error, "Failed to refresh file metadata: #{inspect(reason)}")}
  end

  def handle_refresh_files_async({:exit, reason}, socket) do
    Logger.error("File metadata refresh task crashed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:refreshing_file_metadata, false)
     |> put_flash(:error, "Metadata refresh failed unexpectedly")}
  end

  def handle_rescan_season_files_async(
        {:ok, {season_num, {:ok, success_count, error_count}}},
        socket
      ) do
    message =
      if error_count > 0 do
        "Re-scanned #{success_count} file(s) in Season #{season_num}, #{error_count} failed"
      else
        "Successfully re-scanned #{success_count} file(s) in Season #{season_num}"
      end

    {:noreply,
     socket
     |> assign(:rescanning_season, nil)
     |> assign(:media_item, load_media_item(socket.assigns.media_item.id))
     |> put_flash(:info, message)}
  end

  def handle_rescan_season_files_async({:ok, {season_num, {:error, reason}}}, socket) do
    Logger.error("Season file metadata refresh failed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:rescanning_season, nil)
     |> put_flash(:error, "Failed to refresh Season #{season_num} files: #{inspect(reason)}")}
  end

  def handle_rescan_season_files_async({:exit, reason}, socket) do
    Logger.error("Season file metadata refresh task crashed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:rescanning_season, nil)
     |> put_flash(:error, "Season metadata refresh failed unexpectedly")}
  end

  def handle_rescan_series_async({:ok, {{:ok, scan_result}, {:ok, refreshed, _errors}}}, socket) do
    message = rescan_flash_message("Re-scan", scan_result, refreshed)

    {:noreply,
     socket
     |> assign(:media_item, load_media_item(socket.assigns.media_item.id))
     |> put_flash(:info, message)}
  end

  def handle_rescan_series_async({:ok, {{:error, :not_a_tv_show}, _}}, socket) do
    {:noreply, put_flash(socket, :error, "Re-scan is only available for TV shows")}
  end

  def handle_rescan_series_async({:ok, {{:error, :no_media_files}, _}}, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "No existing media files found. Please import at least one file first."
     )}
  end

  def handle_rescan_series_async({:ok, {{:error, reason}, _}}, socket) do
    Logger.error("Series re-scan failed: #{inspect(reason)}")
    {:noreply, put_flash(socket, :error, "Failed to re-scan series: #{inspect(reason)}")}
  end

  def handle_rescan_series_async({:exit, reason}, socket) do
    Logger.error("Series re-scan task crashed: #{inspect(reason)}")
    {:noreply, put_flash(socket, :error, "Series re-scan failed unexpectedly")}
  end

  def handle_rescan_movie_async({:ok, {{:ok, scan_result}, {:ok, refreshed, _errors}}}, socket) do
    message = rescan_flash_message("Re-scan", scan_result, refreshed)

    {:noreply,
     socket
     |> assign(:media_item, load_media_item(socket.assigns.media_item.id))
     |> put_flash(:info, message)}
  end

  def handle_rescan_movie_async({:ok, {{:error, :not_a_movie}, _}}, socket) do
    {:noreply, put_flash(socket, :error, "Re-scan is only available for movies")}
  end

  def handle_rescan_movie_async({:ok, {{:error, :no_media_files}, _}}, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "No existing media files found. Please import at least one file first."
     )}
  end

  def handle_rescan_movie_async({:ok, {{:error, reason}, _}}, socket) do
    Logger.error("Movie re-scan failed: #{inspect(reason)}")
    {:noreply, put_flash(socket, :error, "Failed to re-scan movie: #{inspect(reason)}")}
  end

  def handle_rescan_movie_async({:exit, reason}, socket) do
    Logger.error("Movie re-scan task crashed: #{inspect(reason)}")
    {:noreply, put_flash(socket, :error, "Movie re-scan failed unexpectedly")}
  end

  def handle_rescan_season_async(
        {:ok, {season_num, {:ok, scan_result}, {:ok, refreshed, _errors}}},
        socket
      ) do
    message = rescan_flash_message("Season #{season_num} re-scan", scan_result, refreshed)

    {:noreply,
     socket
     |> assign(:media_item, load_media_item(socket.assigns.media_item.id))
     |> assign(:rescanning_season, nil)
     |> put_flash(:info, message)}
  end

  def handle_rescan_season_async({:ok, {_season_num, {:error, :not_a_tv_show}, _}}, socket) do
    {:noreply,
     socket
     |> assign(:rescanning_season, nil)
     |> put_flash(:error, "Re-scan is only available for TV shows")}
  end

  def handle_rescan_season_async({:ok, {season_num, {:error, :no_media_files}, _}}, socket) do
    {:noreply,
     socket
     |> assign(:rescanning_season, nil)
     |> put_flash(
       :error,
       "No existing media files found for season #{season_num}. Please import at least one file first."
     )}
  end

  def handle_rescan_season_async({:ok, {season_num, {:error, reason}, _}}, socket) do
    Logger.error("Season #{season_num} re-scan failed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:rescanning_season, nil)
     |> put_flash(:error, "Failed to re-scan season #{season_num}: #{inspect(reason)}")}
  end

  def handle_rescan_season_async({:exit, reason}, socket) do
    Logger.error("Season re-scan task crashed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:rescanning_season, nil)
     |> put_flash(:error, "Season re-scan failed unexpectedly")}
  end

  def handle_rename_files_async({:ok, {:ok, results}}, socket) do
    success_count = Enum.count(results, &match?({:ok, _}, &1))
    error_count = Enum.count(results, &match?({:error, _}, &1))

    message =
      cond do
        error_count == 0 ->
          "Successfully renamed #{success_count} file(s)"

        success_count == 0 ->
          "Failed to rename all files"

        true ->
          "Renamed #{success_count} file(s), #{error_count} failed"
      end

    flash_type = if error_count > 0, do: :warning, else: :info

    {:noreply,
     socket
     |> assign(:renaming_files, false)
     |> assign(:show_rename_modal, false)
     |> assign(:rename_previews, [])
     |> assign(:media_item, load_media_item(socket.assigns.media_item.id))
     |> put_flash(flash_type, message)}
  end

  def handle_rename_files_async({:ok, {:error, reason}}, socket) do
    Logger.error("File rename failed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:renaming_files, false)
     |> put_flash(:error, "Failed to rename files: #{inspect(reason)}")}
  end

  def handle_rename_files_async({:exit, reason}, socket) do
    Logger.error("File rename task crashed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:renaming_files, false)
     |> put_flash(:error, "File rename failed unexpectedly")}
  end

  defp rescan_flash_message(prefix, scan_result, refreshed) do
    deleted = Map.get(scan_result, :deleted_files, 0)

    parts = ["Found #{scan_result.new_files} new file(s)"]

    parts =
      if deleted > 0,
        do: parts ++ ["moved #{deleted} file(s) to trash"],
        else: parts

    parts = parts ++ ["refreshed metadata for #{refreshed} file(s)"]

    parts =
      if Enum.empty?(scan_result.errors),
        do: parts,
        else: parts ++ ["#{length(scan_result.errors)} error(s)"]

    "#{prefix} complete! #{Enum.join(parts, ", ")}"
  end
end
