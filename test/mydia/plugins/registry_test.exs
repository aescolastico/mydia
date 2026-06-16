defmodule Mydia.Plugins.RegistryTest do
  # async: false — exercises the app-wide named Mydia.Plugins.Registry agent.
  use ExUnit.Case, async: false

  alias Mydia.Plugins.Error
  alias Mydia.Plugins.Plugin
  alias Mydia.Plugins.Registry

  setup do
    Registry.clear()
    on_exit(&Registry.clear/0)
    :ok
  end

  defp plugin(slug, attrs \\ %{}) do
    struct(%Plugin{slug: slug, name: slug, version: "1.0.0"}, attrs)
  end

  test "register / lookup / list / unregister round-trip" do
    {:ok, registered} = Registry.register("alpha", plugin("alpha"))
    assert registered.slug == "alpha"

    assert {:ok, %Plugin{slug: "alpha"}} = Registry.lookup("alpha")
    assert Registry.registered?("alpha")
    assert Enum.map(Registry.list(), & &1.slug) == ["alpha"]

    assert :ok = Registry.unregister("alpha")
    refute Registry.registered?("alpha")
    assert Registry.list() == []
  end

  test "lookup of an unknown slug returns an error" do
    assert {:error, %Error{type: :not_found}} = Registry.lookup("ghost")
  end

  test "re-registering a slug updates the descriptor" do
    {:ok, _} = Registry.register("beta", plugin("beta", %{version: "1.0.0"}))
    {:ok, _} = Registry.register("beta", plugin("beta", %{version: "2.0.0", enabled: true}))

    assert {:ok, %Plugin{version: "2.0.0", enabled: true}} = Registry.lookup("beta")
    assert length(Registry.list()) == 1
  end

  test "register/2 keys on the given slug even if the struct slug differs" do
    {:ok, registered} = Registry.register("canonical", plugin("stale"))
    assert registered.slug == "canonical"
    assert {:ok, %Plugin{slug: "canonical"}} = Registry.lookup("canonical")
  end
end
