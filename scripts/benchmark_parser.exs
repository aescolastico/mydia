# Benchmark script for FileParser V1 (legacy) vs V3 (ReleaseParser).
#
# V2 was retired in the V3 migration (Unit 8). V1 retirement is
# tracked in a separate follow-up; until then it still ships in
# `lib/mydia/library/file_parser.ex` for the `mydia.migrate_episode_files`
# mix task.

alias Mydia.Library.FileParser
alias Mydia.Library.ReleaseParser

# Test cases - real-world filenames
test_cases = [
  "Movie.Title.2020.1080p.BluRay.x264-GROUP.mkv",
  "The.Dark.Knight.2008.2160p.UHD.BluRay.x265.HDR.DTS-HD.MA.5.1-GROUP.mkv",
  "Breaking.Bad.S05E16.1080p.BluRay.x264-ROVERS[rarbg].mkv",
  "Show.Name.S01E05.720p.WEB.H264-GROUP.mkv",
  "Black Phone 2. 2025 1080P WEB-DL DDP5.1 Atmos. X265. POOLTED.mkv",
  "Dune.Part.Two.2024.HDR.BluRay.2160p.x265.7.1.aac.VMAF96-Rosy.mkv",
  "2001 A Space Odyssey (1968) 1080p.mkv",
  "Epic.Movie.2021.2160p.UHD.BluRay.HDR10.DolbyVision.TrueHD.Atmos.7.1.x265.mkv",
  "The.Matrix.1999.1080p.BluRay.x.264.DTS-HD.MA.5.1-GROUP.mkv",
  "Avatar.2009.2160p.UHD.BluRay.REMUX.HDR.HEVC.Atmos-FGT.mkv",
  "Show.S01E01.1080p.WEB-DL.DD5.1.H264.mkv",
  "The.Mandalorian.S02E05.1080p.WEB.H264-GLHF.mkv",
  "Inception (2010)/Inception (2010) - 1080p.mkv",
  "Movie Name (2020).mkv",
  "Just A Title 2024.mkv",
  "Mission Impossible 7 Dead Reckoning Part 1 (2023) 1080p.mkv",
  "Movie.Name.2024.PROPER.REPACK.1080p.WEB-DL.10bit.DDP5.1.HEVC-GROUP.mkv",
  "Show.Name.S01E01-E03.1080p.mkv",
  "The Matrix Reloaded (2003) BDRip 2160p-NVENC 10 bit [HDR].mkv",
  "randomfile.mkv"
]

IO.puts("\n=== FileParser Benchmark: V1 vs V3 ===\n")
IO.puts("Running #{length(test_cases)} test cases...\n")

# Benchmark V1
IO.puts("Benchmarking V1...")
{v1_time, v1_results} = :timer.tc(fn ->
  Enum.map(test_cases, fn filename ->
    FileParser.parse(filename)
  end)
end)

# Benchmark V3 (raw mode)
IO.puts("Benchmarking V3 (raw mode)...")
{v3_time, v3_results} = :timer.tc(fn ->
  Enum.map(test_cases, fn filename ->
    ReleaseParser.parse(filename)
  end)
end)

# Benchmark V3 with standardization
IO.puts("Benchmarking V3 (standardized mode)...")
{v3_std_time, _v3_std_results} = :timer.tc(fn ->
  Enum.map(test_cases, fn filename ->
    ReleaseParser.parse(filename, standardize: true)
  end)
end)

# Performance results
IO.puts("\n=== Performance Results ===")
IO.puts("V1 time:              #{Float.round(v1_time / 1000, 2)} ms (#{Float.round(v1_time / length(test_cases) / 1000, 3)} ms/file)")
IO.puts("V3 raw time:          #{Float.round(v3_time / 1000, 2)} ms (#{Float.round(v3_time / length(test_cases) / 1000, 3)} ms/file)")
IO.puts("V3 standardized time: #{Float.round(v3_std_time / 1000, 2)} ms (#{Float.round(v3_std_time / length(test_cases) / 1000, 3)} ms/file)")
IO.puts("\nSpeedup (V3 raw vs V1): #{Float.round(v1_time / v3_time, 2)}x")
IO.puts("Overhead (standardization): #{Float.round((v3_std_time - v3_time) / v3_time * 100, 1)}%")

# Accuracy comparison
IO.puts("\n=== Accuracy Comparison ===")

differences = Enum.zip([test_cases, v1_results, v3_results])
|> Enum.filter(fn {_filename, v1, v3} ->
  v1.type != v3.type || v1.title != v3.title || v1.year != v3.year
end)

if differences == [] do
  IO.puts("All results match between V1 and V3!")
else
  IO.puts("Found #{length(differences)} difference(s):\n")

  Enum.each(differences, fn {filename, v1, v3} ->
    IO.puts("File: #{filename}")
    IO.puts("  V1: type=#{v1.type}, title=#{inspect(v1.title)}, year=#{inspect(v1.year)}")
    IO.puts("  V3: type=#{v3.type}, title=#{inspect(v3.title)}, year=#{inspect(v3.year)}")
    IO.puts("")
  end)
end

# Standardization examples
IO.puts("\n=== Standardization Examples ===")
sample_files = [
  "Movie.2024.1080p.BluRay.DDP5.1.x264.mkv",
  "Show.S01E01.2160p.WEB-DL.HEVC.HDR10.DTS-HD.MA.mkv"
]

Enum.each(sample_files, fn filename ->
  IO.puts("\nFile: #{filename}")
  raw = ReleaseParser.parse(filename)
  std = ReleaseParser.parse(filename, standardize: true)

  IO.puts("  Raw mode:")
  IO.puts("    Resolution: #{raw.quality.resolution}, Source: #{raw.quality.source}")
  IO.puts("    Codec: #{raw.quality.codec}, Audio: #{raw.quality.audio}")

  IO.puts("  Standardized mode:")
  IO.puts("    Resolution: #{std.quality.resolution}, Source: #{std.quality.source}")
  IO.puts("    Codec: #{std.quality.codec}, Audio: #{std.quality.audio}")
end)

# Summary
IO.puts("\n=== Summary ===")
IO.puts("V1: #{length(test_cases)} files parsed in #{Float.round(v1_time / 1000, 2)} ms")
IO.puts("V3 (raw): #{length(test_cases)} files parsed in #{Float.round(v3_time / 1000, 2)} ms")
IO.puts("V3 (standardized): #{length(test_cases)} files parsed in #{Float.round(v3_std_time / 1000, 2)} ms")
IO.puts("Accuracy: #{length(test_cases) - length(differences)}/#{length(test_cases)} matching (#{Float.round((length(test_cases) - length(differences)) / length(test_cases) * 100, 1)}%)")
IO.puts("Performance: V3 is #{Float.round(v1_time / v3_time, 2)}x #{if v3_time < v1_time, do: "faster", else: "slower"} than V1")
IO.puts("Per-file avg (V3 standardized): #{Float.round(v3_std_time / length(test_cases) / 1000, 3)} ms #{if v3_std_time / length(test_cases) / 1000 < 10, do: "(< 10ms target)", else: "(> 10ms target)"}")
