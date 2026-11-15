defmodule MydiaWeb.MediaLive.Index.RenameEvents do
  @moduledoc "Bulk rename events for the movie and TV library pages."

  use Gettext, backend: MydiaWeb.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, start_async: 3]

  alias Mydia.Library.FileRenamer
  alias Mydia.Media
  alias MydiaWeb.MediaLive.Index.Window
  alias MydiaWeb.MediaLive.RenameGroup
  alias MydiaWeb.MediaLive.Show.RenameEvents, as: SingleRenameEvents
  alias MydiaWeb.MediaLive.Show.RenameSelection

  require Logger

  def show_rename_modal(_params, socket) do
    selected_ids =
      socket.assigns.selected_ids
      |> MapSet.intersection(socket.assigns.all_visible_ids)
      |> MapSet.to_list()

    if socket.assigns.live_action in [:movies, :tv_shows] and selected_ids != [] do
      groups =
        socket.assigns.current_scope
        |> Media.list_media_items(
          ids: selected_ids,
          type: socket.assigns.filter_type,
          order_by: :title
        )
        |> Enum.map(fn item ->
          %RenameGroup{
            media_item_id: item.id,
            title: item.title,
            previews: FileRenamer.generate_rename_previews_for_media_item(item)
          }
        end)
        |> Enum.reject(&(&1.previews == []))

      previews = Enum.flat_map(groups, & &1.previews)

      {:noreply,
       socket
       |> assign(:show_rename_modal, true)
       |> assign(:rename_groups, groups)
       |> assign(:rename_previews, previews)
       |> assign(:rename_selected, RenameSelection.initial(previews))}
    else
      {:noreply, socket}
    end
  end

  def hide_rename_modal(_params, socket), do: {:noreply, reset(socket)}

  def toggle_rename_file(%{"file-id" => file_id}, socket) do
    update_selection(socket, &RenameSelection.toggle_file(&1, &2, file_id))
  end

  def toggle_rename_file(_params, socket), do: {:noreply, socket}

  def toggle_rename_season(%{"season-number" => season, "media-item-id" => item_id}, socket)
      when is_binary(season) do
    with {number, ""} <- Integer.parse(season),
         %RenameGroup{} = group <-
           Enum.find(socket.assigns.rename_groups, &(&1.media_item_id == item_id)) do
      selected =
        RenameSelection.toggle_season(socket.assigns.rename_selected, group.previews, number)

      {:noreply, assign(socket, :rename_selected, selected)}
    else
      _ -> {:noreply, socket}
    end
  end

  def toggle_rename_season(_params, socket), do: {:noreply, socket}

  def select_all_rename(_params, socket),
    do: update_selection(socket, fn _selected, previews -> RenameSelection.initial(previews) end)

  def clear_rename_selection(_params, socket),
    do: update_selection(socket, fn _selected, _previews -> MapSet.new() end)

  def confirm_rename_files(_params, socket) do
    specs = RenameSelection.specs(socket.assigns.rename_selected, socket.assigns.rename_previews)
    ready? =
      socket.assigns.live_action in [:movies, :tv_shows] and
        socket.assigns.show_rename_modal and
        not socket.assigns.renaming_files and specs != []

    if ready? do
      {:noreply,
       socket
       |> assign(:renaming_files, true)
       |> start_async(:rename_files, fn -> FileRenamer.rename_files_batch(specs) end)}
    else
      {:noreply, socket}
    end
  end

  def handle_rename_files_async({:ok, {:ok, results}}, socket) do
    {flash_type, message} = SingleRenameEvents.result_flash(results)

    {:noreply,
     socket
     |> reset()
     |> assign(:selection_mode, false)
     |> assign(:selected_ids, MapSet.new())
     |> put_flash(flash_type, message)
     |> Window.load_media_items()}
  end

  def handle_rename_files_async({:ok, {:error, reason}}, socket) do
    Logger.error("Bulk file rename failed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:renaming_files, false)
     |> put_flash(:error, gettext("Failed to rename files: %{reason}", reason: inspect(reason)))}
  end

  def handle_rename_files_async({:exit, reason}, socket) do
    Logger.error("Bulk file rename task crashed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:renaming_files, false)
     |> put_flash(:error, gettext("File rename failed unexpectedly"))}
  end

  defp update_selection(socket, fun) do
    selected = fun.(socket.assigns.rename_selected, socket.assigns.rename_previews)
    {:noreply, assign(socket, :rename_selected, selected)}
  end

  defp reset(socket) do
    socket
    |> assign(:show_rename_modal, false)
    |> assign(:rename_groups, [])
    |> assign(:rename_previews, [])
    |> assign(:rename_selected, MapSet.new())
    |> assign(:renaming_files, false)
  end
end
