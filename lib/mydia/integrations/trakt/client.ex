defmodule Mydia.Integrations.Trakt.Client do
  @moduledoc """
  HTTP client for Trakt operations via the metadata-relay service.

  All requests are proxied through the relay, which holds the Trakt
  client_id and client_secret. User-authenticated endpoints pass the
  user's access token via the `X-Trakt-User-Token` header.
  """

  require Logger

  # ── OAuth ───────────────────────────────────────────────────────────

  @doc """
  Fetches the Trakt client_id from the relay for building authorize URLs.
  """
  def get_config do
    get("/trakt/config")
  end

  @doc """
  Exchanges an authorization code for tokens via the relay.
  """
  def exchange_code(code, redirect_uri) do
    post("/trakt/oauth/token", %{code: code, redirect_uri: redirect_uri})
  end

  @doc """
  Refreshes an expired token via the relay.
  """
  def refresh_token(refresh_token) do
    post("/trakt/oauth/refresh", %{refresh_token: refresh_token})
  end

  @doc """
  Revokes a token via the relay.
  """
  def revoke_token(token) do
    post("/trakt/oauth/revoke", %{token: token})
  end

  # ── Scrobble ────────────────────────────────────────────────────────

  @doc """
  Start scrobbling.
  """
  def scrobble_start(body, user_token) do
    post("/trakt/scrobble/start", body, user_token: user_token)
  end

  @doc """
  Pause scrobbling.
  """
  def scrobble_pause(body, user_token) do
    post("/trakt/scrobble/pause", body, user_token: user_token)
  end

  @doc """
  Stop scrobbling.
  """
  def scrobble_stop(body, user_token) do
    post("/trakt/scrobble/stop", body, user_token: user_token)
  end

  # ── Sync ────────────────────────────────────────────────────────────

  @doc """
  Get sync data (history, ratings, watchlist, collection).
  """
  def get_sync(type, media_type, user_token, params \\ []) do
    get("/trakt/sync/#{type}/#{media_type}", user_token: user_token, params: params)
  end

  @doc """
  Add sync data.
  """
  def add_sync(type, body, user_token) do
    post("/trakt/sync/#{type}", body, user_token: user_token)
  end

  @doc """
  Remove sync data.
  """
  def remove_sync(type, body, user_token) do
    post("/trakt/sync/#{type}/remove", body, user_token: user_token)
  end

  # ── HTTP Helpers ────────────────────────────────────────────────────

  defp get(path, opts \\ []) do
    {user_token, opts} = Keyword.pop(opts, :user_token)
    params = Keyword.get(opts, :params, [])
    headers = build_headers(user_token)

    case Req.get(client(), url: path, headers: headers, params: params) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.warning("Trakt relay request failed: GET #{path} - #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp post(path, body, opts \\ []) do
    {user_token, _opts} = Keyword.pop(opts, :user_token)
    headers = build_headers(user_token)

    case Req.post(client(), url: path, headers: headers, json: body) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Logger.warning("Trakt relay request failed: POST #{path} - #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp client do
    Req.new(base_url: relay_url())
  end

  defp relay_url do
    Mydia.Metadata.metadata_relay_url()
  end

  defp build_headers(nil), do: []
  defp build_headers(user_token), do: [{"x-trakt-user-token", user_token}]
end
