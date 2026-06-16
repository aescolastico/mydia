defmodule MydiaWeb.MediaLive.Show.MediaItemEventsTest do
  @moduledoc """
  Tests for the media-item delete confirmation defaults in
  `MydiaWeb.MediaLive.Show.MediaItemEvents`.
  """
  use ExUnit.Case, async: true

  alias MydiaWeb.MediaLive.Show.MediaItemEvents

  defp stub_socket do
    %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}},
      private: %{live_temp: %{}}
    }
  end

  test "show_delete_confirm opens the modal defaulting to deleting files" do
    {:noreply, socket} = MediaItemEvents.show_delete_confirm(%{}, stub_socket())

    assert socket.assigns.show_delete_confirm == true
    assert socket.assigns.delete_files == true
  end

  test "toggle_delete_files reflects the user's choice" do
    {:noreply, off} =
      MediaItemEvents.toggle_delete_files(%{"delete_files" => "false"}, stub_socket())

    assert off.assigns.delete_files == false

    {:noreply, on} =
      MediaItemEvents.toggle_delete_files(%{"delete_files" => "true"}, stub_socket())

    assert on.assigns.delete_files == true
  end
end
