alias Mydia.Library.ReleaseParser.VocabularyEntry

# Language and language-status tokens. Mined from V2's noise pattern plus
# the common scene/p2p set. These are usually metadata-zone tokens; when
# they sit before the earliest anchor (a movie title that happens to be
# the word "FRENCH", say) we still want the title interpretation to win,
# hence the modest title-zone penalty.

[
  %VocabularyEntry{
    label: :language,
    aliases: ["MULTi", "MULTI"],
    canonical: "Multi",
    confidence: 0.88,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :language,
    aliases: ["FRENCH", "VFF", "VFQ", "VOSTFR"],
    canonical: "French",
    confidence: 0.88,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :language,
    aliases: ["GERMAN"],
    canonical: "German",
    confidence: 0.88,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :language,
    aliases: ["ITALIAN"],
    canonical: "Italian",
    confidence: 0.88,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :language,
    aliases: ["SPANISH"],
    canonical: "Spanish",
    confidence: 0.88,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :language,
    aliases: ["RUSSIAN"],
    canonical: "Russian",
    confidence: 0.88,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :language,
    aliases: ["JAPANESE", "JPN"],
    canonical: "Japanese",
    confidence: 0.88,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :language,
    aliases: ["KOREAN", "KOR"],
    canonical: "Korean",
    confidence: 0.88,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :language,
    aliases: ["CHINESE", "CHS", "CHT"],
    canonical: "Chinese",
    confidence: 0.88,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :language,
    aliases: ["NORDIC"],
    canonical: "Nordic",
    confidence: 0.85,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :language,
    aliases: ["DUBBED"],
    canonical: "Dubbed",
    confidence: 0.85,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :language,
    aliases: ["SUBBED"],
    canonical: "Subbed",
    confidence: 0.85,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  },
  %VocabularyEntry{
    label: :language,
    aliases: ["HINDI"],
    canonical: "Hindi",
    confidence: 0.88,
    title_zone_bonus: -0.3,
    metadata_zone_bonus: 0.05
  }
]
