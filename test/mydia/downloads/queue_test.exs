defmodule Mydia.Downloads.QueueTest do
  @moduledoc """
  Unit tests for `Mydia.Downloads.Queue`'s per-content-type category routing
  and 5-tier priority pass-through. The end-to-end `initiate_download/2`
  pipeline is covered by integration tests elsewhere; this module focuses on
  the two helpers (`resolve_content_type/1` + `resolve_category/3`) because
  they are the unit-of-change for U3 (#124 + #129).
  """
  use Mydia.DataCase, async: false

  alias Mydia.Downloads.Queue
  alias Mydia.Settings.DownloadClientConfig

  import Mydia.MediaFixtures

  describe "resolve_content_type/1" do
    test "episode_id present -> tv" do
      assert Queue.resolve_content_type(episode_id: "any-uuid") == "tv"
    end

    test "episode_id wins over media_item_id (TV show with explicit episode)" do
      movie = media_item_fixture(%{type: "movie"})
      assert Queue.resolve_content_type(episode_id: "ep-id", media_item_id: movie.id) == "tv"
    end

    test "media_item_id pointing at a movie -> movie" do
      movie = media_item_fixture(%{type: "movie"})
      assert Queue.resolve_content_type(media_item_id: movie.id) == "movie"
    end

    test "media_item_id pointing at a tv_show -> tv" do
      tv = media_item_fixture(%{type: "tv_show"})
      assert Queue.resolve_content_type(media_item_id: tv.id) == "tv"
    end

    test "no episode_id and no media_item_id -> nil" do
      assert Queue.resolve_content_type([]) == nil
      assert Queue.resolve_content_type(download_type: :torrent) == nil
    end

    test "media_item_id pointing at a deleted/unknown record falls back to nil" do
      # Provide a UUID that doesn't exist in the DB
      assert Queue.resolve_content_type(media_item_id: Ecto.UUID.generate()) == nil
    end
  end

  describe "resolve_category/3 — happy path (categories map populated)" do
    test "movie content type picks up the per-type category" do
      client =
        %DownloadClientConfig{
          categories: %{"movie" => "movies", "tv" => "shows"},
          category: nil
        }

      assert Queue.resolve_category(client, "movie", []) == "movies"
    end

    test "tv content type picks up the per-type category" do
      client =
        %DownloadClientConfig{
          categories: %{"movie" => "movies", "tv" => "shows"},
          category: nil
        }

      assert Queue.resolve_category(client, "tv", []) == "shows"
    end
  end

  describe "resolve_category/3 — backwards compatibility (legacy field)" do
    test "empty categories map falls back to the legacy :category field for movies" do
      client = %DownloadClientConfig{categories: %{}, category: "all"}
      assert Queue.resolve_category(client, "movie", []) == "all"
    end

    test "empty categories map falls back to the legacy :category field for tv" do
      client = %DownloadClientConfig{categories: %{}, category: "all"}
      assert Queue.resolve_category(client, "tv", []) == "all"
    end

    test "nil categories map falls back to the legacy :category field" do
      client = %DownloadClientConfig{categories: nil, category: "all"}
      assert Queue.resolve_category(client, "movie", []) == "all"
    end

    test "missing key for the requested content type falls back to the legacy field" do
      client =
        %DownloadClientConfig{
          categories: %{"movie" => "movies"},
          category: "legacy"
        }

      # No "tv" key — fall through to legacy
      assert Queue.resolve_category(client, "tv", []) == "legacy"
    end

    test "empty string value for the requested content type falls back to the legacy field" do
      client =
        %DownloadClientConfig{
          categories: %{"movie" => ""},
          category: "legacy"
        }

      assert Queue.resolve_category(client, "movie", []) == "legacy"
    end

    test "content_type is nil -> use legacy :category field" do
      client = %DownloadClientConfig{categories: %{"movie" => "movies"}, category: "legacy"}
      assert Queue.resolve_category(client, nil, []) == "legacy"
    end

    test "no content_type, no categories, no legacy field -> nil" do
      client = %DownloadClientConfig{categories: %{}, category: nil}
      assert Queue.resolve_category(client, nil, []) == nil
    end
  end

  describe "resolve_category/3 — explicit override" do
    test "opts[:category] takes precedence over categories map" do
      client =
        %DownloadClientConfig{
          categories: %{"movie" => "movies"},
          category: "legacy"
        }

      assert Queue.resolve_category(client, "movie", category: "manual-override") ==
               "manual-override"
    end

    test "opts[:category] nil is still considered an explicit override" do
      # The current contract is that *any* presence of :category in opts wins,
      # even nil. This matches Keyword.has_key? semantics. Documented here so
      # future refactors don't break it accidentally.
      client = %DownloadClientConfig{categories: %{"movie" => "movies"}, category: "legacy"}
      assert Queue.resolve_category(client, "movie", category: nil) == nil
    end
  end

  describe "supports_download_type?/2" do
    # Regression: dispatch used to hardcode the torrent_clients list and
    # left :debrid out, so a debrid-only setup logged
    # "No download clients configured" for every torrent search result.
    # See queue.ex supports_download_type?/2.

    setup do
      # Registry.clear/0 is called by registry_test.exs's setup. When that
      # file runs before this one (test order isn't deterministic across
      # processes), the Registry is empty and Queue.supports_download_type?
      # falls through to `{:error, _} -> false`. Re-register the adapters
      # this describe block exercises so the tests are insulated.
      alias Mydia.Downloads.Client.Registry
      Registry.register(:qbittorrent, Mydia.Downloads.Client.QBittorrent)
      Registry.register(:sabnzbd, Mydia.Downloads.Client.Sabnzbd)
      Registry.register(:debrid, Mydia.Downloads.Client.Debrid)
      :ok
    end

    test "debrid client is eligible for :torrent" do
      client = %DownloadClientConfig{type: :debrid, enabled: true}
      assert Queue.supports_download_type?(client, :torrent)
    end

    test "qbittorrent is eligible for :torrent but not :nzb" do
      client = %DownloadClientConfig{type: :qbittorrent, enabled: true}
      assert Queue.supports_download_type?(client, :torrent)
      refute Queue.supports_download_type?(client, :nzb)
    end

    test "sabnzbd is eligible for :nzb but not :torrent" do
      client = %DownloadClientConfig{type: :sabnzbd, enabled: true}
      assert Queue.supports_download_type?(client, :nzb)
      refute Queue.supports_download_type?(client, :torrent)
    end

    test "unknown download_type lets every adapter through (sniff failed)" do
      client = %DownloadClientConfig{type: :qbittorrent, enabled: true}
      assert Queue.supports_download_type?(client, nil)
    end

    test "every Client-behaviour adapter declares supported_protocols/0" do
      # Guards against the original bug class: if someone adds a new adapter
      # but forgets to declare protocols, the queue would never select it
      # for any priority-based dispatch.
      #
      # We only enforce the contract on modules that implement the
      # Mydia.Downloads.Client behaviour (the registry also holds a
      # non-adapter `:http` placeholder).
      for {type, adapter} <- Mydia.Downloads.Client.Registry.list_adapters(),
          implements_client_behaviour?(adapter) do
        assert function_exported?(adapter, :supported_protocols, 0),
               "#{inspect(adapter)} (registered as #{inspect(type)}) must implement supported_protocols/0"

        protocols = adapter.supported_protocols()

        assert is_list(protocols) and protocols != [],
               "#{inspect(adapter)}.supported_protocols/0 must return a non-empty list"

        assert Enum.all?(protocols, &(&1 in [:torrent, :nzb])),
               "#{inspect(adapter)}.supported_protocols/0 returned #{inspect(protocols)} — only :torrent and :nzb are valid"
      end
    end

    defp implements_client_behaviour?(module) do
      behaviours =
        :attributes
        |> module.module_info()
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      Mydia.Downloads.Client in behaviours
    rescue
      _ -> false
    end
  end
end
