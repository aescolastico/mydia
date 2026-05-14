defmodule Mydia.Downloads.DownloadTest do
  use Mydia.DataCase, async: true

  alias Mydia.Downloads.Download

  @valid_attrs %{
    title: "Some.Release.1080p-Group",
    download_url: "https://example.com/release.torrent",
    indexer: "test-indexer",
    download_client: "test-client",
    download_client_id: "abc123"
  }

  describe "wave-2 progress tracking fields" do
    test "last_progress_at defaults to nil and last_known_bytes defaults to 0" do
      {:ok, download} =
        %Download{}
        |> Download.changeset(@valid_attrs)
        |> Repo.insert()

      assert download.last_progress_at == nil
      assert download.last_known_bytes == 0
    end

    test "last_progress_at and last_known_bytes are cast through the changeset" do
      now = DateTime.utc_now()

      attrs =
        @valid_attrs
        |> Map.put(:last_progress_at, now)
        |> Map.put(:last_known_bytes, 123_456_789)

      {:ok, download} =
        %Download{}
        |> Download.changeset(attrs)
        |> Repo.insert()

      assert DateTime.compare(download.last_progress_at, now) == :eq
      assert download.last_known_bytes == 123_456_789
    end

    test "a pre-existing-style download row (no progress tracking values) is queryable" do
      {:ok, inserted} =
        %Download{}
        |> Download.changeset(@valid_attrs)
        |> Repo.insert()

      reloaded = Repo.get!(Download, inserted.id)

      assert reloaded.last_progress_at == nil
      assert reloaded.last_known_bytes == 0
    end

    test "updates to last_progress_at and last_known_bytes persist" do
      {:ok, download} =
        %Download{}
        |> Download.changeset(@valid_attrs)
        |> Repo.insert()

      now = DateTime.utc_now()

      {:ok, updated} =
        download
        |> Download.changeset(%{last_progress_at: now, last_known_bytes: 42})
        |> Repo.update()

      reloaded = Repo.get!(Download, updated.id)
      assert DateTime.compare(reloaded.last_progress_at, now) == :eq
      assert reloaded.last_known_bytes == 42
    end
  end
end
