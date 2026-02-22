defmodule MetadataRelay.Trakt.Client do
  @moduledoc """
  HTTP client for Trakt.tv API v2.

  This module provides a thin wrapper around the Trakt API using Req.
  It handles authentication headers and forwards requests to Trakt,
  returning the raw API responses.

  The relay holds `TRAKT_CLIENT_ID` and `TRAKT_CLIENT_SECRET` centrally
  so individual Mydia instances never need direct access to these secrets.
  """

  @base_url "https://api.trakt.tv"

  @doc """
  Creates a new Req client configured for Trakt API requests.

  Options:
    - `user_token` — Bearer token for user-authenticated requests
  """
  def new(opts \\ []) do
    user_token = Keyword.get(opts, :user_token)

    headers =
      [
        {"content-type", "application/json"},
        {"trakt-api-version", "2"},
        {"trakt-api-key", client_id()}
      ] ++ auth_header(user_token)

    Req.new(
      base_url: @base_url,
      headers: headers
    )
  end

  @doc """
  GET request to Trakt API.

  Returns `{:ok, response_body}` on success or `{:error, reason}` on failure.
  """
  def get(path, opts \\ []) do
    {user_token, opts} = Keyword.pop(opts, :user_token)
    client = new(user_token: user_token)
    params = Keyword.get(opts, :params, [])

    case Req.get(client, url: path, params: params) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  POST request to Trakt API.

  Returns `{:ok, response_body}` on success or `{:error, reason}` on failure.
  """
  def post(path, body, opts \\ []) do
    {user_token, _opts} = Keyword.pop(opts, :user_token)
    client = new(user_token: user_token)

    case Req.post(client, url: path, json: body) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns the client_id (public, safe to expose to Mydia instances for building authorize URLs).
  """
  def client_id do
    Application.get_env(:metadata_relay, :trakt_client_id) ||
      System.get_env("TRAKT_CLIENT_ID") ||
      raise(RuntimeError, "TRAKT_CLIENT_ID environment variable is not set.")
  end

  @doc """
  Returns the client_secret (private, never exposed outside the relay).
  """
  def client_secret do
    Application.get_env(:metadata_relay, :trakt_client_secret) ||
      System.get_env("TRAKT_CLIENT_SECRET") ||
      raise(RuntimeError, "TRAKT_CLIENT_SECRET environment variable is not set.")
  end

  defp auth_header(nil), do: []
  defp auth_header(token), do: [{"authorization", "Bearer #{token}"}]
end
