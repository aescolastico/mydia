defmodule Mydia.Library.FileRenamerTest do
  use ExUnit.Case, async: true

  alias Mydia.Indexers.Structs.QualityInfo
  alias Mydia.Library.FileRenamer

  describe "build_quality_info/1" do
    test "builds QualityInfo from MediaFile with full metadata" do
      file = %Mydia.Library.MediaFile{
        resolution: "1080p",
        codec: "x264",
        audio_codec: "DTS",
        hdr_format: nil,
        metadata: %Mydia.Library.Structs.FileMetadata{source: "BluRay"}
      }

      result = FileRenamer.build_quality_info(file)

      assert %QualityInfo{} = result
      assert result.resolution == "1080p"
      assert result.source == "BluRay"
      assert result.codec == "x264"
      assert result.audio == "DTS"
      assert result.hdr == false
      assert result.hdr_format == nil
      assert result.proper == false
      assert result.repack == false
    end

    test "builds QualityInfo with HDR format" do
      file = %Mydia.Library.MediaFile{
        resolution: "2160p",
        codec: "x265",
        audio_codec: "TrueHD Atmos",
        hdr_format: "DV",
        metadata: %Mydia.Library.Structs.FileMetadata{source: "BluRay"}
      }

      result = FileRenamer.build_quality_info(file)

      assert result.resolution == "2160p"
      assert result.hdr == true
      assert result.hdr_format == "DV"
      assert result.audio == "TrueHD Atmos"
    end

    test "handles nil metadata gracefully" do
      file = %Mydia.Library.MediaFile{
        resolution: "720p",
        codec: "x264",
        audio_codec: nil,
        hdr_format: nil,
        metadata: nil
      }

      result = FileRenamer.build_quality_info(file)

      assert result.resolution == "720p"
      assert result.source == nil
      assert result.codec == "x264"
      assert result.audio == nil
    end

    test "handles empty FileMetadata struct" do
      file = %Mydia.Library.MediaFile{
        resolution: "1080p",
        codec: "x265",
        audio_codec: "AAC",
        hdr_format: nil,
        metadata: %Mydia.Library.Structs.FileMetadata{}
      }

      result = FileRenamer.build_quality_info(file)

      assert result.source == nil
      assert result.codec == "x265"
      assert result.audio == "AAC"
    end

    test "handles all nil fields" do
      file = %Mydia.Library.MediaFile{
        resolution: nil,
        codec: nil,
        audio_codec: nil,
        hdr_format: nil,
        metadata: nil
      }

      result = FileRenamer.build_quality_info(file)

      assert %QualityInfo{} = result
      assert result.resolution == nil
      assert result.source == nil
      assert result.codec == nil
      assert result.audio == nil
      assert result.hdr == false
    end
  end
end
