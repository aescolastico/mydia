defmodule Mydia.Downloads.Structs.DownloadMetadataTest do
  use ExUnit.Case, async: true

  alias Mydia.Downloads.Structs.DownloadMetadata
  alias Mydia.Indexers.Structs.QualityInfo

  describe "to_map/1 and from_map/1 round-trip" do
    test "round-trips quality info through map serialization" do
      quality = QualityInfo.new(resolution: "1080p", source: "BluRay", codec: "x264")

      metadata = DownloadMetadata.new(%{size: 1024, quality: quality})
      serialized = DownloadMetadata.to_map(metadata)

      # Simulate JSON round-trip (atom keys -> string keys)
      json_map =
        serialized
        |> Jason.encode!()
        |> Jason.decode!()

      restored = DownloadMetadata.from_map(json_map)

      assert %QualityInfo{} = restored.quality
      assert restored.quality.resolution == "1080p"
      assert restored.quality.source == "BluRay"
      assert restored.quality.codec == "x264"
    end

    test "round-trips metadata without quality" do
      metadata = DownloadMetadata.new(%{size: 2048, seeders: 10, leechers: 2})
      serialized = DownloadMetadata.to_map(metadata)

      json_map =
        serialized
        |> Jason.encode!()
        |> Jason.decode!()

      restored = DownloadMetadata.from_map(json_map)

      assert restored.size == 2048
      assert restored.seeders == 10
      assert restored.leechers == 2
      assert restored.quality == nil
    end
  end

  describe "from_map/1" do
    test "reconstructs QualityInfo from string-keyed quality map" do
      map = %{
        "size" => 1500,
        "seeders" => 5,
        "quality" => %{
          "resolution" => "1080p",
          "source" => "Telesync",
          "codec" => nil,
          "audio" => nil,
          "hdr" => false,
          "hdr_format" => nil,
          "proper" => false,
          "repack" => false
        }
      }

      result = DownloadMetadata.from_map(map)

      assert %QualityInfo{} = result.quality
      assert result.quality.resolution == "1080p"
      assert result.quality.source == "Telesync"
    end

    test "handles nil quality" do
      map = %{"size" => 1024, "quality" => nil}
      result = DownloadMetadata.from_map(map)
      assert result.quality == nil
    end

    test "returns nil for nil input" do
      assert DownloadMetadata.from_map(nil) == nil
    end

    test "returns nil for empty map" do
      assert DownloadMetadata.from_map(%{}) == nil
    end

    test "defaults size to 0 when missing" do
      result = DownloadMetadata.from_map(%{"seeders" => 10})
      assert result.size == 0
    end
  end

  describe "to_map/1" do
    test "converts QualityInfo struct to plain map" do
      quality = QualityInfo.new(resolution: "1080p", source: "BluRay")
      metadata = DownloadMetadata.new(%{size: 1024, quality: quality})

      result = DownloadMetadata.to_map(metadata)

      assert is_map(result.quality)
      refute Map.has_key?(result.quality, :__struct__)
      assert result.quality.resolution == "1080p"
    end

    test "passes nil quality through" do
      metadata = DownloadMetadata.new(%{size: 1024})
      result = DownloadMetadata.to_map(metadata)
      assert result.quality == nil
    end
  end
end
