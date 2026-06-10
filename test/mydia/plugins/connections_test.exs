defmodule Mydia.Plugins.ConnectionsTest do
  use Mydia.DataCase, async: true

  import Mydia.AccountsFixtures

  alias Mydia.Plugins.Connections
  alias Mydia.Plugins.Kv
  alias Mydia.Settings

  defp install!(slug) do
    {:ok, _} =
      Settings.create_plugin_config(%{
        slug: slug,
        name: slug,
        version: "1.0.0",
        source_url: "test",
        manifest: %{
          "slug" => slug,
          "name" => slug,
          "version" => "1.0.0",
          "capabilities" => %{
            "events:subscribe" => ["media_item.added"],
            "users:connections" => []
          }
        },
        granted_capabilities: %{"users:connections" => []},
        enabled: false
      })

    :ok
  end

  setup do
    install!("connector")
    %{user: user_fixture(), other: user_fixture()}
  end

  describe "connect/3 and reads" do
    test "creates a connection and round-trips identity", %{user: user} do
      assert {:ok, conn} =
               Connections.connect("connector", user.id, %{
                 access_token: "secret-token",
                 external_user_id: "ext-1",
                 external_username: "alice"
               })

      assert conn.status == "connected"
      assert conn.external_username == "alice"

      fetched = Connections.get("connector", user.id)
      assert fetched.id == conn.id
    end

    test "reconnect updates the existing row (no duplicate)", %{user: user} do
      {:ok, _} = Connections.connect("connector", user.id, %{access_token: "t1"})

      {:ok, _} =
        Connections.connect("connector", user.id, %{access_token: "t2", status: "connected"})

      assert Connections.count_for_plugin("connector") == 1
    end

    test "connect on an uninstalled plugin fails", %{user: user} do
      assert {:error, :not_installed} =
               Connections.connect("ghost", user.id, %{access_token: "t"})
    end

    test "the access token is redacted from struct inspection", %{user: user} do
      {:ok, conn} = Connections.connect("connector", user.id, %{access_token: "super-secret"})
      refute inspect(conn) =~ "super-secret"
    end
  end

  describe "consent boundary (R21)" do
    test "connected_user_ids returns only active connections", %{user: user, other: other} do
      {:ok, _} = Connections.connect("connector", user.id, %{access_token: "t"})
      {:ok, _} = Connections.connect("connector", other.id, %{access_token: "t", status: "error"})

      ids = Connections.connected_user_ids("connector")
      assert user.id in ids
      refute other.id in ids
    end

    test "active? is true only for connected status", %{user: user} do
      {:ok, _} = Connections.connect("connector", user.id, %{access_token: "t"})
      assert Connections.active?("connector", user.id)

      Connections.mark_errored("connector", [user.id])
      refute Connections.active?("connector", user.id)
    end
  end

  describe "mark_errored/2" do
    test "flips only users that hold an active connection", %{user: user, other: other} do
      {:ok, _} = Connections.connect("connector", user.id, %{access_token: "t"})
      # `other` has no connection to this plugin.

      assert Connections.mark_errored("connector", [user.id, other.id, "bogus-id"]) == 1
      assert Connections.get("connector", user.id).status == "error"
      assert Connections.get("connector", other.id) == nil
    end
  end

  describe "disconnect and cleanup" do
    test "disconnect sweeps the connection's KV prefix and removes the row", %{user: user} do
      {:ok, conn} = Connections.connect("connector", user.id, %{access_token: "t"})

      {:ok, _} = Kv.set("connector", "conn/#{conn.id}/watermark", "1")
      {:ok, _} = Kv.set("connector", "global", "keep")

      assert :ok = Connections.disconnect("connector", user.id)

      assert Connections.get("connector", user.id) == nil
      assert {:ok, nil} = Kv.get("connector", "conn/#{conn.id}/watermark")
      assert {:ok, "keep"} = Kv.get("connector", "global")
    end

    test "delete_for_user sweeps KV and removes the user's connections", %{user: user} do
      {:ok, conn} = Connections.connect("connector", user.id, %{access_token: "t"})
      {:ok, _} = Kv.set("connector", "conn/#{conn.id}/cursor", "x")

      assert :ok = Connections.delete_for_user(user.id)

      assert Connections.get("connector", user.id) == nil
      assert {:ok, nil} = Kv.get("connector", "conn/#{conn.id}/cursor")
    end
  end
end
