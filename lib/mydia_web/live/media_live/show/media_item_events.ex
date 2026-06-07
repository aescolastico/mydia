defmodule MydiaWeb.MediaLive.Show.MediaItemEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]

  alias Mydia.Media
  alias MydiaWeb.Live.Authorization

  import MydiaWeb.MediaLive.Show.Helpers, only: [media_type_path: 1]

  require Logger

  def show_delete_confirm(_params, socket) do
    {:noreply,
     socket
     |> assign(:show_delete_confirm, true)
     |> assign(:delete_files, true)}
  end

  def hide_delete_confirm(_params, socket) do
    {:noreply,
     socket
     |> assign(:show_delete_confirm, false)
     |> assign(:delete_files, false)}
  end

  def toggle_delete_files(%{"delete_files" => value}, socket) do
    delete_files = value == "true"
    Logger.info("toggle_delete_files", value: value, delete_files: delete_files)
    {:noreply, assign(socket, :delete_files, delete_files)}
  end

  def delete_media(_params, socket) do
    with :ok <- Authorization.authorize_delete_media(socket) do
      media_item = socket.assigns.media_item
      delete_files = socket.assigns.delete_files

      Logger.info("LiveView delete_media event",
        media_item_id: media_item.id,
        title: media_item.title,
        delete_files: delete_files
      )

      case Media.delete_media_item(media_item, delete_files: delete_files) do
        {:ok, _item, 0} ->
          message =
            if delete_files do
              "#{media_item.title} deleted successfully (including files)"
            else
              "#{media_item.title} removed from library (files preserved)"
            end

          {:noreply,
           socket
           |> put_flash(:info, message)
           |> push_navigate(to: media_type_path(media_item.type))}

        {:ok, _item, error_count} ->
          {:noreply,
           socket
           |> put_flash(
             :error,
             "#{media_item.title} removed, but #{error_count} #{pluralize_files(error_count)} " <>
               "could not be deleted from disk. Check permissions and remove them manually."
           )
           |> push_navigate(to: media_type_path(media_item.type))}

        {:error, _changeset} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to delete #{media_item.title}")
           |> assign(:show_delete_confirm, false)}
      end
    else
      {:unauthorized, socket} -> {:noreply, socket}
    end
  end

  defp pluralize_files(1), do: "file"
  defp pluralize_files(_), do: "files"
end
