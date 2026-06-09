defmodule Mydia.Plugins.Notifier.DeliveryTest do
  # async: false — runs the real bundled guest in a pool under the app-wide
  # PoolRegistry. DataCase shares the sandbox connection (async: false), so the
  # guest's data:read host function can reach the DB for enrichment.
  use Mydia.DataCase, async: false

  import Mydia.MediaFixtures

  alias Mydia.Plugins.Host
  alias Mydia.Plugins.HostFunctions
  alias Mydia.Plugins.Manifest
  alias Mydia.Plugins.Notifier.Delivery
  alias Mydia.Plugins.Plugin
  alias Mydia.Plugins.Registry
  alias Mydia.Settings

  @slug "webhook-notifier"

  defp bundled_wasm,
    do: File.read!(Application.app_dir(:mydia, "priv/plugins/webhook_notifier.wasm"))

  defp bundled_manifest,
    do: File.read!(Application.app_dir(:mydia, "priv/plugins/webhook_notifier.json"))

  # Starts the real notifier guest with a grant for the Bypass host and the
  # loopback gate seam, plus a config row carrying the webhook URL.
  defp start_notifier!(bypass, opts \\ []) do
    {:ok, manifest} = Manifest.parse(bundled_manifest())
    host = Keyword.get(opts, :webhook_host, "webhook.test")
    granted_host = Keyword.get(opts, :granted_host, host)

    grants = %{
      "events:subscribe" => manifest.events,
      "net:http" => [granted_host],
      "data:read" => ["media_item"]
    }

    {:ok, _} =
      Settings.create_plugin_config(%{
        slug: @slug,
        name: manifest.name,
        version: manifest.version,
        manifest: %{"capabilities" => manifest.capabilities},
        wasm_module: bundled_wasm(),
        granted_capabilities: grants,
        enabled: true,
        settings: %{
          "webhook_url" => "http://#{host}:#{bypass.port}/hook",
          "delivery" => "durable"
        }
      })

    descriptor =
      Plugin.from_manifest(manifest,
        granted_capabilities: grants,
        enabled: true,
        delivery: :durable
      )

    {:ok, _} = Registry.register(@slug, descriptor)

    imports =
      HostFunctions.imports_for(@slug,
        allow_private: true,
        resolver: fn _ -> {:ok, [{127, 0, 0, 1}]} end
      )

    {:ok, _} = Host.start_plugin(@slug, bundled_wasm(), imports: imports)
    on_exit(fn -> Host.stop_plugin(@slug) end)
    :ok
  end

  defp job(payload), do: %Oban.Job{args: %{"slug" => @slug, "payload" => payload}}

  defp added_payload(media_item) do
    %{
      "event" => "media_item.added",
      "category" => "media",
      "resource_type" => "media_item",
      "resource_id" => media_item.id,
      "metadata" => %{"title" => media_item.title}
    }
  end

  setup do
    Registry.clear()
    on_exit(&Registry.clear/0)
    {:ok, bypass: Bypass.open()}
  end

  test "R16/F3: a media_item.added event drives a webhook POST with the expected payload", %{
    bypass: bypass
  } do
    start_notifier!(bypass)
    item = media_item_fixture(%{title: "Interstellar"})

    test_pid = self()

    Bypass.expect_once(bypass, "POST", "/hook", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:webhook_body, body})
      Plug.Conn.resp(conn, 204, "")
    end)

    assert :ok = Delivery.perform(job(added_payload(item)))

    assert_receive {:webhook_body, body}
    assert body =~ "Interstellar"
    assert body =~ "Added to library"
  end

  test "enriches the payload via data:read (overview from the media item)", %{bypass: bypass} do
    start_notifier!(bypass)

    item =
      media_item_fixture(%{
        title: "Dune",
        metadata: %{overview: "A noble family takes control of a desert planet."}
      })

    test_pid = self()

    Bypass.expect_once(bypass, "POST", "/hook", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:webhook_body, body})
      Plug.Conn.resp(conn, 204, "")
    end)

    assert :ok = Delivery.perform(job(added_payload(item)))
    assert_receive {:webhook_body, body}
    assert body =~ "desert planet"
  end

  test "download.completed also triggers delivery", %{bypass: bypass} do
    start_notifier!(bypass)
    Bypass.expect_once(bypass, "POST", "/hook", fn conn -> Plug.Conn.resp(conn, 200, "") end)

    payload = %{
      "event" => "download.completed",
      "category" => "downloads",
      "metadata" => %{"title" => "Some.Release.1080p"}
    }

    assert :ok = Delivery.perform(job(payload))
  end

  test "returns an error (for Oban retry) when the webhook responds 5xx", %{bypass: bypass} do
    start_notifier!(bypass)
    item = media_item_fixture()
    Bypass.expect(bypass, "POST", "/hook", fn conn -> Plug.Conn.resp(conn, 500, "boom") end)

    assert {:error, _} = Delivery.perform(job(added_payload(item)))
  end

  test "AE2: a webhook host that is not on the grant is blocked by the gate", %{bypass: bypass} do
    # Granted discord.com, but the configured webhook points at webhook.test.
    start_notifier!(bypass, granted_host: "discord.com", webhook_host: "webhook.test")
    item = media_item_fixture()

    # The gate denies before any request, so Bypass is never hit and delivery fails.
    assert {:error, _} = Delivery.perform(job(added_payload(item)))
  end
end
