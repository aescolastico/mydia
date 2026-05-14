---
title: "feat: Usenet improvements rollout (issues #119–#129)"
type: feat
status: completed
date: 2026-05-14
origin: getmydia/mydia#119
---

# feat: Usenet Improvements Rollout

## Overview

This plan ships all 10 open Usenet improvement issues tracked under getmydia/mydia#119 in a single coordinated rollout. The work is sized for parallel subagent dispatch with worktree isolation: 9 implementation units organised into 4 dependency-ordered waves, with U-IDs anchoring each unit so `ce-work` can dispatch them and track progress unambiguously.

The Usenet pipeline itself is **already production-ready** after `docs/plans/2026-04-08-fix-usenet-download-import-pipeline-plan.md` shipped. None of the work below fixes broken behavior — it closes feature-parity gaps versus Sonarr/Radarr and pays down some adapter duplication.

---

## Problem Statement

Mydia's Usenet support works end-to-end, but a coordinated set of gaps and polish items remain:

- **Indexer parsing**: `usenetdate` is extracted from Newznab XML and immediately dropped; `grabs` is misrepresented as `seeders`; Prowlarr emits 1000+ info-level log lines per search.
- **Release lifecycle**: failed downloads aren't blacklisted, so the next search picks them again; stalled downloads at 99% are polled forever with no circuit breaker.
- **Real-time signalling**: completion is polling-only (30s–5min latency); both clients can push via post-processing scripts but there's no endpoint to receive them.
- **Configuration depth**: one category per client, one hardcoded 3-tier priority mapping — users can't separate movies/TV on the same client or take advantage of finer priority tiers.
- **Code health**: SABnzbd (665 LOC) and NZBGet (517 LOC) duplicate state classification, size normalization, and queue+history merging. Adapter parsing tests skew heavily toward error paths.

