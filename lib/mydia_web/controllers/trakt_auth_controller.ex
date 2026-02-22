defmodule MydiaWeb.TraktAuthController do
  @moduledoc """
  Handles the Trakt.tv OAuth2 flow.

  - GET  /auth/trakt          — Redirects user to Trakt authorize URL
  - GET  /auth/trakt/callback — Receives auth code, exchanges for tokens
  - DELETE /auth/trakt        — Revokes token and disconnects
  """
  use MydiaWeb, :controller

  alias Mydia.Auth.Guardian
  alias Mydia.Integrations
  alias Mydia.Integrations.Trakt.Client

  require Logger

  @trakt_authorize_url "https://trakt.tv/oauth/authorize"

  @doc """
  Initiates Trakt OAuth by fetching the client_id from the relay,
  then redirecting the user to Trakt's authorize page.
  """
  def authorize(conn, _params) do
    redirect_uri = callback_url()

    case Client.get_config() do
      {:ok, %{"client_id" => client_id}} ->
        authorize_url =
          "#{@trakt_authorize_url}?" <>
            URI.encode_query(%{
              response_type: "code",
              client_id: client_id,
              redirect_uri: redirect_uri
            })

        redirect(conn, external: authorize_url)

      {:error, reason} ->
        Logger.error("Failed to fetch Trakt config from relay: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Failed to connect to Trakt. Please try again later.")
        |> redirect(to: ~p"/profile")
    end
  end

  @doc """
  Callback from Trakt after user authorizes.
  Exchanges the code for tokens and stores them.
  """
  def callback(conn, %{"code" => code}) do
    user = Guardian.Plug.current_resource(conn)
    redirect_uri = callback_url()

    case Client.exchange_code(code, redirect_uri) do
      {:ok, token_data} ->
        attrs = %{
          provider: "trakt",
          access_token: token_data["access_token"],
          refresh_token: token_data["refresh_token"],
          token_expires_at: compute_expiry(token_data["expires_in"]),
          scopes: Map.get(token_data, "scope")
        }

        case Integrations.create_user_integration(user.id, attrs) do
          {:ok, _integration} ->
            conn
            |> put_flash(:info, "Trakt.tv connected successfully!")
            |> redirect(to: ~p"/profile")

          {:error, reason} ->
            Logger.error("Failed to save Trakt integration: #{inspect(reason)}")

            conn
            |> put_flash(:error, "Failed to save Trakt connection.")
            |> redirect(to: ~p"/profile")
        end

      {:error, reason} ->
        Logger.error("Failed to exchange Trakt code: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Failed to connect Trakt. Please try again.")
        |> redirect(to: ~p"/profile")
    end
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Trakt authorization was denied or failed.")
    |> redirect(to: ~p"/profile")
  end

  @doc """
  Disconnects Trakt by revoking the token and removing the integration.
  """
  def disconnect(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    case Integrations.get_user_integration(user.id, "trakt") do
      nil ->
        conn
        |> put_flash(:info, "Trakt is not connected.")
        |> redirect(to: ~p"/profile")

      integration ->
        # Best-effort revoke with relay
        Client.revoke_token(integration.access_token)

        case Integrations.delete_user_integration(integration) do
          {:ok, _} ->
            conn
            |> put_flash(:info, "Trakt.tv disconnected.")
            |> redirect(to: ~p"/profile")

          {:error, reason} ->
            Logger.error("Failed to delete Trakt integration: #{inspect(reason)}")

            conn
            |> put_flash(:error, "Failed to disconnect Trakt.")
            |> redirect(to: ~p"/profile")
        end
    end
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp callback_url do
    MydiaWeb.Endpoint.url() <> "/auth/trakt/callback"
  end

  defp compute_expiry(nil), do: nil

  defp compute_expiry(expires_in) when is_integer(expires_in) do
    DateTime.utc_now()
    |> DateTime.add(expires_in, :second)
    |> DateTime.truncate(:second)
  end
end
