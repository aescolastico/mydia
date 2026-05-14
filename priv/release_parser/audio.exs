alias Mydia.Library.ReleaseParser.VocabularyEntry

# Audio codec / format tokens. Compound tokens like "DTS-HD" and "DTS-X"
# are split by the tokenizer's dash allow-list — after that split the
# `DTS` token alone may match this vocab, so the resolver in Unit 5 is
# responsible for re-joining adjacent tokens when needed. For now we
# accept the post-split forms.
#
# `MA` is a very short ambiguous token (could be the streaming service
# "Movies Anywhere" or DTS-HD MA channel info), so it carries a heavy
# title-zone penalty.

[
  %VocabularyEntry{
    label: :audio,
    aliases: ["DTS-HD", "DTS-HD.MA", "DTSHDMA"],
    canonical: "DTS-HD MA",
    confidence: 0.95,
    title_zone_bonus: -0.2,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :audio,
    aliases: ["DTS-X", "DTSX"],
    canonical: "DTS-X",
    confidence: 0.95,
    title_zone_bonus: -0.2,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :audio,
    aliases: ["DTS"],
    canonical: "DTS",
    confidence: 0.9,
    title_zone_bonus: -0.2,
    metadata_zone_bonus: 0.0
  },
  # DDP / DD / EAC3 / AC3. Tokenizer splits on dots, so `DDP5.1` arrives
  # as two tokens (`DDP5` and `1`); the resolver in Unit 5 re-joins
  # adjacent channel numbers. Aliases here cover the post-tokenizer
  # forms we actually see (`DDP`, `DDP5`, `DDP51`).
  %VocabularyEntry{
    label: :audio,
    aliases:
      ["EAC3"] ++
        Enum.map(0..9, fn n -> "DDP#{n}" end) ++
        Enum.flat_map(0..9, fn a -> Enum.map(0..9, fn b -> "DDP#{a}#{b}" end) end) ++
        ["DDP"],
    canonical: "Dolby Digital Plus",
    confidence: 0.92,
    title_zone_bonus: -0.2,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :audio,
    aliases:
      ["AC3"] ++
        Enum.map(0..9, fn n -> "DD#{n}" end) ++
        Enum.flat_map(0..9, fn a -> Enum.map(0..9, fn b -> "DD#{a}#{b}" end) end) ++
        ["DD"],
    canonical: "Dolby Digital",
    confidence: 0.88,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :audio,
    aliases: ["TrueHD"],
    canonical: "TrueHD",
    confidence: 0.95,
    title_zone_bonus: -0.1,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :audio,
    aliases: ["Atmos"],
    canonical: "Dolby Atmos",
    confidence: 0.92,
    title_zone_bonus: -0.2,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :audio,
    aliases: ["AAC-LC"],
    canonical: "AAC-LC",
    confidence: 0.92,
    title_zone_bonus: -0.1,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :audio,
    aliases: ["AAC"],
    canonical: "AAC",
    confidence: 0.9,
    title_zone_bonus: -0.2,
    metadata_zone_bonus: 0.0
  },
  %VocabularyEntry{
    label: :audio,
    aliases: ["OPUS"],
    canonical: "Opus",
    confidence: 0.9,
    title_zone_bonus: -0.2,
    metadata_zone_bonus: 0.0
  },
  %VocabularyEntry{
    label: :audio,
    aliases: ["FLAC"],
    canonical: "FLAC",
    confidence: 0.9,
    title_zone_bonus: -0.2,
    metadata_zone_bonus: 0.0
  },
  %VocabularyEntry{
    label: :audio,
    aliases: ["MP3"],
    canonical: "MP3",
    confidence: 0.85,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.0
  }
]
