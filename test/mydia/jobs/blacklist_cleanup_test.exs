defmodule Mydia.Jobs.BlacklistCleanupTest do
  use Mydia.DataCase, async: true
  use Oban.Testing, repo: Mydia.Repo

  alias Mydia.Downloads.Blacklists
  alias Mydia.Downloads.ReleaseBlacklist
  alias Mydia.Jobs.BlacklistCleanup
  alias Mydia.Repo

  describe "perform/1" do
    test "deletes expired rows and preserves active/forever rows" do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, _expired} =
        Blacklists.add("nzbhydra2", "expired-1", "T", "x", expires_at: past)

      {:ok, _active} =
        Blacklists.add("nzbhydra2", "active-1", "T", "x", expires_at: future)

      {:ok, _forever} =
        Blacklists.add("nzbhydra2", "forever-1", "T", "x", expires_at: nil)

      assert :ok = perform_job(BlacklistCleanup, %{})

      remaining = Repo.all(ReleaseBlacklist) |> Enum.map(& &1.guid) |> Enum.sort()
      assert remaining == ["active-1", "forever-1"]
    end

    test "is a no-op when there are no expired rows" do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, _} =
        Blacklists.add("nzbhydra2", "active-only", "T", "x", expires_at: future)

      assert :ok = perform_job(BlacklistCleanup, %{})
      assert Repo.aggregate(ReleaseBlacklist, :count) == 1
    end
  end
end
