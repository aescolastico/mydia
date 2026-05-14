alias Mydia.Library.ReleaseParser.VocabularyEntry

# Known scene / p2p release groups. The set is intentionally small —
# release groups are open-ended (new ones appear every week) and the
# resolver in Unit 5 will also tag bracketed tokens past the title
# boundary as candidate groups regardless of whether they appear here.
# This vocabulary just gives an unambiguous high-confidence anchor for
# the well-known names.

[
  %VocabularyEntry{
    label: :release_group,
    aliases: ["RARBG"],
    canonical: "RARBG",
    confidence: 0.98,
    title_zone_bonus: -0.5,
    metadata_zone_bonus: 0.0
  },
  %VocabularyEntry{
    label: :release_group,
    aliases: ["YIFY"],
    canonical: "YIFY",
    confidence: 0.98,
    title_zone_bonus: -0.5,
    metadata_zone_bonus: 0.0
  },
  %VocabularyEntry{
    label: :release_group,
    aliases: ["YTS"],
    canonical: "YTS",
    confidence: 0.95,
    title_zone_bonus: -0.5,
    metadata_zone_bonus: 0.0
  },
  %VocabularyEntry{
    label: :release_group,
    aliases: ["EVO"],
    canonical: "EVO",
    confidence: 0.9,
    title_zone_bonus: -0.5,
    metadata_zone_bonus: 0.0
  },
  %VocabularyEntry{
    label: :release_group,
    aliases: ["RBG"],
    canonical: "RBG",
    confidence: 0.85,
    title_zone_bonus: -0.5,
    metadata_zone_bonus: 0.0
  },
  %VocabularyEntry{
    label: :release_group,
    aliases: ["NTb"],
    canonical: "NTb",
    confidence: 0.9,
    title_zone_bonus: -0.5,
    metadata_zone_bonus: 0.0
  },
  %VocabularyEntry{
    label: :release_group,
    aliases: ["FLUX"],
    canonical: "FLUX",
    confidence: 0.9,
    title_zone_bonus: -0.5,
    metadata_zone_bonus: 0.0
  },
  %VocabularyEntry{
    label: :release_group,
    aliases: ["SuccessfulCrab"],
    canonical: "SuccessfulCrab",
    confidence: 0.95,
    title_zone_bonus: -0.5,
    metadata_zone_bonus: 0.0
  },
  %VocabularyEntry{
    label: :release_group,
    aliases: ["MeGusta"],
    canonical: "MeGusta",
    confidence: 0.95,
    title_zone_bonus: -0.5,
    metadata_zone_bonus: 0.0
  },
  %VocabularyEntry{
    label: :release_group,
    aliases: ["CMRG"],
    canonical: "CMRG",
    confidence: 0.9,
    title_zone_bonus: -0.5,
    metadata_zone_bonus: 0.0
  },
  %VocabularyEntry{
    label: :release_group,
    aliases: ["KOGi"],
    canonical: "KOGi",
    confidence: 0.9,
    title_zone_bonus: -0.5,
    metadata_zone_bonus: 0.0
  }
]
