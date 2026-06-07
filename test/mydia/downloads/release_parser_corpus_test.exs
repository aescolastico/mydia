defmodule Mydia.Downloads.ReleaseParserCorpusTest do
  @moduledoc """
  Regression corpus for the TorrentParser -> ReleaseParser consolidation (U7).

  The cases below are ported from the retired TorrentParser test suite and run
  against the download parse path (`ReleaseIntake.parse_release/1`, which applies
  torrent-specific name cleaning then ReleaseParser).

  ## Two tiers

  - **Frozen tier** — the type / title / season / episode extractions that
    download matching depends on. These MUST hold; a failure here is a real
    regression and must not be re-baselined to whatever the parser now emits.
    Titles are compared case-insensitively because the V3 parser uses a
    different title-casing convention than the old parser (matching normalizes
    case downstream, so this is cosmetic).

  - **Review tier** — cosmetic / dropped-capability differences. Movie *edition*
    extraction (Director's Cut, Extended, etc.) was intentionally dropped, so we
    only assert the release still classifies as a movie with the base title.
  """
  use ExUnit.Case, async: true

  alias Mydia.Downloads.ReleaseIntake

  defp parse!(name) do
    {:ok, info} = ReleaseIntake.parse_release(name)
    info
  end

  describe "frozen tier — movies" do
    @movies [
      {"The.Matrix.1999.1080p.BluRay.x264-SPARKS", "the matrix", 1999},
      {"Inception (2010) 720p BluRay x264-YIFY", "inception", 2010},
      {"Dune.2021.2160p.WEB-DL.x265-EVO", "dune", 2021},
      {"The.Lord.of.the.Rings.2001.1080p.BluRay.x264-GROUP", "the lord of the rings", 2001},
      {"Interstellar.2014.1080p.BluRay.x264", "interstellar", 2014}
    ]

    for {name, title, year} <- @movies do
      test "movie: #{name}" do
        info = parse!(unquote(name))
        assert info.type == :movie
        assert String.downcase(info.title) == unquote(title)
        assert info.year == unquote(year)
      end
    end
  end

  describe "frozen tier — TV episodes" do
    @episodes [
      {"Breaking.Bad.S01E01.720p.HDTV.x264-CTU", "breaking bad", 1, [1]},
      {"Friends.S1E5.1080p.WEB-DL.x264-NTb", "friends", 1, [5]},
      {"Game.of.Thrones.1x01.720p.HDTV.x264-CTU", "game of thrones", 1, [1]},
      {"The.Big.Bang.Theory.S10E15.1080p.WEB-DL.x264-RBB", "the big bang theory", 10, [15]},
      {"Stranger.Things.S02E03.1080p.WEBRip.x265", "stranger things", 2, [3]},
      {"Breaking.Bad.S05E01.DUAL.1080p.BluRay.x264-GRP", "breaking bad", 5, [1]}
    ]

    for {name, title, season, episodes} <- @episodes do
      test "episode: #{name}" do
        info = parse!(unquote(name))
        assert info.type == :tv_show
        assert String.downcase(info.title) == unquote(title)
        assert info.season == unquote(season)
        assert info.episodes == unquote(episodes)
      end
    end
  end

  describe "frozen tier — season packs" do
    @packs [
      {"House.of.the.Dragon.S01.COMPLETE.2160p.BluRay.x265-GROUP", "house of the dragon", 1},
      {"Yellowstone.S04.1080p.BluRay.x264-MIXED", "yellowstone", 4},
      {"Naruto.S2.720p.WEB-DL.x264-GRP", "naruto", 2},
      {"The.Last.of.Us.S02.1080p.WEB-DL.DDP5.1.x265-GROUP", "the last of us", 2}
    ]

    for {name, title, season} <- @packs do
      test "season pack: #{name}" do
        info = parse!(unquote(name))
        assert info.type == :tv_show
        assert String.downcase(info.title) == unquote(title)
        assert info.season == unquote(season)
        # Season pack: a season with no specific episodes.
        assert info.episodes in [nil, []]
      end
    end
  end

  describe "frozen tier — torrent-specific cleaning (tracker tags / CJK)" do
    @cleaned [
      {"[47BT]Yellowstone.S02.1080p.BluRay.x264-MIXED", "yellowstone", 2},
      {"[Ex-torrenty.org]The.Last.of.Us.S02.1080p.WEB-DL.x265", "the last of us", 2},
      {"[Tracker]Severance.S02.MULTi.1080p.WEB-DL.x264-GRP", "severance", 2}
    ]

    for {name, title, season} <- @cleaned do
      test "cleaned: #{name}" do
        info = parse!(unquote(name))
        assert info.type == :tv_show
        assert String.downcase(info.title) == unquote(title)
        assert info.season == unquote(season)
      end
    end

    test "CJK brackets and season markers are stripped from the title" do
      info =
        parse!("【高清剧集网 www.BTHDTV.com】猎魔人 第二季.The.Witcher.S02E01.1080p.WEB-DL.x265")

      assert info.type == :tv_show
      assert info.season == 2
      assert info.episodes == [1]
      # The CJK site bracket and "第二季" season marker are gone; the show titles
      # (CJK + English) remain.
      assert info.title == "猎魔人 The Witcher"
    end
  end

  describe "review tier — edition (capability intentionally dropped)" do
    # Edition extraction (Director's Cut, Extended, ...) was removed with
    # TorrentParser. These releases must still classify as movies with the base
    # title; the edition itself is no longer represented anywhere.
    @editions [
      {"Blade.Runner.1982.Directors.Cut.1080p.BluRay.x264-GROUP", "blade runner", 1982},
      {"Watchmen.2009.Extended.Cut.1080p.BluRay.x264-GROUP", "watchmen", 2009}
    ]

    for {name, base_title, year} <- @editions do
      test "edition movie still classifies: #{name}" do
        info = parse!(unquote(name))
        assert info.type == :movie
        assert info.year == unquote(year)
        assert String.contains?(String.downcase(info.title), unquote(base_title))
      end
    end
  end
end
