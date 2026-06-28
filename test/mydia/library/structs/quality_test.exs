defmodule Mydia.Library.Structs.QualityTest do
  use ExUnit.Case, async: true

  alias Mydia.Library.Structs.Quality

  describe "new/1" do
    test "defaults boolean flags to false and others to nil" do
      q = Quality.new(resolution: "1080p")
      assert q.resolution == "1080p"
      assert q.source == nil
      assert q.codec == nil
      assert q.audio == nil
      assert q.hdr == false
      assert q.hdr_format == nil
      assert q.proper == false
      assert q.repack == false
    end

    test "accepts a map" do
      q = Quality.new(%{resolution: "2160p", hdr: true, hdr_format: "DV", proper: true})
      assert q.resolution == "2160p"
      assert q.hdr == true
      assert q.hdr_format == "DV"
      assert q.proper == true
      assert q.repack == false
    end
  end

  describe "empty/0 and empty?/1" do
    test "empty/0 is empty?" do
      assert Quality.empty?(Quality.empty())
    end

    test "a struct with only flags set is still empty" do
      assert Quality.empty?(%Quality{hdr: false, proper: false, repack: false})
    end

    test "a struct with content is not empty" do
      refute Quality.empty?(%Quality{resolution: "1080p"})
      refute Quality.empty?(%Quality{hdr_format: "HDR10"})
    end
  end

  describe "format/1" do
    test "joins resolution, source, codec, audio" do
      q = %Quality{resolution: "1080p", source: "BluRay", codec: "x264", audio: "DTS-HD MA"}
      assert Quality.format(q) == "1080p BluRay x264 DTS-HD MA"
    end

    test "uses hdr_format when hdr is true" do
      q = %Quality{resolution: "2160p", source: "WEB-DL", hdr: true, hdr_format: "DV"}
      assert Quality.format(q) == "2160p WEB-DL DV"
    end

    test "shows HDR when hdr is true but no format" do
      q = %Quality{resolution: "2160p", source: "BluRay", hdr: true}
      assert Quality.format(q) == "2160p BluRay HDR"
    end

    test "appends PROPER and REPACK" do
      assert Quality.format(%Quality{resolution: "1080p", source: "BluRay", proper: true}) ==
               "1080p BluRay PROPER"

      assert Quality.format(%Quality{resolution: "720p", source: "WEB-DL", repack: true}) ==
               "720p WEB-DL REPACK"
    end

    test "empty struct formats to empty string; nil to nil" do
      assert Quality.format(Quality.empty()) == ""
      assert Quality.format(nil) == nil
    end
  end

  describe "from_map/1" do
    test "reconstructs from string-keyed map with flag defaults" do
      q = Quality.from_map(%{"resolution" => "1080p", "source" => "BluRay"})
      assert %Quality{} = q
      assert q.resolution == "1080p"
      assert q.source == "BluRay"
      assert q.hdr == false
      assert q.proper == false
      assert q.repack == false
    end

    test "honors atom keys and explicit flags" do
      q = Quality.from_map(%{resolution: "2160p", hdr: true, hdr_format: "DV", repack: true})
      assert q.hdr == true
      assert q.hdr_format == "DV"
      assert q.repack == true
    end

    test "nil maps to nil" do
      assert Quality.from_map(nil) == nil
    end
  end
end