(see origin: getmydia/mydia#119 — tracking issue with full theme breakdown)

---

## Scope and Issues Closed

| Wave | Unit | Issues closed |
|------|------|---------------|
| 1 | U1 | #120, #121, #125 |
| 2 | U2 | (foundation for #122, #124, #126, #129) |
| 2 | U3 | #124, #129 |
| 2 | U4 | #126 |
| 2 | U5 | #122 |
| 2 | U6 | (UI surface for U3, U4, U5) |
| 3 | U7 | #123 |
| 3 | U8 | #127 |
| 3 | U9 | #128 |

### Scope Boundaries

#### Non-goals (deferred to follow-up work)

- **Replacing polling entirely**: webhooks (#122 / U5) are additive. The poll loop stays as the source of truth and webhook fast-path is opportunistic.
- **Per-quality-profile priority** (#129 stretch): this plan delivers per-client priority profiles. Resolving priority by `Download.quality_profile_id` is explicitly out of scope.
- **New download client types** (e.g. additional NZB clients): not in scope.
- **Rewriting `MediaImport`**: its `save_path` fallback (shipped 2026-04-08) is well-tested. We only add idempotency guards.
- **Mock-sabnzbd / mock-nzbget Docker containers under a `usenet` profile**: the prior plan said it shipped this — it didn't (verified by directory listing). For *this* plan, all new tests use `Phoenix.ConnTest`, `Bypass`, and `Mox`. Building the container infra is deferred; if E2E coverage is desired later, it's a clean follow-up.
- **A real `:status` column on `downloads`**: `download_monitor.ex:184/226` already calls `update_download(..., %{status: "missing", ...})` and the `:status` key is silently dropped because it isn't cast. Adding a real column is tempting cleanup but outside the scope of the 10 issues. Note the bug; do not let scope creep absorb it.

---

## Pre-existing State and Correction Flags

Several issue bodies assumed columns or infrastructure that don't actually exist. The plan reflects what's *actually* in the codebase as of 2026-05-14:

1. **Download schema does not have `save_path`, `status`, `progress_pct`, `downloaded_bytes`, `content_type`, `indexer_id`, or `guid` columns.** `save_path` lives in `download.metadata["save_path"]` (JSON map). Any new persistent state in this plan must either (a) be added as a real column via migration, or (b) live in `metadata`. Plan calls out which approach each unit takes.
2. **Mock SABnzbd/NZBGet containers do not exist.** Only `test/mock_services/prowlarr/` and `test/mock_services/qbittorrent/` are present. `compose.test.yml` has no `usenet` profile. New tests in this plan use `Bypass` (already used by `usenet_import_integration_test.exs`) and `Phoenix.ConnTest` — no new containers required.
3. **`MediaImport` has no `unique:` Oban option today** and no early-return on `imported_at`. U5 adds both.
4. **The canonical state struct is `Mydia.Downloads.Structs.TorrentStatus`** with states `:downloading | :seeding | :paused | :checking | :queued | :error | :completed | :unknown`. U8 renames to `DownloadStatus` (already represents both modalities).
5. **The canonical state-classifier name is `parse_state/1`** in each adapter (not `state_from_status` as #127 implied).
6. **`usenetdate` is already extracted into the item map** at `lib/mydia/indexers/adapter/nzbhydra2.ex:267-269` but `parse_result_item/2` never reads `item.usenetdate`. The fix is to consume it.
7. **Filter-vs-rank convention**: per `docs/plans/2026-04-01-fix-duplicate-tv-show-downloads-plan.md`, pre-ranking filters live in callers (`process_episode_results`, `process_movie_results`) using `reject_*` naming. `ReleaseRanker` stays scoring-focused. U1 and U7 honor this.

---

## High-Level Technical Design

### Dependency graph

```
            ┌─────────────────────────────────────────────────────┐
Wave 1:     │ U1: Indexer parsing + NZB-aware ranking + log noise │
            └─────────────────────────────────────────────────────┘
                              │
            ┌─────────────────┴─────────────────┐
Wave 2:     │ U2: Schema foundation (1 migration)│
            └─────────────────┬─────────────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
            ┌─▼──┐         ┌──▼─┐          ┌──▼─┐
            │ U3 │         │ U4 │          │ U5 │
            │Queue│        │Stall│         │Webhook│
            │+adapters│    │detect│        │+idempotency│
            └─┬──┘         └──┬─┘          └──┬─┘
              └───────────────┼───────────────┘
                              │
                       ┌──────▼──────┐
                       │ U6: Admin UI │
                       │ unified pass │
                       └──────┬──────┘
                              │
              ┌───────────────┼───────────────┐
Wave 3:       │               │               │
            ┌─▼──┐         ┌──▼─┐
            │ U7 │         │ U8 │
            │Blacklist│    │Struct unify│
            │(needs U4)│   │(needs U3)│
            └─────┘         └──┬─┘
                               │
                            ┌──▼─┐
                            │ U9 │
                            │Adapter tests│
                            └────┘
```

*Directional guidance for the dependency graph above — this is intent, not literal CI gates. Implementer should treat each arrow as "the prior unit must merge to master before the next is dispatched."*

### Parallel dispatch waves

| Wave | Dispatch | Rationale |
|------|----------|-----------|
| **A** | U1 + U2 in parallel | No file overlap. U1 is indexer axis, U2 is download-client schema. |
| **B** | U3 + U4 + U5 in parallel after U2 merges | All depend on U2's schema columns. No file overlap among themselves (verified). |
| **C** | U6 alone after Wave B merges | Touches the admin form file that U3/U4/U5 all need to render. Sequencing it solo is cleaner than letting three parallel units conflict-resolve on one form. |
| **D** | U7 + U8 in parallel after U6 (U7 needs U4 in master; U8 needs U3 in master) | U7 touches `DownloadMonitor` (U4's territory) + search orchestrators (untouched elsewhere). U8 touches all adapters (U3's territory). No overlap between U7 and U8. |
| **E** | U9 alone after U8 merges | Tests fixtures must reflect U8's unified `DownloadStatus`. |

---

## Implementation Units

### U1. Indexer parsing + NZB-aware ranking + log noise (#120, #121, #125)

**Goal**: Stop dropping `usenetdate`, stop misrepresenting `grabs` as `seeders`, branch ranker scoring by protocol, add a configurable minimum post-age filter, and demote the four noisy Prowlarr `Logger.info` calls.

**Issues**: #120, #121, #125

**Dependencies**: none.

**Files**:
- Modify: `lib/mydia/indexers/search_result.ex`
- Modify: `lib/mydia/indexers/adapter/nzbhydra2.ex`
- Modify: `lib/mydia/indexers/adapter/prowlarr.ex`
- Modify: `lib/mydia/indexers/release_ranker.ex`
- Modify: `lib/mydia/settings/indexer_config.ex`
- Modify: `lib/mydia_web/live/admin_indexers_live/components.ex`
- Create: `priv/repo/migrations/{TIMESTAMP}_add_min_post_age_to_indexer_configs.exs`
- Test (modify): `test/mydia/indexers/release_ranker_test.exs`
- Test (modify): `test/mydia/indexers/adapter/nzbhydra2_test.exs`
- Test (modify): `test/mydia/indexers/adapter/prowlarr_test.exs`

**Approach**:

1. **`SearchResult` additions** — add four fields (all optional, default `nil`):
   - `usenet_date :: DateTime.t() | nil`
   - `nzb_completion :: float | nil` (0.0..1.0)
   - `nzb_grabs :: integer | nil`
   - (do **not** add `download_protocol` — it already exists at `search_result.ex` and is populated by all NZB adapters)
2. **NZBHydra2 parser** — `parse_result_item/2` already has `usenetdate` in the item map at `nzbhydra2.ex:267-269`; consume it into `usenet_date`. Where `grabs` is mapped to `seeders` (lines 297-302, 371), instead populate `nzb_grabs` and leave `seeders`/`leechers` as `nil` for NZB results. Parse `newznab:attr name="completion"` when present (some indexers expose it).
3. **Prowlarr parser** — demote `Logger.info` at lines 305, 316, 328 to `Logger.debug`. Parse `publishDate` into `usenet_date` when `download_protocol == :nzb`. Parse `completion` when the underlying indexer reports it (Prowlarr passes Newznab attrs through transparently).
4. **Ranker filter** — add `min_post_age_minutes` filter to `ReleaseRanker.filter_acceptable/2` (consistent with the existing `meets_seeder_minimum?/2` property-check pattern, not the orchestrator-level `reject_*` pattern). For NZB results with `usenet_date` more recent than `now - min_post_age_minutes`, exclude. Torrent results pass through unchanged.
5. **Ranker scoring** — in `SearchScorer.score_result_with_breakdown/2`, branch on `download_protocol`:
   - `:torrent` → existing `seeders`-based scoring (unchanged)
   - `:nzb` → use `nzb_completion` (default to 1.0 when unknown to avoid penalizing old indexers) + `nzb_grabs` as a tiebreaker
6. **`IndexerConfig` schema** — add `field :min_post_age_minutes, :integer` (nullable). Changeset: cast + `validate_number(:min_post_age_minutes, greater_than_or_equal_to: 0)` when not nil.
7. **Migration**: nullable integer column on `indexer_configs`. SQLite-safe (additive, no default needed).
8. **Admin indexers form** — add a `Min post age (minutes)` input, visible only when the indexer type supports NZB (`prowlarr`, `nzbhydra2`, `jackett` if NZB-capable). Follow the conditional-rendering pattern at `admin_indexers_live/components.ex:367-369` (`is_prowlarr` assign derived at top, then `<%= if @is_prowlarr do %>`).

**Patterns to follow**:
- `SearchResult.new/1` struct construction — `lib/mydia/indexers/search_result.ex`
- `ReleaseRanker.filter_acceptable/2` for the post-age filter — pure property check
- `meets_seeder_minimum?/2` for `nil` setting → no filtering
- Admin form conditional rendering — `admin_indexers_live/components.ex` lines 367-500
- Newznab attr parsing — existing `xpath` extractor in `nzbhydra2.ex:237`

**Execution note**: Test-first for the ranker filter and scoring branch — these are pure functions with clear input/output and the failing-test-first pattern keeps the branch logic honest.

**Test scenarios**:
- *Happy path*: NZBHydra2 fixture with `usenetdate` → `SearchResult.usenet_date` carries a `DateTime`.
- *Happy path*: NZBHydra2 fixture with `grabs="42"` → `nzb_grabs == 42`, `seeders == nil`, `leechers == nil`.
- *Happy path*: Prowlarr fixture with `downloadProtocol: "usenet"` and `publishDate` → `usenet_date` populated, `nzb_grabs` populated.
- *Edge*: NZB result with no `usenetdate` field → `usenet_date == nil`; ranker passes it through (no filter applied).
- *Edge*: NZB result with `usenet_date` exactly equal to `now - min_post_age_minutes` → not filtered (use strict `<` for "too recent").
- *Edge*: `min_post_age_minutes` is `nil` → no filtering at all, even for very fresh NZBs.
- *Filter*: NZB posted 5 minutes ago, `min_post_age_minutes = 30` → filtered out.
- *Filter*: NZB posted 60 minutes ago, `min_post_age_minutes = 30` → kept.
- *Filter*: Torrent with the same age → kept (filter is NZB-only).
- *Scoring*: NZB with `nzb_completion: 1.0, nzb_grabs: 5` outranks NZB with `nzb_completion: 0.6, nzb_grabs: 500`.
- *Scoring*: Torrent scoring is unchanged (regression — pin an existing scoring test).
- *Log demotion*: search against a Bypass-mocked Prowlarr server emits zero `:info`-level log lines for routine result parsing (capture log + assert).

**Verification**:
- `./dev mix test test/mydia/indexers/` is green.
- A manual search through the admin UI shows the new `Min post age (minutes)` field on a Prowlarr indexer and zero info-level log lines in `./dev logs -f`.
- `./dev mix ecto.migrate` runs and rolls back cleanly.

---

### U2. Wave-2 schema foundation (#122, #124, #126, #129 — additive columns only)

**Goal**: Land one migration with all wave-2 schema changes plus the `DownloadClientConfig` and `Download` schema updates. No behavior changes, no UI — pure data-model bedrock so U3/U4/U5 can build on top without colliding migrations.

**Issues**: foundation for #122, #124, #126, #129. None closed yet.

**Dependencies**: none.

**Files**:
- Create: `priv/repo/migrations/{TIMESTAMP}_add_usenet_improvement_columns.exs`
- Modify: `lib/mydia/settings/download_client_config.ex`
- Modify: `lib/mydia/downloads/download.ex`
- Test (modify): `test/mydia/settings/download_client_config_test.exs` (may need to create — verify existence)
- Test (modify): `test/mydia/downloads/download_test.exs` (may need to create — verify existence)

**Approach**:

1. **Migration** adds the following to `download_clients`:
   - `add :webhook_secret, :string` — nullable; populated on next save via changeset auto-generate (see below)
   - `add :categories, :map, default: %{}` — JSON map keyed by `Download.content_type` atom-as-string
   - `add :priority_profile, :map, default: %{}` — JSON map of 5-tier priority taxonomy → client-native string/int
   - `add :incomplete_grace_minutes, :integer, default: 60`
2. **Migration** also adds to `downloads`:
   - `add :last_progress_at, :utc_datetime_usec` — nullable
   - `add :last_known_bytes, :integer, default: 0`
3. **`DownloadClientConfig` schema** — add the four new fields. Changeset:
   - `cast` adds `:categories, :priority_profile, :incomplete_grace_minutes` (do **not** cast `:webhook_secret` — security-sensitive, generated server-side)
   - On insert, when `:webhook_secret` is nil, set it via `put_change(:webhook_secret, generate_secret())`. Use `:crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)`.
   - `validate_number(:incomplete_grace_minutes, greater_than: 0)` when present
   - **Do not** remove the existing `:category` string column. Keep it for backwards compatibility; mark as deprecated in `@moduledoc`. U3 will use `categories` map preferentially, falling back to `category` when the map is empty.
4. **`Download` schema** — add `:last_progress_at` and `:last_known_bytes` fields. Cast both. No validation needed.
5. **No `@type t`** changes mandated, but if the implementer wants to add `@type t :: %__MODULE__{...}` to these schemas (which are missing it per institutional research), that's a free win.

**Patterns to follow**:
- Existing migration shape — see `priv/repo/migrations/20260326000000_add_match_status_to_downloads.exs` for an additive column on `downloads`.
- `connection_settings :: map` on the same `download_clients` table for prior-art on JSON map columns — `download_client_config.ex` field declaration.
- Changeset `put_change` for server-side generated secrets — look for any existing token/secret generation pattern in `lib/mydia/`.

**Execution note**: not test-first — this is a pure schema additive change with no behavior. Tests assert column existence and the secret-generation invariant.

**Test scenarios**:
- *Happy path*: `Settings.create_download_client_config(%{name: "sab", type: :sabnzbd, ...})` returns a config with a non-nil `webhook_secret` ≥ 32 chars.
- *Happy path*: Inserting with `categories: %{"movie" => "movies", "tv" => "tv"}` round-trips through Ecto correctly.
- *Edge*: Updating an existing config with no `webhook_secret` causes one to be generated on next save (changeset `put_change` covers nil → generate path).
- *Edge*: `incomplete_grace_minutes` defaults to 60 when not provided.
- *Edge*: A pre-existing download row with `last_progress_at = nil` and `last_known_bytes = 0` is queryable (migration default works).
- *Error path*: `incomplete_grace_minutes: -1` fails validation.

**Verification**:
- `./dev mix ecto.migrate` runs cleanly; rollback runs cleanly.
- `./dev mix test test/mydia/settings/` and `./dev mix test test/mydia/downloads/download_test.exs` green.
- A SQLite shell check: `.schema download_clients` shows all four new columns; `.schema downloads` shows the two new columns.

---

### U3. Queue submission: per-content-type categories + priority profile (#124, #129)

**Goal**: Route categories by content type at submission time, and pass a 5-tier priority atom through to adapters which resolve it via each client's `priority_profile` map. All six adapters updated.

**Issues closed**: #124, #129

**Dependencies**: U2.

**Files**:
- Create: `lib/mydia/downloads/priority.ex`
- Modify: `lib/mydia/downloads/queue.ex`
- Modify: `lib/mydia/downloads/client/sabnzbd.ex`
- Modify: `lib/mydia/downloads/client/nzbget.ex`
- Modify: `lib/mydia/downloads/client/qbittorrent.ex`
- Modify: `lib/mydia/downloads/client/transmission.ex`
- Modify: `lib/mydia/downloads/client/rtorrent.ex`
- Modify: `lib/mydia/downloads/client/blackhole.ex` (priority is no-op for blackhole; document)
- Test (modify): `test/mydia/downloads/queue_test.exs` (may need to create if absent — verify)
- Test (modify): per-adapter test files for priority/category mapping

**Approach**:

1. **`Mydia.Downloads.Priority`** — new module defining the 5-tier taxonomy:
   ```
   :verylow | :low | :normal | :high | :veryhigh
   ```
   Constants: `Priority.all/0`, `Priority.default/0` (`:normal`).
2. **`Mydia.Downloads.Queue.select_and_add_to_client/2`** — derive `content_type` from the `Download` record:
   - if `download.episode_id != nil` → `"tv"`
   - else if `download.media_item_id != nil` and `MediaItem.type == :movie` → `"movie"`
   - else → fall back to `:download_protocol` from `search_result` → `"tv"`/`"movie"` per existing detection
   (Use a private helper `resolve_content_type/1` so future content types can be added in one place.)
3. **`Queue.add_torrent_to_client_with_input/4`** — extend the opts construction at `queue.ex:607`:
   - `:category` resolved as `client_config.categories[content_type] || client_config.category || nil` (backwards compat: empty map falls back to the legacy single-field).
   - `:priority` resolved as `Priority.default/0` for now. Future hook (deferred): per-quality-profile resolution.
4. **Adapter behaviour** — `add_torrent/3` already accepts `opts`. Extend each adapter's option handling:
   - **SABnzbd** (`sabnzbd.ex` ~lines 130–216 and `parse_state/1` neighborhood for `do_add_nzb`): look up `opts[:priority]` (a `Priority` atom) in `client_config.priority_profile`. Fall back to today's hardcoded mapping (`:low → "-1" | :normal → "0" | :high → "1"`) when the profile is empty. Add `:verylow → "-100"` and `:veryhigh → "2"` (SABnzbd's actual range is `-100..2`).
   - **NZBGet** (`nzbget.ex` ~lines 128-142, `parse_state/1` at 470): same shape. Today's `:low → -50 | :normal → 0 | :high → 50`. Extend to `:verylow → -100, :veryhigh → 100`. Validator: integer only.
   - **qBittorrent, Transmission, rTorrent**: today these may not pass priority through. Add the look-up but allow `priority_profile` to be empty (no-op default). Document the per-client value range in `@moduledoc`.
   - **Blackhole**: priority is a no-op (filesystem drop has no queue). Document this; do not pass priority.
5. **Backwards compatibility**: a client created before this migration has `priority_profile: %{}` and `categories: %{}`. The lookups must fall back to the hardcoded today-mappings (priority) and the legacy `:category` string (categories). Existing behavior preserved by default.

**Patterns to follow**:
- Existing per-adapter `do_add_torrent/2` shapes (already accept `opts`).
- The `client_config.category || nil` pattern at `queue.ex:607` for "use this or fall back."
- `Mydia.Downloads.Client` behaviour at `lib/mydia/downloads/client.ex` — keep signatures stable; this unit extends opts, not behaviour callbacks.

**Execution note**: test-first for the per-adapter priority lookup — small pure function on each adapter, makes a clean red-green pair.

**Test scenarios**:
- *Happy path*: a movie download submitted to a SABnzbd client with `categories: %{"movie" => "movies"}` → SABnzbd `add_torrent` receives `category: "movies"`.
- *Happy path*: a TV episode submitted to the same client with `categories: %{"tv" => "tv"}` → receives `category: "tv"`.
- *Backwards compat*: a client with `categories: %{}` and legacy `category: "all"` → both movie and TV submissions receive `category: "all"`.
- *Backwards compat*: a client with `priority_profile: %{}` → SABnzbd `:high` resolves to `"1"`, NZBGet `:high` resolves to `50` (today's behavior preserved).
- *Edge*: a client with `priority_profile: %{"high" => "2"}` → SABnzbd `:high` resolves to `"2"`, falls back to today's mapping for other atoms.
- *Edge*: blackhole client with priority set → priority is silently ignored (no error).
- *Edge*: `Priority.all/0 |> Enum.each(&assert &1 in [:verylow, :low, :normal, :high, :veryhigh])` (regression guard against accidental atom additions).
- *Error path*: invalid priority profile value rejected by changeset (SABnzbd: must parse as integer in `-100..2`; NZBGet: any integer).

**Verification**:
- `./dev mix test test/mydia/downloads/` is green.
- Manual: create a SABnzbd client with `categories: %{"movie" => "movies", "tv" => "tv"}`, submit a movie + a TV episode, verify in SABnzbd UI that they landed in different categories.

---

### U4. Stall detection in DownloadMonitor (#126)

**Goal**: Detect downloads that have made no progress for longer than the client's `incomplete_grace_minutes` and transition them to `:error`. Surface "stalled" state in the downloads UI.

**Issues closed**: #126

**Dependencies**: U2.

**Files**:
- Modify: `lib/mydia/jobs/download_monitor.ex`
- Modify: `lib/mydia_web/live/downloads_live/index.ex` (or its sibling `index.html.heex`)
- Test (modify): `test/mydia/jobs/download_monitor_test.exs` (verify existence)
- Test (create or modify): `test/mydia/jobs/usenet_import_integration_test.exs` — add stalled-flow describe block

**Approach**:

1. **`DownloadMonitor.perform/1`** — on each poll, when a download's `:downloading` or `:checking` state is observed:
   - Read `client_status.downloaded_bytes` (already on `TorrentStatus`).
   - If `client_status.downloaded_bytes > download.last_known_bytes`, update `last_progress_at: now()` and `last_known_bytes: client_status.downloaded_bytes`.
   - Else if `client_status.downloaded_bytes == download.last_known_bytes` and `(now - download.last_progress_at) > grace_minutes_for(download.download_client_id)`:
     - Log structured event: `download_id, client, last_progress_at, downloaded_bytes`.
     - Optionally call adapter's `remove_torrent/3` (configurable per-client setting? — out of scope; just log a TODO).
     - Mark `import_failed_at: now()`, `import_last_error: "stalled after #{grace_minutes}m without progress"`.
     - **Do not** call `update_download(..., %{status: "stalled"})` — `:status` is not cast on `Download` (known bug, out of scope). Use `import_failed_at` as the signal.
   - On terminal states (`:completed`, `:error`), no progress tracking needed.
2. **Grace resolution** — helper: `grace_minutes_for(download_client_id)` reads `client_config.incomplete_grace_minutes` (defaults to 60 from migration). Cache per poll (the monitor already loads all clients).
3. **Downloads LiveView** — in `downloads_live/index.html.heex`, derive a stalled indicator:
   - If `download.import_failed_at != nil` and `download.import_last_error =~ "stalled"` → render with a yellow `badge` ("Stalled") instead of a green one.
   - Wrap the existing badge-rendering helper.

**Patterns to follow**:
- `DownloadMonitor.handle_completion/1` and `handle_failure/1` for state-transition patterns.
- The async health-check pattern noted in research (use structured logging, `MydiaLogger.extract_error_message/1` for any error messages surfaced to the user).
- DaisyUI `badge` classes already used in the downloads LiveView.

**Execution note**: test-first for the time-based transition — easy to write a failing test with a stubbed `now()` (or use a `time_provider` injection).

**Test scenarios**:
- *Happy path*: a download with `downloaded_bytes: 100MB` is observed at 200MB → `last_progress_at` updates, `last_known_bytes: 200_000_000`.
- *Happy path*: a download with `downloaded_bytes: 200MB` observed again at 200MB after 5 minutes → no change (state unchanged).
- *Stall trigger*: a download stuck at 200MB for `grace + 1 minute` → `import_failed_at` set, `import_last_error` matches `"stalled"`.
- *Edge*: a fresh download with `last_progress_at = nil` and `last_known_bytes = 0` observed at 0 → initialize `last_progress_at: now()`, do not flag as stalled.
- *Edge*: `incomplete_grace_minutes` exactly elapsed → not yet stalled (use strict `>`, not `>=`).
- *Edge*: download already in `:completed` state → no progress tracking, no false stall.
- *Integration*: stub `Mydia.Downloads.ClientMock` to return constant `downloaded_bytes` for `grace + 2 minutes` of simulated time → `Downloads.get_download!/1` shows `import_failed_at` populated.
- *Negative*: simulated frozen progress for `grace - 1 minute` → not stalled (regression guard).

**Verification**:
- `./dev mix test test/mydia/jobs/download_monitor_test.exs` is green.
- Manual: in dev, pause a real NZB download mid-flight, wait `grace_minutes`, observe the LiveView badge flip to "Stalled" and the log lines.

---

### U5. Webhook receiver + MediaImport idempotency (#122)

**Goal**: Accept SABnzbd notification-script and NZBGet pp-script POSTs to trigger `MediaImport` immediately; make `MediaImport` idempotent so polling and webhook racing is a no-op.

**Issues closed**: #122

**Dependencies**: U2.

**Files**:
- Create: `lib/mydia_web/controllers/api/webhook/usenet_controller.ex`
- Create: `lib/mydia_web/plugs/webhook_secret_auth.ex`
- Modify: `lib/mydia_web/router.ex`
- Modify: `lib/mydia/jobs/media_import.ex`
- Modify: `lib/mydia/downloads.ex` (add lookup helper if absent: `get_download_by_client_and_remote_id/2`)
- Test (create): `test/mydia_web/controllers/api/webhook/usenet_controller_test.exs`
- Test (modify): `test/mydia/jobs/media_import_test.exs` — add idempotency describe block

**Approach**:

1. **Router** — new scope outside `:browser` and `:api_auth`:
   ```
   scope "/api/webhooks", MydiaWeb.Api.Webhook do
     pipe_through [:api]
     post "/usenet/:client_id", UsenetController, :completed
   end
   ```
   Pipeline `:api` already exists in the router; do not chain `:api_auth` (webhooks authenticate by per-client signed secret).
2. **`WebhookSecretAuth` plug** — reads `?secret=...` query param OR `X-Mydia-Webhook-Secret` header, looks up `DownloadClientConfig` by `:client_id` path param, constant-time compares secrets. On failure: 401 with empty body.
3. **`UsenetController.completed/2`** — parse request body. Detect payload shape by header / param:
   - SABnzbd notification script POSTs JSON or form-encoded with keys like `name`, `nzo_id`, `status`, `storage`.
   - NZBGet pp-script POSTs (technically env vars in script, but typical bridge scripts POST a JSON envelope) with keys like `NZBID`, `NZBName`, `DestDir`, `Status`.
   - Branch on `?client=sabnzbd` query param OR `User-Agent`. Document the expected payload shape in `@moduledoc`.
4. **Download lookup** — `Mydia.Downloads.get_download_by_client_and_remote_id(client_id, remote_id)` returns the `Download` row whose `download_client_id == remote_id` and `download_client.id == client_id`. The unique index `[:download_client, :download_client_id]` makes this fast.
5. **Enqueue `MediaImport`** — call `MediaImport.new(%{"download_id" => download.id}) |> Oban.insert/1`. With idempotency via `unique:` (below), duplicate triggers are deduplicated by Oban.
6. **`MediaImport` idempotency** — at `media_import.ex:20-22`:
   - Add `unique: [period: 600, keys: [:download_id], states: [:available, :scheduled, :executing, :retryable]]` to the `use Oban.Worker` opts. Pattern from `lib/mydia/jobs/import_list_sync.ex:20`.
   - In `perform/1`, immediately after `Downloads.get_download!/1`: `if download.imported_at, do: :ok` — short-circuit re-imports. Below this guard, the existing snooze-loop machinery stays in place.
7. **Response** — always `200 OK` with empty body on valid auth + valid payload. `400` for malformed payload. `404` for unknown client. `401` for bad secret. Errors logged at `:warning`.

**Patterns to follow**:
- Router scope shape — `MydiaWeb.Router` (read for existing scope/pipeline conventions).
- `use Oban.Worker, unique: [...]` — `lib/mydia/jobs/import_list_sync.ex:20`.
- Plug pattern — search `lib/mydia_web/plugs/` (or `lib/mydia_web/auth/` if plugs live there).
- Conn → JSON response — existing controllers under `lib/mydia_web/controllers/api/`.

**Execution note**: test-first for the controller — `Phoenix.ConnTest` makes the auth + payload-parsing path easy to nail down before implementation.

**Test scenarios**:
- *Happy path SABnzbd*: `POST /api/webhooks/usenet/:id?secret=valid` with SABnzbd-shaped JSON body → 200, `MediaImport` job enqueued with `download_id`.
- *Happy path NZBGet*: same with `?client=nzbget` query and NZBGet-shaped JSON → 200, job enqueued.
- *Auth fail*: invalid secret → 401, no job enqueued (assert via `Oban.Testing.assert_enqueued/1`).
- *Auth fail*: missing secret → 401.
- *Unknown client*: `client_id` doesn't exist in DB → 404.
- *Idempotency racing webhook*: same payload posted twice in quick succession → only one `MediaImport` job enqueued (Oban `unique:` dedupes).
- *Idempotency racing poll + webhook*: monitor enqueues a `MediaImport` job; webhook fires 100ms later; only one job runs.
- *Already imported*: download with `imported_at != nil` → controller still enqueues; `perform/1` short-circuits with `:ok` immediately (no work done).
- *Malformed payload*: empty body → 400.
- *Constant-time comparison*: using `Plug.Crypto.secure_compare/2` for secrets, not `==`.

**Verification**:
- `./dev mix test test/mydia_web/controllers/api/webhook/` is green.
- Manual: configure a real SABnzbd notification script pointing at `http://mydia:4000/api/webhooks/usenet/:client_id?secret=...`, complete a small NZB, observe `MediaImport` enqueued within 1 second.

---

### U6. Admin form unified rewrite (#122, #124, #126, #129 UI surface)

**Goal**: One coherent pass on the download-clients admin form surfacing all four wave-2 features. Sequencing this after U3/U4/U5 lets the implementer design the form holistically rather than collide three parallel branches on the same file.

**Issues closed**: UI portion of #122, #124, #126, #129.

**Dependencies**: U3, U4, U5.

**Files**:
- Modify: `lib/mydia_web/live/admin_download_clients_live/index.ex`
- Modify: `lib/mydia_web/live/admin_download_clients_live/index.html.heex` (if separate)
- Modify: `lib/mydia_web/live/admin_download_clients_live/components.ex`
- Test (modify): `test/mydia_web/live/admin_download_clients_live_test.exs` (verify existence)

**Approach**:

1. **Per-content-type category inputs** (#124) — replace the single `<.input field={@form[:category]}>` with three labeled inputs:
   - `categories[movie]`, `categories[tv]`, `categories[music]`
   - Use the nested-form-name pattern at `admin_download_clients_live/components.ex:263-289` (already used for blackhole `connection_settings`).
   - Show only for NZB and torrent clients (hide for blackhole).
2. **Priority profile** (#129) — collapsed advanced section using `<details class="collapse collapse-arrow">`:
   - Five inputs for `:verylow, :low, :normal, :high, :veryhigh` → client-native string/int.
   - Placeholder values show the today-default per client type (`SABnzbd: "-100"/"-1"/"0"/"1"/"2"`, `NZBGet: "-100"/"-50"/"0"/"50"/"100"`).
   - Only shown for SABnzbd, NZBGet, qBittorrent, Transmission, rTorrent. Blackhole hides this entirely.
3. **`incomplete_grace_minutes` input** (#126) — single `<.input type="number" field={@form[:incomplete_grace_minutes]} label="Stalled timeout (minutes)" placeholder="60">`. Visible for all client types.
4. **Webhook URL + script snippet** (#122) — for SABnzbd and NZBGet only:
   - Render the full URL: `https://${host}/api/webhooks/usenet/${client.id}?secret=${client.webhook_secret}`.
   - Render a copy-pasteable post-processing script snippet per client type (small `<pre>` block, `phx-no-curly-interpolation` annotation if using bash heredoc).
   - "Copy" button using a `Hook` (`assets/js/hooks/copy_to_clipboard.js` if a similar hook exists; otherwise inline a small `phx-click` handler).
   - Show only after the client is saved (webhook_secret exists). For new clients, show a hint: "Save the client to reveal the webhook URL."
5. **Form change validation** — every new field plumbed through the `changeset/2` call from `handle_event("validate_download_client", ...)`. Nested `categories` map fields parsed from form params: `params["download_client_config"]["categories"] = %{"movie" => ..., "tv" => ...}`.

**Patterns to follow**:
- `admin_download_clients_live/components.ex` `download_client_modal/1` (line 156) for the form shape.
- The nested-form pattern at lines 263-289 (`name="download_client_config[connection_settings][watch_folder]"`) for `categories` and `priority_profile`.
- DaisyUI `<details class="collapse collapse-arrow">` for the advanced section.
- `Phoenix.HTML.Form.input_value/2` for deriving conditional render flags at the top of the function.

**Execution note**: not strict TDD — form testing in LiveView benefits more from happy-path-first then regression coverage. Test via `Phoenix.LiveViewTest.render_change/2` and `render_submit/2`.

**Test scenarios**:
- *Happy path*: submitting the form with `categories[movie]=movies, categories[tv]=tv` saves the map.
- *Happy path*: priority profile values save round-trip.
- *Conditional render*: a SABnzbd client form shows the webhook URL section; a qBittorrent client form does not.
- *Conditional render*: a blackhole client form shows neither categories nor priority profile.
- *Empty state*: a new SABnzbd client (not yet saved) shows the "Save the client to reveal the webhook URL" hint, not a broken URL.
- *Form validation*: submitting `incomplete_grace_minutes=-5` shows an inline validation error.
- *Backwards compat*: an existing client with legacy `category: "all"` and empty `categories: %{}` shows "all" in the per-content-type inputs (read-only? or all three pre-filled with "all"?) — decide during implementation; document the choice.

**Verification**:
- `./dev mix test test/mydia_web/live/admin_download_clients_live_test.exs` green.
- Manual: open the admin UI, click "Edit" on a SABnzbd client, verify all four new sections render correctly and save round-trips.

---

### U7. Release blacklist (#123)

**Goal**: When a download enters `:error`, write a row to `release_blacklist`. Filter blacklisted releases out of future search results in the orchestrators (not in `ReleaseRanker`). Admin LiveView for inspection and manual removal.

**Issues closed**: #123

**Dependencies**: U4 (DownloadMonitor changes in master).

**Files**:
- Create: `priv/repo/migrations/{TIMESTAMP}_create_release_blacklist.exs`
- Create: `lib/mydia/downloads/release_blacklist.ex` (schema)
- Create: `lib/mydia/downloads/blacklists.ex` (context functions: `add/4`, `blacklisted?/2`, `list/1`, `remove/1`, `cleanup_expired/0`)
- Modify: `lib/mydia/jobs/download_monitor.ex` — `handle_failure/1` writes a blacklist row
- Modify: `lib/mydia/jobs/tv_show_search.ex` (or wherever `process_episode_results/4` lives — verify path) — add `reject_blacklisted/2` step
- Modify: `lib/mydia/jobs/movie_search.ex` — same `reject_blacklisted/2` step
- Modify: `lib/mydia/config/schema.ex` — add `release_blacklist_default_ttl_days :: integer` (default 30)
- Create: `lib/mydia_web/live/admin_release_blacklist_live/index.ex`
- Create: `lib/mydia_web/live/admin_release_blacklist_live/index.html.heex`
- Modify: `lib/mydia_web/router.ex` — register the new admin route in `live_session :admin`
- Test (create): `test/mydia/downloads/blacklists_test.exs`
- Test (modify): `test/mydia/jobs/download_monitor_test.exs` — assert blacklist row on failure
- Test (create): `test/mydia_web/live/admin_release_blacklist_live_test.exs`

**Approach**:

1. **Schema** — `release_blacklist` table:
   - `indexer :: string` (matches `SearchResult.indexer`)
   - `guid :: string` (matches `SearchResult.metadata["guid"]` or a hash if guid isn't stable — see decision below)
   - `title :: string` (for admin UI)
   - `failure_reason :: string` (e.g., `"par2_failed"`, `"client_reported_failure"`, `"stalled"`)
   - `expires_at :: utc_datetime_usec` nullable (null = forever)
   - `inserted_at`
   - Unique index on `(indexer, guid)` to prevent duplicates.
2. **Guid decision** — `Download` has no `guid` or `indexer_id` columns (verified). The release's stable identifier must be plumbed from `search_result.metadata["guid"]` through `Download.metadata`. At download creation (`Queue.add_torrent_to_client_with_input` or upstream), copy `search_result.indexer` and `search_result.metadata["guid"]` into `Download.metadata["indexer"]` and `Download.metadata["guid"]`. Read from there on failure. If guid is missing, use a hash of `(indexer, title, size)` as a fallback — document this.
3. **Producer** — in `DownloadMonitor.handle_failure/1`, after the existing delete logic (or after marking the download), call `Blacklists.add(indexer, guid, title, reason)`. Default `expires_at: now + release_blacklist_default_ttl_days`.
4. **Consumer** — per the institutional learning ("filter, don't rank"), add `reject_blacklisted/2` in `TvShowSearch.process_episode_results/4` and `MovieSearch.process_movie_results/N`. Use the existing `reject_*` pipeline pattern. Each rejection logs at `:info` with the `(indexer, guid)` pair for debuggability.
5. **TTL cleanup** — new Oban worker (or piggyback on an existing periodic worker) `Mydia.Jobs.BlacklistCleanup` that deletes rows where `expires_at < now`. Schedule daily via cron.
6. **Admin LiveView** — `/admin/release-blacklist`:
   - Paginated list of rows, ordered by `inserted_at desc`.
   - "Block forever" action sets `expires_at: nil`.
   - "Remove" action deletes the row (instant un-blacklist).
   - Filter by `failure_reason`.
   - DaisyUI `table` component for layout.

**Patterns to follow**:
- Migration shape — match recent migrations under `priv/repo/migrations/`.
- `reject_*` filter pattern — `lib/mydia/indexers/release_ranker.ex` (`reject_tv_releases_for_movies/1`, `reject_title_mismatches/1`).
- Admin LiveView shape — `lib/mydia_web/live/admin_download_clients_live/index.ex` for layout, `<Layouts.app>` wrapper, `on_mount: [{MydiaWeb.UserAuth, :ensure_admin}]`.
- DaisyUI `table table-zebra` for tabular display.
- Periodic Oban worker — `lib/mydia/jobs/import_list_sync.ex` for cron-scheduled patterns.

**Execution note**: test-first for the blacklist context (`Blacklists.add/4`, `blacklisted?/2`) — pure functions on the DB layer, small surface, fits TDD cleanly.

**Test scenarios**:
- *Happy path*: `Blacklists.add("nzbhydra2", "abc123", "Show.S01E01", "par2_failed")` inserts a row.
- *Happy path*: `Blacklists.blacklisted?("nzbhydra2", "abc123")` returns `true` when an active row exists.
- *Happy path*: `Blacklists.blacklisted?("nzbhydra2", "abc123")` returns `false` when `expires_at < now`.
- *Happy path*: `Blacklists.blacklisted?("nzbhydra2", "abc123")` returns `true` when `expires_at = nil`.
- *Edge*: inserting a duplicate `(indexer, guid)` updates `failure_reason` and `expires_at` instead of erroring (upsert).
- *Integration*: a simulated download failure → blacklist row exists → next search excludes the release.
- *Integration (negative)*: a non-blacklisted release passes through `reject_blacklisted/2` unchanged.
- *TTL*: rows with `expires_at < now` deleted by `BlacklistCleanup` job.
- *Admin UI*: list view paginates correctly; "Block forever" sets `expires_at: nil`; "Remove" deletes the row.
- *Edge*: blacklist guard works for both `indexer` matches — case-sensitive or normalized? — pick normalized (lowercase) to avoid `Prowlarr` vs `prowlarr` mismatches.

**Verification**:
- `./dev mix test test/mydia/downloads/blacklists_test.exs` green.
- Manual: trigger a download failure in dev, observe a blacklist row appear, re-run search, observe the release is filtered out.

---

### U8. Unify DownloadStatus struct + extract shared helpers (#127)

**Goal**: Rename `TorrentStatus` → `DownloadStatus`. Extract `parse_size_mb_to_bytes/1`, `parse_size_bytes/1`, `parse_timestamp_unix/1` into `Mydia.Downloads.Client.Helpers`. All six adapters route through the shared struct and helpers. State classifiers stay per-adapter (state strings are client-specific) but their output uses the shared taxonomy.

**Issues closed**: #127

**Dependencies**: U3 (priority changes in adapters already merged).

**Files**:
- Rename + modify: `lib/mydia/downloads/structs/torrent_status.ex` → `lib/mydia/downloads/structs/download_status.ex` (rename module `TorrentStatus` → `DownloadStatus`)
- Create: `lib/mydia/downloads/client/helpers.ex`
- Modify: `lib/mydia/downloads/client.ex` (behaviour module — update callback specs to reference `DownloadStatus`)
- Modify all 6 adapters: `sabnzbd.ex, nzbget.ex, qbittorrent.ex, transmission.ex, rtorrent.ex, blackhole.ex`
- Modify: `lib/mydia/downloads/history.ex` (uses `TorrentStatus` per research)
- Modify: `lib/mydia/downloads/queue.ex` (references `save_path` from status)
- Grep for `TorrentStatus` and update all call sites (compile-time error otherwise)
- Modify all adapter tests for the renamed struct

**Approach**:

1. **Rename file + module** — `lib/mydia/downloads/structs/torrent_status.ex` → `download_status.ex`. Module `Mydia.Downloads.Structs.TorrentStatus` → `Mydia.Downloads.Structs.DownloadStatus`. Fields unchanged.
2. **Backwards-compat alias** — add `defmodule Mydia.Downloads.Structs.TorrentStatus, do: defdelegate ...` ? No — internal-only module, no external deps. Hard rename + update all call sites in one commit.
3. **Helpers module** — `Mydia.Downloads.Client.Helpers` with:
   - `parse_size_mb_to_bytes(value)` — handles string/int/nil, multiplies by 1_048_576.
   - `parse_size_bytes(value)` — handles string/int/nil.
   - `parse_timestamp_unix(value)` — handles string/int Unix epoch → `DateTime`.
4. **Adapter consolidation** — for each adapter, replace inline implementations of size and timestamp parsing with calls to `Helpers.*`. State classifier (`parse_state/1`) stays in each adapter because state strings differ per client, but each returns the shared taxonomy from `DownloadStatus.@state_values`.
5. **State taxonomy** — confirm taxonomy from `download_status.ex:29`: `:downloading | :seeding | :paused | :checking | :queued | :error | :completed | :unknown`. Add a module attribute `@state_values` and document each:
   - `:downloading` — receiving data
   - `:seeding` — torrent only; post-completion upload
   - `:paused` — manually paused
   - `:checking` — verifying/repairing/unpacking (NZB Extracting/Moving lands here per the 2026-04-08 fix)
   - `:queued` — waiting to start
   - `:error` — terminal failure
   - `:completed` — terminal success
   - `:unknown` — fallback
6. **Behaviour contract** — `Mydia.Downloads.Client` callback `@spec`s reference `DownloadStatus.t/0` and `ClientInfo.t/0`. Add `@type t :: %__MODULE__{...}` to `DownloadStatus` and `ClientInfo` while touching them (institutional research flagged this gap).
7. **No behavior change** — all existing tests must stay green. This is mechanical.

**Patterns to follow**:
- Existing `Mydia.Downloads.Structs` module shape.
- Existing per-adapter `parse_state/1` shape — keep, just ensure return value is in `@state_values`.
- Look for any helper module already in `lib/mydia/downloads/` for the conventional name/location.

**Execution note**: characterization-first — before refactoring, the adapter tests serve as the regression net. Run them, confirm green, then refactor in place. Do not add new tests in this unit — that's U9.

**Test scenarios**: (no new scenarios — preservation only)
- *Regression*: all of `./dev mix test test/mydia/downloads/client/` stays green throughout the refactor.
- *Integration*: `test/mydia/jobs/usenet_import_integration_test.exs` stays green (uses `TorrentStatus` indirectly via real adapter calls).
- *Behaviour conformance*: each adapter's `get_status/2` returns a `%DownloadStatus{}` and never a raw map.

**Verification**:
- All adapter tests + integration tests green.
- `grep -rn TorrentStatus lib/ test/ | wc -l` returns 0 after the rename (or only references in a comment explaining the rename).
- Each adapter is ~50–100 LOC shorter than before (size + timestamp duplication removed).

---

### U9. Adapter parsing/state-mapping unit tests with frozen fixtures (#128)

**Goal**: Round out adapter unit test coverage with frozen JSON/XML fixtures and table-driven state-mapping tests. Catches the class of subtle mis-mapping the integration test can't see.

**Issues closed**: #128

**Dependencies**: U8 (fixtures and tests reference `DownloadStatus`).

**Files**:
- Modify: `test/mydia/downloads/client/sabnzbd_test.exs`
- Modify: `test/mydia/downloads/client/nzbget_test.exs`
- Modify: `test/mydia/indexers/adapter/prowlarr_test.exs`
- Create: `test/support/fixtures/sabnzbd/queue.json`
- Create: `test/support/fixtures/sabnzbd/history.json`
- Create: `test/support/fixtures/nzbget/listgroups.json`
- Create: `test/support/fixtures/nzbget/history.json`
- Create: `test/support/fixtures/prowlarr/nzb_results.xml`
- Create: `test/support/fixtures/prowlarr/mixed_protocol_results.xml`

**Approach**:

1. **SABnzbd fixtures** — capture realistic queue and history JSON from a live SABnzbd or vendor docs. Include:
   - Multi-item queue with varied states (`Downloading`, `Paused`, `Queued`, `Verifying`, `Extracting`, `Moving`).
   - History with multiple terminal states (`Completed`, `Failed`).
   - Test asserts the full list parses into `[%DownloadStatus{}]` matching expected fields (id, name, size, downloaded, state, progress).
2. **NZBGet fixtures** — same shape for `listgroups` JSON-RPC response and `history` response. Include `DOWNLOADING, PP_QUEUED, VERIFYING, REPAIRING, UNPACKING, MOVING, SUCCESS, FAILURE`.
3. **Prowlarr fixtures** — two new XML fixtures:
   - NZB-only response (Newznab XML with `downloadProtocol: "usenet"`).
   - Mixed-protocol response (both `usenet` and `torrent` items in one XML).
4. **Table-driven state mapping** — one parameterized test per adapter:
   ```
   for {client_state, expected_internal} <- @state_table do
     assert ClientAdapter.parse_state(client_state) == expected_internal
   end
   ```
   Covering every documented state including the Extracting/Moving → `:checking` correction from the 2026-04-08 fix.
5. **ETA parsing edge cases (SABnzbd)** — `parse_state/1`'s neighbor `parse_eta/1`-equivalent: zero (`"0:00:00"`), large (`"99:59:59"`), malformed (`""` or `"-"` or `"unknown"`).
6. **Computed ETA (NZBGet)** — given `RemainingSizeMB` and `DownloadRate`, assert ETA computes correctly. Cover divide-by-zero (no rate → ETA nil or `:infinity`).
7. **Protocol detection priority (Prowlarr)** — explicit `downloadProtocol` field wins over `.nzb` URL heuristic. Add a fixture row where these conflict.

**Patterns to follow**:
- Existing `Bypass`-based tests in `test/mydia/downloads/client/sabnzbd_test.exs` for HTTP shape.
- Read fixtures via `File.read!(Path.expand("../../support/fixtures/...", __DIR__))`.
- Existing NZBHydra2 XML parsing test for the fixture-read pattern.

**Execution note**: not strict TDD here — this is coverage extension on stable code post-U8. Write tests, verify they catch realistic mis-mappings, ship.

**Test scenarios**: (the unit itself is test scenarios — no separate list)

**Verification**:
- `./dev mix test test/mydia/downloads/client/sabnzbd_test.exs test/mydia/downloads/client/nzbget_test.exs test/mydia/indexers/adapter/prowlarr_test.exs` green.
- New tests fail if `parse_state/1` regressed (e.g., introduce a bug, see the table test catch it, revert).
- No network calls in any new test (`Bypass` only, with fixtures pre-loaded).

---

## Cross-Cutting Concerns

### Migrations

All four migrations in this plan are additive on existing tables (`indexer_configs`, `download_clients`, `downloads`) or create new tables (`release_blacklist`). SQLite-safe: no column drops, no `NOT NULL` adds to existing rows, no data backfill required. Nullable columns get sensible defaults at the migration layer.

### Backwards compatibility

- **`DownloadClientConfig.category` (string)** stays alongside the new `categories` (map). U3 prefers map; falls back to string when map is empty. Removal is a follow-up after a few release cycles confirm no installs still rely on the string field exclusively.
- **Hardcoded priority mapping** stays as the default when `priority_profile: %{}`. U3's 5-tier taxonomy adds two new tiers (`:verylow`, `:veryhigh`) without breaking 3-tier callers.
- **Existing downloads without `metadata["guid"]`** are blacklist-immune (no key to compare against). New downloads get the field; old ones quietly skip blacklist matching. Acceptable.

### Logging hygiene

U1 demotes Prowlarr `Logger.info` → `:debug`. The pattern (info-spam during routine parsing) likely repeats in NZBHydra2 and the search jobs — the implementer should grep `Logger.info` in those areas opportunistically. Out-of-scope additions if found > 5 sites; in-scope if 1–5 sites.

### Performance

- Stall detection (U4) adds a per-download timestamp comparison on each poll. O(n) over active downloads; n is small (rarely > 50). Negligible.
- Blacklist consumer (U7) adds one extra query per search: `SELECT 1 FROM release_blacklist WHERE (indexer, guid) IN (...)`. Bulk lookup, indexed on `(indexer, guid)`. Negligible.
- Webhook idempotency (U5) `unique:` Oban query is indexed by Oban itself. Negligible.

### Security

- Webhook auth (U5): constant-time secret comparison via `Plug.Crypto.secure_compare/2`. Secrets generated server-side via `:crypto.strong_rand_bytes(32)`. Never logged.
- No PII in any new log line (download titles are OK; user data is not).

### System-Wide Impact

- **`MediaImport` snooze loop** (U5): the `unique:` Oban option must include `[:available, :scheduled, :executing, :retryable]` so that a snoozed (`:scheduled` for retry) job dedupes against a webhook-triggered fresh insert. Without `:scheduled`, a webhook fires a duplicate job while a snooze is pending → two jobs run when the snooze fires. Catch this in the idempotency test.
- **DownloadMonitor failure path** (U7): inserting a blacklist row should NOT block the failure handling — if blacklist insert fails (DB locked, constraint violation, etc.), log and continue. Don't propagate the error up; failure handling itself must succeed.
- **Admin form changes** (U6): the LiveView's `handle_event("save_download_client", ...)` already calls `Settings.create_download_client_config/1` or `update_download_client_config/2`. New fields plumb through the changeset automatically once cast. Verify with a `Phoenix.LiveViewTest.render_submit/2` round-trip.

---

## Implementation-Time Unknowns

Items deliberately deferred to `ce-work`:

1. **Exact `update_download/2` interaction in U4**: do we add `import_failed_at` directly, or introduce a new field like `stalled_at`? The plan says reuse `import_failed_at` + an `import_last_error` string match — but if the implementer finds string-matching brittle, a dedicated `stalled: boolean` field is fine. Decide during U4.
2. **`Download.metadata["guid"]` plumbing in U7**: where exactly is the right place to copy `search_result.metadata["guid"]` into the download's metadata? Likely `Queue.add_torrent_to_client_with_input` at `queue.ex:607` or in the upstream create call. The implementer should grep for "guid" usage during U7.
3. **Webhook payload shape ambiguity (U5)**: SABnzbd's actual notification-script payload varies by SABnzbd version. The plan assumes JSON; if the real version sends form-encoded, branch the controller. Verify against a live SABnzbd 4.x notification script when writing the controller tests.
4. **Priority profile UI placement (U6)**: collapsed `<details>` advanced section vs. a dedicated tab. The plan suggests collapsed; the implementer should match whichever pattern other "advanced config" sections in the admin already use.
5. **BlacklistCleanup scheduling (U7)**: daily cron via `oban_pro` (if installed) or a `Oban.Cron` config entry. Verify which is wired up in `config/config.exs`.
6. **`:status` column resolution**: out of scope but flagged. If the implementer can't avoid touching the `update_download(..., %{status: ...})` lines in U4 or U7, decide whether to cast `:status` or remove the dead key. Document the decision in the unit's commit message.

---

## Acceptance Criteria

When all units merge, the rollout closes:

- [ ] #120 — Prowlarr `Logger.info` demoted to `:debug` in 3 sites; manual search emits zero info-level lines.
- [ ] #121 — `SearchResult.usenet_date` populated by NZBHydra2 + Prowlarr; `min_post_age_minutes` on `IndexerConfig`; ReleaseRanker filters NZB by age; admin form exposes the field.
- [ ] #122 — `POST /api/webhooks/usenet/:id` accepts SABnzbd + NZBGet payloads with per-client secret; `MediaImport` is idempotent; admin form shows webhook URL.
- [ ] #123 — `release_blacklist` table populated by failure handler; consumed by `process_episode_results` and `process_movie_results`; admin LiveView lists and removes.
- [ ] #124 — `download_clients.categories` map populated and resolved at submit time by `Download.content_type`.
- [ ] #125 — `SearchResult.nzb_completion` and `nzb_grabs` populated; `seeders`/`leechers` `nil` for NZB; ReleaseRanker branches scoring by protocol.
- [ ] #126 — `last_progress_at` + `last_known_bytes` on downloads; `DownloadMonitor` transitions stalled downloads to `:error` after grace; UI surfaces "Stalled" badge.
- [ ] #127 — `DownloadStatus` struct unified; `Mydia.Downloads.Client.Helpers` extracted; each adapter ~50–100 LOC shorter; behaviour callbacks reference shared struct.
- [ ] #128 — Each of `{sabnzbd, nzbget, prowlarr}_test.exs` has frozen fixtures, table-driven state-mapping tests, no network.
- [ ] #129 — `priority_profile` map column; 5-tier taxonomy via `Mydia.Downloads.Priority`; adapters look up via profile with backwards-compat default; admin form exposes advanced override.

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Wave-2 schema migration touches 2 tables with 5+ new columns; reverting partial wave-2 work needs careful rollback. | Low | Medium | Single migration in U2 keeps all wave-2 schema changes atomic. `ce-work` runs the migration before dispatching U3/U4/U5. Rollback reverses cleanly. |
| `MediaImport` idempotency change interacts with the existing snooze loop. | Medium | Medium | `unique:` includes `:scheduled` state. Test scenario explicitly covers snoozed-job + webhook race. |
| Backwards-compat `:category` string + `categories` map creates two sources of truth. | Medium | Low | U3 falls back to `:category` only when `categories` map is empty. Document deprecation in `@moduledoc`. Schedule removal for a future release after telemetry confirms zero installs rely on `:category` alone. |
| U8's rename of `TorrentStatus` → `DownloadStatus` ripples through the codebase. | High | Low | All references are internal (verified by grep). Compile-time error catches any miss. Run full test suite after the rename. |
| Admin form UI (U6) collides with U3/U4/U5 if any of them sneak in UI changes. | Medium | Medium | Plan explicitly puts ALL UI in U6. If an implementer is tempted to add UI in U3-5, the unit's `Files:` list flags the violation. Code review catches it. |
| `Download.metadata["guid"]` may not always be present for old downloads. | Medium | Low | Blacklist consumer treats missing guid as "not blacklisted" — safe default. Old downloads are blacklist-immune; new downloads aren't. Acceptable behavior gap. |
| Webhook payload shape varies by SABnzbd/NZBGet version. | Medium | Low | U5 tests against documented schemas; manual verification step in U5's `Verification` section catches drift. If drift is found, branch on payload shape. |

---

## Sources and References

### Origin
- **Tracking issue**: getmydia/mydia#119 — "Improve Usenet support: tracking issue"
- **Sub-issues**: getmydia/mydia#120, #121, #122, #123, #124, #125, #126, #127, #128, #129

### Prior plans
- `docs/plans/2026-04-08-fix-usenet-download-import-pipeline-plan.md` — the import-pipeline fix this plan sits on top of. Note the verified discrepancies: claimed `save_path` column was implemented as `metadata["save_path"]` JSON key; claimed mock-sabnzbd/mock-nzbget containers were not actually added.
- `docs/brainstorms/2026-04-08-usenet-import-fix-brainstorm.md` — origin context.

### Institutional learnings
- `docs/plans/2026-04-01-fix-duplicate-tv-show-downloads-plan.md` — established "filter, don't rank" convention; `reject_*` naming; blacklist filtering belongs in `process_episode_results`, not `ReleaseRanker`.
- `docs/plans/2026-03-23-refactor-comprehensive-type-safety-plan.md` — `Mydia.Downloads.Client` behaviour already exists with `@spec` callbacks; 45/46 schemas missing `@type t :: %__MODULE__{...}` (opportunistic add).
- `docs/plans/2026-04-03-refactor-phoenix-architecture-cleanup-plan.md` — admin LiveView is one-per-tab; health checks use `Task.start` not `Task.async`; never call client HTTP in LiveView mount paths.

### Internal references
- `lib/mydia/indexers/search_result.ex` — struct shape
- `lib/mydia/indexers/adapter/nzbhydra2.ex:267-269` — `usenetdate` already extracted and dropped
- `lib/mydia/indexers/adapter/prowlarr.ex:305,316,328` — noisy `Logger.info` sites
- `lib/mydia/indexers/release_ranker.ex` — filter pipeline + scoring
- `lib/mydia/settings/download_client_config.ex` — current schema
- `lib/mydia/downloads/download.ex` — current schema (no save_path/status/guid columns)
- `lib/mydia/downloads/queue.ex:607` — `add_torrent_to_client_with_input/4` opts construction
- `lib/mydia/downloads/structs/torrent_status.ex` — canonical state struct
- `lib/mydia/downloads/client.ex` — behaviour module
- `lib/mydia/jobs/download_monitor.ex` — poll loop + state transitions
- `lib/mydia/jobs/media_import.ex` — entry point (no `unique:` today, no `imported_at` early-return)
- `lib/mydia/jobs/import_list_sync.ex:20` — pattern for `unique:` Oban opts
- `lib/mydia_web/live/admin_download_clients_live/components.ex:156` — admin form modal pattern
- `test/mydia/jobs/usenet_import_integration_test.exs` — integration test pattern (Bypass-based, no containers)
