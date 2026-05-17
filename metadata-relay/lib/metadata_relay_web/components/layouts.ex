defmodule MetadataRelayWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: MetadataRelayWeb.Endpoint,
    router: MetadataRelayWeb.Router,
    statics: ~w(assets css js images favicon.ico robots.txt)

  attr(:flash, :map, default: %{})
  slot(:inner_block, required: true)

  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 text-base-content">
      <div class="mx-auto flex min-h-screen w-full max-w-7xl flex-col gap-6 px-4 py-6 sm:px-6 lg:px-8">
        <div :if={Phoenix.Flash.get(@flash, :error)} id="dashboard-flash-error" class="alert alert-error shadow-sm">
          <span>{Phoenix.Flash.get(@flash, :error)}</span>
        </div>

        <div :if={Phoenix.Flash.get(@flash, :info)} id="dashboard-flash-info" class="alert alert-info shadow-sm">
          <span>{Phoenix.Flash.get(@flash, :info)}</span>
        </div>

        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  embed_templates("layouts/*")
end
