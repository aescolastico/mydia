# Auto File Renaming on Import

**Date:** 2026-03-25
**Status:** Ready for planning

## What We're Building

Automatic file renaming when media files are downloaded and imported into a library. Currently, imported files keep their original scene/release names (e.g., `The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv`). After this change, files will be automatically renamed to a clean, standardized TRaSH Guides format (e.g., `The Matrix (1999) [BluRay-1080p] [DTS-HD MA 5.1] [x264]-GROUP.mkv`).

This also includes folder organization — ensuring files land in the correct directory structure (`Show Title/Season 01/` for TV, `Title (Year)/` for movies).

## Why This Approach

**The infrastructure already exists but is disconnected:**

- `FileNamer` generates TRaSH Guides-compatible filenames but is never called during import (the `rename_files` arg is always `false` in `DownloadMonitor.enqueue_import_job`)
- `FileRenamer` handles post-import manual renaming via a UI button, but uses a simpler naming format
- `FileOrganizer` handles folder structure but is only used when `auto_organize` is enabled on the library path

**Consolidation opportunity:** Two naming modules (`FileNamer` and `FileRenamer`) serve the same purpose with different formats. Consolidating to a single TRaSH Guides format (from `FileNamer`) simplifies the codebase and ensures consistency between auto-rename on import and manual rename from the UI.

## Key Decisions

1. **Per-library-path configuration** — Each library path gets an `auto_rename` boolean field (default: `true`). This allows different policies for different libraries.

2. **TRaSH Guides naming format** — The consolidated naming scheme follows TRaSH standards, preserving quality metadata in filenames:
   - Movies: `{Title} ({Year}) [Source-Resolution] [Audio] [HDR] [Codec]-ReleaseGroup.ext`
   - TV: `{Title} ({Year}) - S##E## - {Episode Title} [Source-Resolution] [Audio] [HDR] [Codec]-ReleaseGroup.ext`

3. **Consolidate FileNamer + FileRenamer** — Use `FileNamer`'s TRaSH format as the single naming engine. Update `FileRenamer` (used by the manual rename UI) to delegate to `FileNamer` instead of having its own format logic.

4. **Rename + organize folders** — Auto-rename also ensures proper folder structure, not just filename. Leverages existing `FileOrganizer` logic.

5. **Default ON for new libraries** — New library paths have auto-rename enabled by default.

## Scope

### In Scope

- Add `auto_rename` field to `LibraryPath` schema (migration, default `true`)
- Wire `DownloadMonitor.enqueue_import_job` to pass the library path's `auto_rename` setting to `MediaImport`
- Activate the existing `FileNamer` code path in `MediaImport` when `rename_files: true`
- Consolidate `FileRenamer` to use `FileNamer`'s naming logic for manual renames
- Ensure folder organization works together with renaming
- Add UI toggle in library path settings

### Out of Scope

- Custom naming templates / user-defined formats
- Renaming already-imported files in bulk (existing manual rename button covers this)
- Rename-on-metadata-change (only on import)

## Existing Code Map

| Module | Role | Status |
|--------|------|--------|
| `FileNamer` | TRaSH-style name generation | Has code + tests, but never called in import pipeline |
| `FileRenamer` | Manual rename UI backend | Active, uses simpler format — needs consolidation |
| `FileOrganizer` | Folder structure placement | Active, used when `auto_organize` is enabled |
| `MediaImport` | Import job, checks `rename_files` arg | Has the conditional, but arg is always `false` |
| `DownloadMonitor` | Enqueues import jobs | Never sets `rename_files: true` |
| `LibraryPath` | Library config schema | Has `auto_organize` but no `auto_rename` field |
