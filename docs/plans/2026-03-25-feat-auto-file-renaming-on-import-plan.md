---
title: "feat: Auto File Renaming on Import"
type: feat
status: completed
date: 2026-03-25
origin: docs/brainstorms/2026-03-25-auto-file-renaming-brainstorm.md
---

# feat: Auto File Renaming on Import

## Overview

Downloaded files currently keep their original scene/release names (e.g., `The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv`). This feature enables automatic renaming to a standardized TRaSH Guides format on import (e.g., `The Matrix (1999) [BluRay-1080p] [DTS] [x264]-GROUP.mkv`), controlled per library path via an `auto_rename` toggle (default: ON for new libraries).

Additionally, consolidates the two separate naming modules (`FileNamer` for TRaSH style, `FileRenamer` for simpler style) into a single naming engine so manual rename and auto-rename produce identical results.

## Problem Statement / Motivation

- `FileNamer` (TRaSH-style name generation) exists with tests but is **dead code** — never called during the import pipeline because `DownloadMonitor` never sets `rename_files: true` in the import job args
- `MediaImport` already has the conditional check (`if args.rename_files`) but it always evaluates to `false`
- Two naming modules produce different formats, causing inconsistency between auto-import and manual rename
- Users expect a media management app to organize and name files consistently (see brainstorm: `docs/brainstorms/2026-03-25-auto-file-renaming-brainstorm.md`)

## Proposed Solution

Wire the existing dead code path and consolidate naming into a single TRaSH Guides format:

1. Add `auto_rename` field to `LibraryPath` schema
2. Have `MediaImport` read `auto_rename` from the resolved library path at execution time (not from job args — avoids race conditions if settings change between enqueue and execution)
3. Consolidate `FileRenamer` to delegate naming to `FileNamer`
4. Add UI toggle in library path settings

## Technical Considerations

### Architecture

**Evaluation at execution time, not enqueue time** (see brainstorm). `MediaImport.process_import/3` already calls `determine_library_path/1` which returns the `LibraryPath` struct. After this call, override `args.rename_files` based on `library_path.auto_rename`. This avoids duplicating library path resolution in `DownloadMonitor` and eliminates timing issues.

**Key files:**

| File | Change |
|------|--------|
| `lib/mydia/settings/library_path.ex` | Add `auto_rename` field, typespec, cast |
| `lib/mydia/jobs/media_import.ex` | Read `auto_rename` from library path after `determine_library_path` |
| `lib/mydia/library/file_renamer.ex` | Replace private naming functions with `FileNamer` delegation |
| `lib/mydia_web/live/admin_config_live/components.ex` | Add toggle to library path modal |
| `priv/repo/migrations/` | New migration adding `auto_rename` column |

### Quality Info Bridge (for consolidation)

`FileNamer` expects a `QualityInfo` struct (from `QualityParser.parse/1`). For manual rename, the quality source should be **`MediaFile` DB fields** (populated by FFprobe analysis), not re-parsing the filename (which may already be renamed). Build a `QualityInfo` struct from `MediaFile.resolution`, `.codec`, `.audio_codec`, `.hdr_format`, and `.metadata`.

### Migration Strategy

- Column default: `true` (new library paths get auto-rename enabled)
- Existing rows: Explicitly set to `false` in the migration to avoid surprising users with unexpected renames on next import

### Performance

No performance concerns — renaming adds a string formatting step to each file during import, which is negligible compared to the file copy/hardlink/move operation.

### Security

No security concerns — file operations stay within library path boundaries, same as existing import logic.

## System-Wide Impact

- **Interaction graph**: `DownloadMonitor` → `MediaImport` (existing flow, no new interactions). `FileRenamer` → `FileNamer` (new delegation). UI → `LibraryPath` changeset (existing pattern).
- **Error propagation**: `generate_filename/4` already has a fallback to original filename on failure. `FileRenamer.rename_file/2` already rolls back filesystem changes on DB failure. No new error paths.
- **State lifecycle risks**: Pre-existing issue in `MediaImport` — if `create_media_file_record` fails after file copy, the file is orphaned on disk. Not introduced by this change but worth noting. Out of scope for this PR.
- **API surface parity**: No GraphQL or external API changes needed. The feature is internal to the import pipeline.

