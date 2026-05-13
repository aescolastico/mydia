alias Mydia.Library.ReleaseParser.VocabularyEntry

# Streaming-service tags. Most are 2–4 character abbreviations that can
# collide with title content (the worst offenders are `iT`, `MA`, `NF`).
# Those carry a strong title-zone penalty so a movie title containing the
# word "It" doesn't get tagged as Apple's iTunes service.

[
  %VocabularyEntry{
    label: :streaming_service,
    aliases: ["AMZN"],
    canonical: "Amazon",
    confidence: 0.92,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :streaming_service,
    aliases: ["ATVP"],
    canonical: "Apple TV+",
    confidence: 0.92,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :streaming_service,
    aliases: ["DSNP"],
    canonical: "Disney+",
    confidence: 0.92,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :streaming_service,
    aliases: ["HMAX"],
    canonical: "HBO Max",
    confidence: 0.92,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :streaming_service,
    aliases: ["HULU"],
    canonical: "Hulu",
    confidence: 0.92,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :streaming_service,
    aliases: ["NF"],
    canonical: "Netflix",
    confidence: 0.88,
    title_zone_bonus: -0.6,
    metadata_zone_bonus: 0.1
  },
  %VocabularyEntry{
    label: :streaming_service,
    aliases: ["PMTP"],
    canonical: "Paramount+",
    confidence: 0.92,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :streaming_service,
    aliases: ["PCOK"],
    canonical: "Peacock",
    confidence: 0.92,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :streaming_service,
    aliases: ["STAN"],
    canonical: "Stan",
    confidence: 0.88,
    title_zone_bonus: -0.5,
    metadata_zone_bonus: 0.1
  },
  %VocabularyEntry{
    label: :streaming_service,
    aliases: ["iT", "ITUNES"],
    canonical: "iTunes",
    confidence: 0.85,
    title_zone_bonus: -0.7,
    metadata_zone_bonus: 0.15
  },
  %VocabularyEntry{
    label: :streaming_service,
    aliases: ["MA"],
    canonical: "Movies Anywhere",
    confidence: 0.8,
    title_zone_bonus: -0.7,
    metadata_zone_bonus: 0.15
  },
  %VocabularyEntry{
    label: :streaming_service,
    aliases: ["MAX"],
    canonical: "Max",
    confidence: 0.85,
    title_zone_bonus: -0.6,
    metadata_zone_bonus: 0.1
  }
]
