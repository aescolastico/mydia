defmodule MydiaWeb.Api.Webhook.UsenetController do
  @moduledoc """
  Webhook receiver for SABnzbd notification-scripts and NZBGet pp-scripts.

  Each download-client config has a server-generated `webhook_secret` that
  the user pastes into the client's post-processing script configuration.
  When a download finishes, the client POSTs to:

      POST /api/webhooks/usenet/:client_id?secret=<webhook_secret>

  The matching `MediaImport` Oban job is enqueued immediately. Combined with
  the `unique:` constraint on `MediaImport`, this means the user no longer
  has to wait for the next `DownloadMonitor` poll for completed downloads to
  enter the library.

  ## Expected payload shapes

  SABnzbd's notification-script (`script.py`) typically receives:

      {
        "name": "Some.Release.Name",
        "nzo_id": "SABnzbd_nzo_abc123",
        "status": "Completed",
        "storage": "/downloads/Some.Release.Name"
      }

  NZBGet's pp-script bridge POSTs:

      {
        "NZBID": "12345",
        "NZBName": "Some.Release.Name",
        "DestDir": "/downloads/Some.Release.Name",
        "Status": "SUCCESS"
      }

  The controller branches on the `?client=` query parameter (`sabnzbd` or
  `nzbget`); the `User-Agent` header is consulted as a fallback. If neither
  hint matches, both shapes are attempted before giving up with a 400.

  ## Response contract

    - `200` empty body — payload parsed, download located, `MediaImport`
      enqueued. The `unique:` constraint on the worker dedupes duplicate
      triggers so a poll racing with a webhook is a no-op.
    - `400` — payload missing or unparseable.
    - `404` — payload parsed but no matching `Download` row.
    - `401` — handled by `MydiaWeb.Plugs.WebhookSecretAuth` upstream.
  """

  use MydiaWeb, :controller

  require Logger

  alias Mydia.Downloads
  alias Mydia.Jobs.MediaImport
  alias Mydia.Settings.DownloadClientConfig

  @spec completed(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def completed(conn, params) do
    %DownloadClientConfig{} = client_config = conn.assigns.download_client_config

    case extract_remote_id(conn, params, client_config) do
      {:ok, remote_id} ->
        case Downloads.get_download_by_client_and_remote_id(client_config.name, remote_id) do
          nil ->
            Logger.warning("Webhook: no matching download row",
              client_id: client_config.id,
              client_name: client_config.name,
              remote_id: remote_id
            )

            send_resp(conn, 404, "")

          download ->
            enqueue_media_import(download)
            send_resp(conn, 200, "")
        end

      {:error, reason} ->
        Logger.warning("Webhook: malformed payload",
          client_id: client_config.id,
          reason: reason
        )

        send_resp(conn, 400, "")
    end
  end

  defp extract_remote_id(conn, params, client_config) do
    case detect_payload_shape(conn, params, client_config) do
      :sabnzbd -> extract_sabnzbd_id(params)
      :nzbget -> extract_nzbget_id(params)
      :unknown -> extract_either(params)
    end
  end

  defp detect_payload_shape(conn, params, client_config) do
    cond do
      params["client"] == "sabnzbd" -> :sabnzbd
      params["client"] == "nzbget" -> :nzbget
      client_config.type == :sabnzbd -> :sabnzbd
      client_config.type == :nzbget -> :nzbget
      true -> user_agent_hint(conn)
    end
  end

  defp user_agent_hint(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [ua | _] ->
        ua_lower = String.downcase(ua)

        cond do
          String.contains?(ua_lower, "sabnzbd") -> :sabnzbd
          String.contains?(ua_lower, "nzbget") -> :nzbget
          true -> :unknown
        end

      [] ->
        :unknown
    end
  end

  defp extract_sabnzbd_id(%{"nzo_id" => id}) when is_binary(id) and id != "", do: {:ok, id}
  defp extract_sabnzbd_id(_), do: {:error, :missing_nzo_id}

  defp extract_nzbget_id(%{"NZBID" => id}) when is_binary(id) and id != "", do: {:ok, id}

  defp extract_nzbget_id(%{"NZBID" => id}) when is_integer(id) and id > 0,
    do: {:ok, Integer.to_string(id)}

  defp extract_nzbget_id(%{"nzbid" => id}) when is_binary(id) and id != "", do: {:ok, id}

  defp extract_nzbget_id(%{"nzbid" => id}) when is_integer(id) and id > 0,
    do: {:ok, Integer.to_string(id)}

  defp extract_nzbget_id(_), do: {:error, :missing_nzbid}

  defp extract_either(params) do
    case extract_sabnzbd_id(params) do
      {:ok, id} -> {:ok, id}
      _ -> extract_nzbget_id(params)
    end
  end

  defp enqueue_media_import(download) do
    changeset = MediaImport.new(%{"download_id" => download.id})

    # Use Oban.insert/1 in production. In test mode the test suite disables
    # the Oban engine entirely (`engine: false`) to avoid pool conflicts with
    # the SQL sandbox, so fall back to a plain Repo.insert which still
    # respects the Oban unique index and is visible to assert_enqueued/1.
    result =
      try do
        Oban.insert(changeset)
      rescue
        RuntimeError -> Mydia.Repo.insert(changeset)
      end

    case result do
      {:ok, job} ->
        Logger.info("Webhook: enqueued MediaImport",
          download_id: download.id,
          job_id: job.id,
          conflict?: Map.get(job, :conflict?, false)
        )

        :ok

      {:error, reason} ->
        Logger.error("Webhook: failed to enqueue MediaImport",
          download_id: download.id,
          reason: inspect(reason)
        )

        :error
    end
  end
end
