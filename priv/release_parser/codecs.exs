alias Mydia.Library.ReleaseParser.VocabularyEntry

# Video codecs. Aliases are matched case-insensitively against token
# values produced by the Tokenizer. Canonical forms follow the V2 output
# (`H.264/AVC`, `H.265/HEVC`) so downstream Quality fields keep their
# existing shape.

[
  # Tokenizer splits on dots, so `x.264` arrives as two tokens (`x`,
  # `264`). The single-token forms below (`x264`, `h264`) are what we
  # actually see; the resolver re-joins dotted variants in Unit 5 if
  # needed.
  %VocabularyEntry{
    label: :codec,
    aliases: ["x264", "h264", "AVC"],
    canonical: "H.264/AVC",
    confidence: 0.95,
    title_zone_bonus: -0.1,
    metadata_zone_bonus: 0.0
  },
  %VocabularyEntry{
    label: :codec,
    aliases: ["x265", "h265", "HEVC"],
    canonical: "H.265/HEVC",
    confidence: 0.95,
    title_zone_bonus: -0.1,
    metadata_zone_bonus: 0.0
  },
  %VocabularyEntry{
    label: :codec,
    aliases: ["XviD"],
    canonical: "XviD",
    confidence: 0.9,
    title_zone_bonus: -0.1,
    metadata_zone_bonus: 0.0
  },
  %VocabularyEntry{
    label: :codec,
    aliases: ["DivX"],
    canonical: "DivX",
    confidence: 0.9,
    title_zone_bonus: -0.1,
    metadata_zone_bonus: 0.0
  },
  %VocabularyEntry{
    label: :codec,
    aliases: ["VP9"],
    canonical: "VP9",
    confidence: 0.9,
    title_zone_bonus: -0.1,
    metadata_zone_bonus: 0.0
  },
  %VocabularyEntry{
    label: :codec,
    aliases: ["AV1"],
    canonical: "AV1",
    confidence: 0.9,
    title_zone_bonus: -0.1,
    metadata_zone_bonus: 0.0
  },
  %VocabularyEntry{
    label: :codec,
    aliases: ["NVENC"],
    canonical: "NVENC",
    confidence: 0.7,
    title_zone_bonus: -0.2,
    metadata_zone_bonus: 0.0
  }
]
