defmodule Mydia.Downloads.Client.Debrid.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Mydia.Downloads.Client.Debrid.RateLimiter

  setup do
    # Ensure the RateLimiter ETS table exists. The supervisor starts it in
    # `Mydia.Application`, but in test contexts that don't load the full
    # supervision tree we may need to start it ourselves.
    case Process.whereis(RateLimiter) do
      nil ->
        start_supervised!(RateLimiter)

      _pid ->
        :ok
    end

    api_key = "tester-#{System.unique_integer([:positive])}"
    on_exit(fn -> RateLimiter.clear(:test_provider, api_key) end)
    {:ok, api_key: api_key}
  end

  describe "acquire/3" do
    test "permits requests while under budget", %{api_key: key} do
      assert :ok = RateLimiter.acquire(:test_provider, key, {3, 60})
      assert :ok = RateLimiter.acquire(:test_provider, key, {3, 60})
      assert :ok = RateLimiter.acquire(:test_provider, key, {3, 60})
    end

    test "refuses when budget is exhausted within the window", %{api_key: key} do
      Enum.each(1..3, fn _ -> assert :ok = RateLimiter.acquire(:test_provider, key, {3, 60}) end)
      assert {:error, :rate_limited} = RateLimiter.acquire(:test_provider, key, {3, 60})
    end

    test "different {provider, api_key} tuples are isolated", %{api_key: key} do
      # Different provider, same key.
      assert :ok = RateLimiter.acquire(:test_provider_a, key, {1, 60})
      assert :ok = RateLimiter.acquire(:test_provider_b, key, {1, 60})

      # Same provider, different key.
      other_key = "other-#{System.unique_integer([:positive])}"
      assert :ok = RateLimiter.acquire(:test_provider_a, other_key, {1, 60})
      assert {:error, :rate_limited} = RateLimiter.acquire(:test_provider_a, key, {1, 60})

      RateLimiter.clear(:test_provider_a, key)
      RateLimiter.clear(:test_provider_a, other_key)
      RateLimiter.clear(:test_provider_b, key)
    end

    test "usage/3 reports the count inside the window", %{api_key: key} do
      Enum.each(1..2, fn _ -> RateLimiter.acquire(:test_provider, key, {10, 60}) end)
      assert RateLimiter.usage(:test_provider, key, 60) == 2
    end

    test "clear/2 removes only the targeted bucket", %{api_key: key} do
      other = "other-#{System.unique_integer([:positive])}"

      RateLimiter.acquire(:test_provider, key, {10, 60})
      RateLimiter.acquire(:test_provider, other, {10, 60})

      RateLimiter.clear(:test_provider, key)

      assert RateLimiter.usage(:test_provider, key, 60) == 0
      assert RateLimiter.usage(:test_provider, other, 60) >= 1

      RateLimiter.clear(:test_provider, other)
    end
  end
end
