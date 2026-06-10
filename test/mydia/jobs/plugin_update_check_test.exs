defmodule Mydia.Jobs.PluginUpdateCheckTest do
  use Mydia.DataCase, async: false

  alias Mydia.Jobs.PluginUpdateCheck

  setup do
    {:ok, bypass: Bypass.open()}
  end

  defp catalog_json(version) do
    Jason.encode!(%{
      "version" => 1,
      "plugins" => [
        %{
          "package_url" => "http://allowed.test/p.wasm",
          "integrity" => "sha256:ab",
          "manifest" => %{
            "slug" => "webhook-notifier",
            "name" => "Webhook Notifier",
            "version" => version,
            "capabilities" => %{"events:subscribe" => ["media_item.added"]}
          }
        }
      ]
    })
  end

  test "perform/1 is a no-op when nothing is installed (no network)" do
    assert :ok = PluginUpdateCheck.perform(%Oban.Job{args: %{}})
  end

  test "check_for_updates emits a plugin.update_available event for a newer version", %{
    bypass: bypass
  } do
    {:ok, _} =
      Mydia.Settings.create_plugin_config(%{
        slug: "webhook-notifier",
        name: "Webhook Notifier",
        version: "1.0.0"
      })

    Bypass.expect_once(bypass, "GET", "/index.json", fn conn ->
      Plug.Conn.resp(conn, 200, catalog_json("1.5.0"))
    end)

    updates =
      Mydia.Plugins.check_for_updates(
        sources: ["http://allowed.test:#{bypass.port}/index.json"],
        allow_private: true,
        resolver: fn _ -> {:ok, [{127, 0, 0, 1}]} end
      )

    assert [%{slug: "webhook-notifier", current: "1.0.0", latest: "1.5.0"}] = updates

    events = Mydia.Events.list_events(category: "plugin", type: "plugin.update_available")
    assert Enum.any?(events, &(&1.actor_id == "webhook-notifier"))
  end

  test "no update event when the installed version is current", %{bypass: bypass} do
    {:ok, _} =
      Mydia.Settings.create_plugin_config(%{
        slug: "webhook-notifier",
        name: "Webhook Notifier",
        version: "1.5.0"
      })

    Bypass.expect_once(bypass, "GET", "/index.json", fn conn ->
      Plug.Conn.resp(conn, 200, catalog_json("1.5.0"))
    end)

    assert [] =
             Mydia.Plugins.check_for_updates(
               sources: ["http://allowed.test:#{bypass.port}/index.json"],
               allow_private: true,
               resolver: fn _ -> {:ok, [{127, 0, 0, 1}]} end
             )
  end
end
