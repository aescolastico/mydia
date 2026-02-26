defmodule MydiaWeb.Schema.Resolvers.IntegrationResolver do
  @moduledoc """
  GraphQL resolvers for Trakt.tv and other external integrations.
  """

  alias Mydia.Integrations
  alias Mydia.Integrations.Trakt.Client
  alias Mydia.Integrations.UserIntegration

  require Logger

  @doc """
  Returns the current user's Trakt integration status.
  """
  def trakt_status(_parent, _args, %{context: context}) do
    case context[:current_user] do
      nil ->
        {:error, "Authentication required"}

      user ->
        case Integrations.get_user_integration(user.id, "trakt") do
          nil ->
            {:ok,
             %{
               connected: false,
               enabled: false,
               external_username: nil,
               last_synced_at: nil,
               settings: %{scrobbling: false, auto_sync: false}
             }}

          integration ->
            {:ok,
             %{
               id: integration.id,
               connected: true,
               enabled: integration.enabled,
               external_username: integration.external_username,
               last_synced_at: integration.last_synced_at,
               settings: build_settings(integration)
             }}
        end
    end
  end

  @doc """
  Generates a device code for the Trakt device authorization flow.
  """
  def generate_device_code(_parent, _args, %{context: context}) do
    case context[:current_user] do
      nil ->
        {:error, "Authentication required"}

      _user ->
        case Client.generate_device_code() do
          {:ok, data} ->
            {:ok,
             %{
               device_code: data["device_code"],
               user_code: data["user_code"],
               verification_url: data["verification_url"],
               expires_in: data["expires_in"],
               interval: data["interval"]
             }}

          {:error, reason} ->
            {:error, "Failed to generate device code: #{inspect(reason)}"}
        end
    end
  end

  @doc """
  Polls for the device token after the user has entered the code on Trakt.
  Returns status + integration on success.
  """
  def poll_device_token(_parent, %{device_code: device_code}, %{context: context}) do
    case context[:current_user] do
      nil ->
        {:error, "Authentication required"}

      user ->
        case Client.poll_device_token(device_code) do
          {:ok, token_data} ->
            attrs = %{
              provider: "trakt",
              access_token: token_data["access_token"],
              refresh_token: token_data["refresh_token"],
              token_expires_at: compute_expiry(token_data["expires_in"]),
              scopes: Map.get(token_data, "scope")
            }

            case Integrations.create_user_integration(user.id, attrs) do
              {:ok, integration} ->
                {:ok,
                 %{
                   status: "authorized",
                   integration: %{
                     id: integration.id,
                     connected: true,
                     enabled: integration.enabled,
                     external_username: integration.external_username,
                     last_synced_at: nil,
                     settings: build_settings(integration)
                   }
                 }}

              {:error, changeset} ->
                {:error, "Failed to save integration: #{inspect(changeset.errors)}"}
            end

          {:error, {:http_error, 400, _}} ->
            {:ok, %{status: "pending", integration: nil}}

          {:error, {:http_error, 410, _}} ->
            {:ok, %{status: "expired", integration: nil}}

          {:error, {:http_error, 418, _}} ->
            {:ok, %{status: "denied", integration: nil}}

          {:error, {:http_error, 429, _}} ->
            {:ok, %{status: "slow_down", integration: nil}}

          {:error, _reason} ->
            {:ok, %{status: "error", integration: nil}}
        end
    end
  end

  @doc """
  Disconnects Trakt integration.
  """
  def disconnect_trakt(_parent, _args, %{context: context}) do
    case context[:current_user] do
      nil ->
        {:error, "Authentication required"}

      user ->
        case Integrations.get_user_integration(user.id, "trakt") do
          nil ->
            {:ok, true}

          integration ->
            # Best-effort revoke
            Client.revoke_token(integration.access_token)
            Integrations.delete_user_integration(integration)
            {:ok, true}
        end
    end
  end

  @doc """
  Updates Trakt integration settings.
  """
  def update_trakt_settings(_parent, %{settings: settings_input}, %{context: context}) do
    case context[:current_user] do
      nil ->
        {:error, "Authentication required"}

      user ->
        case Integrations.get_user_integration(user.id, "trakt") do
          nil ->
            {:error, "Trakt is not connected"}

          integration ->
            current_settings = integration.settings || %{}

            new_settings =
              current_settings
              |> maybe_put("scrobbling", settings_input[:scrobbling])
              |> maybe_put("auto_sync", settings_input[:auto_sync])

            attrs = %{settings: new_settings}

            attrs =
              if Map.has_key?(settings_input, :enabled) do
                Map.put(attrs, :enabled, settings_input.enabled)
              else
                attrs
              end

            case Integrations.update_user_integration(integration, attrs) do
              {:ok, updated} ->
                {:ok,
                 %{
                   id: updated.id,
                   connected: true,
                   enabled: updated.enabled,
                   external_username: updated.external_username,
                   last_synced_at: updated.last_synced_at,
                   settings: build_settings(updated)
                 }}

              {:error, changeset} ->
                {:error, "Failed to update settings: #{inspect(changeset.errors)}"}
            end
        end
    end
  end

  @doc """
  Enqueues a manual Trakt sync job.
  """
  def trigger_sync(_parent, %{sync_type: sync_type}, %{context: context}) do
    case context[:current_user] do
      nil ->
        {:error, "Authentication required"}

      user ->
        if Integrations.trakt_enabled?(user.id) do
          %{user_id: user.id, sync_type: sync_type}
          |> Mydia.Jobs.TraktSync.new()
          |> Oban.insert()

          {:ok, %{success: true, message: "Sync job queued"}}
        else
          {:error, "Trakt is not connected or disabled"}
        end
    end
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp build_settings(%UserIntegration{settings: nil}) do
    %{scrobbling: true, auto_sync: false}
  end

  defp build_settings(%UserIntegration{settings: settings}) do
    %{
      scrobbling: Map.get(settings, "scrobbling", true),
      auto_sync: Map.get(settings, "auto_sync", false)
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp compute_expiry(nil), do: nil

  defp compute_expiry(expires_in) when is_integer(expires_in) do
    DateTime.utc_now()
    |> DateTime.add(expires_in, :second)
    |> DateTime.truncate(:second)
  end
end
