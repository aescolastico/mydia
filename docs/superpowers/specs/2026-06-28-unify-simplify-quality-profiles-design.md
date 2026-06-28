# Unify & Simplify Quality Profiles — Design

**Date:** 2026-06-28
**Status:** Approved (ready for implementation plan)

## Goal

Collapse the quality-profile feature down to one quality model, one parsed-quality
struct, and zero dead configuration. This is a **clean break**: a single data
migration converts existing rows, and all backward-compatibility / fallback code is
deleted afterward — nothing tolerant of the old shapes is left behind.

## Background

`quality_profiles` (schema `Mydia.Settings.QualityProfile`, context
`Mydia.Settings.QualityProfiles`) are Radarr/Sonarr-style acquisition profiles that
decide which releases to download and how to rank them. They are attached to
`MediaItem`, `ImportList`, and (after batch evaluation) `MediaFile`, and drive the
search/download pipeline (`movie_search` / `tv_show_search` → `RankingOptions` →
`ReleaseRanker` → `SearchScorer` → `QualityProfile.score_media_file/2`, plus
`QualityMatcher`).

The schema has churned twice already (`rules` → `quality_standards`). Three tangles
remain, all in scope:

1. **Dual quality model.** A legacy flat `qualities` list (resolution strings,
   *required*) coexists with the newer structured `quality_standards` map. The
   scoring engine keys *entirely* off `quality_standards`; `qualities` only
   duplicates `quality_standards.preferred_resolutions`. Reconciliation code is
   spread across `QualityMatcher` (reads `profile.qualities`) and `SearchScorer`
   (synthesizes `preferred_resolutions` from `qualities`).
2. **Dead config bolted onto profiles.** `metadata_preferences` (~460 lines across
   schema validation + a 264-line defaults module + an unused reader + import/export
   plumbing) and `customizations` are both defined, validated, and round-tripped —
   but **never read or applied** anywhere. Metadata language already flows from the
   global `config.metadata.language` setting, independent of profiles. Neither field
   has any UI.
3. **Duplicate parsed-quality structs.** `Mydia.Indexers.Structs.QualityInfo` is a
   strict superset of `Mydia.Library.Structs.Quality` (same five fields plus `hdr`,
   `proper`, `repack` and the `format/1` / `from_map/1` helpers).

## Decisions (locked)

- **Backward-compat appetite:** Clean break. One data migration, then delete all
  fallback/compat code.
- **`metadata_preferences`:** Delete entirely.
- **`customizations`:** Delete entirely (same justification — dead config).
- **Parser scope:** Merge the two structs only. Leave the two parsers
  (`indexers/quality_parser.ex`, `release_parser/quality_extractor.ex`) as-is; they
  parse different inputs and just emit the unified struct.
- **Canonical parsed-quality module:** `Mydia.Library.Structs.Quality`, extended to
  the superset shape.
- **`upgrade_until_quality`:** Keep as-is (single-resolution cap) to contain scope.

---

## Section A — Collapse the dual quality model

`quality_standards` becomes the single source of truth. The standalone `qualities`
list is dropped.

### Schema (`quality_profiles` table & `Mydia.Settings.QualityProfile`)

- Drop the `qualities` column. The resolution allow-list now lives in
  `quality_standards.preferred_resolutions`; `min_resolution` / `max_resolution`
  already live there too.
- Changeset:
  - Remove `:qualities` from `cast`.
  - Remove `validate_required([:name, :qualities])` → `validate_required([:name])`.
  - Remove `validate_length(:qualities, min: 1)`.
  - Add validation that `quality_standards` is present and has a non-empty
    `preferred_resolutions` list (so a profile still must specify at least one
    resolution).
- Drop `qualities` from the `@type t` and the `schema` block.

### Consumers

- `Mydia.Settings.QualityMatcher`
  - `is_upgrade?/3`: replace `result_quality not in profile.qualities` with a check
    against `quality_standards.preferred_resolutions`.
  - `check_quality_allowed/2` (the "legacy qualities" branch in `matches?/2`): read
    allowed resolutions from `quality_standards.preferred_resolutions`.
- `Mydia.Indexers.SearchScorer`
  - Delete `ensure_preferred_resolutions/1` and the `profile_with_resolution_fallback`
    call site (lines ~187–188, ~363–406). With canonical data the synthesize step is
    unnecessary.
- `Mydia.Indexers.RankingOptions`
  - Source `preferred_qualities` from `quality_standards` instead of `profile.qualities`.
