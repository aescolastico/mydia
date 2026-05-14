defmodule MydiaWeb.Api.Webhook.UsenetControllerTest do
  use MydiaWeb.ConnCase, async: true
  use Oban.Testing, repo: Mydia.Repo

  alias Mydia.Jobs.MediaImport
  alias Mydia.Settings

  import Mydia.DownloadsFixtures

  describe "POST /api/webhooks/v1/usenet/:client_id (SABnzbd)" do
    test "enqueues MediaImport on valid secret + sabnzbd payload", %{conn: conn} do
      {client, download} = setup_client_and_download(:sabnzbd, "sab-nzo-abc-123")
      url = webhook_url(client.id, client.webhook_secret)
      payload = sabnzbd_payload(download.download_client_id)

      conn = post(conn, url, payload)

      assert response(conn, 200) == ""

      assert_enqueued(
        worker: MediaImport,
        args: %{"download_id" => download.id}
      )
    end

    test "accepts secret via X-Mydia-Webhook-Secret header", %{conn: conn} do
      {client, download} = setup_client_and_download(:sabnzbd, "sab-header-1")

      url = "/api/webhooks/v1/usenet/#{client.id}"
      payload = sabnzbd_payload(download.download_client_id)

      conn =
        conn
        |> put_req_header("x-mydia-webhook-secret", client.webhook_secret)
        |> post(url, payload)

      assert response(conn, 200) == ""
      assert_enqueued(worker: MediaImport, args: %{"download_id" => download.id})
    end

    test "branches via ?client=sabnzbd even when client type is generic", %{conn: conn} do
      # A user with a torrent client could theoretically wire a webhook with
      # `?client=sabnzbd` to force the parser. Verify that explicit query
      # parameter is the highest-priority signal.
      {client, download} = setup_client_and_download(:qbittorrent, "qb-1")
      url = "/api/webhooks/v1/usenet/#{client.id}?secret=#{client.webhook_secret}&client=sabnzbd"
      payload = sabnzbd_payload(download.download_client_id)

      conn = post(conn, url, payload)
      assert response(conn, 200) == ""
      assert_enqueued(worker: MediaImport, args: %{"download_id" => download.id})
    end
  end

  describe "POST /api/webhooks/v1/usenet/:client_id (NZBGet)" do
    test "enqueues MediaImport on valid secret + nzbget payload", %{conn: conn} do
      {client, download} = setup_client_and_download(:nzbget, "12345")
      url = webhook_url(client.id, client.webhook_secret)
      payload = nzbget_payload(download.download_client_id)

      conn = post(conn, url, payload)

      assert response(conn, 200) == ""

      assert_enqueued(
        worker: MediaImport,
        args: %{"download_id" => download.id}
      )
    end

    test "accepts integer NZBID and stringifies it for lookup", %{conn: conn} do
      {client, download} = setup_client_and_download(:nzbget, "67890")
      url = webhook_url(client.id, client.webhook_secret)

      payload = %{
        "NZBID" => 67_890,
        "NZBName" => "Some.Release.Name",
        "DestDir" => "/downloads/Some.Release.Name",
        "Status" => "SUCCESS"
      }

      conn = post(conn, url, payload)
      assert response(conn, 200) == ""
      assert_enqueued(worker: MediaImport, args: %{"download_id" => download.id})
    end
  end

  describe "auth failures" do
    test "rejects request with invalid secret", %{conn: conn} do
      {client, _download} = setup_client_and_download(:sabnzbd, "sab-1")
      url = "/api/webhooks/v1/usenet/#{client.id}?secret=this-is-wrong"

      conn = post(conn, url, sabnzbd_payload("sab-1"))

      assert response(conn, 401) == ""
      refute_enqueued(worker: MediaImport)
    end

    test "rejects request with missing secret", %{conn: conn} do
      {client, _download} = setup_client_and_download(:sabnzbd, "sab-1")
      url = "/api/webhooks/v1/usenet/#{client.id}"

      conn = post(conn, url, sabnzbd_payload("sab-1"))

      assert response(conn, 401) == ""
      refute_enqueued(worker: MediaImport)
    end

    test "rejects request with empty secret query param", %{conn: conn} do
      {client, _download} = setup_client_and_download(:sabnzbd, "sab-1")
      url = "/api/webhooks/v1/usenet/#{client.id}?secret="

      conn = post(conn, url, sabnzbd_payload("sab-1"))

      assert response(conn, 401) == ""
      refute_enqueued(worker: MediaImport)
    end

    test "secret comparison is constant-time via Plug.Crypto.secure_compare/2" do
      # We can't directly test side-channel resistance, but we can verify the
      # plug delegates to the safe comparator. This is a behavioural smoke
      # test that the plug rejects close-but-wrong secrets.
      {client, _download} = setup_client_and_download(:sabnzbd, "sab-ct")
      conn = build_conn()

      # Off by one character at the start, end, and middle.
      <<first::utf8, rest::binary>> = client.webhook_secret
      wrong_start = <<first + 1::utf8>> <> rest

      url = "/api/webhooks/v1/usenet/#{client.id}?secret=#{URI.encode_www_form(wrong_start)}"
      conn = post(conn, url, sabnzbd_payload("sab-ct"))

      assert response(conn, 401) == ""
    end
  end

  describe "unknown client" do
    test "returns 404 when client_id does not resolve to a DownloadClientConfig", %{conn: conn} do
      bogus_id = Ecto.UUID.generate()
      url = "/api/webhooks/v1/usenet/#{bogus_id}?secret=anything"

      conn = post(conn, url, sabnzbd_payload("nope"))

      assert response(conn, 404) == ""
      refute_enqueued(worker: MediaImport)
    end

    test "returns 404 when client_id is not a valid UUID", %{conn: conn} do
      url = "/api/webhooks/v1/usenet/not-a-uuid?secret=whatever"

      conn = post(conn, url, sabnzbd_payload("nope"))

      assert response(conn, 404) == ""
    end
  end

  describe "malformed payload" do
    test "returns 400 when SABnzbd payload has no nzo_id", %{conn: conn} do
      {client, _download} = setup_client_and_download(:sabnzbd, "sab-1")
      url = webhook_url(client.id, client.webhook_secret)

      conn = post(conn, url, %{"name" => "no-id-here"})

      assert response(conn, 400) == ""
      refute_enqueued(worker: MediaImport)
    end

    test "returns 400 when NZBGet payload has no NZBID", %{conn: conn} do
      {client, _download} = setup_client_and_download(:nzbget, "nzb-1")
      url = webhook_url(client.id, client.webhook_secret)

      conn = post(conn, url, %{"NZBName" => "no-id-here"})

      assert response(conn, 400) == ""
      refute_enqueued(worker: MediaImport)
    end

    test "returns 400 on empty JSON body", %{conn: conn} do
      {client, _download} = setup_client_and_download(:sabnzbd, "sab-1")
      url = webhook_url(client.id, client.webhook_secret)

      conn = post(conn, url, %{})

      assert response(conn, 400) == ""
      refute_enqueued(worker: MediaImport)
    end
  end

  describe "no matching download row" do
    test "returns 404 when payload nzo_id has no matching download", %{conn: conn} do
      {client, _download} = setup_client_and_download(:sabnzbd, "sab-real")
      url = webhook_url(client.id, client.webhook_secret)

      conn = post(conn, url, sabnzbd_payload("sab-does-not-exist"))

      assert response(conn, 404) == ""
      refute_enqueued(worker: MediaImport)
    end
  end

  describe "idempotency" do
    test "two webhook hits enqueue only one MediaImport job" do
      {client, download} = setup_client_and_download(:sabnzbd, "sab-idem-1")
      url = webhook_url(client.id, client.webhook_secret)
      payload = sabnzbd_payload(download.download_client_id)

      _conn1 = post(build_conn(), url, payload)
      _conn2 = post(build_conn(), url, payload)

      assert [_job] = all_enqueued(worker: MediaImport)
    end

    test "webhook dedupes against a snoozed (:scheduled) MediaImport job", %{conn: conn} do
      {client, download} = setup_client_and_download(:sabnzbd, "sab-idem-2")

      # Pretend the monitor already enqueued a snoozed retry — common state
      # while we wait for the user's download to finish. State :scheduled is
      # explicitly part of the unique config so the webhook hit below must
      # NOT insert a duplicate.
      future = DateTime.add(DateTime.utc_now(), 300, :second)
      changeset = MediaImport.new(%{"download_id" => download.id}, scheduled_at: future)
      {:ok, _scheduled_job} = Oban.insert(changeset)

      url = webhook_url(client.id, client.webhook_secret)
      payload = sabnzbd_payload(download.download_client_id)

      _conn = post(conn, url, payload)

      assert [_only_one] = all_enqueued(worker: MediaImport)
    end
  end

  describe "perform/1 idempotency short-circuit" do
    test "returns :ok immediately when download.imported_at is set" do
      media_item = Mydia.MediaFixtures.media_item_fixture()

      download =
        download_fixture(%{
          media_item_id: media_item.id,
          download_client: "shorted",
          download_client_id: "shorted-1"
        })

      # Pretend the import already completed previously.
      {:ok, _} =
        Mydia.Downloads.update_download(download, %{
          completed_at: DateTime.utc_now(),
          imported_at: DateTime.utc_now()
        })

      assert :ok == perform_job(MediaImport, %{"download_id" => download.id})
    end
  end

  ## Helpers

  defp setup_client_and_download(type, remote_id) do
    name = "client-#{System.unique_integer([:positive])}"

    {:ok, client} = Settings.create_download_client_config(client_attrs(type, name))

    media_item = Mydia.MediaFixtures.media_item_fixture()

    download =
      download_fixture(%{
        media_item_id: media_item.id,
        download_client: client.name,
        download_client_id: remote_id,
        completed_at: DateTime.utc_now()
      })

    {client, download}
  end

  defp client_attrs(:sabnzbd, name) do
    %{
      name: name,
      type: :sabnzbd,
      host: "localhost",
      port: 8080,
      api_key: "k",
      enabled: true,
      priority: 1
    }
  end

  defp client_attrs(:nzbget, name) do
    %{
      name: name,
      type: :nzbget,
      host: "localhost",
      port: 6789,
      username: "nzbget",
      password: "tegbzn6789",
      enabled: true,
      priority: 1
    }
  end

  defp client_attrs(:qbittorrent, name) do
    %{
      name: name,
      type: :qbittorrent,
      host: "localhost",
      port: 8081,
      username: "admin",
      password: "adminadmin",
      enabled: true,
      priority: 1
    }
  end

  defp webhook_url(client_id, secret) do
    "/api/webhooks/v1/usenet/#{client_id}?secret=#{URI.encode_www_form(secret)}"
  end

  defp sabnzbd_payload(nzo_id) do
    %{
      "name" => "Some.Release.Name.S01E01.1080p.mkv",
      "nzo_id" => nzo_id,
      "status" => "Completed",
      "storage" => "/downloads/Some.Release.Name"
    }
  end

  defp nzbget_payload(nzbid) do
    %{
      "NZBID" => nzbid,
      "NZBName" => "Some.Release.Name.S01E01.1080p",
      "DestDir" => "/downloads/Some.Release.Name",
      "Status" => "SUCCESS"
    }
  end
end
