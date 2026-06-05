defmodule Mydia.Repo.Migrations.AddMetadataSourceToMediaItemsTest do
  use ExUnit.Case, async: true

  # Migration modules are not compiled into the app, so load the file explicitly.
  Code.require_file("priv/repo/migrations/20260604120100_add_metadata_source_to_media_items.exs")

  alias Mydia.Repo.Migrations.AddMetadataSourceToMediaItems, as: Migration

  # Helpers for building the metadata JSON string as stored at rest.
  defp meta(attrs), do: Jason.encode!(attrs)

  describe "provider_id_from_metadata/1" do
    test "returns provider_id string when present in JSON" do
      assert Migration.provider_id_from_metadata(meta(%{"provider_id" => "123"})) == "123"
    end

    test "coerces integer provider_id to string" do
      assert Migration.provider_id_from_metadata(meta(%{"provider_id" => 456})) == "456"
    end

    test "returns nil when provider_id key is missing" do
      assert Migration.provider_id_from_metadata(meta(%{"other" => "val"})) == nil
    end

    test "returns nil when provider_id is nil in JSON" do
      assert Migration.provider_id_from_metadata(meta(%{"provider_id" => nil})) == nil
    end

    test "returns nil for empty binary" do
      assert Migration.provider_id_from_metadata("") == nil
    end

    test "returns nil for nil" do
      assert Migration.provider_id_from_metadata(nil) == nil
    end

    test "returns nil for non-JSON binary (malformed)" do
      assert Migration.provider_id_from_metadata("not-json{{") == nil
    end

    test "returns nil for non-binary input" do
      assert Migration.provider_id_from_metadata(42) == nil
    end
  end

  describe "derive_source/1" do
    test "provider_id matches tvdb_id -> tvdb (even when tmdb_id is also present)" do
      row = %{
        tvdb_id: 111,
        tmdb_id: 999,
        metadata: meta(%{"provider_id" => "111"})
      }

      assert Migration.derive_source(row) == "tvdb"
    end

    test "provider_id matches tmdb_id -> tmdb (even when tvdb_id is also present)" do
      row = %{
        tvdb_id: 111,
        tmdb_id: 999,
        metadata: meta(%{"provider_id" => "999"})
      }

      assert Migration.derive_source(row) == "tmdb"
    end

    test "metadata absent, only tvdb_id present -> tvdb (id-presence fallback)" do
      row = %{tvdb_id: 111, tmdb_id: nil, metadata: nil}
      assert Migration.derive_source(row) == "tvdb"
    end

    test "metadata empty string, only tvdb_id present -> tvdb (id-presence fallback)" do
      row = %{tvdb_id: 111, tmdb_id: nil, metadata: ""}
      assert Migration.derive_source(row) == "tvdb"
    end

    test "only tmdb_id present, no metadata -> tmdb (id-presence fallback)" do
      row = %{tvdb_id: nil, tmdb_id: 999, metadata: nil}
      assert Migration.derive_source(row) == "tmdb"
    end

    test "neither id nor metadata -> nil" do
      row = %{tvdb_id: nil, tmdb_id: nil, metadata: nil}
      assert Migration.derive_source(row) == nil
    end

    test "metadata is non-empty binary that fails JSON decode -> falls through to id-presence" do
      row = %{tvdb_id: 111, tmdb_id: 999, metadata: "not valid json {{"}
      # provider_id_from_metadata returns nil; tvdb_id is present, so fallback picks tvdb
      assert Migration.derive_source(row) == "tvdb"
    end

    test "metadata is non-empty binary that fails JSON decode, only tmdb_id -> tmdb" do
      row = %{tvdb_id: nil, tmdb_id: 999, metadata: "not valid json {{"}
      assert Migration.derive_source(row) == "tmdb"
    end

    test "metadata is non-empty binary that fails JSON decode, no ids -> nil" do
      row = %{tvdb_id: nil, tmdb_id: nil, metadata: "not valid json {{"}
      assert Migration.derive_source(row) == nil
    end

    test "both ids present, provider_id does not match either -> tvdb wins id-presence" do
      row = %{
        tvdb_id: 111,
        tmdb_id: 999,
        metadata: meta(%{"provider_id" => "000"})
      }

      # provider_id doesn't match either id; tvdb_id is non-nil so fallback is tvdb
      assert Migration.derive_source(row) == "tvdb"
    end
  end
end
