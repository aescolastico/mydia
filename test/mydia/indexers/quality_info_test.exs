defmodule Mydia.Indexers.Structs.QualityInfoTest do
  use ExUnit.Case, async: true

  alias Mydia.Indexers.Structs.QualityInfo

  describe "format/1" do
    test "formats full quality info" do
      qi = %QualityInfo{
        resolution: "1080p",
        source: "BluRay",
        codec: "x264",
        audio: "DTS-HD MA",
        hdr: false,
        hdr_format: nil,
        proper: false,
        repack: false
      }

      assert QualityInfo.format(qi) == "1080p BluRay x264 DTS-HD MA"
    end

    test "formats resolution and source only" do
      qi = %QualityInfo{
        resolution: "1080p",
        source: "Telesync",
        codec: nil,
        audio: nil,
        hdr: false,
        hdr_format: nil,
        proper: false,
        repack: false
      }

      assert QualityInfo.format(qi) == "1080p Telesync"
    end

    test "includes HDR format when hdr is true" do
      qi = %QualityInfo{
        resolution: "2160p",
        source: "WEB-DL",
        codec: nil,
        audio: nil,
        hdr: true,
        hdr_format: "DV",
        proper: false,
        repack: false
      }

      assert QualityInfo.format(qi) == "2160p WEB-DL DV"
    end

    test "includes generic HDR label when hdr is true without format" do
      qi = %QualityInfo{
        resolution: "2160p",
        source: "BluRay",
        codec: nil,
        audio: nil,
        hdr: true,
        hdr_format: nil,
        proper: false,
        repack: false
      }

      assert QualityInfo.format(qi) == "2160p BluRay HDR"
    end

    test "includes PROPER flag" do
      qi = %QualityInfo{
        resolution: "1080p",
        source: "BluRay",
        codec: nil,
        audio: nil,
        hdr: false,
        hdr_format: nil,
        proper: true,
        repack: false
      }

      assert QualityInfo.format(qi) == "1080p BluRay PROPER"
    end

    test "includes REPACK flag" do
      qi = %QualityInfo{
        resolution: "720p",
        source: "WEB-DL",
        codec: nil,
        audio: nil,
        hdr: false,
        hdr_format: nil,
        proper: false,
        repack: true
      }

      assert QualityInfo.format(qi) == "720p WEB-DL REPACK"
    end

    test "returns empty string for empty quality info" do
      qi = QualityInfo.empty()
      assert QualityInfo.format(qi) == ""
    end

    test "returns nil for nil input" do
      assert QualityInfo.format(nil) == nil
    end
  end

  describe "from_map/1" do
    test "reconstructs from string-keyed map (JSON deserialization)" do
      map = %{
        "resolution" => "1080p",
        "source" => "Telesync",
        "codec" => nil,
        "audio" => nil,
        "hdr" => false,
        "hdr_format" => nil,
        "proper" => false,
        "repack" => false
      }

      result = QualityInfo.from_map(map)

      assert %QualityInfo{} = result
      assert result.resolution == "1080p"
      assert result.source == "Telesync"
      assert result.codec == nil
      assert result.hdr == false
      assert result.proper == false
    end

    test "reconstructs from atom-keyed map" do
      map = %{
        resolution: "2160p",
        source: "BluRay",
        codec: "x265",
        audio: "TrueHD Atmos",
        hdr: true,
        hdr_format: "DV",
        proper: false,
        repack: false
      }

      result = QualityInfo.from_map(map)

      assert %QualityInfo{} = result
      assert result.resolution == "2160p"
      assert result.hdr == true
      assert result.hdr_format == "DV"
      assert result.audio == "TrueHD Atmos"
    end

    test "defaults boolean fields to false when missing" do
      map = %{"resolution" => "720p"}

      result = QualityInfo.from_map(map)

      assert result.hdr == false
      assert result.proper == false
      assert result.repack == false
    end

    test "returns nil for nil input" do
      assert QualityInfo.from_map(nil) == nil
    end
  end
end
