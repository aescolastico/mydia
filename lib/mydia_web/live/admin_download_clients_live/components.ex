defmodule MydiaWeb.AdminDownloadClientsLive.Components do
  @moduledoc false
  use MydiaWeb, :html

  alias Mydia.Settings

  # Client types that surface category configuration in the admin form.
  # Blackhole uses filesystem paths (no concept of a per-content-type
  # category); HTTP is a generic transport with no client-side category
  # taxonomy either.
  @category_aware_types ~w(qbittorrent transmission rtorrent sabnzbd nzbget)

  # Client types that surface the 5-tier priority profile UI. Same set as
  # `@category_aware_types` minus blackhole — every adapter that maps the
  # abstract priority to a native value is listed here.
  @priority_profile_types ~w(qbittorrent transmission rtorrent sabnzbd nzbget)

  # Client types that emit post-processing webhooks. These are the only
  # adapters with a UI affordance for the webhook URL + script snippet.
  @webhook_capable_types ~w(sabnzbd nzbget)

  # Placeholder hints shown in the per-tier priority profile inputs. Each
  # adapter has its own native priority value domain; the placeholder mirrors
  # the hardcoded default mapping so users see what value they'd get if they
  # left the override blank.
  @priority_profile_placeholders %{
    "sabnzbd" => %{
      "verylow" => "-100",
      "low" => "-1",
      "normal" => "0",
      "high" => "1",
      "veryhigh" => "2"
    },
    "nzbget" => %{
      "verylow" => "-100",
      "low" => "-50",
      "normal" => "0",
      "high" => "50",
      "veryhigh" => "100"
    },
    "qbittorrent" => %{
      "verylow" => "(unset)",
      "low" => "(unset)",
      "normal" => "(unset)",
      "high" => "(unset)",
      "veryhigh" => "(unset)"
    },
    "transmission" => %{
      "verylow" => "-1",
      "low" => "-1",
      "normal" => "0",
      "high" => "1",
      "veryhigh" => "1"
    },
    "rtorrent" => %{
      "verylow" => "0",
      "low" => "1",
      "normal" => "2",
      "high" => "3",
      "veryhigh" => "3"
    }
  }

  @priority_tiers [
    {"verylow", "Very Low"},
    {"low", "Low"},
    {"normal", "Normal"},
    {"high", "High"},
    {"veryhigh", "Very High"}
  ]

  @content_types [
    {"movie", "Movies"},
    {"tv", "TV Shows"},
    {"music", "Music"}
  ]

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
  attr :editing_download_client, :any, default: nil
  attr :webhook_base_url, :string, default: ""

  def download_client_modal(assigns) do
    # Get the currently selected type to conditionally show fields. The
    # `nil`/`""` clauses match before the catch-all `is_atom` branch
    # because `is_atom(nil)` would otherwise stringify to `"nil"` for a
    # fresh changeset — defaulting to qBittorrent yields a more useful
    # empty form.
    selected_type =
      case Phoenix.HTML.Form.input_value(assigns.download_client_form, :type) do
        nil -> "qbittorrent"
        "" -> "qbittorrent"
        type when is_binary(type) -> type
        type when is_atom(type) -> Atom.to_string(type)
        _ -> "qbittorrent"
      end

    form = assigns.download_client_form

    # Derive the current per-content-type categories map for prefilling
    # inputs. Falls back to the legacy single `:category` value for all
    # three slots when the new map is empty — this surfaces existing
    # behaviour without forcing the user to re-enter on first edit.
    categories_value =
      case Phoenix.HTML.Form.input_value(form, :categories) do
        map when is_map(map) and map_size(map) > 0 -> map
        _ -> %{}
      end

    legacy_category =
      case Phoenix.HTML.Form.input_value(form, :category) do
        value when is_binary(value) -> value
        _ -> ""
      end

    has_legacy_only? = map_size(categories_value) == 0 and legacy_category != ""

    priority_profile_value =
      case Phoenix.HTML.Form.input_value(form, :priority_profile) do
        map when is_map(map) -> map
        _ -> %{}
      end

    show_categories? = selected_type in @category_aware_types
    show_priority_profile? = selected_type in @priority_profile_types
    show_webhook? = selected_type in @webhook_capable_types

    webhook_secret =
      case assigns[:editing_download_client] do
        %{webhook_secret: secret} when is_binary(secret) and secret != "" -> secret
        _ -> nil
      end

    client_id =
      case assigns[:editing_download_client] do
        %{id: id} when is_binary(id) -> id
        _ -> nil
      end

    webhook_url =
      if (show_webhook? and webhook_secret) && client_id && assigns[:webhook_base_url] != "" do
        "#{assigns.webhook_base_url}/api/webhooks/usenet/#{client_id}?secret=#{webhook_secret}"
      else
        nil
      end

    priority_placeholders = Map.get(@priority_profile_placeholders, selected_type, %{})

    assigns =
      assigns
      |> assign(:selected_type, selected_type)
      |> assign(:categories_value, categories_value)
      |> assign(:legacy_category, legacy_category)
      |> assign(:has_legacy_only?, has_legacy_only?)
      |> assign(:priority_profile_value, priority_profile_value)
      |> assign(:show_categories?, show_categories?)
      |> assign(:show_priority_profile?, show_priority_profile?)
      |> assign(:show_webhook?, show_webhook?)
      |> assign(:webhook_url, webhook_url)
      |> assign(:priority_placeholders, priority_placeholders)
      |> assign(:priority_tiers, @priority_tiers)
      |> assign(:content_types, @content_types)

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
                    field={@download_client_form[:download_directory]}
                    type="text"
                    label="Download Directory"
                  />
                </div>
              </div>
            <% end %>

            <%!-- Per-content-type categories. Hidden for blackhole and HTTP transports. --%>
            <%= if @show_categories? do %>
              <div class="space-y-3" id="download-client-categories">
                <div class="flex items-center gap-2 text-sm font-medium text-base-content/80">
                  <.icon name="hero-tag" class="w-4 h-4" />
                  <span>Categories</span>
                </div>

                <%= if @has_legacy_only? do %>
                  <div class="alert alert-warning text-sm py-2">
                    <.icon name="hero-information-circle" class="w-4 h-4" />
                    <span>
                      This client uses the legacy single category
                      <code class="font-mono">{@legacy_category}</code>
                      for all content types. Saving will migrate it to per-content-type categories below.
                    </span>
                  </div>
                <% end %>

                <p class="text-xs text-base-content/50">
                  Optional. Routes downloads to the right client-side category by content type.
                </p>

                <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
                  <%= for {key, label} <- @content_types do %>
                    <.input
                      name={"download_client_config[categories][#{key}]"}
                      id={"download-client-categories-#{key}"}
                      type="text"
                      label={label}
                      placeholder="mydia"
                      value={
                        Map.get(@categories_value, key) || (@has_legacy_only? && @legacy_category) ||
                          ""
                      }
                    />
                  <% end %>
                </div>
              </div>
            <% end %>

            <%!-- Stalled timeout. Visible for every client type. --%>
            <div class="space-y-2">
              <.input
                field={@download_client_form[:incomplete_grace_minutes]}
                id="download-client-grace-minutes"
                type="number"
                label="Stalled timeout (minutes)"
                placeholder="60"
                min="1"
              />
              <p class="text-xs text-base-content/50">
                A download with no byte progress for this many minutes is flagged as stalled.
              </p>
            </div>

            <%!-- Priority profile (collapsed advanced section). --%>
            <%= if @show_priority_profile? do %>
              <details
                class="collapse collapse-arrow bg-base-200"
                id="download-client-priority-profile"
              >
                <summary class="collapse-title text-sm font-medium flex items-center gap-2">
                  <.icon name="hero-bolt" class="w-4 h-4 text-base-content/60" />
                  <span>Advanced: Priority profile</span>
                  <span class="text-xs text-base-content/50">
                    (overrides the per-tier value sent to the client)
                  </span>
                </summary>
                <div class="collapse-content space-y-3">
                  <p class="text-xs text-base-content/50">
                    Map each abstract priority tier to the value this client understands.
                    Leave blank to use the adapter's built-in default (shown as placeholder).
                  </p>
                  <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-3">
                    <%= for {key, label} <- @priority_tiers do %>
                      <.input
                        name={"download_client_config[priority_profile][#{key}]"}
                        id={"download-client-priority-#{key}"}
                        type="text"
                        label={label}
                        placeholder={Map.get(@priority_placeholders, key) || ""}
                        value={Map.get(@priority_profile_value, key) || ""}
                      />
                    <% end %>
                  </div>
                </div>
              </details>
            <% end %>

            <%!-- Webhook URL + post-processing script (SABnzbd/NZBGet only). --%>
            <%= if @show_webhook? do %>
              <div class="space-y-3" id="download-client-webhook">
                <div class="flex items-center gap-2 text-sm font-medium text-base-content/80">
                  <.icon name="hero-bell" class="w-4 h-4" />
                  <span>Post-processing webhook</span>
                </div>

                <%= cond do %>
                  <% @download_client_mode == :new -> %>
                    <div class="alert alert-info text-sm py-2" id="download-client-webhook-new-hint">
                      <.icon name="hero-information-circle" class="w-4 h-4" />
                      <span>Save the client to reveal the webhook URL.</span>
                    </div>
                  <% is_nil(@webhook_url) -> %>
                    <div
                      class="alert alert-warning text-sm py-2"
                      id="download-client-webhook-missing-hint"
                    >
                      <.icon name="hero-exclamation-triangle" class="w-4 h-4" />
                      <span>Webhook secret not yet generated. Save once to provision it.</span>
                    </div>
                  <% true -> %>
                    <p class="text-xs text-base-content/50">
                      Paste this URL into your client's post-processing script so Mydia imports the download
                      the moment it finishes (instead of waiting for the next poll).
                    </p>

                    <div class="flex items-center gap-2">
                      <input
                        type="text"
                        class="input input-bordered input-sm font-mono w-full"
                        value={@webhook_url}
                        readonly
                        id="download-client-webhook-url"
                        aria-label="Webhook URL"
                      />
                      <button
                        type="button"
                        class="btn btn-sm btn-ghost"
                        title="Copy URL"
                        onclick={"navigator.clipboard.writeText('#{@webhook_url}')"}
                      >
                        <.icon name="hero-clipboard-document" class="w-4 h-4" />
                      </button>
                    </div>

                    <%= if @selected_type == "sabnzbd" do %>
                      <div class="space-y-1">
                        <p class="text-xs font-medium text-base-content/70">
                          SABnzbd notification script (save as
                          <code class="font-mono">mydia_notify.py</code>
                          under the script folder, then select it as <em>Notification script</em>
                          in Config &rarr; General):
                        </p>
                        <pre
                          class="bg-base-300 text-xs p-3 rounded-lg overflow-x-auto font-mono"
                          id="download-client-webhook-snippet-sabnzbd"
                          phx-no-curly-interpolation
                        ><%= sabnzbd_script(@webhook_url) %></pre>
                      </div>
                    <% end %>

                    <%= if @selected_type == "nzbget" do %>
                      <div class="space-y-1">
                        <p class="text-xs font-medium text-base-content/70">
                          NZBGet post-processing script (save as
                          <code class="font-mono">mydia_notify.sh</code>
                          under the scripts folder, mark executable, then enable under <em>Settings &rarr; Extension scripts</em>):
                        </p>
                        <pre
                          class="bg-base-300 text-xs p-3 rounded-lg overflow-x-auto font-mono"
                          id="download-client-webhook-snippet-nzbget"
                          phx-no-curly-interpolation
                        ><%= nzbget_script(@webhook_url) %></pre>
                      </div>
                    <% end %>

                    <button
                      type="button"
                      class="btn btn-sm btn-ghost gap-1"
                      title="Copy script"
                      id="download-client-webhook-script-copy"
                      onclick={"navigator.clipboard.writeText(document.getElementById('download-client-webhook-snippet-#{@selected_type}').innerText)"}
                    >
                      <.icon name="hero-clipboard-document" class="w-4 h-4" /> Copy script
                    </button>
                <% end %>
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

  # Post-processing script templates for the SABnzbd notification webhook.
  # Kept as plain Elixir strings (not heredocs in templates) to sidestep
  # HEEx's curly-brace interpolation rules while keeping the script
  # comfortably editable.
  defp sabnzbd_script(webhook_url) do
    """
    #!/usr/bin/env python3
    import json, os, sys, urllib.request

    payload = {
        "name": os.environ.get("SAB_FINAL_NAME", ""),
        "nzo_id": os.environ.get("SAB_NZO_ID", ""),
        "status": os.environ.get("SAB_STATUS", ""),
        "storage": os.environ.get("SAB_COMPLETE_DIR", ""),
    }

    req = urllib.request.Request(
        "#{webhook_url}",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "User-Agent": "SABnzbd"},
    )
    try:
        urllib.request.urlopen(req, timeout=10).read()
    except Exception as exc:
        print("mydia webhook failed:", exc, file=sys.stderr)
        sys.exit(1)
    """
  end

  defp nzbget_script(webhook_url) do
    """
    #!/usr/bin/env bash
    # NZBGet post-processing script for Mydia
    set -eu

    curl -fsS -X POST \\
      -H "Content-Type: application/json" \\
      -H "User-Agent: NZBGet" \\
      --data "{\\"NZBID\\":\\"$NZBPP_NZBID\\",\\"NZBName\\":\\"$NZBPP_NZBNAME\\",\\"DestDir\\":\\"$NZBPP_DIRECTORY\\",\\"Status\\":\\"$NZBPP_STATUS\\"}" \\
      "#{webhook_url}" \\
      || echo "mydia webhook failed (continuing)"

    exit 93
    """
  end
end
