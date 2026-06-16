defmodule Mydia.Downloads.Client.RegistryTest do
  use ExUnit.Case, async: false

  alias Mydia.Downloads.Client.{Error, Registry}

  # Test adapter modules
  defmodule TestAdapter do
    @behaviour Mydia.Downloads.Client

    @impl true
    def supported_protocols, do: [:torrent]

    @impl true
    def test_connection(_config), do: {:ok, %{version: "1.0.0"}}

    @impl true
    def add_torrent(_config, _torrent, _opts), do: {:ok, "test-id"}

    @impl true
    def get_status(_config, _id), do: {:ok, %{}}

    @impl true
    def list_torrents(_config, _opts), do: {:ok, []}

    @impl true
    def remove_torrent(_config, _id, _opts), do: :ok

    @impl true
    def pause_torrent(_config, _id), do: :ok

    @impl true
    def resume_torrent(_config, _id), do: :ok
  end

  defmodule AnotherTestAdapter do
    @behaviour Mydia.Downloads.Client

    @impl true
    def supported_protocols, do: [:torrent]

    @impl true
    def test_connection(_config), do: {:ok, %{version: "2.0.0"}}

    @impl true
    def add_torrent(_config, _torrent, _opts), do: {:ok, "another-id"}

    @impl true
    def get_status(_config, _id), do: {:ok, %{}}

    @impl true
    def list_torrents(_config, _opts), do: {:ok, []}

    @impl true
    def remove_torrent(_config, _id, _opts), do: :ok

    @impl true
    def pause_torrent(_config, _id), do: :ok

    @impl true
    def resume_torrent(_config, _id), do: :ok
  end

  setup do
    # Clear registry before each test to ensure clean state
    Registry.clear()

    # Every resolution site (queue, history, client_health, untracked_matcher,
    # media_import) now resolves adapters through this Registry. Clearing it here
    # would leave the production adapters unregistered for any test file that runs
    # afterward, so restore them once this file's tests complete.
    on_exit(fn -> Mydia.Downloads.register_clients() end)
    :ok
  end

  describe "register/2" do
    test "registers a new adapter" do
      assert :ok = Registry.register(:test_client, TestAdapter)
      assert Registry.registered?(:test_client)
    end

    test "allows registering multiple adapters" do
      assert :ok = Registry.register(:test_client, TestAdapter)
      assert :ok = Registry.register(:another_client, AnotherTestAdapter)

      assert Registry.registered?(:test_client)
      assert Registry.registered?(:another_client)
    end

    test "overwrites existing adapter with same type" do
      assert :ok = Registry.register(:test_client, TestAdapter)
      assert :ok = Registry.register(:test_client, AnotherTestAdapter)

      {:ok, adapter} = Registry.get_adapter(:test_client)
      assert adapter == AnotherTestAdapter
    end
  end

  describe "get_adapter/1" do
    test "returns adapter module when registered" do
      Registry.register(:test_client, TestAdapter)

      assert {:ok, TestAdapter} = Registry.get_adapter(:test_client)
    end

    test "returns error when adapter not registered" do
      assert {:error, %Error{type: :invalid_config}} = Registry.get_adapter(:unknown_client)
    end

    test "error includes client type in message" do
      {:error, error} = Registry.get_adapter(:unknown_client)

      assert error.message =~ "unknown_client"
      assert error.message =~ "Unknown client type"
    end
  end

  describe "lookup/1" do
    test "returns adapter module when registered" do
      Registry.register(:test_client, TestAdapter)

      assert Registry.lookup(:test_client) == TestAdapter
    end

    test "returns nil when adapter not registered" do
      assert Registry.lookup(:unknown_client) == nil
    end
  end

  describe "consolidated adapter resolution (single source of truth)" do
    # Characterizes that register_clients/0 is the one place mapping client type
    # to adapter module, replacing the four private dispatch tables that formerly
    # lived in history.ex, untracked_matcher.ex, client_health.ex, and
    # media_import.ex. Every production type must resolve to its adapter via the
    # Registry, since those call sites now depend on it.
    @production_adapters %{
      qbittorrent: Mydia.Downloads.Client.QBittorrent,
      transmission: Mydia.Downloads.Client.Transmission,
      rqbit: Mydia.Downloads.Client.Rqbit,
      rtorrent: Mydia.Downloads.Client.Rtorrent,
      blackhole: Mydia.Downloads.Client.Blackhole,
      sabnzbd: Mydia.Downloads.Client.Sabnzbd,
      nzbget: Mydia.Downloads.Client.Nzbget,
      debrid: Mydia.Downloads.Client.Debrid
    }

    setup do
      Mydia.Downloads.register_clients()
      :ok
    end

    test "every production client type resolves to its adapter module" do
      for {type, module} <- @production_adapters do
        assert Registry.lookup(type) == module,
               "expected #{type} to resolve to #{inspect(module)}"
      end
    end

    test "unknown type resolves to nil (matches former dispatch-table fallback)" do
      assert Registry.lookup(:no_such_client) == nil
    end

    test ":http is not a registered client type (removed non-functional placeholder)" do
      assert Registry.lookup(:http) == nil
    end
  end

  describe "get_adapter!/1" do
    test "returns adapter module when registered" do
      Registry.register(:test_client, TestAdapter)

      assert TestAdapter = Registry.get_adapter!(:test_client)
    end

    test "raises error when adapter not registered" do
      assert_raise Error, fn ->
        Registry.get_adapter!(:unknown_client)
      end
    end

    test "raised error includes helpful message" do
      error =
        assert_raise Error, fn ->
          Registry.get_adapter!(:unknown_client)
        end

      assert error.message =~ "unknown_client"
    end
  end

  describe "list_adapters/0" do
    test "returns empty list when no adapters registered" do
      assert [] = Registry.list_adapters()
    end

    test "returns all registered adapters" do
      Registry.register(:test_client, TestAdapter)
      Registry.register(:another_client, AnotherTestAdapter)

      adapters = Registry.list_adapters()

      assert length(adapters) == 2
      assert {:test_client, TestAdapter} in adapters
      assert {:another_client, AnotherTestAdapter} in adapters
    end
  end

  describe "registered?/1" do
    test "returns true when adapter is registered" do
      Registry.register(:test_client, TestAdapter)

      assert Registry.registered?(:test_client)
    end

    test "returns false when adapter is not registered" do
      refute Registry.registered?(:unknown_client)
    end
  end

  describe "unregister/1" do
    test "removes registered adapter" do
      Registry.register(:test_client, TestAdapter)
      assert Registry.registered?(:test_client)

      Registry.unregister(:test_client)

      refute Registry.registered?(:test_client)
    end

    test "does nothing when adapter not registered" do
      assert :ok = Registry.unregister(:unknown_client)
    end
  end

  describe "clear/0" do
    test "removes all registered adapters" do
      Registry.register(:test_client, TestAdapter)
      Registry.register(:another_client, AnotherTestAdapter)

      assert length(Registry.list_adapters()) == 2

      Registry.clear()

      assert [] = Registry.list_adapters()
    end
  end

  describe "integration with real adapters" do
    test "can dynamically select and use adapters" do
      Registry.register(:test_client, TestAdapter)
      Registry.register(:another_client, AnotherTestAdapter)

      config1 = %{type: :test_client, host: "localhost", port: 8080}
      config2 = %{type: :another_client, host: "localhost", port: 9091}

      {:ok, adapter1} = Registry.get_adapter(config1.type)
      {:ok, adapter2} = Registry.get_adapter(config2.type)

      assert {:ok, "test-id"} = adapter1.add_torrent(config1, {:magnet, "magnet:?"}, [])
      assert {:ok, "another-id"} = adapter2.add_torrent(config2, {:magnet, "magnet:?"}, [])
    end
  end
end
