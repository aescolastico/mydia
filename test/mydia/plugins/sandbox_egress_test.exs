defmodule Mydia.Plugins.SandboxEgressTest do
  # async: false — starts a real pool under the app-wide PoolRegistry and
  # registers a descriptor in the app-wide Plugins.Registry.
  use ExUnit.Case, async: false

  alias Mydia.Plugins.Error
  alias Mydia.Plugins.Host
  alias Mydia.Plugins.HostFunctions
  alias Mydia.Plugins.Plugin
  alias Mydia.Plugins.Registry

  # A component whose only host import it exercises is the gated http-request
  # function. Its "http" branch requests https://example.test/hook and surfaces
  # the host's typed result error as the guest's own error string. There is no
  # socket API and no other egress import, so even an ambient-network platform
  # would leave this guest no way out.
  @fixture Path.join([
             __DIR__,
             "..",
             "..",
             "support",
             "fixtures",
             "plugins",
             "host_fns_fixture.wasm"
           ])

  defp fixture_bytes, do: File.read!(@fixture)

  defp payload(event), do: %{"event" => event, "metadata" => %{}}

  setup do
    Registry.clear()
    on_exit(&Registry.clear/0)
    :ok
  end

  defp start_probe!(slug, granted) do
    {:ok, _} =
      Registry.register(slug, %Plugin{
        slug: slug,
        name: slug,
        granted_capabilities: granted,
        enabled: true
      })

    {:ok, _pid} =
      Host.start_plugin(slug, fixture_bytes(), imports: HostFunctions.imports_for(slug))

    on_exit(fn -> Host.stop_plugin(slug) end)
    :ok
  end

  test "R1: a guest with no net:http grant cannot reach the network — egress denied" do
    slug = "egress-probe"
    # Deny-by-default: registered with no granted capabilities.
    start_probe!(slug, %{})

    assert {:error, %Error{type: :guest_error, message: msg}} =
             Host.call(slug, "handle", payload("http"))

    assert msg =~ "Denied"
  end

  test "R1: the same guest is still gated once net:http is granted" do
    slug = "egress-granted"
    # Granted discord.com, but the guest requests example.test — the gate's
    # allowlist still denies it. Egress is never ambient; it is always gated.
    start_probe!(slug, %{"net:http" => ["discord.com"]})

    assert {:error, %Error{type: :guest_error, message: msg}} =
             Host.call(slug, "handle", payload("http"))

    # Passed the capability check, but the requested host is off the allowlist.
    assert msg =~ "Denied"
    assert msg =~ "allowlist"
  end
end
