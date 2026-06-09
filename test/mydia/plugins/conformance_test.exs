defmodule Mydia.Plugins.ConformanceTest do
  # async: false — starts a real pool under the app-wide PoolRegistry and seeds
  # PluginConfig rows that the activation path reads.
  use Mydia.DataCase, async: false

  alias Mydia.Plugins
  alias Mydia.Plugins.Error
  alias Mydia.Plugins.Host
  alias Mydia.Plugins.HostFunctions
  alias Mydia.Settings

  defp host_version, do: :mydia |> Application.spec(:vsn) |> List.to_string()

  # A component built from the canonical mydia:plugin@1.0.0 WIT (via the SDK).
  @fixture Path.join([
             __DIR__,
             "..",
             "..",
             "support",
             "fixtures",
             "plugins",
             "host_fns_fixture.wasm"
           ])

  defp payload(event), do: %{"event" => event, "metadata" => %{}}

  setup do
    # Plugin lifecycle calls Plugins.reload/0, which replaces the global
    # :runtime_config — restore it so the pollution doesn't outlive the test.
    original_runtime = Application.get_env(:mydia, :runtime_config)
    on_exit(fn -> Application.put_env(:mydia, :runtime_config, original_runtime) end)
    :ok
  end

  describe "WIT contract conformance (R9)" do
    test "a guest built from the canonical WIT instantiates against the live host" do
      # If plugin.wit drifted from the host's expected interface/version
      # (Host.@handler_export or the host-import namespace), wasmtime's component
      # linker would refuse this guest at instantiation. A clean call proves the
      # host provides exactly the contract the SDK builds guests against.
      bytes = File.read!(@fixture)

      {:ok, _pid} =
        Host.start_plugin("conformance", bytes, imports: HostFunctions.imports_for("conformance"))

      on_exit(fn -> Host.stop_plugin("conformance") end)

      assert {:ok, %{"logged" => true}} = Host.call("conformance", "handle", payload("log"))
    end
  end

  describe "min_host_version floor (R7)" do
    defp seed!(slug, min_host_version) do
      manifest = %{
        "slug" => slug,
        "name" => slug,
        "version" => "1.0.0",
        "min_host_version" => min_host_version,
        "capabilities" => %{"events:subscribe" => ["media_item.added"]}
      }

      {:ok, _} =
        Settings.create_plugin_config(%{
          slug: slug,
          name: slug,
          version: "1.0.0",
          source_url: "test",
          manifest: manifest,
          granted_capabilities: %{},
          enabled: false
        })

      :ok
    end

    test "refuses a plugin whose floor exceeds the host with an actionable message" do
      seed!("floor-too-high", "999.0.0")

      assert {:error, %Error{type: :host_version, message: msg}} =
               Plugins.set_enabled("floor-too-high", true)

      assert msg =~ "requires mydia >= 999.0.0"
    end

    test "a floor at or below the host passes the floor check" do
      # A satisfiable floor (the host's own version) must not be what blocks
      # activation. This synthetic plugin has no resolvable artifact, so
      # activation still fails — but with a non-floor error, proving the floor
      # gate let it through.
      seed!("floor-ok", host_version())

      assert {:error, %Error{type: type}} = Plugins.set_enabled("floor-ok", true)
      refute type == :host_version
    end
  end
end
