defmodule Mydia.Streaming.CodecStringTest do
  use ExUnit.Case, async: true

  alias Mydia.Streaming.CodecString
  alias Mydia.Library.Structs.FileMetadata

  describe "video_codec_string/2" do
    test "returns nil for nil input" do
      assert CodecString.video_codec_string(nil, %FileMetadata{}) == nil
    end

    test "generates H.264 codec strings from profile name" do
      # High profile (most common)
      result = CodecString.video_codec_string("H.264 (High)", %FileMetadata{})
      assert result =~ "avc1.64"

      # Main profile
      result = CodecString.video_codec_string("H.264 (Main)", %FileMetadata{})
      assert result =~ "avc1.4d"

      # Baseline profile
      result = CodecString.video_codec_string("H.264 (Baseline)", %FileMetadata{})
      assert result =~ "avc1.42"

      # Generic H.264 defaults to High
      result = CodecString.video_codec_string("H.264", %FileMetadata{})
      assert result =~ "avc1.64"
    end

    test "generates H.264 codec strings from raw FFprobe metadata" do
      # High profile Level 4.0
      metadata = %FileMetadata{
        video_profile_idc: 100,
        video_level_idc: 40,
        video_constraint_set: 0
      }

      result = CodecString.video_codec_string("H.264 (High)", metadata)
      assert result == "avc1.640028"

      # Main profile Level 3.1
      metadata = %FileMetadata{
        video_profile_idc: 77,
        video_level_idc: 31,
        video_constraint_set: 0
      }

      result = CodecString.video_codec_string("H.264 (Main)", metadata)
      assert result == "avc1.4d001f"
    end

    test "generates HEVC codec strings from profile name" do
      # Main profile
      result = CodecString.video_codec_string("HEVC (Main)", %FileMetadata{})
      assert result =~ "hvc1.1"

      # Main 10 profile (HDR content)
      result = CodecString.video_codec_string("HEVC (Main 10)", %FileMetadata{})
      assert result =~ "hvc1.2"

      # Generic HEVC defaults to Main
      result = CodecString.video_codec_string("HEVC", %FileMetadata{})
      assert result =~ "hvc1.1"
    end

    test "generates HEVC codec strings from raw FFprobe metadata" do
      # Main profile Level 4.0
      metadata = %FileMetadata{
        hevc_profile_idc: 1,
        hevc_level_idc: 120,
        hevc_tier_flag: 0
      }

      result = CodecString.video_codec_string("HEVC (Main)", metadata)
      assert result == "hvc1.1.4.L120.B0"

      # Main 10 profile, High tier
      metadata = %FileMetadata{
        hevc_profile_idc: 2,
        hevc_level_idc: 150,
        hevc_tier_flag: 1
      }

      result = CodecString.video_codec_string("HEVC (Main 10)", metadata)
      assert result == "hvc1.2.4.H150.B0"
    end

    test "generates VP9 codec strings" do
      result = CodecString.video_codec_string("VP9", %FileMetadata{})
      assert result =~ "vp09"

      # With specific profile and level
      metadata = %FileMetadata{
        vp9_profile: 2,
        vp9_level: 41,
        bit_depth: 10
      }

      result = CodecString.video_codec_string("VP9", metadata)
      assert result == "vp09.02.41.10"
    end

    test "generates VP8 codec string" do
      result = CodecString.video_codec_string("VP8", %FileMetadata{})
      assert result == "vp8"
    end

    test "generates AV1 codec strings" do
      result = CodecString.video_codec_string("AV1", %FileMetadata{})
      assert result =~ "av01"

      # With specific profile and level
      metadata = %FileMetadata{
        av1_profile: 0,
        av1_level: 9,
        av1_tier: 0,
        bit_depth: 10
      }

      result = CodecString.video_codec_string("AV1", metadata)
      assert result == "av01.0.09M.10"
    end

    test "returns nil for unknown codecs" do
      assert CodecString.video_codec_string("SomeUnknownCodec", %FileMetadata{}) == nil
    end
  end

  describe "audio_codec_string/2" do
    test "returns nil for nil input" do
      assert CodecString.audio_codec_string(nil, %FileMetadata{}) == nil
    end

    test "generates AAC codec strings" do
      # Standard AAC-LC
      assert CodecString.audio_codec_string("AAC Stereo", %FileMetadata{}) == "mp4a.40.2"
      assert CodecString.audio_codec_string("AAC 5.1", %FileMetadata{}) == "mp4a.40.2"

      # HE-AAC
      assert CodecString.audio_codec_string("HE-AAC", %FileMetadata{}) == "mp4a.40.5"
    end

    test "generates MP3 codec string" do
      assert CodecString.audio_codec_string("MP3", %FileMetadata{}) == "mp4a.40.34"
    end

    test "generates AC-3 codec string" do
      assert CodecString.audio_codec_string("AC3 5.1", %FileMetadata{}) == "ac-3"
    end

    test "generates E-AC-3 codec string" do
      assert CodecString.audio_codec_string("DD+ 7.1", %FileMetadata{}) == "ec-3"
      assert CodecString.audio_codec_string("EAC3", %FileMetadata{}) == "ec-3"
    end

    test "returns nil for DTS codecs (not web-compatible)" do
      assert CodecString.audio_codec_string("DTS 5.1", %FileMetadata{}) == nil
      assert CodecString.audio_codec_string("DTS-HD MA 7.1", %FileMetadata{}) == nil
    end

    test "returns nil for TrueHD codecs (not web-compatible)" do
      assert CodecString.audio_codec_string("TrueHD", %FileMetadata{}) == nil
      assert CodecString.audio_codec_string("TrueHD Atmos", %FileMetadata{}) == nil
    end

    test "generates Opus codec string" do
      assert CodecString.audio_codec_string("Opus", %FileMetadata{}) == "opus"
    end

    test "generates Vorbis codec string" do
      assert CodecString.audio_codec_string("Vorbis", %FileMetadata{}) == "vorbis"
    end

    test "generates FLAC codec string" do
      assert CodecString.audio_codec_string("FLAC", %FileMetadata{}) == "flac"
    end

    test "returns nil for unknown codecs" do
      assert CodecString.audio_codec_string("SomeUnknownCodec", %FileMetadata{}) == nil
    end
  end

  describe "build_mime_type/3" do
    test "builds MP4 MIME type with video and audio codecs" do
      result = CodecString.build_mime_type("mp4", "avc1.640028", "mp4a.40.2")
      assert result == ~s(video/mp4; codecs="avc1.640028, mp4a.40.2")
    end

    test "builds MP4 MIME type with video only" do
      result = CodecString.build_mime_type("mp4", "avc1.640028", nil)
      assert result == ~s(video/mp4; codecs="avc1.640028")
    end

    test "builds MP4 MIME type with audio only" do
      result = CodecString.build_mime_type("mp4", nil, "mp4a.40.2")
      assert result == ~s(video/mp4; codecs="mp4a.40.2")
    end

    test "builds MP4 MIME type without codecs when both are nil" do
      result = CodecString.build_mime_type("mp4", nil, nil)
      assert result == "video/mp4"
    end

    test "builds WebM MIME type" do
      result = CodecString.build_mime_type("webm", "vp9", "opus")
      assert result == ~s(video/webm; codecs="vp9, opus")
    end

    test "maps MKV to x-matroska" do
      result = CodecString.build_mime_type("mkv", "avc1.640028", nil)
      assert result =~ "video/x-matroska"
    end
  end

  describe "video_codec_variants/2" do
    test "returns empty list for nil input" do
      assert CodecString.video_codec_variants(nil, %FileMetadata{}) == []
    end

    test "returns multiple H.264 variants for compatibility testing" do
      variants = CodecString.video_codec_variants("H.264 (High)", %FileMetadata{})

      assert length(variants) > 1
      assert Enum.all?(variants, &String.starts_with?(&1, "avc1"))
      # Should include a generic fallback
      assert "avc1" in variants
    end

    test "returns multiple HEVC variants for compatibility testing" do
      variants = CodecString.video_codec_variants("HEVC (Main)", %FileMetadata{})

      assert length(variants) > 1
      # Should include both hvc1 and hev1 variants
      assert Enum.any?(variants, &String.starts_with?(&1, "hvc1"))
      assert Enum.any?(variants, &String.starts_with?(&1, "hev1"))
    end

    test "returns VP9 variants" do
      variants = CodecString.video_codec_variants("VP9", %FileMetadata{})

      assert length(variants) > 1
      assert Enum.any?(variants, &String.starts_with?(&1, "vp09"))
      assert "vp9" in variants
    end

    test "returns AV1 variants" do
      variants = CodecString.video_codec_variants("AV1", %FileMetadata{})

      assert length(variants) > 1
      assert Enum.any?(variants, &String.starts_with?(&1, "av01"))
      assert "av01" in variants
    end

    test "returns single variant for VP8" do
      variants = CodecString.video_codec_variants("VP8", %FileMetadata{})
      assert variants == ["vp8"]
    end

    test "returns empty list for unknown codecs" do
      assert CodecString.video_codec_variants("SomeUnknownCodec", %FileMetadata{}) == []
    end
  end

  describe "real-world codec examples" do
    test "typical 1080p BluRay rip (H.264 High + DTS)" do
      video = CodecString.video_codec_string("H.264 (High)", %FileMetadata{})
      audio = CodecString.audio_codec_string("DTS 5.1", %FileMetadata{})

      assert video =~ "avc1.64"
      # DTS is not web-compatible, returns nil
      assert audio == nil
    end

    test "4K HDR content (HEVC Main 10 + TrueHD)" do
      video = CodecString.video_codec_string("HEVC (Main 10)", %FileMetadata{})
      audio = CodecString.audio_codec_string("TrueHD Atmos", %FileMetadata{})

      assert video =~ "hvc1.2"
      # TrueHD is not web-compatible, returns nil
      assert audio == nil
    end

    test "typical web video (H.264 + AAC)" do
      video = CodecString.video_codec_string("H.264 (Main)", %FileMetadata{})
      audio = CodecString.audio_codec_string("AAC Stereo", %FileMetadata{})

      assert video =~ "avc1.4d"
      assert audio == "mp4a.40.2"

      # Can build full MIME type
      mime = CodecString.build_mime_type("mp4", video, audio)
      assert mime =~ ~s(video/mp4; codecs=")
      assert mime =~ "avc1"
      assert mime =~ "mp4a.40.2"
    end

    test "streaming service content (HEVC + E-AC-3)" do
      video = CodecString.video_codec_string("HEVC (Main)", %FileMetadata{})
      audio = CodecString.audio_codec_string("DD+ 5.1", %FileMetadata{})

      assert video =~ "hvc1.1"
      assert audio == "ec-3"
    end
  end
end
