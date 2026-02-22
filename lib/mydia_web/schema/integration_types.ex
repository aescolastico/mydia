defmodule MydiaWeb.Schema.IntegrationTypes do
  @moduledoc """
  GraphQL type definitions for external service integrations (e.g. Trakt.tv).
  """

  use Absinthe.Schema.Notation

  alias MydiaWeb.Schema.Resolvers.IntegrationResolver

  # ── Types ─────────────────────────────────────────────────────────────

  @desc "Status of a Trakt.tv integration"
  object :trakt_integration do
    field :id, :id
    field :connected, non_null(:boolean)
    field :enabled, non_null(:boolean)
    field :external_username, :string
    field :last_synced_at, :datetime
    field :auth_url, :string, description: "URL to redirect user for Trakt authorization"

    field :settings, :trakt_settings
  end

  @desc "Trakt integration settings"
  object :trakt_settings do
    field :scrobbling, non_null(:boolean)
    field :auto_sync, non_null(:boolean)
  end

  @desc "Input for updating Trakt settings"
  input_object :trakt_settings_input do
    field :scrobbling, :boolean
    field :auto_sync, :boolean
    field :enabled, :boolean
  end

  @desc "Result of a Trakt sync operation"
  object :trakt_sync_result do
    field :success, non_null(:boolean)
    field :message, :string
  end

  # ── Queries ───────────────────────────────────────────────────────────

  object :integration_queries do
    @desc "Get the current user's Trakt.tv integration status"
    field :trakt_integration, :trakt_integration do
      resolve(&IntegrationResolver.trakt_status/3)
    end
  end

  # ── Mutations ─────────────────────────────────────────────────────────

  object :integration_mutations do
    @desc "Connect Trakt.tv by exchanging an authorization code"
    field :connect_trakt, :trakt_integration do
      arg(:code, non_null(:string), description: "Authorization code from Trakt OAuth")
      arg(:redirect_uri, non_null(:string), description: "Redirect URI used in the OAuth flow")
      resolve(&IntegrationResolver.connect_trakt/3)
    end

    @desc "Disconnect Trakt.tv integration"
    field :disconnect_trakt, :boolean do
      resolve(&IntegrationResolver.disconnect_trakt/3)
    end

    @desc "Update Trakt.tv settings"
    field :update_trakt_settings, :trakt_integration do
      arg(:settings, non_null(:trakt_settings_input))
      resolve(&IntegrationResolver.update_trakt_settings/3)
    end

    @desc "Trigger a manual Trakt.tv sync"
    field :sync_trakt, :trakt_sync_result do
      arg(:sync_type, :string,
        default_value: "full",
        description: "Sync type: full, history, ratings, collection, watchlist"
      )

      resolve(&IntegrationResolver.trigger_sync/3)
    end
  end
end
