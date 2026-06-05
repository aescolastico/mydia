defmodule MydiaWeb.FlareSolverrStatusComponent do
  @moduledoc """
  FlareSolverr status probe used by the Indexers tab.

  Exposes `get_status/0`, which reports whether FlareSolverr is configured and
  reachable. The rendering lives in the Indexers tab's `flaresolverr_panel`
  component (`MydiaWeb.AdminIndexersLive.Components`).
  """

  alias Mydia.Indexers.FlareSolverr

  @doc """
  Gets the current FlareSolverr status.

  Returns a map with:
  - configured: boolean indicating if FlareSolverr URL is set
  - status: :healthy, :unhealthy, or :disabled
  - url: the configured URL
  - version: FlareSolverr version (if healthy)
  - sessions: list of active sessions (if healthy)
  - error: error details (if unhealthy)
  """
  def get_status do
    config = FlareSolverr.config()

    if config && config.enabled && is_binary(config.url) && config.url != "" do
      case FlareSolverr.health_check() do
        {:ok, info} ->
          %{
            configured: true,
            status: :healthy,
            url: config.url,
            version: info[:version],
            sessions: info[:sessions] || []
          }

        {:error, reason} ->
          %{
            configured: true,
            status: :unhealthy,
            url: config.url,
            error: reason
          }
      end
    else
      %{
        configured: config != nil && is_binary(config[:url]) && config[:url] != "",
        status: :disabled,
        url: config && config[:url]
      }
    end
  end
end
