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

  describe "bytes_pulled field" do
    test "defaults to nil when not provided" do
      {:ok, download} =
        %Download{}
        |> Download.changeset(@valid_attrs)
        |> Repo.insert()

      assert download.bytes_pulled == nil
    end

    test "casts an integer value cleanly and round-trips through the database" do
      attrs = Map.put(@valid_attrs, :bytes_pulled, 8_388_608)

      {:ok, inserted} =
        %Download{}
        |> Download.changeset(attrs)
        |> Repo.insert()

      assert inserted.bytes_pulled == 8_388_608

      reloaded = Repo.get!(Download, inserted.id)
      assert reloaded.bytes_pulled == 8_388_608
    end

    test "updates to bytes_pulled persist" do
      {:ok, download} =
        %Download{}
        |> Download.changeset(@valid_attrs)
        |> Repo.insert()

      {:ok, updated} =
        download
        |> Download.changeset(%{bytes_pulled: 1024})
        |> Repo.update()

      reloaded = Repo.get!(Download, updated.id)
      assert reloaded.bytes_pulled == 1024
    end
  end

  describe "stall observation fields (last_observed_at / stalled_since)" do
    test "both default to nil when not provided" do
      {:ok, download} =
        %Download{}
        |> Download.changeset(@valid_attrs)
        |> Repo.insert()

      assert download.last_observed_at == nil
      assert download.stalled_since == nil
    end

    test "last_observed_at and stalled_since round-trip through the changeset" do
      now = DateTime.utc_now()

      attrs =
        @valid_attrs
        |> Map.put(:last_observed_at, now)
        |> Map.put(:stalled_since, now)

      download =
        %Download{}
        |> Download.changeset(attrs)
        |> Ecto.Changeset.apply_changes()

      assert DateTime.compare(download.last_observed_at, now) == :eq
      assert DateTime.compare(download.stalled_since, now) == :eq
    end

    test "accepts nil for both (existing-row compatibility)" do
      now = DateTime.utc_now()

      {:ok, download} =
        %Download{}
        |> Download.changeset(Map.put(@valid_attrs, :stalled_since, now))
        |> Repo.insert()

      {:ok, cleared} =
        download
        |> Download.changeset(%{last_observed_at: nil, stalled_since: nil})
        |> Repo.update()

      reloaded = Repo.get!(Download, cleared.id)
      assert reloaded.last_observed_at == nil
      assert reloaded.stalled_since == nil
    end

    test "a soft-stalled row (stalled_since set, import_failed_at nil) is still occupying" do
      now = DateTime.utc_now()

      {:ok, download} =
        %Download{}
        |> Download.changeset(Map.put(@valid_attrs, :stalled_since, now))
        |> Repo.insert()

      occupying_ids = Download.occupying() |> Repo.all() |> Enum.map(& &1.id)
      assert download.id in occupying_ids
    end
  end
end
