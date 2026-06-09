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

    test "parses data:read with a valid namespace (available in v1)" do
      map =
        valid_map(%{
          "capabilities" => %{
            "events:subscribe" => ["media_item.added"],
            "net:http" => ["discord.com"],
            "data:read" => ["media_item"]
          }
        })

      assert {:ok, %Manifest{capabilities: caps}} = Manifest.parse(map)
      assert caps["data:read"] == ["media_item"]
    end

    test "rejects a data:read namespace outside the v1 catalog" do
      map =
        valid_map(%{
          "capabilities" => %{
            "events:subscribe" => ["media_item.added"],
            "data:read" => ["secrets"]
          }
        })

      assert {:error, %Error{type: :invalid_manifest, message: msg}} = Manifest.parse(map)
      assert msg =~ "secrets"
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

  describe "parse/1 settings_schema" do
    defp schema_map(schema) do
      valid_map(%{"settings_schema" => schema})
    end

    test "parses a schema with url (host-granting), secret, and enum fields" do
      map =
        schema_map([
          %{
            "key" => "target",
            "type" => "enum",
            "label" => "Target",
            "options" => ["discord", "ntfy"]
          },
          %{
            "key" => "webhook_url",
            "type" => "url",
            "label" => "Server URL",
            "grants_host" => true
          },
          %{"key" => "ntfy_token", "type" => "secret", "label" => "Access token"}
        ])

      assert {:ok, %Manifest{settings_schema: schema}} = Manifest.parse(map)
      assert length(schema) == 3
      assert Manifest.host_granting_keys(schema) == ["webhook_url"]
    end

    test "defaults to an empty schema when absent (backward compatible)" do
      assert {:ok, %Manifest{settings_schema: []}} = Manifest.parse(valid_map())
    end

    test "host_granting_keys/1 works on a parsed manifest struct" do
      {:ok, manifest} =
        Manifest.parse(
          schema_map([%{"key" => "webhook_url", "type" => "url", "grants_host" => true}])
        )

      assert Manifest.host_granting_keys(manifest) == ["webhook_url"]
    end

    test "rejects grants_host on a non-url field" do
      map = schema_map([%{"key" => "secret_field", "type" => "secret", "grants_host" => true}])
      assert {:error, %Error{type: :invalid_manifest, message: msg}} = Manifest.parse(map)
      assert msg =~ "grants_host"
    end

    test "rejects an unknown field type" do
      map = schema_map([%{"key" => "weird", "type" => "datetime"}])
      assert {:error, %Error{type: :invalid_manifest, message: msg}} = Manifest.parse(map)
      assert msg =~ "datetime"
    end

    test "rejects an enum field with no options" do
      map = schema_map([%{"key" => "target", "type" => "enum"}])
      assert {:error, %Error{type: :invalid_manifest, message: msg}} = Manifest.parse(map)
      assert msg =~ "options"
    end

    test "rejects a blank field key" do
      map = schema_map([%{"key" => "", "type" => "string"}])
      assert {:error, %Error{type: :invalid_manifest, message: msg}} = Manifest.parse(map)
      assert msg =~ "key"
    end

    test "rejects duplicate field keys" do
      map =
        schema_map([
          %{"key" => "dup", "type" => "string"},
          %{"key" => "dup", "type" => "url"}
        ])

      assert {:error, %Error{type: :invalid_manifest, message: msg}} = Manifest.parse(map)
      assert msg =~ "unique"
    end

    test "rejects a non-list settings_schema" do
      map = schema_map(%{"key" => "x", "type" => "string"})
      assert {:error, %Error{type: :invalid_manifest, message: msg}} = Manifest.parse(map)
      assert msg =~ "list"
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
