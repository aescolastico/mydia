defmodule Mydia.Jobs.MetadataRefresh do
  @moduledoc """
  Background job for refreshing media metadata.

  This job:
  - Fetches the latest metadata from providers
  - Updates media items with fresh data
  - For TV shows, updates episode information
  - Can be triggered manually or scheduled

  For scheduled "refresh all" runs, a random delay (0-30 minutes) is applied
  to spread load across self-hosted instances hitting the metadata relay.
  """

  use Oban.Worker,
    queue: :media,
    max_attempts: 3

  require Logger
  alias Mydia.{Media, Metadata}

  defmodule Args do
    @moduledoc false
    defstruct [:media_item_id, refresh_all: false, fetch_episodes: true, skip_delay: false]

    @type t :: %__MODULE__{
            media_item_id: String.t() | nil,
            refresh_all: boolean(),
            fetch_episodes: boolean(),
            skip_delay: boolean()
          }

    def parse(%{"media_item_id" => media_item_id} = raw) do
      %__MODULE__{
        media_item_id: media_item_id,
        fetch_episodes: Map.get(raw, "fetch_episodes", true),
        skip_delay: Map.get(raw, "skip_delay", false)
      }
    end

    def parse(%{"refresh_all" => true} = raw) do
      %__MODULE__{
        refresh_all: true,
        skip_delay: Map.get(raw, "skip_delay", false)
      }
    end

    def parse(raw) when raw == %{} do
      %__MODULE__{refresh_all: true, skip_delay: true}
    end
  end

  # Random delay range for scheduled refresh_all (0-30 minutes in ms)
  @max_startup_delay_ms 30 * 60 * 1000

  @spec perform(Oban.Job.t()) :: :ok | {:ok, term()} | {:error, term()} | {:snooze, pos_integer()}
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"media_item_id" => media_item_id} = raw_args}) do
    args = Args.parse(raw_args)
    start_time = System.monotonic_time(:millisecond)
    fetch_episodes = args.fetch_episodes
    config = Metadata.default_relay_config()

    Logger.info("Starting metadata refresh", media_item_id: media_item_id)

    result =
      case Media.get_media_item!(media_item_id) do
        nil ->
          Logger.error("Media item not found", media_item_id: media_item_id)
          {:error, :not_found}

        media_item ->
          refresh_media_item(media_item, config, fetch_episodes)
      end

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      :ok ->
        Logger.info("Metadata refresh completed",
          duration_ms: duration,
          media_item_id: media_item_id
        )

        :ok

      {:error, reason} ->
        Logger.error("Metadata refresh failed",
          error: inspect(reason),
          duration_ms: duration,
          media_item_id: media_item_id
        )

        {:error, reason}
    end
  rescue
    _e in Ecto.NoResultsError ->
      Logger.error("Media item not found", media_item_id: media_item_id)
      {:error, :not_found}
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"refresh_all" => true} = raw_args}) do
    args = Args.parse(raw_args)

    # Add random delay for scheduled runs to spread load across instances
    # Skip delay for manual triggers (skip_delay: true)
    unless args.skip_delay do
      delay_ms = :rand.uniform(@max_startup_delay_ms)
      delay_minutes = Float.round(delay_ms / 60_000, 1)

      Logger.info("Metadata refresh scheduled, waiting #{delay_minutes} minutes before starting")
      Process.sleep(delay_ms)
    end

    start_time = System.monotonic_time(:millisecond)
    Logger.info("Starting metadata refresh for all media items")

    result = refresh_all_media()
    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, count} ->
        Logger.info("Metadata refresh all completed",
          duration_ms: duration,
          items_processed: count
        )

        :ok
    end
  end

  # Fallback for manual trigger from UI (empty args) - skip delay for immediate execution
  @impl Oban.Worker
  def perform(%Oban.Job{args: raw_args}) when raw_args == %{} do
    perform(%Oban.Job{args: %{"refresh_all" => true, "skip_delay" => true}})
  end

  ## Private Functions

  defp refresh_media_item(media_item, config, fetch_episodes) do
    media_type = parse_media_type(media_item.type)

    # Get the appropriate provider ID and its source (tvdb_id for TV shows, tmdb_id for movies)
    {provider_id, provider_source} = get_or_extract_provider_id(media_item, media_type)

    # If no provider ID, try to recover it via the shared Media function
    {provider_id, provider_source, media_item} =
      if provider_id do
        {provider_id, provider_source, media_item}
      else
        Logger.info("No provider ID found, attempting to recover by title search",
          media_item_id: media_item.id,
          title: media_item.title
        )

        case Media.recover_provider_id_by_title(media_item, media_type) do
          {:ok, found_id, updated_item} ->
            Logger.info("Successfully recovered provider ID via title search",
              media_item_id: media_item.id,
              title: media_item.title,
              provider_id: found_id
            )

            source = if updated_item.tvdb_id, do: :tvdb, else: :tmdb
            {found_id, source, updated_item}

          {:error, reason} ->
            Logger.warning("Failed to recover provider ID via title search",
              media_item_id: media_item.id,
              title: media_item.title,
              reason: reason
            )

            {nil, nil, media_item}
        end
      end

    if provider_id do
      Logger.info("Refreshing metadata",
        media_item_id: media_item.id,
        title: media_item.title,
        provider_id: provider_id,
        provider_source: provider_source,
        media_type: media_type
      )

      case fetch_updated_metadata(provider_id, media_type, provider_source, config) do
        {:ok, metadata} ->
          attrs = build_update_attrs(metadata, media_type, media_item)

          case Media.update_media_item(media_item, attrs, reason: "Metadata refreshed") do
            {:ok, updated_item} ->
              Logger.info("Successfully refreshed metadata",
                media_item_id: updated_item.id,
                title: updated_item.title
              )

              # For TV shows, optionally refresh episodes
              if media_type == :tv_show and fetch_episodes do
                Media.refresh_episodes_for_tv_show(updated_item)
              end

              :ok

            {:error, changeset} ->
              Logger.error("Failed to update media item",
                media_item_id: media_item.id,
                errors: inspect(changeset.errors)
              )

              {:error, :update_failed}
          end

        {:error, reason} ->
          Logger.error("Failed to fetch updated metadata",
            media_item_id: media_item.id,
            provider_id: provider_id,
            reason: reason
          )

          {:error, reason}
      end
    else
      Logger.warning("Media item has no provider ID and could not recover via title search",
        media_item_id: media_item.id
      )

      {:error, :no_provider_id}
    end
  end

  defp refresh_all_media do
    media_items = Media.list_media_items(monitored: true)

    Logger.info("Refreshing metadata for #{length(media_items)} media items")

    results =
      Enum.map(media_items, fn media_item ->
        config = Metadata.default_relay_config()
        refresh_media_item(media_item, config, false)
      end)

    successful = Enum.count(results, &(&1 == :ok))
    failed = Enum.count(results, &match?({:error, _}, &1))

    Logger.info("Metadata refresh completed",
      total: length(results),
      successful: successful,
      failed: failed
    )

    {:ok, successful}
  end

  defp parse_media_type("movie"), do: :movie
  defp parse_media_type("tv_show"), do: :tv_show
  defp parse_media_type(_), do: :movie

  defp fetch_updated_metadata(provider_id, media_type, provider_source, config) do
    fetch_opts = [
      media_type: media_type,
      provider: provider_source,
      append_to_response: ["credits", "images", "videos", "keywords"]
    ]

    Metadata.fetch_by_id(config, to_string(provider_id), fetch_opts)
  end

  defp build_update_attrs(metadata, media_type, media_item) do
    base_attrs = %{
      title: metadata.title,
      original_title: metadata.original_title,
      year: extract_year(metadata),
      imdb_id: metadata.imdb_id,
      metadata: metadata
    }

    # Route the metadata ID to the correct field based on provider source
    {_provider_id, provider_source} = get_or_extract_provider_id(media_item, media_type)

    case provider_source do
      :tvdb ->
        Map.put(base_attrs, :tvdb_id, metadata.id)

      _ ->
        Map.put(base_attrs, :tmdb_id, metadata.id)
    end
  end

  defp get_or_extract_provider_id(media_item, media_type) do
    cond do
      # For TV shows, prefer tvdb_id
      media_type == :tv_show and media_item.tvdb_id ->
        {media_item.tvdb_id, :tvdb}

      # Fall back to tmdb_id for any media type
      media_item.tmdb_id ->
        {media_item.tmdb_id, :tmdb}

      # Try to extract from metadata["id"] (new format - string key)
      media_item.metadata && media_item.metadata["id"] ->
        id =
          case media_item.metadata["id"] do
            id when is_integer(id) ->
              id

            id when is_binary(id) ->
              case Integer.parse(id) do
                {parsed_id, ""} -> parsed_id
                _ -> nil
              end

            _ ->
              nil
          end

        {id, :tmdb}

      # Try to extract from metadata["provider_id"] (old format - string key)
      media_item.metadata && media_item.metadata["provider_id"] ->
        id =
          case Integer.parse(media_item.metadata["provider_id"]) do
            {id, ""} -> id
            _ -> nil
          end

        {id, :tmdb}

      # No provider ID available
      true ->
        {nil, nil}
    end
  end

  defp extract_year(metadata) do
    cond do
      metadata.release_date ->
        metadata.release_date.year

      metadata.first_air_date ->
        metadata.first_air_date.year

      true ->
        nil
    end
  end
end
