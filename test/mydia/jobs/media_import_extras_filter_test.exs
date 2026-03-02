defmodule Mydia.Jobs.MediaImportExtrasFilterTest do
  @moduledoc """
  Tests that the MediaImport job correctly filters out extras, samples, and trailers
  when importing files. Since filter_extras_and_samples/1 is a private function,
  we test the filtering logic through SampleDetector applied to the same file map
  structure that MediaImport uses.
  """
  use ExUnit.Case, async: true

  alias Mydia.Library.SampleDetector

  # Mirrors the file map structure used by MediaImport (from list_files_recursive)
  defp file_map(path) do
    %{
      path: path,
      name: Path.basename(path),
      size: 1_000_000
    }
  end

  # Replicates the filter logic from MediaImport.filter_extras_and_samples/1
  defp filter_extras_and_samples(files) do
    Enum.reject(files, fn file ->
      if SampleDetector.skip_detection?(file.path) do
        false
      else
        detection = SampleDetector.detect(file.path)
        SampleDetector.excluded?(detection)
      end
    end)
  end

  describe "filtering extras from import file list" do
    test "passes through regular movie files" do
      files = [
        file_map("/downloads/Avatar.2009.1080p.BluRay/Avatar.2009.1080p.BluRay.x264.mkv")
      ]

      assert filter_extras_and_samples(files) == files
    end

    test "passes through regular TV episode files" do
      files = [
        file_map("/downloads/Breaking.Bad.S01E01.720p/Breaking.Bad.S01E01.mkv"),
        file_map("/downloads/Breaking.Bad.S01E01.720p/Breaking.Bad.S01E02.mkv")
      ]

      assert filter_extras_and_samples(files) == files
    end

    test "filters files in Sample folder" do
      files = [
        file_map("/downloads/Avatar.2009/Avatar.2009.1080p.mkv"),
        file_map("/downloads/Avatar.2009/Sample/avatar-sample.mkv")
      ]

      result = filter_extras_and_samples(files)

      assert length(result) == 1
      assert hd(result).name == "Avatar.2009.1080p.mkv"
    end

    test "filters files in Featurettes folder" do
      files = [
        file_map("/downloads/Movie/Movie.mkv"),
        file_map("/downloads/Movie/Featurettes/making-of.mkv"),
        file_map("/downloads/Movie/Featurettes/cast-interviews.mkv")
      ]

      result = filter_extras_and_samples(files)

      assert length(result) == 1
      assert hd(result).name == "Movie.mkv"
    end

    test "filters files in Trailers folder" do
      files = [
        file_map("/downloads/Movie/Movie.mkv"),
        file_map("/downloads/Movie/Trailers/official-trailer.mkv")
      ]

      result = filter_extras_and_samples(files)

      assert length(result) == 1
      assert hd(result).name == "Movie.mkv"
    end

    test "filters files in Behind The Scenes folder" do
      files = [
        file_map("/downloads/Movie/Movie.mkv"),
        file_map("/downloads/Movie/Behind The Scenes/bts.mkv")
      ]

      result = filter_extras_and_samples(files)

      assert length(result) == 1
    end

    test "filters files in Extras folder" do
      files = [
        file_map("/downloads/Movie/Movie.mkv"),
        file_map("/downloads/Movie/Extras/bonus.mkv")
      ]

      result = filter_extras_and_samples(files)

      assert length(result) == 1
    end

    test "filters files with -sample filename suffix" do
      files = [
        file_map("/downloads/Movie/Movie.mkv"),
        file_map("/downloads/Movie/Movie-sample.mkv")
      ]

      result = filter_extras_and_samples(files)

      assert length(result) == 1
      assert hd(result).name == "Movie.mkv"
    end

    test "filters files with -trailer filename suffix" do
      files = [
        file_map("/downloads/Movie/Movie.mkv"),
        file_map("/downloads/Movie/Movie-trailer.mkv")
      ]

      result = filter_extras_and_samples(files)

      assert length(result) == 1
      assert hd(result).name == "Movie.mkv"
    end

    test "preserves .strm files even in Sample folders (skip_detection)" do
      files = [
        file_map("/downloads/Movie/Sample/stream.strm")
      ]

      result = filter_extras_and_samples(files)

      assert length(result) == 1
    end

    test "preserves .m2ts files even in Sample folders (skip_detection)" do
      files = [
        file_map("/downloads/Movie/Sample/clip.m2ts")
      ]

      result = filter_extras_and_samples(files)

      assert length(result) == 1
    end

    test "filters multiple extras types in a single torrent" do
      files = [
        file_map("/downloads/Movie.2024.BluRay/Movie.2024.BluRay.mkv"),
        file_map("/downloads/Movie.2024.BluRay/Sample/sample.mkv"),
        file_map("/downloads/Movie.2024.BluRay/Featurettes/making-of.mkv"),
        file_map("/downloads/Movie.2024.BluRay/Trailers/trailer1.mkv"),
        file_map("/downloads/Movie.2024.BluRay/Behind The Scenes/bts.mkv"),
        file_map("/downloads/Movie.2024.BluRay/Extras/deleted-scenes.mkv")
      ]

      result = filter_extras_and_samples(files)

      assert length(result) == 1
      assert hd(result).name == "Movie.2024.BluRay.mkv"
    end

    test "returns empty list when all files are extras" do
      files = [
        file_map("/downloads/Movie/Sample/sample.mkv"),
        file_map("/downloads/Movie/Featurettes/featurette.mkv")
      ]

      assert filter_extras_and_samples(files) == []
    end
  end
end
