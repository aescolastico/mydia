defmodule MydiaWeb.Plugs.WebhookSecretAuth do
  @moduledoc """
  Authenticates webhook callbacks from external download clients (SABnzbd
  notification scripts, NZBGet pp-scripts) using a per-client shared secret.

  The plug looks up the `DownloadClientConfig` by the `:client_id` path
  parameter, reads the candidate secret from either the `?secret=...` query
  parameter or the `X-Mydia-Webhook-Secret` header, and constant-time compares
  the two via `Plug.Crypto.secure_compare/2`.

  Response semantics:

    - `200` (pass-through) — secret matched. The matched client is stored on
      the conn assigns under `:download_client_config` for the controller to
      use without re-querying.
    - `401` (halt) — secret missing or mismatched. Body is empty so we don't
      leak whether the client_id exists.
    - `404` (halt) — `:client_id` path parameter does not resolve to a
      known DB-backed `DownloadClientConfig`. Body is empty.

  Runtime-only download clients (no DB row) are intentionally rejected — they
  have no persisted `webhook_secret` and shouldn't be reachable via webhooks.
  """

  import Plug.Conn
  require Logger

  alias Mydia.Repo
  alias Mydia.Settings.DownloadClientConfig

  @header_name "x-mydia-webhook-secret"

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, client_id} <- fetch_client_id(conn),
         {:ok, config} <- fetch_client_config(client_id),
         {:ok, provided} <- fetch_provided_secret(conn),
         :ok <- verify_secret(config, provided) do
      assign(conn, :download_client_config, config)
    else
      {:error, :not_found} ->
        Logger.warning("Webhook auth: download client not found",
          client_id: conn.path_params["client_id"]
        )

        conn
        |> send_resp(404, "")
        |> halt()

      {:error, reason} ->
        Logger.warning("Webhook auth: rejected", reason: reason)

        conn
        |> send_resp(401, "")
        |> halt()
    end
  end

  defp fetch_client_id(conn) do
    case conn.path_params do
      %{"client_id" => id} when is_binary(id) and id != "" -> {:ok, id}
      _ -> {:error, :missing_client_id}
    end
  end

  defp fetch_client_config(client_id) do
    case Ecto.UUID.cast(client_id) do
      {:ok, uuid} ->
        case Repo.get(DownloadClientConfig, uuid) do
          nil -> {:error, :not_found}
          config -> {:ok, config}
        end

      :error ->
        {:error, :not_found}
    end
  end

  defp fetch_provided_secret(conn) do
    case get_req_header(conn, @header_name) do
      [secret | _] when is_binary(secret) and secret != "" ->
        {:ok, secret}

      _ ->
        case conn.query_params do
          %{"secret" => secret} when is_binary(secret) and secret != "" -> {:ok, secret}
          _ -> {:error, :missing_secret}
        end
    end
  end

  defp verify_secret(%DownloadClientConfig{webhook_secret: expected}, provided)
       when is_binary(expected) and expected != "" do
    if Plug.Crypto.secure_compare(expected, provided) do
      :ok
    else
      {:error, :invalid_secret}
    end
  end

  defp verify_secret(_config, _provided), do: {:error, :no_configured_secret}
end
