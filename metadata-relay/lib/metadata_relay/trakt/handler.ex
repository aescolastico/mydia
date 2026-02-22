defmodule MetadataRelay.Trakt.Handler do
  @moduledoc """
  Request handlers for Trakt.tv API endpoints.

  Each function corresponds to a Trakt API operation and forwards
  the request through the relay client. OAuth-sensitive operations
  (token exchange, refresh, revoke) inject the client_secret so
  individual Mydia instances never need it.
  """

  alias MetadataRelay.Trakt.Client

  # ── Config ──────────────────────────────────────────────────────────

  @doc """
  Returns the Trakt client_id so Mydia instances can build authorize URLs.
  """
  def get_config do
    {:ok, %{client_id: Client.client_id()}}
  end

  # ── OAuth ───────────────────────────────────────────────────────────

  @doc """
  Exchange an authorization code for access + refresh tokens.
  The relay injects `client_id` and `client_secret` automatically.
  """
  def exchange_code(params) do
    body = %{
      code: Map.fetch!(params, "code"),
      redirect_uri: Map.fetch!(params, "redirect_uri"),
      grant_type: "authorization_code",
      client_id: Client.client_id(),
      client_secret: Client.client_secret()
    }

    Client.post("/oauth/token", body)
  end

  @doc """
  Refresh an expired access token.
  The relay injects `client_id` and `client_secret` automatically.
  """
  def refresh_token(params) do
    body = %{
      refresh_token: Map.fetch!(params, "refresh_token"),
      redirect_uri: Map.get(params, "redirect_uri", "urn:ietf:wg:oauth:2.0:oob"),
      grant_type: "refresh_token",
      client_id: Client.client_id(),
      client_secret: Client.client_secret()
    }

    Client.post("/oauth/token", body)
  end

  @doc """
  Revoke a user's access token.
  The relay injects `client_secret` automatically.
  """
  def revoke_token(params) do
    body = %{
      token: Map.fetch!(params, "token"),
      client_id: Client.client_id(),
      client_secret: Client.client_secret()
    }

    Client.post("/oauth/revoke", body)
  end

  # ── Scrobble ────────────────────────────────────────────────────────

  @doc """
  Start scrobbling (user starts watching).
  """
  def scrobble_start(body, user_token) do
    Client.post("/scrobble/start", body, user_token: user_token)
  end

  @doc """
  Pause scrobbling (user pauses playback).
  """
  def scrobble_pause(body, user_token) do
    Client.post("/scrobble/pause", body, user_token: user_token)
  end

  @doc """
  Stop scrobbling (user stops watching).
  """
  def scrobble_stop(body, user_token) do
    Client.post("/scrobble/stop", body, user_token: user_token)
  end

  # ── Sync: History ───────────────────────────────────────────────────

  @doc """
  Get user's watch history. `media_type` is "movies" or "shows".
  """
  def get_history(media_type, user_token, params \\ []) do
    Client.get("/sync/history/#{media_type}", user_token: user_token, params: params)
  end

  @doc """
  Add items to user's watch history.
  """
  def add_to_history(body, user_token) do
    Client.post("/sync/history", body, user_token: user_token)
  end

  @doc """
  Remove items from user's watch history.
  """
  def remove_from_history(body, user_token) do
    Client.post("/sync/history/remove", body, user_token: user_token)
  end

  # ── Sync: Ratings ───────────────────────────────────────────────────

  @doc """
  Get user's ratings. `media_type` is "movies", "shows", or "episodes".
  """
  def get_ratings(media_type, user_token, params \\ []) do
    Client.get("/sync/ratings/#{media_type}", user_token: user_token, params: params)
  end

  @doc """
  Add ratings.
  """
  def add_ratings(body, user_token) do
    Client.post("/sync/ratings", body, user_token: user_token)
  end

  @doc """
  Remove ratings.
  """
  def remove_ratings(body, user_token) do
    Client.post("/sync/ratings/remove", body, user_token: user_token)
  end

  # ── Sync: Watchlist ─────────────────────────────────────────────────

  @doc """
  Get user's watchlist. `media_type` is "movies" or "shows".
  """
  def get_watchlist(media_type, user_token, params \\ []) do
    Client.get("/sync/watchlist/#{media_type}", user_token: user_token, params: params)
  end

  @doc """
  Add items to watchlist.
  """
  def add_to_watchlist(body, user_token) do
    Client.post("/sync/watchlist", body, user_token: user_token)
  end

  @doc """
  Remove items from watchlist.
  """
  def remove_from_watchlist(body, user_token) do
    Client.post("/sync/watchlist/remove", body, user_token: user_token)
  end

  # ── Sync: Collection ───────────────────────────────────────────────

  @doc """
  Get user's collection. `media_type` is "movies" or "shows".
  """
  def get_collection(media_type, user_token, params \\ []) do
    Client.get("/sync/collection/#{media_type}", user_token: user_token, params: params)
  end

  @doc """
  Add items to collection.
  """
  def add_to_collection(body, user_token) do
    Client.post("/sync/collection", body, user_token: user_token)
  end

  @doc """
  Remove items from collection.
  """
  def remove_from_collection(body, user_token) do
    Client.post("/sync/collection/remove", body, user_token: user_token)
  end
end
