defmodule MydiaWeb.AdminDownloadClientsLive.Components do
  @moduledoc false
  use MydiaWeb, :html

  alias Mydia.Settings

  @doc """
  Renders the Download Clients tab content.
  """
  attr :download_clients, :list, required: true
  attr :client_health, :map, required: true

  def download_clients_tab(assigns) do
    ~H"""
    <div class="p-4 sm:p-6 space-y-4">
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <h2 class="text-lg font-semibold flex items-center gap-2">
          <.icon name="hero-arrow-down-tray" class="w-5 h-5 opacity-60" /> Download Clients
          <span class="badge badge-ghost">{length(@download_clients)}</span>
        </h2>
        <button class="btn btn-sm btn-primary" phx-click="new_download_client">
          <.icon name="hero-plus" class="w-4 h-4" /> New
        </button>
      </div>

      <%= if @download_clients == [] do %>
        <div class="alert alert-info">
          <.icon name="hero-information-circle" class="w-5 h-5" />
          <span>
            No download clients configured yet. Add qBittorrent or Transmission to get started.
          </span>
        </div>
      <% else %>
        <div class="bg-base-200 rounded-box divide-y divide-base-300">
          <%= for client <- @download_clients do %>
            <% health = Map.get(@client_health, client.id, %{status: :unknown}) %>
            <% is_runtime = Settings.runtime_config?(client) %>

            <div class="p-3 sm:p-4">
              <%!-- Mobile: stacked, Desktop: flex row --%>
              <div class="flex flex-col sm:flex-row sm:items-center gap-3">
                <%!-- Client Info --%>
                <div class="flex-1 min-w-0">
                  <div class="font-semibold flex items-center gap-2 flex-wrap">
                    {client.name}
                    <%= if is_runtime do %>
                      <span
                        class="badge badge-primary badge-xs tooltip"
                        data-tip="Configured via environment variables (read-only)"
                      >
                        <.icon name="hero-lock-closed" class="w-3 h-3" /> ENV
                      </span>
                    <% end %>
                  </div>
                  <div class="text-xs opacity-60 mt-1 truncate">
                    <span class="font-mono">
                      <%= if client.type == :blackhole do %>
                        {get_in(client.connection_settings || %{}, ["watch_folder"]) ||
                          "No watch folder"}
                      <% else %>
                        {if client.use_ssl, do: "https://", else: "http://"}{client.host}:{client.port}
                      <% end %>
                    </span>
                    <%= if client.category do %>
                      <span class="ml-2">Category: {client.category}</span>
                    <% end %>
                  </div>
                </div>

                <%!-- Status Badges + Actions row --%>
                <div class="flex flex-wrap items-center gap-2">
                  <%!-- Status Badges --%>
                  <span class="badge badge-sm badge-outline">{client.type}</span>
                  <span class={[
                    "badge badge-sm",
                    if(client.enabled, do: "badge-success", else: "badge-ghost")
                  ]}>
                    {if client.enabled, do: "Enabled", else: "Disabled"}
                  </span>
                  <span class={"badge badge-sm #{health_status_badge_class(health.status)}"}>
                    <.icon name={health_status_icon(health.status)} class="w-3 h-3 mr-1" />
                    {health_status_label(health.status)}
                  </span>
                  <%= if health.status == :unhealthy and health[:error] do %>
                    <div class="tooltip tooltip-left" data-tip={health.error}>
                      <.icon name="hero-information-circle" class="w-4 h-4 text-error" />
                    </div>
                  <% end %>
                  <%= if health.status == :healthy and health[:details] && Map.get(health.details, :version) do %>
                    <div
                      class="tooltip tooltip-left"
                      data-tip={"Version: #{health.details.version}"}
                    >
                      <.icon name="hero-information-circle" class="w-4 h-4 text-success" />
                    </div>
                  <% end %>

                  <%!-- Actions --%>
                  <div class="join ml-auto sm:ml-2">
                    <button
                      class="btn btn-sm btn-ghost join-item"
                      phx-click="test_download_client"
                      phx-value-id={client.id}
                      title="Test Connection"
                    >
                      <.icon name="hero-signal" class="w-4 h-4" />
                    </button>
                    <%= if is_runtime do %>
                      <div class="tooltip" data-tip="Cannot edit runtime-configured clients">
                        <button class="btn btn-sm btn-ghost join-item" disabled>
                          <.icon name="hero-pencil" class="w-4 h-4 opacity-30" />
                        </button>
                      </div>
                      <div class="tooltip" data-tip="Cannot delete runtime-configured clients">
                        <button class="btn btn-sm btn-ghost join-item" disabled>
                          <.icon name="hero-trash" class="w-4 h-4 opacity-30" />
                        </button>
                      </div>
                    <% else %>
                      <button
                        class="btn btn-sm btn-ghost join-item"
                        phx-click="edit_download_client"
                        phx-value-id={client.id}
                        title="Edit"
                      >
                        <.icon name="hero-pencil" class="w-4 h-4" />
                      </button>
                      <button
                        class="btn btn-sm btn-ghost join-item text-error"
                        phx-click="delete_download_client"
                        phx-value-id={client.id}
                        data-confirm="Are you sure you want to delete this download client?"
                        title="Delete"
                      >
                        <.icon name="hero-trash" class="w-4 h-4" />
                      </button>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the Download Client modal.
  """
  attr :download_client_form, :any, required: true
  attr :download_client_mode, :atom, required: true
  attr :testing_download_client_connection, :boolean, default: false

  def download_client_modal(assigns) do
    # Get the currently selected type to conditionally show fields
    selected_type =
      case Phoenix.HTML.Form.input_value(assigns.download_client_form, :type) do
        type when is_binary(type) -> type
        type when is_atom(type) -> Atom.to_string(type)
        _ -> "qbittorrent"
      end

    assigns = assign(assigns, :selected_type, selected_type)

    ~H"""
    <div class="modal modal-open">
      <div class="modal-box max-w-2xl">
        <.form
          for={@download_client_form}
          id="download-client-form"
          phx-change="validate_download_client"
          phx-submit="save_download_client"
        >
          <%!-- Header --%>
          <div class="flex items-center justify-between mb-5">
            <div class="flex items-center gap-3">
              <div class="w-10 h-10 rounded-xl bg-primary/20 flex items-center justify-center">
                <.icon
                  name={
                    if(@download_client_mode == :new,
                      do: "hero-plus-circle",
                      else: "hero-pencil-square"
                    )
                  }
                  class="w-5 h-5 text-primary"
                />
              </div>
              <div>
                <h3 class="font-bold text-lg">
                  {if @download_client_mode == :new,
                    do: "Add Download Client",
                    else: "Edit Download Client"}
                </h3>
                <p class="text-sm text-base-content/60">
                  {if @download_client_mode == :new,
                    do: "Configure a new download client",
                    else: "Update client settings"}
                </p>
              </div>
            </div>
            <label class="label cursor-pointer gap-2">
              <span class="label-text text-sm">Enabled</span>
              <input
                type="checkbox"
                name={@download_client_form[:enabled].name}
                value="true"
                checked={
                  Phoenix.HTML.Form.normalize_value("checkbox", @download_client_form[:enabled].value)
                }
                class="toggle toggle-success toggle-sm"
              />
            </label>
          </div>
          <div class="space-y-5">
            <%!-- Basic Settings Row --%>
            <div class="grid grid-cols-6 gap-3">
              <div class="col-span-6 md:col-span-3">
                <.input field={@download_client_form[:name]} type="text" label="Name" required />
              </div>
              <div class="col-span-4 md:col-span-2">
                <.input
                  field={@download_client_form[:type]}
                  type="select"
                  label="Type"
                  options={[
                    {"qBittorrent", "qbittorrent"},
                    {"Transmission", "transmission"},
                    {"rTorrent", "rtorrent"},
                    {"Blackhole", "blackhole"},
                    {"SABnzbd", "sabnzbd"},
                    {"NZBGet", "nzbget"},
                    {"HTTP", "http"}
                  ]}
                  required
                />
              </div>
              <div class="col-span-2 md:col-span-1">
                <.input field={@download_client_form[:priority]} type="number" label="Priority" />
              </div>
            </div>

            <div class="divider my-1"></div>

            <%= if @selected_type == "blackhole" do %>
              <%!-- Blackhole-specific fields --%>
              <div class="space-y-3">
                <div class="flex items-center gap-2 text-sm font-medium text-base-content/80">
                  <.icon name="hero-folder" class="w-4 h-4" />
                  <span>Folder Settings</span>
                </div>

                <div class="alert alert-info text-sm py-2">
                  <.icon name="hero-information-circle" class="w-4 h-4" />
                  <span>
                    Blackhole writes .torrent files to a watch folder for external processing.
                  </span>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                  <.input
                    name="download_client_config[connection_settings][watch_folder]"
                    type="text"
                    label="Watch Folder"
                    placeholder="/path/to/watch"
                    value={
                      get_in(
                        Phoenix.HTML.Form.input_value(@download_client_form, :connection_settings) ||
                          %{},
                        ["watch_folder"]
                      ) || ""
                    }
                    required
                  />
                  <.input
                    name="download_client_config[connection_settings][completed_folder]"
                    type="text"
                    label="Completed Folder"
                    placeholder="/path/to/completed"
                    value={
                      get_in(
                        Phoenix.HTML.Form.input_value(@download_client_form, :connection_settings) ||
                          %{},
                        ["completed_folder"]
                      ) || ""
                    }
                    required
                  />
                </div>

                <div class="flex items-center justify-between bg-base-200 rounded-lg px-4 py-3">
                  <div class="flex items-center gap-3">
                    <.icon name="hero-folder-open" class="w-4 h-4 text-base-content/60" />
                    <div>
                      <span class="text-sm font-medium">Category Subfolders</span>
                      <p class="text-xs text-base-content/50">Create movies/tv subfolders</p>
                    </div>
                  </div>
                  <input
                    type="checkbox"
                    name="download_client_config[connection_settings][use_category_subfolders]"
                    value="true"
                    checked={
                      get_in(
                        Phoenix.HTML.Form.input_value(@download_client_form, :connection_settings) ||
                          %{},
                        ["use_category_subfolders"]
                      ) == true
                    }
                    class="toggle toggle-primary toggle-sm"
                  />
                </div>
              </div>
            <% else %>
              <%!-- Network client fields --%>
              <div class="space-y-3">
                <div class="flex items-center gap-2 text-sm font-medium text-base-content/80">
                  <.icon name="hero-server" class="w-4 h-4" />
                  <span>Connection</span>
                </div>

                <div class="grid grid-cols-6 gap-3">
                  <div class="col-span-6 md:col-span-4">
                    <.input
                      field={@download_client_form[:host]}
                      type="text"
                      label="Host"
                      placeholder="localhost"
                      required
                    />
                  </div>
                  <div class="col-span-3 md:col-span-1">
                    <.input field={@download_client_form[:port]} type="number" label="Port" required />
                  </div>
                  <div class="col-span-3 md:col-span-1">
                    <.input field={@download_client_form[:use_ssl]} type="checkbox" label="SSL" />
                  </div>
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                  <.input field={@download_client_form[:username]} type="text" label="Username" />
                  <.input field={@download_client_form[:password]} type="password" label="Password" />
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                  <.input field={@download_client_form[:api_key]} type="password" label="API Key" />
                  <.input
                    field={@download_client_form[:url_base]}
                    type="text"
                    label="URL Base"
                    placeholder="/transmission/"
                  />
                </div>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                  <.input
                    field={@download_client_form[:category]}
                    type="text"
                    label="Category"
                    placeholder="mydia"
                  />
                  <.input
                    field={@download_client_form[:download_directory]}
                    type="text"
                    label="Download Directory"
                  />
                </div>
              </div>
            <% end %>

            <div class="divider my-1"></div>

            <%!-- Options Section --%>
            <div class="space-y-3">
              <div class="flex items-center gap-2 text-sm font-medium text-base-content/80">
                <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
                <span>Options</span>
              </div>

              <div class="flex items-center justify-between bg-base-200 rounded-lg px-4 py-3">
                <div class="flex items-center gap-3">
                  <.icon name="hero-trash" class="w-4 h-4 text-base-content/60" />
                  <div>
                    <span class="text-sm font-medium">Remove After Import</span>
                    <p class="text-xs text-base-content/50">
                      Remove downloads from client after importing
                    </p>
                  </div>
                </div>
                <input
                  type="checkbox"
                  name={@download_client_form[:remove_completed].name}
                  value="true"
                  checked={
                    Phoenix.HTML.Form.normalize_value(
                      "checkbox",
                      @download_client_form[:remove_completed].value
                    )
                  }
                  class="toggle toggle-primary toggle-sm"
                />
              </div>
            </div>
          </div>

          <%!-- Modal Actions --%>
          <div class="modal-action mt-6 pt-4 border-t border-base-300">
            <button type="button" class="btn btn-ghost" phx-click="close_download_client_modal">
              Cancel
            </button>
            <button
              type="button"
              class="btn btn-outline btn-secondary gap-2"
              phx-click="test_download_client_connection"
              disabled={@testing_download_client_connection}
            >
              <%= if @testing_download_client_connection do %>
                <span class="loading loading-spinner loading-sm"></span> Testing...
              <% else %>
                <.icon name="hero-signal" class="w-4 h-4" /> Test Connection
              <% end %>
            </button>
            <button type="submit" class="btn btn-primary gap-2">
              <.icon name="hero-check" class="w-4 h-4" />
              {if @download_client_mode == :new, do: "Add Client", else: "Save Changes"}
            </button>
          </div>
        </.form>
      </div>
      <div class="modal-backdrop bg-black/50" phx-click="close_download_client_modal"></div>
    </div>
    """
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp health_status_badge_class(:healthy), do: "badge-success"
  defp health_status_badge_class(:unhealthy), do: "badge-error"
  defp health_status_badge_class(:unknown), do: "badge-ghost"

  defp health_status_icon(:healthy), do: "hero-check-circle"
  defp health_status_icon(:unhealthy), do: "hero-x-circle"
  defp health_status_icon(:unknown), do: "hero-question-mark-circle"

  defp health_status_label(:healthy), do: "Healthy"
  defp health_status_label(:unhealthy), do: "Unhealthy"
  defp health_status_label(:unknown), do: "Unknown"
end