- Audit remaining `profile.qualities` readers and convert each to read from
  `quality_standards.preferred_resolutions`.

### Defaults & presets

- `Mydia.Settings.DefaultQualityProfiles` (8 built-ins) and
  `Mydia.Settings.QualityProfilePresets` (~20 curated): drop the now-redundant
  `qualities:` key from each profile map. They already define `quality_standards`;
  ensure every one has a non-empty `preferred_resolutions`.

> Note: unifying the preset/default *authoring duplication* (the two modules that
> hand-write full profile maps) is explicitly **out of scope** for this change.

---

## Section B — Delete dead config (`metadata_preferences` + `customizations`)

Both are unused — no consumers, no UI. Removed entirely in the clean-break migration.

- Drop the `metadata_preferences` and `customizations` columns.
- Delete `Mydia.Settings.DefaultMetadataPreferences`
  (`lib/mydia/settings/default_metadata_preferences.ex`, 264 lines).
- Delete `validate_metadata_preferences/1` and all its sub-validators
  (`validate_provider_priority`, `validate_field_providers`,
  `validate_language_settings`, `validate_auto_fetch_settings`,
  `validate_fallback_settings`, `validate_conflict_resolution`) from
  `quality_profile.ex` (~200 lines).
- Delete the never-called `Mydia.Settings.QualityProfileEngine.get_metadata_preferences/1`.
- Remove `:metadata_preferences` and `:customizations` from:
  - the changeset `cast`,
  - the `@type t` and `schema` block,
  - clone, import, and export paths in `Mydia.Settings.QualityProfiles`
    (and any references in `Mydia.Settings`).
- Confirm metadata language is unaffected: it continues to resolve via
  `Mydia.Metadata.metadata_language/0` → `config.metadata.language`. No change there.

---

## Section C — Merge parsed-quality structs (struct only)

Collapse to one canonical struct: **`Mydia.Library.Structs.Quality`**, extended to the
superset shape.

- Fields: `resolution, source, codec, audio, hdr, hdr_format, proper, repack`.
- Helpers (merged from both modules): `new/1`, `empty/0`, `empty?/1`, `format/1`,
  `from_map/1`. Boolean fields (`hdr`, `proper`, `repack`) default to `false`;
  on-disk files simply leave them at the defaults.
- Delete `Mydia.Indexers.Structs.QualityInfo`.
- Update all references to the unified struct: `indexers/quality_parser.ex`,
  `search_scorer.ex`, `release_ranker.ex`, `Indexers.Structs.SearchResult`, and any
  other `QualityInfo` users.
- Both parsers stay as-is and emit `Mydia.Library.Structs.Quality`.

---

## Migration & testing

### Migration (single, adapter-aware)

Supports both SQLite (default) and PostgreSQL via `Mydia.Repo.Migrations.Helpers`
(`postgres?/0`, `sqlite?/0`, `recreate_table/1`).

1. Backfill: for every `quality_profiles` row whose `quality_standards` lacks a
   non-empty `preferred_resolutions`, set `preferred_resolutions` from the row's
   `qualities` value (and reasonable `min_resolution` / `max_resolution` if absent).
2. Drop columns `qualities`, `metadata_preferences`, `customizations`.
   - PostgreSQL: `ALTER TABLE ... DROP COLUMN`.
   - SQLite: table rebuild (rename → create → copy → drop) via the helpers.

### Testing

- Update changeset tests (no more `qualities`; require `preferred_resolutions`).
- Update `QualityProfile.score_media_file/2` tests if affected.
- Update `QualityMatcher` tests (`is_upgrade?`, `matches?`, `check_quality_allowed`).
- Update `SearchScorer` tests (fallback removed).
- Update struct/parser tests to the unified `Quality` struct; delete `QualityInfo`
  tests.
- Add a migration backfill test (old `qualities` → `preferred_resolutions`).
- `mix precommit` green at the end.

## Net effect

- ~700+ lines of dead and duplicate code removed.
- One quality model (`quality_standards`), one parsed-quality struct
  (`Library.Structs.Quality`), no "backward compatibility" branches.

## Out of scope

- Unifying the preset/default authoring duplication
  (`DefaultQualityProfiles` + `QualityProfilePresets`).
- Merging the two parsers.
- The playback/transcode "quality" concept (HLS ladder, codec compatibility, Flutter
  player) — a separate domain with no `QualityProfile` involvement.
- Folding `upgrade_until_quality` into `quality_standards`.
