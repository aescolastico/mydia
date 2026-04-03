defmodule MydiaWeb.AdminRemoteAccessLive.Index do
  use MydiaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mydia.PubSub, "remote_access:claims")
    end

    {:ok,
     socket
     |> assign(:page_title, "Configuration - Remote Access")
     |> assign(:active_tab, :remote_access)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  ## Timer relay for RemoteAccessComponent

  @impl true
  def handle_info({:remote_access_countdown_tick, component_id}, socket) do
    Process.send_after(self(), {:remote_access_do_countdown_tick, component_id}, 1000)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:remote_access_do_countdown_tick, component_id}, socket) do
    send_update(MydiaWeb.AdminRemoteAccessLive.RemoteAccessComponent,
      id: component_id,
      countdown_tick: true
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:remote_access_refresh_p2p, component_id}, socket) do
    send_update(MydiaWeb.AdminRemoteAccessLive.RemoteAccessComponent,
      id: component_id,
      refresh_p2p: true
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:claim_consumed, %{code: code, user_id: user_id}}, socket) do
    if socket.assigns.current_scope && socket.assigns.current_scope.user.id == user_id do
      send_update(MydiaWeb.AdminRemoteAccessLive.RemoteAccessComponent,
        id: "remote-access",
        claim_consumed: code
      )
    end

    {:noreply, socket}
  end
end
