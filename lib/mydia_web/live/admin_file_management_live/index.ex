defmodule MydiaWeb.AdminFileManagementLive.Index do
  use MydiaWeb, :live_view

  alias Mydia.Config.Schema.Naming
  alias Mydia.Library.NamingTemplate
  alias Mydia.Settings
  alias Mydia.Settings.RuntimeConfig

  require Logger
  alias Mydia.Logger, as: MydiaLogger

  # Fields persisted as `naming.<field>` config settings, in display order.
  @string_fields ~w(season_folder movie_folder tv_folder movie_file episode_file)a
  @boolean_fields ~w(season_folders)a

  # Token catalog surfaced in the reference table: {token, description, sample}.
  # Movie-oriented examples are used for the title/year/id tokens; the
  # season/episode tokens stay TV-oriented since they only apply to episodes.
  @token_catalog [
    {"title", "Media title", "Casino Royale"},
    {"year", "Release year", "2006"},
    {"season", "Season number (zero-padded)", "01"},
    {"episode", "Episode number (zero-padded)", "05"},
    {"sxxeyy", "Season/episode marker", "S01E05"},
    {"episode_title", "Episode title", "Pilot"},
    {"quality", "Quality / resolution tag", "Bluray-1080p"},
    {"audio", "Audio codec tag", "DTS"},
    {"hdr", "HDR/Dolby Vision tag", "HDR"},
    {"codec", "Video codec tag", "x265"},
    {"release_group", "Release group (with leading dash)", "-RlsGrp"},
    {"tmdb", "TMDB ID value", "36557"},
    {"tvdb", "TVDB ID value", "73244"},
    {"imdb", "IMDb ID value", "tt0381061"}
  ]

  # Movie previews (movie_folder, movie_file) render against a movie sample so
  # the UI never shows a TV title for a movie convention.
  @movie_context %{
    "title" => "Casino Royale",
    "year" => "2006",
    "season" => "",
    "episode" => "",
    "sxxeyy" => "",
    "episode_title" => "",
    "quality" => "Bluray-1080p",
    "audio" => "DTS",
    "hdr" => "",
    "codec" => "x265",
    "release_group" => "-RlsGrp",
    "tmdb" => "36557",
    "tvdb" => "",
    "imdb" => "tt0381061"
  }

  # TV previews (tv_folder, season_folder, episode_file) render against a TV
  # sample with season/episode data populated.
  @tv_context %{
    "title" => "The Office",
    "year" => "2005",
    "season" => "01",
    "episode" => "05",
    "sxxeyy" => "S01E05",
    "episode_title" => "Pilot",
    "quality" => "Bluray-1080p",
    "audio" => "DTS",
    "hdr" => "",
    "codec" => "x265",
    "release_group" => "-RlsGrp",
    "tmdb" => "2316",
    "tvdb" => "73244",
    "imdb" => "tt0386676"
  }

  @impl true
  def mount(_params, _session, socket) do
    naming = RuntimeConfig.get_naming_config()

    {:ok,
     socket
     |> assign(:page_title, "Configuration - Files")
     |> assign(:active_tab, :file_management)
     |> assign(:token_catalog, @token_catalog)
     |> load_form(naming_to_params(naming))}
  end

  @impl true
  def handle_event("validate", %{"naming" => params}, socket) do
    {:noreply, load_form(socket, params)}
  end

  @impl true
  def handle_event("save", %{"naming" => params}, socket) do
    socket = load_form(socket, params)

    if socket.assigns.errors == %{} do
      persist(socket, params)
    else
      {:noreply, put_flash(socket, :error, "Fix the highlighted templates before saving.")}
    end
  end

  ## Components

  attr :preview, :string, default: ""
  attr :error, :string, default: nil

  def field_preview(assigns) do
    ~H"""
    <div class="-mt-1 mb-1 text-xs">
      <p :if={@error} class="text-error flex items-center gap-1">
        <.icon name="hero-exclamation-circle" class="w-4 h-4" />{@error}
      </p>
      <p :if={is_nil(@error) and @preview != ""} class="text-base-content/60">
        Preview: <span class="font-mono text-base-content/80">{@preview}</span>
      </p>
    </div>
    """
  end

  ## Helpers

  defp persist(socket, params) do
    user_id = socket.assigns.current_user.id

    results =
      Enum.map(@string_fields ++ @boolean_fields, fn field ->
        key = "naming.#{field}"
        value = params[to_string(field)] || ""

        Settings.upsert_config_setting(%{
          key: key,
          value: to_string(value),
          category: :naming,
          updated_by_id: user_id
        })
      end)

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      # Settings are persisted; reflect the saved values immediately regardless
      # of whether the live reload succeeds, so the form never reverts.
      socket = load_form(socket, params)

      case Mydia.Config.Loader.reload() do
        {:ok, _config} ->
          {:noreply, put_flash(socket, :info, "File naming settings saved.")}

        {:error, reason} ->
          MydiaLogger.log_error(:liveview, "Saved naming settings but reload failed",
            operation: :reload_naming,
            user_id: user_id,
            reason: inspect(reason)
          )

          {:noreply,
           put_flash(
             socket,
             :error,
             "Settings saved, but could not be applied live: #{format_reload_error(reason)}. A restart may be required."
           )}
      end
    else
      MydiaLogger.log_error(:liveview, "Failed to save naming settings",
        operation: :save_naming,
        user_id: user_id
      )

      {:noreply, put_flash(socket, :error, "Could not save settings. Please try again.")}
    end
  end

  defp load_form(socket, params) do
    params = normalize_params(params)
    errors = validate_params(params)
    previews = build_previews(params)

    socket
    |> assign(:form, to_form(params, as: :naming))
    |> assign(:season_folders, params["season_folders"] == "true")
    |> assign(:errors, errors)
    |> assign(:previews, previews)
  end

  defp normalize_params(params) do
    base =
      Map.new(@string_fields, fn field ->
        {to_string(field), params[to_string(field)] || ""}
      end)

    Map.put(base, "season_folders", to_string(params["season_folders"] in [true, "true", "on"]))
  end

  defp validate_params(params) do
    tokens = NamingTemplate.tokens()

    Enum.reduce(@string_fields, %{}, fn field, acc ->
      key = to_string(field)
      value = params[key] || ""

      cond do
        String.trim(value) == "" ->
          Map.put(acc, key, "can't be blank")

        true ->
          case NamingTemplate.validate(value, tokens) do
            :ok ->
              acc

            {:error, unknown} ->
              Map.put(acc, key, "Unknown token(s): #{Enum.map_join(unknown, ", ", &"{{#{&1}}}")}")
          end
      end
    end)
  end

  defp build_previews(params) do
    %{
      "season_folder" => render_preview(params["season_folder"], @tv_context),
      "movie_folder" => render_preview(params["movie_folder"], @movie_context),
      "tv_folder" => render_preview(params["tv_folder"], @tv_context),
      "movie_file" => render_preview(params["movie_file"], @movie_context) <> ".mkv",
      "episode_file" => render_preview(params["episode_file"], @tv_context) <> ".mkv"
    }
  end

  defp render_preview(template, context) when is_binary(template) and template != "" do
    NamingTemplate.render(template, context)
  end

  defp render_preview(_, _), do: ""

  defp naming_to_params(%Naming{} = naming) do
    %{
      "season_folders" => to_string(naming.season_folders),
      "season_folder" => naming.season_folder,
      "movie_folder" => naming.movie_folder,
      "tv_folder" => naming.tv_folder,
      "movie_file" => naming.movie_file,
      "episode_file" => naming.episode_file
    }
  end

  defp format_reload_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> flatten_errors()
    |> Enum.join("; ")
  end

  defp format_reload_error(reason) when is_binary(reason), do: reason
  defp format_reload_error(reason), do: inspect(reason)

  defp flatten_errors(errors, prefix \\ "") do
    Enum.flat_map(errors, fn {key, value} ->
      path = if prefix == "", do: to_string(key), else: "#{prefix}.#{key}"

      cond do
        is_map(value) -> flatten_errors(value, path)
        is_list(value) -> Enum.map(value, fn msg -> "#{path} #{msg}" end)
        true -> ["#{path} #{value}"]
      end
    end)
  end
end
