defmodule Mydia.Integrations do
  @moduledoc """
  Context for managing external service integrations (e.g. Trakt.tv).
  """

  import Ecto.Query, warn: false
  alias Mydia.Repo
  alias Mydia.Integrations.UserIntegration

  require Logger

  # ── CRUD ──────────────────────────────────────────────────────────────

  @doc """
  Gets a user integration by user_id and provider.
  Returns nil if not found.
  """
  def get_user_integration(user_id, provider) do
    Repo.get_by(UserIntegration, user_id: user_id, provider: provider)
  end

  @doc """
  Gets a user integration by ID.
  """
  def get_user_integration!(id) do
    Repo.get!(UserIntegration, id)
  end

  @doc """
  Lists all integrations for a user.
  """
  def list_user_integrations(user_id) do
    from(i in UserIntegration, where: i.user_id == ^user_id)
    |> Repo.all()
  end

  @doc """
  Creates a user integration.
  `user_id` is set explicitly (not via cast) for security.
  """
  def create_user_integration(user_id, attrs) do
    %UserIntegration{user_id: user_id}
    |> UserIntegration.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :user_id, :inserted_at]},
      conflict_target: [:user_id, :provider]
    )
  end

  @doc """
  Updates an existing user integration.
  """
  def update_user_integration(%UserIntegration{} = integration, attrs) do
    integration
    |> UserIntegration.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user integration.
  """
  def delete_user_integration(%UserIntegration{} = integration) do
    Repo.delete(integration)
  end

  # ── Trakt Helpers ─────────────────────────────────────────────────────

  @doc """
  Returns the user's Trakt access token, refreshing if expired.
  Returns `{:ok, token}` or `{:error, reason}`.
  """
  def get_trakt_token(user_id) do
    case get_user_integration(user_id, "trakt") do
      nil ->
        {:error, :not_connected}

      %UserIntegration{enabled: false} ->
        {:error, :disabled}

      %UserIntegration{} = integration ->
        if UserIntegration.token_expired?(integration) do
          refresh_trakt_token(integration)
        else
          {:ok, integration.access_token}
        end
    end
  end

  @doc """
  Refreshes a Trakt token via the metadata-relay.
  """
  def refresh_trakt_token(%UserIntegration{} = integration) do
    alias Mydia.Integrations.Trakt.Client

    case Client.refresh_token(integration.refresh_token) do
      {:ok, token_data} ->
        expires_at = compute_expiry(token_data["expires_in"])

        attrs = %{
          access_token: token_data["access_token"],
          refresh_token: token_data["refresh_token"],
          token_expires_at: expires_at
        }

        case update_user_integration(integration, attrs) do
          {:ok, updated} -> {:ok, updated.access_token}
          {:error, changeset} -> {:error, changeset}
        end

      {:error, reason} ->
        Logger.warning(
          "Failed to refresh Trakt token for user #{integration.user_id}: #{inspect(reason)}"
        )

        {:error, :refresh_failed}
    end
  end

  @doc """
  Returns true if the user has Trakt enabled.
  """
  def trakt_enabled?(user_id) do
    case get_user_integration(user_id, "trakt") do
      %UserIntegration{enabled: true} -> true
      _ -> false
    end
  end

  @doc """
  Returns true if the user has Trakt scrobbling enabled.
  """
  def trakt_scrobbling_enabled?(user_id) do
    case get_user_integration(user_id, "trakt") do
      %UserIntegration{enabled: true, settings: settings} ->
        Map.get(settings || %{}, "scrobbling", true)

      _ ->
        false
    end
  end

  @doc """
  Lists all users with active Trakt integrations.
  """
  def list_active_trakt_users do
    from(i in UserIntegration,
      where: i.provider == "trakt" and i.enabled == true,
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc """
  Lists integrations with tokens expiring within the given number of days.
  """
  def list_integrations_needing_refresh(days \\ 7) do
    cutoff = DateTime.utc_now() |> DateTime.add(days * 86_400, :second)

    from(i in UserIntegration,
      where:
        i.enabled == true and
          not is_nil(i.token_expires_at) and
          i.token_expires_at < ^cutoff
    )
    |> Repo.all()
  end

  # ── Private Helpers ───────────────────────────────────────────────────

  defp compute_expiry(nil), do: nil

  defp compute_expiry(expires_in) when is_integer(expires_in) do
    DateTime.utc_now()
    |> DateTime.add(expires_in, :second)
    |> DateTime.truncate(:second)
  end
end
