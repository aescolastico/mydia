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
