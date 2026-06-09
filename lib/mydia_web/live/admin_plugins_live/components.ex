defmodule MydiaWeb.AdminPluginsLive.Components do
  @moduledoc """
  Components for the admin plugin store and capability-approval UI (U9).

  The capability labels here are **host-owned**: they are derived from the
  capability *class*, never from author-supplied manifest free-text (KTD6). A
  plugin author cannot influence the words the admin reads when approving — that
  is the whole point of the approval surface.
  """
  use MydiaWeb, :html

  @doc """
  Plain-language description of a single declared capability.

  `class` is the taxonomy class and `values` its declared values (hosts, events,
  namespaces). Always host-authored.
  """
  @spec capability_label(String.t(), [String.t()]) :: String.t()
  def capability_label("net:http", hosts),
    do: "Make network requests to: #{join(hosts)}"

  def capability_label("events:subscribe", events),
    do: "React to these events: #{join(events)}"

  def capability_label("data:read", namespaces),
    do: "Read your library data: #{join(namespaces)}"

  def capability_label("surfaces:write", surfaces),
    do: "Write to these surfaces: #{join(surfaces)}"

  def capability_label(other, values),
    do: "#{other}: #{join(values)}"

  @doc "The hero icon for a capability class (host-owned)."
  @spec capability_icon(String.t()) :: String.t()
  def capability_icon("net:http"), do: "hero-globe-alt"
  def capability_icon("events:subscribe"), do: "hero-bell-alert"
  def capability_icon("data:read"), do: "hero-book-open"
  def capability_icon("surfaces:write"), do: "hero-pencil-square"
  def capability_icon(_), do: "hero-key"

  @doc "True when a capability class carries privacy/security weight worth emphasizing."
  @spec sensitive_capability?(String.t()) :: boolean()
  def sensitive_capability?(class), do: class in ["net:http", "data:read", "surfaces:write"]

  defp join([]), do: "(none)"
  defp join(values), do: Enum.join(values, ", ")

  @doc """
  Renders the Plugins tab: header, installed summary rows, and the store catalog.

  Each installed plugin renders a compact summary row with provenance and
  lifecycle actions; env-sourced rows render read-only. The catalog lists
  available store entries with an Install action.
  """
  attr :installed, :list, required: true
  attr :catalog, :list, required: true
  attr :updates, :any, required: true
  attr :browse_error, :string, default: nil

  def plugins_tab(assigns) do
    ~H"""
    <div class="p-4 sm:p-6 space-y-4">
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <div>
          <h2 class="text-lg font-semibold flex items-center gap-2">
            <.icon name="hero-puzzle-piece" class="w-5 h-5 opacity-60" /> Plugins
            <span class="badge badge-ghost">{length(@installed)}</span>
          </h2>
          <p class="text-sm text-base-content/70 mt-1">
            Sandboxed extensions. Each plugin runs with only the capabilities you approve.
          </p>
        </div>
        <.button
          id="browse-store"
          variant="primary"
          class="btn btn-sm btn-primary"
          phx-click="browse_store"
        >
          <.icon name="hero-squares-plus" class="w-4 h-4" /> Browse store
        </.button>
      </div>

      <%!-- Installed plugins --%>
      <div id="plugins-installed" class="space-y-2">
        <div :if={@installed == []} class="alert alert-info">
          <.icon name="hero-information-circle" class="w-5 h-5" />
          <span>No plugins installed yet. Browse the store to add one.</span>
        </div>

        <div :if={@installed != []} class="bg-base-200 rounded-box divide-y divide-base-300">
          <.plugin_row :for={plugin <- @installed} plugin={plugin} updates={@updates} />
        </div>
      </div>

      <%!-- Store catalog --%>
      <div :if={@browse_error} id="browse-error" class="alert alert-error">
        <.icon name="hero-exclamation-triangle" class="w-5 h-5" />
        <span>Could not reach a plugin source: {@browse_error}</span>
      </div>

      <div :if={@catalog != []} id="plugin-catalog" class="space-y-2">
        <h3 class="text-base font-semibold">Available</h3>
        <div class="bg-base-200 rounded-box divide-y divide-base-300">
          <.catalog_row :for={entry <- @catalog} entry={entry} />
        </div>
      </div>
    </div>
    """
  end

  @doc "A compact summary row for one installed plugin (provenance + lifecycle)."
  attr :plugin, :map, required: true
  attr :updates, :any, required: true

  def plugin_row(assigns) do
    ~H"""
    <div
      id={"plugin-row-#{@plugin.slug}"}
      class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 p-3 sm:p-4"
    >
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2 flex-wrap">
          <span class="font-medium truncate">{@plugin.name}</span>
          <span class="text-xs text-base-content/50">v{@plugin.version}</span>
          <.source_badge source={@plugin.source} />
          <span class={[
            "badge badge-sm",
            (@plugin.enabled && "badge-success") || "badge-ghost"
          ]}>
            {if(@plugin.enabled, do: "active", else: "inactive")}
          </span>
          <span
            :if={MapSet.member?(@updates, @plugin.slug)}
            id={"update-badge-#{@plugin.slug}"}
            class="badge badge-sm badge-warning"
          >
            update available
          </span>
        </div>
        <p :if={@plugin.network_hosts != []} class="text-xs text-base-content/60 mt-1">
          <.icon name="hero-globe-alt" class="w-3 h-3 inline" />
          Can contact: {Enum.join(@plugin.network_hosts, ", ")}
        </p>
      </div>

      <div class="flex flex-wrap items-center gap-2 shrink-0">
        <span :if={@plugin.read_only} class="text-xs text-base-content/50">
          configured via env
        </span>

        <.button
          :if={not @plugin.read_only and @plugin.pending_approval}
          id={"approve-#{@plugin.slug}"}
          class="btn btn-warning btn-sm"
          phx-click="review_approve"
          phx-value-slug={@plugin.slug}
        >
          Review &amp; approve
        </.button>

        <div :if={not @plugin.read_only and not @plugin.pending_approval} class="join">
          <.button
            id={"toggle-#{@plugin.slug}"}
            class="btn btn-ghost btn-sm join-item"
            phx-click="toggle_enabled"
            phx-value-slug={@plugin.slug}
          >
            {if(@plugin.enabled, do: "Disable", else: "Enable")}
          </.button>
          <.button
            :if={@plugin.has_settings}
            id={"settings-#{@plugin.slug}"}
            class="btn btn-ghost btn-sm join-item"
            phx-click="edit_settings"
            phx-value-slug={@plugin.slug}
          >
            Settings
          </.button>
          <.button
            id={"details-#{@plugin.slug}"}
            class="btn btn-ghost btn-sm join-item"
            phx-click="show_detail"
            phx-value-slug={@plugin.slug}
          >
            Details
          </.button>
          <.button
            id={"remove-#{@plugin.slug}"}
            class="btn btn-ghost btn-sm join-item text-error"
            phx-click="remove"
            phx-value-slug={@plugin.slug}
            data-confirm={"Remove #{@plugin.name}?"}
          >
            <.icon name="hero-trash" class="w-4 h-4" />
          </.button>
        </div>
      </div>
    </div>
    """
  end

  @doc "A compact summary row for one store catalog entry."
  attr :entry, :map, required: true

  def catalog_row(assigns) do
    ~H"""
    <div
      id={"catalog-row-#{@entry.slug}"}
      class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 p-3 sm:p-4"
    >
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <span class="font-medium">{@entry.name}</span>
          <span class="text-xs text-base-content/50">v{@entry.version}</span>
        </div>
        <p :if={@entry.description} class="text-sm text-base-content/70 truncate">
          {@entry.description}
        </p>
      </div>
      <.button
        id={"install-#{@entry.slug}"}
        variant="primary"
        class="btn btn-primary btn-sm"
        phx-click="review_install"
        phx-value-slug={@entry.slug}
      >
        Install
      </.button>
    </div>
    """
  end

  @doc """
  The capability-approval modal: the emphasized surface.

  Activation is gated behind explicit approval. Capabilities render in
  host-owned plain language (see `capability_list/1`); the network destination
  is made legible. Uses DaisyUI `modal modal-open` markup so the element is only
  present when an approval is in flight.
  """
  attr :approval, :map, required: true

  def approval_modal(assigns) do
    ~H"""
    <div id="approval-modal" class="modal modal-open">
      <div class="modal-box max-w-lg">
        <h3 class="text-lg font-bold flex items-center gap-2">
          <.icon name="hero-shield-check" class="w-5 h-5" /> Approve {@approval.name}
        </h3>
        <p class="text-sm text-base-content/70 mt-1">
          {@approval.name} (v{@approval.version}) is requesting the capabilities below.
          It cannot run until you approve them. Approval is all-or-nothing.
        </p>

        <div class="my-4 space-y-2">
          <.capability_list id="approval-capabilities" capabilities={@approval.capabilities} />
          <.host_grant_note id="approval-host-grant" settings_schema={@approval.settings_schema} />
        </div>

        <div class="modal-action">
          <.button id="decline-approval" class="btn btn-ghost" phx-click="decline_approval">
            Decline
          </.button>
          <.button
            id="confirm-approval"
            variant="primary"
            class="btn btn-primary"
            phx-click="confirm_approval"
          >
            Approve &amp; activate
          </.button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="decline_approval"></div>
    </div>
    """
  end

  @doc """
  Per-plugin detail modal: granted capabilities + recent egress audit + Revoke.
  """
  attr :detail, :map, required: true

  def detail_modal(assigns) do
    ~H"""
    <div id="detail-modal" class="modal modal-open">
      <div class="modal-box max-w-lg">
        <h3 class="text-lg font-bold">{@detail.name}</h3>

        <h4 class="font-semibold mt-4 mb-2">Granted capabilities</h4>
        <.capability_list
          :if={@detail.granted != %{}}
          id="detail-capabilities"
          capabilities={@detail.granted}
        />
        <p :if={@detail.granted == %{}} class="text-sm text-base-content/60">
          No capabilities granted.
        </p>
        <.host_grant_note id="detail-host-grant" settings_schema={@detail.settings_schema} />

        <h4 class="font-semibold mt-4 mb-2">Recent network activity</h4>
        <div id="detail-audit" class="text-xs space-y-1 max-h-40 overflow-y-auto">
          <p :if={@detail.audit == []} class="text-base-content/60">No recorded requests.</p>
          <div :for={event <- @detail.audit} class="flex justify-between gap-2 font-mono">
            <span class="truncate">{event.metadata["host"]}</span>
            <span class="text-base-content/60">{event.metadata["outcome"]}</span>
          </div>
        </div>

        <div class="modal-action">
          <.button
            id={"detail-revoke-#{@detail.slug}"}
            class="btn btn-warning btn-sm"
            phx-click="revoke"
            phx-value-slug={@detail.slug}
            data-confirm="Revoke all capabilities and deactivate this plugin?"
          >
            Revoke capabilities
          </.button>
          <.button class="btn btn-ghost btn-sm" phx-click="close_detail">
            Close
          </.button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="close_detail"></div>
    </div>
    """
  end

  @doc """
  The operator settings modal (U3): renders a plugin's manifest-declared
  `settings_schema` as a form. Field inputs are derived from each field's
  declared `type`; secrets are write-only (never echoed back). Saving recomputes
  the host grant from any host-granting URL field (see `Mydia.Plugins.update_settings/2`).
  """
  attr :settings, :map, required: true

  def settings_modal(assigns) do
    ~H"""
    <div id="settings-modal" class="modal modal-open">
      <div class="modal-box max-w-lg">
        <h3 class="text-lg font-bold flex items-center gap-2">
          <.icon name="hero-cog-6-tooth" class="w-5 h-5" /> {@settings.name} settings
        </h3>
        <.form for={@settings.form} id="plugin-settings-form" phx-submit="save_settings">
          <input type="hidden" name="slug" value={@settings.slug} />
          <div class="space-y-3 my-4">
            <.settings_field :for={field <- @settings.schema} field={field} form={@settings.form} />
          </div>
          <div class="modal-action">
            <.button type="button" class="btn btn-ghost" phx-click="close_settings">
              Cancel
            </.button>
            <.button type="submit" variant="primary" class="btn btn-primary">
              Save settings
            </.button>
          </div>
        </.form>
      </div>
      <div class="modal-backdrop" phx-click="close_settings"></div>
    </div>
    """
  end

  # Renders one settings field from its declared type.
  attr :field, :map, required: true
  attr :form, :any, required: true

  defp settings_field(%{field: %{"type" => "enum"}} = assigns) do
    ~H"""
    <.input
      field={@form[@field["key"]]}
      type="select"
      label={@field["label"] || @field["key"]}
      options={@field["options"] || []}
    />
    """
  end

  defp settings_field(%{field: %{"type" => "secret"}} = assigns) do
    ~H"""
    <.input
      field={@form[@field["key"]]}
      type="password"
      autocomplete="off"
      label={@field["label"] || @field["key"]}
      placeholder="••••••••"
    />
    """
  end

  defp settings_field(%{field: %{"type" => "url"}} = assigns) do
    ~H"""
    <.input field={@form[@field["key"]]} type="url" label={@field["label"] || @field["key"]} />
    """
  end

  defp settings_field(assigns) do
    ~H"""
    <.input field={@form[@field["key"]]} type="text" label={@field["label"] || @field["key"]} />
    """
  end

  @doc """
  Notes that the plugin will reach the host of whatever URL the operator enters
  in its host-granting settings (U4). Renders nothing when the plugin declares no
  host-granting field. Keeps approval consent legible: static hosts come from
  `capability_list`, operator-chosen hosts are disclosed here.
  """
  attr :settings_schema, :list, default: []
  attr :id, :string, required: true

  def host_grant_note(assigns) do
    assigns = assign(assigns, :fields, host_granting_fields(assigns.settings_schema))

    ~H"""
    <div
      :if={@fields != []}
      id={@id}
      class="flex items-start gap-3 rounded-lg p-3 bg-warning/10"
    >
      <.icon name="hero-globe-alt" class="w-5 h-5 mt-0.5 shrink-0" />
      <div>
        <p class="font-medium">Plus any host you enter in: {Enum.join(@fields, ", ")}</p>
        <p class="text-xs text-base-content/60">
          This plugin reaches the server at the URL you configure in these settings.
        </p>
      </div>
    </div>
    """
  end

  # Labels of the host-granting (url + grants_host) fields in a settings schema.
  defp host_granting_fields(schema) when is_list(schema) do
    for field <- schema,
        Map.get(field, "type") == "url",
        Map.get(field, "grants_host") == true,
        do: Map.get(field, "label") || Map.get(field, "key")
  end

  defp host_granting_fields(_), do: []

  @doc """
  Renders the ordered list of declared capabilities for an approval surface.

  `capabilities` is the manifest map `%{class => values}`.
  """
  attr :capabilities, :map, required: true
  attr :id, :string, required: true

  def capability_list(assigns) do
    ~H"""
    <ul id={@id} class="space-y-2">
      <li
        :for={{class, values} <- Enum.sort_by(@capabilities, &elem(&1, 0))}
        id={"#{@id}-#{dom_slug(class)}"}
        class={[
          "flex items-start gap-3 rounded-lg p-3",
          (sensitive_capability?(class) && "bg-warning/10") || "bg-base-200"
        ]}
      >
        <.icon name={capability_icon(class)} class="w-5 h-5 mt-0.5 shrink-0" />
        <div>
          <p class="font-medium">{capability_label(class, List.wrap(values))}</p>
          <p :if={sensitive_capability?(class)} class="text-xs text-base-content/60">
            Review this carefully. It grants access beyond Mydia.
          </p>
        </div>
      </li>
    </ul>
    """
  end

  @doc "A small source-provenance badge (env/index/db)."
  attr :source, :atom, required: true

  def source_badge(assigns) do
    {label, cls} =
      case assigns.source do
        :env -> {"env", "badge-info"}
        :index -> {"index", "badge-ghost"}
        _ -> {"db", "badge-ghost"}
      end

    assigns = assign(assigns, label: label, cls: cls)

    ~H"""
    <span class={["badge badge-sm", @cls]}>{@label}</span>
    """
  end

  defp dom_slug(class), do: String.replace(class, ~r/[^a-z0-9]+/, "-")
end
