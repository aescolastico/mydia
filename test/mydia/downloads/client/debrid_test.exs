defmodule Mydia.Downloads.Client.DebridTest do
  @moduledoc """
  Placeholder tests landing alongside U1.

  Asserts that the `:debrid` adapter is wired into the Registry and that the
  module satisfies the `Mydia.Downloads.Client` behaviour. The full dispatch
  test surface is exercised by U4 once provider modules exist.
  """
  use ExUnit.Case, async: false

  alias Mydia.Downloads.Client.{Debrid, Registry}

  setup do
    # The application supervisor registers adapters at startup. Re-register
    # here to make this test independent of init ordering.
    Registry.register(:debrid, Debrid)
    :ok
  end

  describe "registration" do
    test "the :debrid type resolves to Mydia.Downloads.Client.Debrid" do
      assert {:ok, Debrid} = Registry.get_adapter(:debrid)
    end

    test "Debrid implements the Mydia.Downloads.Client behaviour" do
      behaviours =
        Debrid.module_info(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()

      assert Mydia.Downloads.Client in behaviours
    end

    test "the seven Client callbacks are exported" do
      callbacks = [
        {:test_connection, 1},
        {:add_torrent, 3},
        {:get_status, 2},
        {:list_torrents, 2},
        {:remove_torrent, 3},
        {:pause_torrent, 2},
        {:resume_torrent, 2}
      ]

      exports = Debrid.module_info(:exports)

      for cb <- callbacks do
        assert cb in exports, "expected Debrid to export #{inspect(cb)}"
      end
    end
  end
end
