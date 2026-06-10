defmodule Mydia.Plugins.HostLogsTest do
  # async: false — pools register app-wide and the DataCase shared sandbox lets
  # the guest `log` host function (which runs in the component instance process)
  # persist rows.
  use Mydia.DataCase, async: false

  alias Mydia.Plugins.Error
  alias Mydia.Plugins.Host
  alias Mydia.Plugins.HostFunctions
  alias Mydia.Plugins.Logs

  defp fixture(name) do
    Path.join([__DIR__, "..", "..", "support", "fixtures", "plugins", name])
  end

  # host_test_fixture: "ok"/default -> {"first":true}; "trap" -> abort.
  defp runtime_bytes, do: File.read!(fixture("host_test_fixture.wasm"))
  # host_fns_fixture: "log" -> calls host::log("info","hello from guest").
  defp host_fns_bytes, do: File.read!(fixture("host_fns_fixture.wasm"))

  defp start!(slug, bytes, opts \\ []) do
    opts = Keyword.put_new(opts, :imports, HostFunctions.imports_for(slug))
    {:ok, _pid} = Host.start_plugin(slug, bytes, opts)
    on_exit(fn -> Host.stop_plugin(slug) end)
    :ok
  end

  defp payload(event), do: %{"event" => event, "metadata" => %{}}

  describe "host outcome markers (U2)" do
    test "a successful invocation gets a start marker and an ok end marker" do
      start!("mk-ok", runtime_bytes())
      assert {:ok, _} = Host.call("mk-ok", "handle", payload("media_item.added"))

      host = "mk-ok" |> Logs.recent() |> Enum.filter(&(&1.source == :host))
      assert Enum.any?(host, &(&1.metadata["phase"] == "start"))

      end_marker = Enum.find(host, &(&1.metadata["phase"] == "end"))
      assert end_marker.metadata["outcome"] == "ok"
      assert is_integer(end_marker.metadata["duration_ms"])
      # the triggering event is captured on the start marker
      assert Enum.any?(host, &(&1.metadata["event"] == "media_item.added"))

      # the guest's returned result is summarized into the end-marker message
      # (the fixture returns {"first":true}), so a successful run is not a bare
      # "ok" but shows what it produced.
      assert end_marker.message =~ "first=true"
      assert end_marker.metadata["detail"] == "first=true"
    end

    test "a trap is recorded as an error end marker, not silence (AE1)" do
      start!("mk-trap", runtime_bytes())
      assert {:error, %Error{type: :trap}} = Host.call("mk-trap", "handle", payload("trap"))

      rows = Logs.recent("mk-trap")

      assert Enum.any?(rows, fn r ->
               r.source == :host and r.level == :error and r.metadata["outcome"] == "trap"
             end)
    end
  end

  describe "guest log host function" do
    test "a guest log() line is captured and correlated to the invocation" do
      start!("lg", host_fns_bytes())
      assert {:ok, _} = Host.call("lg", "handle", payload("log"))

      rows = Logs.recent("lg")
      guest = Enum.find(rows, &(&1.source == :guest))

      assert guest, "expected a guest-source log row"
      assert guest.message == "hello from guest"
      assert guest.level == :info

      host_invocation = rows |> Enum.find(&(&1.source == :host)) |> Map.get(:invocation_id)
      assert guest.invocation_id == host_invocation
    end
  end
end
