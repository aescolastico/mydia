defmodule MydiaWeb.AdminFileNamingLive.Index do
  use MydiaWeb, :live_view

  alias Mydia.Library.NamingTemplate
  alias Mydia.Settings.Naming
  alias Mydia.Settings.RuntimeConfig

  require Logger

  @movie_example %{
    "title" => "Casino Royale",
    "year" => "2006",
    "quality" => "[BluRay-1080p]",
    "audio" => "[DTS]",
    "hdr" => "",
    "codec" => "[x265]",
    "release_group" => "-RlsGrp",
    "tmdb" => "36557",
    "tvdb" => "",
    "imdb" => "tt0381061"
  }
  @tv_example Map.merge(@movie_example, %{
                "title" => "The Office",
                "year" => "2005",
                "season" => "01",
                "episode" => "05",
                "sxxeyy" => "S01E05",
                "episode_title" => "Pilot",
                "tmdb" => "2316",
                "tvdb" => "73244"
              })

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("File Naming"))
     |> assign(:env_overrides, Naming.env_overrides())
     |> assign(:token_catalog, token_catalog())
     |> load_form(Naming.params(RuntimeConfig.get_naming_config()))}
  end

  @impl true
  def handle_event("validate", %{"naming" => params}, socket) do
    {:noreply, load_form(socket, params)}
  end

  @impl true
  def handle_event("save", %{"naming" => params}, socket) do
    socket = load_form(socket, params)

    case Naming.save(params, socket.assigns.current_user.id) do
      {:ok, config} ->
        message =
          if socket.assigns.env_overrides == [],
            do: gettext("File naming settings saved"),
            else: gettext("Settings saved. Environment variables still take precedence.")

        {:noreply,
         socket
         |> load_form(Naming.params(config.naming))
         |> put_flash(:info, message)}

      {:error, {:validation, _errors}} ->
        {:noreply, put_flash(socket, :error, gettext("Fix the highlighted templates"))}

      {:error, reason} ->
        Logger.error("Could not save file naming settings: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, gettext("Could not apply file naming settings"))}
    end
  end

  attr(:field, Phoenix.HTML.FormField, required: true)
  attr(:label, :string, required: true)
  attr(:preview, :string, required: true)
  attr(:error, :string, default: nil)

  defp template_field(assigns) do
    ~H"""
    <div>
      <.input field={@field} type="text" label={@label} autocomplete="off" />
      <p :if={@error} class="-mt-1 mb-3 text-sm text-error flex items-center gap-1">
        <.icon name="hero-exclamation-circle" class="size-4" />{@error}
      </p>
      <p :if={!@error} class="-mt-1 mb-3 text-xs text-base-content/60 break-all">
        {gettext("Preview:")} <span class="font-mono text-base-content/80">{@preview}</span>
      </p>
    </div>
    """
  end

  defp load_form(socket, params) do
    params =
      Map.put(
        params,
        "season_folders",
        to_string(params["season_folders"] in [true, "true", "on", "1"])
      )

    errors = Naming.validate(params)

    previews = %{
      "movie_folder" => preview(params, "movie_folder", @movie_example),
      "tv_folder" => preview(params, "tv_folder", @tv_example),
      "season_folder" => preview(params, "season_folder", @tv_example),
      "movie_file" => preview(params, "movie_file", @movie_example) <> ".mkv",
      "episode_file" => preview(params, "episode_file", @tv_example) <> ".mkv"
    }

    socket
    |> assign(:form, to_form(params, as: :naming))
    |> assign(:season_folders, params["season_folders"] == "true")
    |> assign(:errors, errors)
    |> assign(:previews, previews)
  end

  defp preview(params, field, context) do
    case Map.get(params, field) do
      value when is_binary(value) -> NamingTemplate.render(value, context)
      _ -> ""
    end
  end

  defp token_catalog do
    [
      {"title", gettext("Media title"), "The Office"},
      {"year", gettext("Release year"), "2005"},
      {"season", gettext("Season number"), "01"},
      {"episode", gettext("Episode number"), "05"},
      {"sxxeyy", gettext("Season and episode marker"), "S01E05"},
      {"episode_title", gettext("Episode title"), "Pilot"},
      {"quality", gettext("Quality tag"), "[BluRay-1080p]"},
      {"audio", gettext("Audio tag"), "[DTS]"},
      {"hdr", gettext("HDR tag"), "[HDR10]"},
      {"codec", gettext("Video codec tag"), "[x265]"},
      {"release_group", gettext("Release group"), "-RlsGrp"},
      {"tmdb", gettext("TMDB ID"), "2316"},
      {"tvdb", gettext("TVDB ID"), "73244"},
      {"imdb", gettext("IMDb ID"), "tt0386676"}
    ]
  end
end
