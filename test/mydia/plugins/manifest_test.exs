defmodule Mydia.Plugins.ManifestTest do
  use ExUnit.Case, async: true

  alias Mydia.Plugins.Error
  alias Mydia.Plugins.Manifest
  alias Mydia.Plugins.Plugin

  defp valid_map(overrides \\ %{}) do
    Map.merge(
      %{
        "slug" => "webhook-notifier",
        "name" => "Webhook Notifier",
        "version" => "1.0.0",
        "description" => "Posts events to a webhook",
        "author" => "Mydia",
        "capabilities" => %{
          "events:subscribe" => ["media_item.added", "download.completed"],
          "net:http" => ["discord.com"]
        }
      },
      overrides
    )
  end

  describe "parse/1" do
    test "parses a valid manifest with capabilities and event subscriptions" do
      assert {:ok, %Manifest{} = manifest} = Manifest.parse(valid_map())
      assert manifest.slug == "webhook-notifier"
      assert manifest.name == "Webhook Notifier"
      assert manifest.version == "1.0.0"
      assert manifest.entrypoint == "handle"
      assert manifest.events == ["media_item.added", "download.completed"]
      assert manifest.capabilities["net:http"] == ["discord.com"]
    end

    test "accepts a JSON string" do
      assert {:ok, %Manifest{slug: "webhook-notifier"}} =
               Manifest.parse(Jason.encode!(valid_map()))
    end

    test "rejects invalid JSON" do
      assert {:error, %Error{type: :invalid_manifest}} = Manifest.parse("{not json")
    end

    test "rejects a manifest missing required fields" do
      assert {:error, %Error{type: :invalid_manifest, message: msg}} =
               Manifest.parse(Map.delete(valid_map(), "version"))

      assert msg =~ "version"
    end

    test "rejects an event outside the v1 catalog" do
      map = valid_map(%{"capabilities" => %{"events:subscribe" => ["media_item.exploded"]}})
      assert {:error, %Error{type: :invalid_manifest, message: msg}} = Manifest.parse(map)
      assert msg =~ "media_item.exploded"
    end

    test "rejects an unknown capability class" do
      map =
        valid_map(%{
          "capabilities" => %{"events:subscribe" => ["media_item.added"], "fs:write" => ["/tmp"]}
        })

      assert {:error, %Error{type: :invalid_manifest, message: msg}} = Manifest.parse(map)
      assert msg =~ "fs:write"
    end

    test "rejects data:read in v1 (reserved, not available)" do
      map =
        valid_map(%{
          "capabilities" => %{
            "events:subscribe" => ["media_item.added"],
            "data:read" => ["media"]
          }
        })

      assert {:error, %Error{type: :capability_unavailable, message: msg}} = Manifest.parse(map)
      assert msg =~ "data:read"
    end

    test "rejects surfaces:write in v1 (reserved, not available)" do
      map =
        valid_map(%{
          "capabilities" => %{
            "events:subscribe" => ["media_item.added"],
            "surfaces:write" => ["recommended"]
          }
        })

      assert {:error, %Error{type: :capability_unavailable}} = Manifest.parse(map)
    end

    test "rejects a net:http wildcard hostname (KTD5 exact-match rule)" do
      map =
        valid_map(%{
          "capabilities" => %{
            "events:subscribe" => ["media_item.added"],
            "net:http" => ["*.discord.com"]
          }
        })

      assert {:error, %Error{type: :invalid_manifest, message: msg}} = Manifest.parse(map)
      assert msg =~ "wildcard"
    end

    test "requires events:subscribe to be present" do
      map = valid_map(%{"capabilities" => %{"net:http" => ["discord.com"]}})
      assert {:error, %Error{type: :invalid_manifest}} = Manifest.parse(map)
    end

    test "requires at least one capability" do
      map = valid_map(%{"capabilities" => %{}})
      assert {:error, %Error{type: :invalid_manifest}} = Manifest.parse(map)
    end
  end

  describe "Plugin.from_manifest/2 (R5 deny-by-default)" do
    test "builds a descriptor that declares capabilities but grants none" do
      {:ok, manifest} = Manifest.parse(valid_map())
      plugin = Plugin.from_manifest(manifest)

      assert %Plugin{} = plugin
      assert plugin.slug == "webhook-notifier"
      assert plugin.events == ["media_item.added", "download.completed"]
      assert plugin.capabilities["net:http"] == ["discord.com"]

      # Parsing/building confers no active capability.
      assert plugin.granted_capabilities == %{}
      assert plugin.enabled == false
      refute Plugin.granted?(plugin, "net:http")
      assert Plugin.granted_http_hosts(plugin) == []
    end

    test "carries grants only when explicitly provided (e.g. from persisted config)" do
      {:ok, manifest} = Manifest.parse(valid_map())

      plugin =
        Plugin.from_manifest(manifest,
          granted_capabilities: %{"net:http" => ["discord.com"]},
          enabled: true,
          source: :index
        )

      assert Plugin.granted?(plugin, "net:http")
      assert Plugin.granted_http_hosts(plugin) == ["discord.com"]
      assert plugin.enabled
      assert plugin.source == :index
    end
  end
end
