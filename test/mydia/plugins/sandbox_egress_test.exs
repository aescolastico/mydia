defmodule Mydia.Plugins.SandboxEgressTest do
  # async: false — starts a real pool under the app-wide PoolRegistry and
  # registers a descriptor in the app-wide Plugins.Registry.
  use ExUnit.Case, async: false

  alias Mydia.Plugins.Host
  alias Mydia.Plugins.HostFunctions
  alias Mydia.Plugins.Plugin
  alias Mydia.Plugins.Registry

  # A guest whose only import is the gated http_request host function. It calls
  # it for a request and returns the host's JSON response envelope as its result.
  # If the platform ever granted ambient network access, this guest would still
  # have no way to use it — there is no socket API and no other import.
  @egress_wat """
  (module
    (import "mydia" "http_request"
      (func $http (param i32 i32 i32 i32) (result i32)))
    (memory (export "memory") 2)
    (data (i32.const 0) "{\\"url\\":\\"https://evil.test/\\"}")
    (func (export "mydia_alloc") (param $len i32) (result i32) (i32.const 4096))
    (func (export "handle") (param $ptr i32) (param $len i32) (result i64)
      (local $n i32)
      (local.set $n
        (call $http (i32.const 0) (i32.const 28) (i32.const 1024) (i32.const 2048)))
      (i64.or
        (i64.shl (i64.const 1024) (i64.const 32))
        (i64.extend_i32_u (local.get $n)))))
  """

  defp wasm!(wat) do
    {:ok, bytes} = Wasmex.Wat.to_wasm(wat)
    bytes
  end

  setup do
    Registry.clear()
    on_exit(&Registry.clear/0)
    :ok
  end

  test "R1: a guest with no net:http grant cannot reach the network — egress denied" do
    slug = "egress-probe"

    # Deny-by-default: registered with no granted capabilities.
    {:ok, _} =
      Registry.register(slug, %Plugin{
        slug: slug,
        name: slug,
        granted_capabilities: %{},
        enabled: true
      })

    {:ok, _pid} =
      Host.start_plugin(slug, wasm!(@egress_wat), imports: HostFunctions.imports_for(slug))

    on_exit(fn -> Host.stop_plugin(slug) end)

    assert {:ok, %{"type" => "capability_denied"}} = Host.call(slug, "handle", %{})
  end

  test "R1: the same guest reaches the network only once net:http is granted (but still gated)" do
    slug = "egress-granted"

    # Granted discord.com, but the guest requests evil.test — the gate's
    # allowlist still denies it. Egress is never ambient; it is always gated.
    {:ok, _} =
      Registry.register(slug, %Plugin{
        slug: slug,
        name: slug,
        granted_capabilities: %{"net:http" => ["discord.com"]},
        enabled: true
      })

    {:ok, _pid} =
      Host.start_plugin(slug, wasm!(@egress_wat), imports: HostFunctions.imports_for(slug))

    on_exit(fn -> Host.stop_plugin(slug) end)

    # net:http is granted, so it passes the capability check, but the requested
    # host (evil.test) is off the allowlist — still denied at the gate.
    assert {:ok, %{"type" => "capability_denied"}} = Host.call(slug, "handle", %{})
  end
end
