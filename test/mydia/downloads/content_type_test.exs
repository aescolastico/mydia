defmodule Mydia.Downloads.ContentTypeTest do
  use ExUnit.Case, async: true

  alias Mydia.Downloads.ContentType

  describe "detect/1" do
    test "classifies a magnet URI" do
      assert ContentType.detect("magnet:?xt=urn:btih:abcdef0123456789") == :magnet
    end

    test "classifies a classic tracker-based torrent (announce first)" do
      # d8:announce…4:infod…ee
      body =
        "d8:announce20:http://tracker:8080" <>
          "4:infod6:lengthi42e4:name8:test.binee"

      assert ContentType.detect(body) == :torrent
    end

    test "classifies a trackerless torrent whose first key is `comment`" do
      # This is the exact prefix that anacrolix/torrent emits and that the
      # old prefix-based detector mistakenly rejected as HTML, causing the
      # `Off Campus` season pack to fail to download every hour.
      body =
        "d7:comment28:dynamic metainfo from client" <>
          "10:created by10:go.torrent" <>
          "13:creation datei1778661767e" <>
          "4:infod6:lengthi42e4:name8:test.binee"

      assert ContentType.detect(body) == :torrent
    end

    test "classifies a trackerless torrent whose first key is `created by`" do
      body =
        "d10:created by10:go.torrent" <>
          "4:infod6:lengthi1e4:name1:xee"

      assert ContentType.detect(body) == :torrent
    end

    test "classifies an NZB XML document" do
      body =
        ~s(<?xml version="1.0" encoding="iso-8859-1" ?>) <>
          ~s(<!DOCTYPE nzb PUBLIC "-//newzBin//DTD NZB 1.1//EN" "http://www.newzbin.com/DTD/nzb/nzb-1.1.dtd">) <>
          ~s(<nzb xmlns="http://www.newzbin.com/DTD/2003/nzb"></nzb>)

      assert ContentType.detect(body) == :nzb
    end

    test "returns :unknown for an HTML page" do
      body = "<!DOCTYPE html><html><body>Cloudflare check</body></html>"
      assert ContentType.detect(body) == :unknown
    end

    test "returns :unknown for an empty binary" do
      assert ContentType.detect("") == :unknown
    end

    test "returns :unknown for non-binary input" do
      assert ContentType.detect(nil) == :unknown
    end

    test "does not mistake a bencode-shaped string without an info dict for a torrent" do
      # Leading `d` but no `info` key — must not be treated as a torrent.
      body = "d4:name8:test.bin6:lengthi42ee"
      assert ContentType.detect(body) == :unknown
    end
  end
end
