defmodule MydiaWeb.ProfileLive.Index do
  use MydiaWeb, :live_view

  alias Mydia.Accounts
  alias Mydia.Accounts.UserPreference
  alias Mydia.Integrations
  alias Mydia.Integrations.Trakt.Client, as: TraktClient
  alias Mydia.Plugins
  alias Mydia.Plugins.Connections
  alias Mydia.Plugins.DeviceFlow

  require Logger

  @themes [
    {"System", "system"},
    {"Light", "light"},
    {"Dark", "dark"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    is_oidc_user = Accounts.oidc_user?(user)
    preference = Accounts.get_user_preference!(user)

    trakt_integration = Integrations.get_user_integration(user.id, "trakt")

    socket =
      socket
      |> assign(:is_oidc_user, is_oidc_user)
      |> assign(:profile_form, to_form(Accounts.change_profile(user)))
      |> assign(:password_form, to_form(password_changeset(), as: :password))
      |> assign(:show_password_modal, false)
      |> assign(:password_error, nil)
      # Preferences
      |> assign(:preference, preference)
      |> assign(:themes, @themes)
      |> assign(:theme, UserPreference.theme(preference))
      # Trakt integration
      |> assign(:trakt_integration, trakt_integration)
      |> assign(:trakt_device_code, nil)
      |> assign(:trakt_user_code, nil)
      |> assign(:trakt_verification_url, nil)
      |> assign(:trakt_polling, false)
      |> assign(:trakt_poll_interval, nil)
      |> assign(:trakt_error, nil)
      # Generic plugin connections (U8)
      |> assign(:plugin_connections, load_plugin_connections(user.id))
      |> assign(:plugin_connect, nil)

    {:ok, socket}
  end

  defp load_plugin_connections(user_id) do
    Enum.map(Plugins.list_connectable(), fn pc ->
      Map.put(pc, :connection, Connections.get(pc.slug, user_id))
    end)
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :page_title, "Profile & Preferences")}
  end

  ## Profile Events

  @impl true
  def handle_event("validate_profile", %{"user" => params}, socket) do
    changeset =
      socket.assigns.current_user
      |> Accounts.change_profile(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :profile_form, to_form(changeset))}
  end

  @impl true
  def handle_event("save_profile", %{"user" => params}, socket) do
    case Accounts.update_profile(socket.assigns.current_user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_user, user)
         |> assign(:profile_form, to_form(Accounts.change_profile(user)))
         |> put_flash(:info, "Profile updated successfully")}

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("show_password_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_password_modal, true)
     |> assign(:password_form, to_form(password_changeset(), as: :password))
     |> assign(:password_error, nil)}
  end

  @impl true
  def handle_event("hide_password_modal", _params, socket) do
    {:noreply, assign(socket, :show_password_modal, false)}
  end

  @impl true
  def handle_event("validate_password", %{"password" => params}, socket) do
    changeset =
      password_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :password_form, to_form(changeset, as: :password))}
  end

  @impl true
  def handle_event("change_password", %{"password" => params}, socket) do
    current_password = params["current_password"] || ""
    new_password = params["new_password"] || ""
    confirm_password = params["confirm_password"] || ""

    case Accounts.change_password(
           socket.assigns.current_user,
           current_password,
           new_password,
           confirm_password
         ) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(:show_password_modal, false)
         |> assign(:password_form, to_form(password_changeset(), as: :password))
         |> assign(:password_error, nil)
         |> put_flash(:info, "Password changed successfully")}

      {:error, :invalid_password} ->
        {:noreply, assign(socket, :password_error, "Current password is incorrect")}

      {:error, changeset} ->
        {:noreply, assign(socket, :password_form, to_form(changeset, as: :password))}
    end
  end

  ## Preferences Events

  @impl true
  def handle_event("update_theme", %{"theme" => theme}, socket) do
    case Accounts.update_preference(socket.assigns.preference, %{"theme" => theme}) do
      {:ok, preference} ->
        {:noreply,
         socket
         |> assign(:preference, preference)
         |> assign(:theme, theme)
         |> push_event("theme_changed", %{theme: theme})
         |> put_flash(:info, "Theme updated")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update theme")}
    end
  end

  ## Trakt Events

  @impl true
  def handle_event("trakt_connect", _params, socket) do
    case TraktClient.generate_device_code() do
      {:ok, data} ->
        interval = (data["interval"] || 5) * 1000
        Process.send_after(self(), :trakt_poll, interval)

        {:noreply,
         socket
         |> assign(:trakt_device_code, data["device_code"])
         |> assign(:trakt_user_code, data["user_code"])
         |> assign(:trakt_verification_url, data["verification_url"])
         |> assign(:trakt_polling, true)
         |> assign(:trakt_poll_interval, interval)
         |> assign(:trakt_error, nil)}

      {:error, reason} ->
        Logger.error("Failed to generate Trakt device code: #{inspect(reason)}")

        {:noreply,
         assign(socket, :trakt_error, "Failed to start Trakt authorization. Please try again.")}
    end
  end

  @impl true
  def handle_event("trakt_cancel", _params, socket) do
    {:noreply,
     socket
     |> assign(:trakt_device_code, nil)
     |> assign(:trakt_user_code, nil)
     |> assign(:trakt_verification_url, nil)
     |> assign(:trakt_polling, false)
     |> assign(:trakt_poll_interval, nil)
     |> assign(:trakt_error, nil)}
  end

  @impl true
  def handle_event("trakt_disconnect", _params, socket) do
    user = socket.assigns.current_user

    case Integrations.get_user_integration(user.id, "trakt") do
      nil ->
        {:noreply, assign(socket, :trakt_integration, nil)}

      integration ->
        # Best-effort revoke
        TraktClient.revoke_token(integration.access_token)
        Integrations.delete_user_integration(integration)

        {:noreply,
         socket
         |> assign(:trakt_integration, nil)
         |> put_flash(:info, "Trakt.tv disconnected")}
    end
  end

  @impl true
  def handle_event("plugin_connect", %{"slug" => slug}, socket) do
    case find_connectable(socket, slug) do
      nil ->
        {:noreply, socket}

      pc ->
        opts = [allowed_hosts: pc.allowed_hosts, slug: slug]

        case DeviceFlow.request_code(pc.descriptor, pc.client_id, opts) do
          {:ok, code} ->
            Process.send_after(self(), {:plugin_poll, slug}, code.interval_ms)

            connect =
              Map.merge(pc, %{
                user_code: code.user_code,
                verification_url: code.verification_url,
                poll_token: code.poll_token,
                interval_ms: code.interval_ms,
                expires_at: System.system_time(:second) + code.expires_in_s,
                error: nil
              })

            {:noreply, assign(socket, :plugin_connect, connect)}

          {:error, reason} ->
            Logger.warning("plugin #{slug} connect failed: #{inspect(reason)}")

            {:noreply,
             assign(socket, :plugin_connect, %{
               slug: slug,
               error: "Could not start the connection. Please try again."
             })}
        end
    end
  end

  @impl true
  def handle_event("plugin_cancel", _params, socket) do
    {:noreply, assign(socket, :plugin_connect, nil)}
  end

  @impl true
  def handle_event("plugin_disconnect", %{"slug" => slug}, socket) do
    user = socket.assigns.current_user
    Connections.disconnect(slug, user.id)

    {:noreply,
     socket
     |> assign(:plugin_connections, load_plugin_connections(user.id))
     |> assign(:plugin_connect, nil)
     |> put_flash(:info, "Disconnected.")}
  end

  @impl true
  def handle_info(:trakt_poll, socket) do
    if socket.assigns.trakt_polling do
      device_code = socket.assigns.trakt_device_code
      interval = socket.assigns.trakt_poll_interval

      case TraktClient.poll_device_token(device_code) do
        {:ok, token_data} ->
          user = socket.assigns.current_user

          attrs = %{
            provider: "trakt",
            access_token: token_data["access_token"],
            refresh_token: token_data["refresh_token"],
            token_expires_at: compute_trakt_expiry(token_data["expires_in"]),
            scopes: Map.get(token_data, "scope")
          }

          case Integrations.create_user_integration(user.id, attrs) do
            {:ok, integration} ->
              {:noreply,
               socket
               |> assign(:trakt_integration, integration)
               |> assign(:trakt_device_code, nil)
               |> assign(:trakt_user_code, nil)
               |> assign(:trakt_verification_url, nil)
               |> assign(:trakt_polling, false)
               |> assign(:trakt_poll_interval, nil)
               |> assign(:trakt_error, nil)
               |> put_flash(:info, "Trakt.tv connected successfully!")}

            {:error, reason} ->
              Logger.error("Failed to save Trakt integration: #{inspect(reason)}")

              {:noreply,
               socket
               |> assign(:trakt_polling, false)
               |> assign(:trakt_error, "Failed to save Trakt connection.")}
          end

        {:error, {:http_error, 400, _}} ->
          # Pending — schedule next poll
          Process.send_after(self(), :trakt_poll, interval)
          {:noreply, socket}

        {:error, {:http_error, 410, _}} ->
          # Expired
          {:noreply,
           socket
           |> assign(:trakt_polling, false)
           |> assign(:trakt_device_code, nil)
           |> assign(:trakt_user_code, nil)
           |> assign(:trakt_verification_url, nil)
           |> assign(:trakt_error, "Authorization code expired. Please try again.")}

        {:error, {:http_error, 418, _}} ->
          # Denied
          {:noreply,
           socket
           |> assign(:trakt_polling, false)
           |> assign(:trakt_device_code, nil)
           |> assign(:trakt_user_code, nil)
           |> assign(:trakt_verification_url, nil)
           |> assign(:trakt_error, "Authorization was denied.")}

        {:error, {:http_error, 429, _}} ->
          # Slow down — increase interval
          new_interval = interval + 1000
          Process.send_after(self(), :trakt_poll, new_interval)
          {:noreply, assign(socket, :trakt_poll_interval, new_interval)}

        {:error, reason} ->
          Logger.error("Trakt device poll error: #{inspect(reason)}")

          {:noreply,
           socket
           |> assign(:trakt_polling, false)
           |> assign(:trakt_error, "An error occurred. Please try again.")}
      end
    else
      {:noreply, socket}
    end
  end

  ## Plugin Connections (U8)

  @impl true
  def handle_info({:plugin_poll, slug}, socket) do
    connect = socket.assigns.plugin_connect

    if connect && connect.slug == slug && Map.get(connect, :user_code) do
      poll_plugin(socket, connect, slug)
    else
      {:noreply, socket}
    end
  end

  defp poll_plugin(socket, connect, slug) do
    if System.system_time(:second) >= connect.expires_at do
      {:noreply,
       assign(socket, :plugin_connect, connect_error(slug, "The code expired. Please try again."))}
    else
      opts = [allowed_hosts: connect.allowed_hosts, slug: slug]

      handle_poll(
        socket,
        connect,
        slug,
        DeviceFlow.poll(connect.descriptor, connect.poll_token, connect.client_id, opts)
      )
    end
  end

  defp handle_poll(socket, connect, slug, {:ok, token}) do
    user = socket.assigns.current_user

    attrs = %{
      access_token: token.access_token,
      external_user_id: Map.get(token, :external_user_id),
      status: "connected"
    }

    case Connections.connect(slug, user.id, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:plugin_connect, nil)
         |> assign(:plugin_connections, load_plugin_connections(user.id))
         |> put_flash(:info, "#{connect.name} connected.")}

      {:error, _} ->
        {:noreply,
         assign(socket, :plugin_connect, connect_error(slug, "Could not save the connection."))}
    end
  end

  defp handle_poll(socket, connect, slug, :pending) do
    Process.send_after(self(), {:plugin_poll, slug}, connect.interval_ms)
    {:noreply, socket}
  end

  defp handle_poll(socket, connect, slug, :slow_down) do
    # Honor the provider's back-pressure: double the interval, capped at 30s.
    new_interval = min(connect.interval_ms * 2, 30_000)
    Process.send_after(self(), {:plugin_poll, slug}, new_interval)
    {:noreply, assign(socket, :plugin_connect, %{connect | interval_ms: new_interval})}
  end

  defp handle_poll(socket, _connect, slug, :expired) do
    {:noreply,
     assign(socket, :plugin_connect, connect_error(slug, "The code expired. Please try again."))}
  end

  defp handle_poll(socket, _connect, slug, :denied) do
    {:noreply, assign(socket, :plugin_connect, connect_error(slug, "Authorization was denied."))}
  end

  defp handle_poll(socket, connect, slug, {:error, _reason}) do
    # A transient gate/network error — keep polling until expiry.
    Process.send_after(self(), {:plugin_poll, slug}, connect.interval_ms)
    {:noreply, socket}
  end

  defp connect_error(slug, message), do: %{slug: slug, error: message}

  defp find_connectable(socket, slug) do
    Enum.find(socket.assigns.plugin_connections, &(&1.slug == slug))
  end

  ## Private Helpers

  defp password_changeset(params \\ %{}) do
    types = %{
      current_password: :string,
      new_password: :string,
      confirm_password: :string
    }

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required([:current_password, :new_password, :confirm_password])
    |> Ecto.Changeset.validate_length(:new_password,
      min: 8,
      message: "must be at least 8 characters"
    )
    |> validate_password_confirmation()
  end

  defp validate_password_confirmation(changeset) do
    new_password = Ecto.Changeset.get_change(changeset, :new_password)
    confirm_password = Ecto.Changeset.get_change(changeset, :confirm_password)

    if new_password && confirm_password && new_password != confirm_password do
      Ecto.Changeset.add_error(changeset, :confirm_password, "does not match new password")
    else
      changeset
    end
  end

  defp auth_type(user) do
    if Accounts.oidc_user?(user) do
      "OpenID Connect (SSO)"
    else
      "Local"
    end
  end

  defp format_datetime(nil), do: "Never"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
  end

  defp compute_trakt_expiry(nil), do: nil

  defp compute_trakt_expiry(expires_in) when is_integer(expires_in) do
    DateTime.utc_now()
    |> DateTime.add(expires_in, :second)
    |> DateTime.truncate(:second)
  end
end
