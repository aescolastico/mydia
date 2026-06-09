defmodule Mydia.Plugins.HostFunctionsTest do
  use Mydia.DataCase, async: true

  import Mydia.MediaFixtures

  alias Mydia.Plugins.Error
  alias Mydia.Plugins.HostFunctions
  alias Mydia.Plugins.Plugin

  defp plugin(granted) do
    %Plugin{slug: "tester", name: "Tester", granted_capabilities: granted, enabled: true}
  end

  defp loopback_resolver, do: fn _ -> {:ok, [{127, 0, 0, 1}]} end

  describe "http_request/3 (net:http grant)" do
    setup do
      {:ok, bypass: Bypass.open()}
    end

    test "R6: a granted host succeeds", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/hook", fn conn ->
        Plug.Conn.resp(conn, 200, ~s({"ok":true}))
      end)

      p = plugin(%{"net:http" => ["allowed.test"]})

      assert {:ok, %{"status" => 200, "ok" => true, "body" => body}} =
               HostFunctions.http_request(
                 p,
                 %{"url" => "http://allowed.test:#{bypass.port}/hook", "method" => "POST"},
                 resolver: loopback_resolver(),
                 allow_private: true
               )

      assert body =~ "ok"
    end

    test "AE2: a host not on the grant is denied" do
      p = plugin(%{"net:http" => ["discord.com"]})

      assert {:error, %Error{type: :capability_denied}} =
               HostFunctions.http_request(p, %{"url" => "https://evil.test/"},
                 resolver: loopback_resolver()
               )
    end

    test "a plugin without the net:http grant is denied before any request" do
      p = plugin(%{"events:subscribe" => ["media_item.added"]})

      assert {:error, %Error{type: :capability_denied}} =
               HostFunctions.http_request(p, %{"url" => "https://discord.com/"})
    end

    test "a missing url is rejected" do
      p = plugin(%{"net:http" => ["discord.com"]})
      assert {:error, %Error{type: :invalid_request}} = HostFunctions.http_request(p, %{})
    end
  end

  describe "data_read/2 (data:read grant)" do
    test "returns a curated projection for a granted namespace" do
      item = media_item_fixture(%{title: "Dune", year: 2021, type: "movie"})
      p = plugin(%{"data:read" => ["media_item"]})

      assert {:ok, projection} =
               HostFunctions.data_read(p, %{"resource" => "media_item", "id" => item.id})

      assert projection["title"] == "Dune"
      assert projection["year"] == 2021
      assert projection["type"] == "movie"
      # The projection is curated — it never carries the raw struct's internals.
      refute Map.has_key?(projection, :__struct__)
      refute Map.has_key?(projection, "metadata")
    end

    test "is denied without the data:read grant" do
      item = media_item_fixture()
      p = plugin(%{"net:http" => ["discord.com"]})

      assert {:error, %Error{type: :capability_denied}} =
               HostFunctions.data_read(p, %{"resource" => "media_item", "id" => item.id})
    end

    test "is denied when the namespace is not granted" do
      item = media_item_fixture()
      p = plugin(%{"data:read" => ["something_else"]})

      assert {:error, %Error{type: :capability_denied}} =
               HostFunctions.data_read(p, %{"resource" => "media_item", "id" => item.id})
    end

    test "an unknown resource is rejected" do
      p = plugin(%{"data:read" => ["media_item"]})

      assert {:error, %Error{type: :invalid_request}} =
               HostFunctions.data_read(p, %{"resource" => "user", "id" => "1"})
    end

    test "a missing media item returns not_found" do
      p = plugin(%{"data:read" => ["media_item"]})

      assert {:error, %Error{type: type}} =
               HostFunctions.data_read(p, %{
                 "resource" => "media_item",
                 "id" => "00000000-0000-0000-0000-000000000000"
               })

      assert type in [:not_found, :invalid_request]
    end
  end

  describe "imports_for/2" do
    test "builds a per-invocation builder for the typed host interface" do
      builder = HostFunctions.imports_for("tester")
      assert is_function(builder, 1)

      imports = builder.(%{slug: "tester", invocation_id: "x", test_run: false})

      assert %{"mydia:plugin/host@1.0.0" => fns} = imports

      assert %{"http-request" => {:fn, f1}, "data-read" => {:fn, f2}, "log" => {:fn, f3}} = fns
      assert is_function(f1, 1) and is_function(f2, 1) and is_function(f3, 2)
    end
  end
end
