defmodule Mydia.Downloads.Client.DebridTest do
  @moduledoc """
  Dispatch tests for the public Debrid adapter. Uses the hand-rolled
  `StubProvider` in `test/support/` since the repo does NOT use Mox.
  """
  use Mydia.DataCase, async: false

  alias Mydia.Downloads.Client.{Debrid, Registry}
  alias Mydia.Downloads.Client.Debrid.{Fetcher, ProviderJob, StubProvider}
  alias Mydia.Downloads.Client.Error
  alias Mydia.Downloads.Download
  alias Mydia.Downloads.Structs.ClientInfo
  alias Mydia.Downloads.Structs.DownloadStatus

  setup do
    Registry.register(:debrid, Debrid)
    StubProvider.ensure_started!()
    StubProvider.reset()
    on_exit(fn -> StubProvider.reset() end)

    ensure_started!(
      {Registry, [keys: :unique, name: Mydia.Downloads.Client.Debrid.FetcherRegistry]}
    )

    ensure_started!(
      {DynamicSupervisor,
       [name: Mydia.Downloads.Client.Debrid.FetcherSupervisor, strategy: :one_for_one]}
    )

    ensure_started!(Mydia.Downloads.Client.Debrid.RateLimiter)

    prior = Application.get_env(:mydia, :debrid_relaxed_url_validation, false)
    Application.put_env(:mydia, :debrid_relaxed_url_validation, true)
    on_exit(fn -> Application.put_env(:mydia, :debrid_relaxed_url_validation, prior) end)

    # Stub the dispatch's provider resolution. Since Provider.module_for/1
    # returns the production modules by string, we substitute the
    # StubProvider via Application config.
    prior_overrides = Application.get_env(:mydia, :debrid_provider_overrides, %{})

    Application.put_env(:mydia, :debrid_provider_overrides, %{
      "real_debrid" => StubProvider,
      "all_debrid" => StubProvider,
      "premiumize" => StubProvider,
      "tor_box" => StubProvider
    })

    on_exit(fn -> Application.put_env(:mydia, :debrid_provider_overrides, prior_overrides) end)

    :ok
  end

  defp ensure_started!(child_spec) do
    case start_supervised(child_spec) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, :already_started} -> :ok
    end
  end

  defp config(opts \\ []) do
    Map.new(
      type: :debrid,
      api_key: "key-#{System.unique_integer([:positive])}",
      connection_settings: %{"provider" => "real_debrid"},
      download_directory: nil
    )
    |> Map.merge(Map.new(opts))
  end

  defp insert_download(client_id, extra \\ %{}) do
    attrs =
      Map.merge(
        %{
          title: "Some.Release.1080p",
          download_client: "my-debrid",
          download_client_id: client_id,
          metadata: %{}
        },
        extra
      )

    %Download{}
    |> Download.changeset(attrs)
    |> Repo.insert!()
  end

  defp provider_job(client_id, state, extras) do
    base = %{
      provider_id: client_id,
      state: state,
      progress: 0.0,
      name: "release",
      total_bytes: 1_000_000,
      files: [],
      hoster_links: []
    }

    ProviderJob.new(Map.merge(base, extras))
  end

  describe "registration" do
    test "the :debrid type resolves to Debrid" do
      assert {:ok, Debrid} = Registry.get_adapter(:debrid)
    end
  end

  describe "test_connection/1" do
    test "happy path returns a Debrid ClientInfo with provider label" do
      StubProvider.set(:validate_credentials, {:ok, %ClientInfo{version: "v1"}})

      assert {:ok, %ClientInfo{version: version}} = Debrid.test_connection(config())
      assert version =~ "Debrid"
      assert version =~ "Real-Debrid"
    end

    test "invalid provider in connection_settings returns :invalid_config" do
      cfg = config(connection_settings: %{"provider" => "bogus"})

      assert {:error, %Error{type: :invalid_config}} = Debrid.test_connection(cfg)
    end

    test "missing provider in connection_settings returns :invalid_config" do
      cfg = config(connection_settings: %{})
      assert {:error, %Error{type: :invalid_config}} = Debrid.test_connection(cfg)
    end

    test "sanitizes sensitive details from provider errors" do
      key = "operator-secret-token"

      StubProvider.set(
        :validate_credentials,
        {:error, Error.api_error("bad", %{"apikey" => key, "message" => "denied: #{key}"})}
      )

      cfg = config(api_key: key)
      assert {:error, %Error{details: details}} = Debrid.test_connection(cfg)
      refute Map.has_key?(details, "apikey")
      refute String.contains?(details["message"], key)
      assert String.contains?(details["message"], "[REDACTED]")
    end
  end

  describe "add_torrent/3" do
    test "magnet input submits and calls post_submission_setup" do
      StubProvider.set(:submit_torrent, {:ok, "job-1"})
      StubProvider.set(:post_submission_setup, :ok)

      assert {:ok, "job-1"} = Debrid.add_torrent(config(), {:magnet, "magnet:?xt=abc"})
    end

    test "file input rejects NZB content before any provider call" do
      nzb_bytes = ~s(<?xml version="1.0"?><nzb></nzb>)

      # Provider stub would crash if called; this proves we bailed early.
      StubProvider.set(:submit_torrent, {:error, Error.unknown("should not be called")})

      assert {:error, %Error{type: :invalid_torrent}} =
               Debrid.add_torrent(config(), {:file, nzb_bytes})
    end

    test "file input with .torrent magic bytes is submitted as :file" do
      torrent_bytes = "d8:announce" <> String.duplicate("x", 100)

      StubProvider.set(:submit_torrent, {:ok, "job-2"})
      StubProvider.set(:post_submission_setup, :ok)

      assert {:ok, "job-2"} = Debrid.add_torrent(config(), {:file, torrent_bytes})
    end
  end

  describe "list_torrents/2" do
    test "returns {:ok, []} when no downloads opt is passed" do
      assert {:ok, []} = Debrid.list_torrents(config(), [])
    end

    test "returns {:ok, []} when downloads opt is empty" do
      assert {:ok, []} = Debrid.list_torrents(config(), downloads: %{})
    end

    test "synthesizes a :downloading status from a non-ready job without starting a fetcher" do
      download = insert_download("client-1")
      downloads = %{"client-1" => download}

      StubProvider.set(
        :list_jobs,
        {:ok,
         %{
           "client-1" => provider_job("client-1", :downloading, %{progress: 25.0})
         }}
      )

      assert {:ok, [status]} = Debrid.list_torrents(config(), downloads: downloads)
      assert %DownloadStatus{id: "client-1", state: :downloading} = status

      assert :error = Fetcher.whereis(download.id)
    end

    test "on a :ready job, persists R8 URLs (RD/AD/PM shape) and claims a Fetcher" do
      download = insert_download("client-rd")
      downloads = %{"client-rd" => download}

      url = "https://example.com/file.bin"

      StubProvider.set(
        :list_jobs,
        {:ok, %{"client-rd" => provider_job("client-rd", :ready, %{progress: 100.0})}}
      )

      StubProvider.set(:get_download_urls, {:ok, [url]})

      assert {:ok, [_status]} = Debrid.list_torrents(config(), downloads: downloads)

      # Wait briefly for the metadata write to complete (the dispatch
      # persists synchronously in the calling process before claiming the
      # Fetcher, so this should be visible immediately).
      reloaded = Repo.get!(Download, download.id)
      assert is_list(reloaded.metadata["debrid_urls"])
      assert [%{"url" => ^url, "resolved_at" => _}] = reloaded.metadata["debrid_urls"]

      # Fetcher was claimed. Terminate it so it doesn't try to actually
      # fetch from example.com.
      Fetcher.terminate(download.id)
    end

    test "TorBox-shaped descriptor persists without leaking a token=value" do
      download = insert_download("client-tb")
      downloads = %{"client-tb" => download}

      descriptor = %{"provider" => "torbox", "torrent_id" => 1, "file_id" => 5}

      StubProvider.set(
        :list_jobs,
        {:ok, %{"client-tb" => provider_job("client-tb", :ready, %{progress: 100.0})}}
      )

      StubProvider.set(:get_download_urls, {:ok, [descriptor]})

      cfg = config(connection_settings: %{"provider" => "tor_box"})

      {:ok, _} = Debrid.list_torrents(cfg, downloads: downloads)

      reloaded = Repo.get!(Download, download.id)
      [persisted] = reloaded.metadata["debrid_urls"]

      assert persisted == descriptor
      refute Enum.any?(Map.values(persisted), fn v -> is_binary(v) and v =~ "token=" end)

      # Terminate the claimed Fetcher; it would otherwise try to
      # materialize the descriptor via a non-existent stub callback.
      Fetcher.terminate(download.id)
    end

    test "does not re-claim a Fetcher that's already running" do
      download = insert_download("client-once")
      downloads = %{"client-once" => download}

      url = "https://example.com/once.bin"

      StubProvider.set(
        :list_jobs,
        {:ok, %{"client-once" => provider_job("client-once", :ready, %{progress: 100.0})}}
      )

      StubProvider.set(:get_download_urls, {:ok, [url]})

      {:ok, _} = Debrid.list_torrents(config(), downloads: downloads)

      # Track url-resolution call count via the stub by counting on a
      # different op. Easier: snapshot metadata after the first tick.
      reloaded_first = Repo.get!(Download, download.id)
      first_urls = reloaded_first.metadata["debrid_urls"]
      assert is_list(first_urls)

      # Second tick: Fetcher is still registered (it's processing). The
      # dispatch must skip the get_download_urls call and not re-persist.
      {:ok, _} = Debrid.list_torrents(config(), downloads: downloads)

      reloaded_second = Repo.get!(Download, download.id)
      assert reloaded_second.metadata["debrid_urls"] == first_urls

      Fetcher.terminate(download.id)
    end

    test "synthesizes :completed when the download has a save_path and no fetcher running" do
      staging = "/tmp/fake-#{System.unique_integer([:positive])}"

      download =
        insert_download("client-done", %{
          metadata: %{"save_path" => staging}
        })

      downloads = %{"client-done" => download}

      StubProvider.set(
        :list_jobs,
        {:ok, %{"client-done" => provider_job("client-done", :ready, %{progress: 100.0})}}
      )

      assert {:ok, [status]} = Debrid.list_torrents(config(), downloads: downloads)
      assert %DownloadStatus{state: :completed, save_path: ^staging} = status
    end
  end

  describe "get_status/2 (synchronous)" do
    test "returns a synthesized status without persisting R8 or starting a fetcher" do
      download = insert_download("client-sync")

      StubProvider.set(
        :get_job,
        {:ok, provider_job("client-sync", :downloading, %{progress: 33.3})}
      )

      assert {:ok, status} = Debrid.get_status(config(), "client-sync")
      assert %DownloadStatus{state: :downloading} = status

      # No R8 write happened.
      reloaded = Repo.get!(Download, download.id)
      refute Map.has_key?(reloaded.metadata, "debrid_urls")

      # No fetcher claimed.
      assert :error = Fetcher.whereis(download.id)
    end
  end

  describe "rate-limit errors" do
    test "rate limiter denial bubbles up as :api_error with :rate_limited" do
      Mydia.Downloads.Client.Debrid.RateLimiter.clear(:real_debrid, "rl-key")
      # Saturate RD's 250/60s budget.
      for _ <- 1..250 do
        Mydia.Downloads.Client.Debrid.RateLimiter.acquire(:real_debrid, "rl-key", {250, 60})
      end

      cfg = config(api_key: "rl-key")

      assert {:error, %Error{type: :api_error, details: %{reason: :rate_limited}}} =
               Debrid.test_connection(cfg)

      Mydia.Downloads.Client.Debrid.RateLimiter.clear(:real_debrid, "rl-key")
    end
  end

  describe "pause/resume no-ops" do
    test "pause_torrent/2 returns :ok regardless of provider" do
      assert :ok = Debrid.pause_torrent(config(), "any-id")
    end

    test "resume_torrent/2 returns :ok regardless of provider" do
      assert :ok = Debrid.resume_torrent(config(), "any-id")
    end
  end
end
