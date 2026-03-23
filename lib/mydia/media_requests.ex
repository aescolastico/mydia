defmodule Mydia.MediaRequests do
  @moduledoc """
  The MediaRequests context handles media request submissions, approvals, and rejections.
  """

  import Ecto.Query, warn: false
  import Mydia.QueryHelpers
  require Logger

  alias Mydia.Repo
  alias Mydia.Media
  alias Mydia.Media.MediaRequest
  alias Ecto.Multi

  @doc """
  Returns the list of media requests.

  ## Options
    - `:status` - Filter by status ("pending", "approved", "rejected")
    - `:requester_id` - Filter by requester
    - `:preload` - List of associations to preload
  """
  def list_requests(opts \\ []) do
    MediaRequest
    |> apply_request_filters(opts)
    |> maybe_preload(opts[:preload])
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single media request.

  ## Options
    - `:preload` - List of associations to preload

  Raises `Ecto.NoResultsError` if the request does not exist.
  """
  def get_request!(id, opts \\ []) do
    MediaRequest
    |> maybe_preload(opts[:preload])
    |> Repo.get!(id)
  end

  @doc """
  Creates a media request.

  Performs duplicate detection to check if:
  - The media item already exists
  - There's a pending request for the same media

  Returns `{:error, :duplicate_media}` if media exists.
  Returns `{:error, :duplicate_request}` if pending request exists.
  """
  def create_request(attrs \\ %{}) do
    changeset = MediaRequest.create_changeset(%MediaRequest{}, attrs)

    with :ok <- check_duplicate_media(changeset),
         :ok <- check_duplicate_request(changeset),
         {:ok, request} <- Repo.insert(changeset) do
      {:ok, Repo.preload(request, [:requester])}
    end
  end

  @doc """
  Approves a media request and creates the corresponding media item.

  This operation is atomic - if media creation fails, the approval is rolled back.

  ## Attributes
    - `approved_by_id` - Required, ID of the admin approving the request
    - `admin_notes` - Optional notes from the admin
  """
  def approve_request(%MediaRequest{} = request, attrs \\ %{}) do
    Multi.new()
    |> Multi.run(:media_item, fn _repo, _changes ->
      # Create media item from request
      create_media_from_request(request, attrs[:approved_by_id])
    end)
    |> Multi.run(:request, fn _repo, %{media_item: media_item} ->
      # Update request with approval
      request
      |> MediaRequest.approve_changeset(Map.put(attrs, :media_item_id, media_item.id))
      |> Repo.update()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{request: updated_request, media_item: media_item}} ->
        Logger.info(
          "Request #{request.id} approved by user #{attrs[:approved_by_id]}, created media #{media_item.id}"
        )

        {:ok, %{request: updated_request, media_item: media_item}}

      {:error, :media_item, changeset, _changes} ->
        Logger.error("Failed to create media item for request #{request.id}")
        {:error, changeset}

      {:error, :request, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Rejects a media request.

  ## Attributes
    - `rejection_reason` - Required, reason for rejection
    - `approved_by_id` - Required, ID of the admin rejecting the request
    - `admin_notes` - Optional additional notes
  """
  def reject_request(%MediaRequest{} = request, attrs \\ %{}) do
    request
    |> MediaRequest.reject_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_request} ->
        Logger.info(
          "Request #{request.id} rejected by user #{attrs[:approved_by_id]}: #{attrs[:rejection_reason]}"
        )

        {:ok, updated_request}

      error ->
        error
    end
  end

  @doc """
  Returns the count of pending requests.
  """
  def count_pending_requests do
    MediaRequest
    |> where([r], r.status == "pending")
    |> Repo.aggregate(:count)
  end

  @doc """
  Checks if a request with the given TMDB ID is pending.
  """
  def pending_request_exists?(tmdb_id) when is_integer(tmdb_id) do
    MediaRequest
    |> where([r], r.tmdb_id == ^tmdb_id and r.status == "pending")
    |> Repo.exists?()
  end

  def pending_request_exists?(_), do: false

  # Private functions

  defp apply_request_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:status, status}, query when is_binary(status) ->
        where(query, [r], r.status == ^status)

      {:requester_id, requester_id}, query ->
        where(query, [r], r.requester_id == ^requester_id)

      _other, query ->
        query
    end)
  end

  defp check_duplicate_media(changeset) do
    tmdb_id = Ecto.Changeset.get_field(changeset, :tmdb_id)

    if tmdb_id && Media.get_media_item_by_tmdb(tmdb_id) do
      {:error, :duplicate_media}
    else
      :ok
    end
  end

  defp check_duplicate_request(changeset) do
    tmdb_id = Ecto.Changeset.get_field(changeset, :tmdb_id)

    if tmdb_id && pending_request_exists?(tmdb_id) do
      {:error, :duplicate_request}
    else
      :ok
    end
  end

  defp create_media_from_request(request, approved_by_id) do
    media_attrs = %{
      type: request.media_type,
      title: request.title,
      original_title: request.original_title,
      year: request.year,
      tmdb_id: request.tmdb_id,
      imdb_id: request.imdb_id,
      monitored: true
    }

    Media.create_media_item(media_attrs,
      actor_type: :user,
      actor_id: approved_by_id
    )
  end
end