## Acceptance Criteria

### Phase 1: Schema & Migration

- [x] Add `auto_rename` boolean field to `LibraryPath` schema (`lib/mydia/settings/library_path.ex`) with default `true`
- [x] Add field to typespec, cast list in changeset
- [x] Create migration: adds column with default `true`, then updates existing rows to `false`
- [x] Add toggle to library path settings modal (`lib/mydia_web/live/admin_config_live/components.ex`) following the `auto_import`/`auto_organize` toggle pattern

### Phase 2: Wire Auto-Rename in Import Pipeline

- [x] In `MediaImport.process_import/3`, after `determine_library_path/1`, override `args.rename_files` based on `library_path.auto_rename`
- [x] Verify `generate_filename/4` correctly calls `FileNamer` when `rename_files` is `true`
- [x] No changes needed to `DownloadMonitor` — it stays unaware of rename configuration

### Phase 3: Consolidate FileRenamer → FileNamer

- [x] Create a helper function in `FileRenamer` that builds a `QualityInfo` struct from `MediaFile` DB fields (`.resolution`, `.codec`, `.audio_codec`, `.hdr_format`, `.metadata`)
- [x] Replace `FileRenamer.generate_movie_filename/3` with a call to `FileNamer.generate_movie_filename/3`
- [x] Replace `FileRenamer.generate_episode_filename/4` with a call to `FileNamer.generate_episode_filename/4`
- [x] Update `generate_filename_from_path/2` to also use `FileNamer` (with parsed quality info from current filename as fallback)
- [x] Remove the now-unused private helpers (`get_quality_for_file/1`, `get_source_from_metadata/1`, old `sanitize_filename/1`)
- [x] Verify manual rename preview + confirm still works end-to-end

### Phase 4: Tests

- [x] Test `LibraryPath` changeset with `auto_rename` field
- [ ] Test that `MediaImport` respects `auto_rename: true` on the library path (generates TRaSH filename)
- [ ] Test that `MediaImport` respects `auto_rename: false` (keeps original filename)
- [x] Test `FileRenamer` consolidation — preview generates TRaSH-style names
- [x] Test quality info bridge — builds correct `QualityInfo` from `MediaFile` DB fields

## Out of Scope (deferred)

- Multi-episode file naming (S01E01E02) — `FileNamer` currently only accepts a single episode. Follow-up task.
- Subtitle/sidecar file renaming — known limitation, document separately
- Custom naming templates — brainstorm explicitly excluded this
- Unifying `sanitize_filename`/`sanitize_title` across all modules — worth doing but separate refactor
- HDR format specificity (`[DV HDR10]` vs `[HDR]`) — improvement to `FileNamer`, not blocking
- Rollback logic for orphaned files on DB failure during import — pre-existing issue, separate fix

## Dependencies & Risks

- **Low risk**: All infrastructure exists. This is primarily wiring and consolidation, not new logic.
- **Migration risk**: Mitigated by defaulting existing rows to `false`. New installs get `true`.
- **Consolidation risk**: `FileRenamer` tests don't exist currently. Manual testing of the rename modal is needed after consolidation. Add tests as part of Phase 4.

## Sources & References

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-03-25-auto-file-renaming-brainstorm.md](docs/brainstorms/2026-03-25-auto-file-renaming-brainstorm.md) — Key decisions: per-library-path config, TRaSH format as single standard, consolidate FileRenamer→FileNamer, default ON for new libraries.

### Internal References

- LibraryPath schema (pattern for boolean fields): `lib/mydia/settings/library_path.ex:39-62`
- MediaImport rename conditional: `lib/mydia/jobs/media_import.ex:854-889`
- FileNamer (target naming engine): `lib/mydia/library/file_namer.ex`
- FileRenamer (to be consolidated): `lib/mydia/library/file_renamer.ex`
- Admin UI toggle pattern: `lib/mydia_web/live/admin_config_live/components.ex:3266-3320`
- Migration pattern: `priv/repo/migrations/20251210013242_add_auto_import_to_library_paths.exs`
- QualityInfo struct: `lib/mydia/indexers/structs/quality_info.ex`
- FileNamer tests: `test/mydia/library/file_namer_test.exs`
