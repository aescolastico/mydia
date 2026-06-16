defmodule Mydia.Plugins.KvTest do
  use Mydia.DataCase, async: true

  alias Mydia.Plugins.Error
  alias Mydia.Plugins.Kv
  alias Mydia.Settings

  defp install!(slug) do
    {:ok, config} =
      Settings.create_plugin_config(%{
        slug: slug,
        name: slug,
        version: "1.0.0",
        source_url: "test",
        manifest: %{
          "slug" => slug,
          "name" => slug,
          "version" => "1.0.0",
          "capabilities" => %{"events:subscribe" => ["media_item.added"], "state:kv" => []}
        },
        granted_capabilities: %{"state:kv" => []},
        enabled: false
      })

    config
  end

  describe "get/set/delete" do
    setup do
      install!("kvtest")
      :ok
    end

    test "set then get round-trips" do
      assert {:ok, "v1"} = Kv.set("kvtest", "k", "v1")
      assert {:ok, "v1"} = Kv.get("kvtest", "k")
    end

    test "get on a missing key returns nil" do
      assert {:ok, nil} = Kv.get("kvtest", "absent")
    end

    test "set overwrites (last write wins) without a constraint error" do
      assert {:ok, "a"} = Kv.set("kvtest", "k", "a")
      assert {:ok, "b"} = Kv.set("kvtest", "k", "b")
      assert {:ok, "c"} = Kv.set("kvtest", "k", "c")
      assert {:ok, "c"} = Kv.get("kvtest", "k")
      assert Kv.key_count("kvtest") == 1
    end

    test "delete removes the key" do
      {:ok, _} = Kv.set("kvtest", "k", "v")
      assert :ok = Kv.delete("kvtest", "k")
      assert {:ok, nil} = Kv.get("kvtest", "k")
    end

    test "delete on a missing key is a no-op" do
      assert :ok = Kv.delete("kvtest", "absent")
    end
  end

  describe "quotas" do
    setup do
      install!("kvtest")
      :ok
    end

    test "a value over the size limit is rejected and nothing is written" do
      big = String.duplicate("x", Kv.max_value_bytes() + 1)

      assert {:error, %Error{type: :invalid_request}} = Kv.set("kvtest", "k", big)
      assert {:ok, nil} = Kv.get("kvtest", "k")
    end

    test "a value at exactly the size limit is accepted" do
      ok = String.duplicate("x", Kv.max_value_bytes())
      assert {:ok, _} = Kv.set("kvtest", "k", ok)
    end

    test "the key-count quota bites a new key but never an overwrite" do
      for i <- 1..Kv.max_keys() do
        {:ok, _} = Kv.set("kvtest", "k#{i}", "v")
      end

      assert Kv.key_count("kvtest") == Kv.max_keys()

      # A new key past the cap is rejected...
      assert {:error, %Error{type: :invalid_request}} = Kv.set("kvtest", "overflow", "v")
      # ...but overwriting an existing key is still allowed at the cap.
      assert {:ok, "updated"} = Kv.set("kvtest", "k1", "updated")
    end
  end

  describe "isolation and lifecycle" do
    test "two plugins with the same key are isolated" do
      install!("plugin-a")
      install!("plugin-b")

      {:ok, _} = Kv.set("plugin-a", "shared", "from-a")
      {:ok, _} = Kv.set("plugin-b", "shared", "from-b")

      assert {:ok, "from-a"} = Kv.get("plugin-a", "shared")
      assert {:ok, "from-b"} = Kv.get("plugin-b", "shared")
    end

    test "set on an uninstalled plugin returns not_found" do
      assert {:error, %Error{type: :not_found}} = Kv.set("never-installed", "k", "v")
    end

    test "delete_connection_prefix removes only that connection's keys" do
      install!("kvtest")

      {:ok, _} = Kv.set("kvtest", "conn/abc/watermark", "1")
      {:ok, _} = Kv.set("kvtest", "conn/abc/pending", "2")
      {:ok, _} = Kv.set("kvtest", "conn/xyz/watermark", "3")
      {:ok, _} = Kv.set("kvtest", "global", "4")

      assert Kv.delete_connection_prefix("kvtest", "abc") == 2

      assert {:ok, nil} = Kv.get("kvtest", "conn/abc/watermark")
      assert {:ok, nil} = Kv.get("kvtest", "conn/abc/pending")
      assert {:ok, "3"} = Kv.get("kvtest", "conn/xyz/watermark")
      assert {:ok, "4"} = Kv.get("kvtest", "global")
    end
  end
end
