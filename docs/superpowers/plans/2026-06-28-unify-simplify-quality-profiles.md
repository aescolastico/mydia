# Unify & Simplify Quality Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the quality-profile feature to one quality model (`quality_standards`), one parsed-quality struct (`Mydia.Library.Structs.Quality`), and zero dead configuration, via a single clean-break data migration — and enforce **UI⟺effect parity**: every quality-profile option is editable in the UI, and every UI option has a real runtime effect.

**Architecture:** Extend the canonical `Library.Structs.Quality` struct to a superset shape and retire the duplicate `Indexers.Structs.QualityInfo`. Make `quality_standards.preferred_resolutions` the single resolution allow-list, dropping the parallel `qualities` column. Delete the never-read `metadata_preferences`/`customizations` config and all backward-compat/fallback branches. One adapter-aware migration backfills then drops the three columns. Then close the UI/effect gaps: wire `preferred_audio_channels` into search scoring, remove the bitrate preference keys (un-wireable for search), and expose the orphaned-but-real `upgrades_allowed`, `upgrade_until_quality`, and `min_ratio` controls.

**Tech Stack:** Elixir, Phoenix, Ecto (SQLite default + PostgreSQL), Phoenix LiveView, DaisyUI/Tailwind.

## Global Constraints

- **Clean break:** one data migration, then delete all fallback/compat code. No branch may tolerate the old shapes afterward.
- **Database portability:** every migration must run on both SQLite (default) and PostgreSQL. Use `Mydia.Repo.Migrations.Helpers` (`postgres?/0`, `sqlite?/0`, `recreate_table/1`) and branch on the adapter. Prefer adapter-agnostic SQL; do the JSON backfill in Elixir, not adapter-specific SQL.
- **Canonical parsed-quality module:** `Mydia.Library.Structs.Quality`, extended to fields `resolution, source, codec, audio, hdr, hdr_format, proper, repack`. Boolean fields (`hdr`, `proper`, `repack`) default to `false`.
- **Delete entirely:** `metadata_preferences`, `customizations`, `Mydia.Indexers.Structs.QualityInfo`, `Mydia.Settings.DefaultMetadataPreferences`.
- **Keep as-is (scope containment):** `upgrade_until_quality` (single-resolution cap); both parsers (`indexers/quality_parser.ex`, `library/release_parser/quality_extractor.ex`) — they keep their logic and just emit the unified `Quality` struct.
- **Metadata language is unaffected:** it resolves via `Mydia.Metadata.metadata_language/0` → `config.metadata.language`. Do not touch it.
- **UI⟺effect parity (added requirement):** every persisted quality-profile option must be editable in the UI **and** have a real runtime effect (search/download ranking or library re-scoring); conversely no UI control may be inert. Resolution policy (decided): (a) wire `preferred_audio_channels` into search scoring; (b) **remove** the `min_video_bitrate_mbps` / `max_video_bitrate_mbps` / `preferred_video_bitrate_mbps` / `min_audio_bitrate_kbps` / `max_audio_bitrate_kbps` / `preferred_audio_bitrate_kbps` preference keys entirely — they cannot affect search (release titles carry no bitrate); (c) expose `upgrades_allowed`, `upgrade_until_quality`, and `min_ratio` in the UI with validation.
- **`MediaFile.bitrate` stays:** only the quality-*standards* bitrate *preference* keys are removed. The on-disk `MediaFile.bitrate` column and its uses (e.g. `library_test.exs`, `adult_test.exs`) are out of scope and untouched.
- **Run all commands through the dev wrapper:** `./dev mix test ...`, `./dev mix ecto.migrate`, `./dev mix precommit`. Run `git` inside the devenv shell.
- **No attribution** in commits or any output (no "Compound Engineering", "Claude", "Co-Authored-By", model/harness badges, etc.).

---

## File Structure

**Modified:**
- `lib/mydia/library/structs/quality.ex` — extended to the superset struct (canonical).
- `lib/mydia/indexers/search_result.ex` — `quality` typed as `Quality.t()`.
- `lib/mydia/downloads/structs/download_metadata.ex` — `quality` reconstruct/dump via `Quality`.
- `lib/mydia/indexers/quality_parser.ex` — emits/scoring uses `Quality`.
- `lib/mydia/library/file_renamer.ex` — `build_quality_info/1` builds a `Quality`.
- `lib/mydia_web/live/downloads_live/index.ex` + `index.html.heex` — alias + `Quality.format/1`.
- `lib/mydia/settings/quality_matcher.ex` — read resolutions from `quality_standards.preferred_resolutions`.
- `lib/mydia/indexers/search_scorer.ex` — delete `ensure_preferred_resolutions/1` fallback.
- `lib/mydia/indexers/ranking_options.ex` — source `preferred_qualities` from `quality_standards`.
- `lib/mydia_web/live/admin_quality_profiles_live/components.ex` — remove "Allowed Qualities" block.
- `lib/mydia_web/live/admin_quality_profiles_live/index.ex` — remove `qualities` param building.
- `lib/mydia/settings/quality_profile.ex` — drop fields/validators; new `preferred_resolutions` validation.
- `lib/mydia/settings/quality_profiles.ex` — drop dead fields from clone/export/import/compare; delete metadata-pref functions.
- `lib/mydia/settings/quality_profile_engine.ex` — delete `get_metadata_preferences/1`.
- `lib/mydia/settings.ex` — delete metadata-pref delegates; fix doc example.
- `lib/mydia/settings/default_quality_profiles.ex` — drop `qualities:`; fix "Any" `preferred_resolutions`.
- `lib/mydia/settings/quality_profile_presets.ex` — drop `qualities:` from each preset.

**Created:**
- `priv/repo/migrations/20260628000000_unify_quality_profiles.exs` — backfill + drop columns.

**Deleted:**
- `lib/mydia/indexers/structs/quality_info.ex`
- `lib/mydia/settings/default_metadata_preferences.ex`
- `test/mydia/indexers/quality_info_test.exs`

---

## Task 1: Extend `Library.Structs.Quality` to the superset

**Files:**
- Modify: `lib/mydia/library/structs/quality.ex`
- Test: `test/mydia/library/structs/quality_test.exs` (Create)

**Interfaces:**
- Produces: `Mydia.Library.Structs.Quality` struct with fields `resolution, source, codec, audio, hdr, hdr_format, proper, repack` (booleans default `false`, others `nil`). Functions:
  - `new(attrs :: keyword() | map()) :: t()`
  - `empty() :: t()`
  - `empty?(t()) :: boolean()` — true when `resolution`, `source`, `codec`, `audio`, `hdr_format` are all `nil` (booleans ignored).
  - `format(t() | nil) :: String.t() | nil`
  - `from_map(map() | nil) :: t() | nil`

This task is purely additive — `Library.Structs.Quality` currently has 5 fields and is already used by the release-parser pipeline; adding boolean fields with `false` defaults and new helpers does not break existing callers.

- [ ] **Step 1: Write the failing tests**

Create `test/mydia/library/structs/quality_test.exs`:

```elixir
defmodule Mydia.Library.Structs.QualityTest do
  use ExUnit.Case, async: true

  alias Mydia.Library.Structs.Quality

  describe "new/1" do
    test "defaults boolean flags to false and others to nil" do
      q = Quality.new(resolution: "1080p")
      assert q.resolution == "1080p"
      assert q.source == nil
      assert q.codec == nil
      assert q.audio == nil
      assert q.hdr == false
      assert q.hdr_format == nil
      assert q.proper == false
      assert q.repack == false
    end

    test "accepts a map" do
      q = Quality.new(%{resolution: "2160p", hdr: true, hdr_format: "DV", proper: true})
      assert q.resolution == "2160p"
      assert q.hdr == true
      assert q.hdr_format == "DV"
      assert q.proper == true
      assert q.repack == false
    end
  end

  describe "empty/0 and empty?/1" do
    test "empty/0 is empty?" do
      assert Quality.empty?(Quality.empty())
    end

    test "a struct with only flags set is still empty" do
      assert Quality.empty?(%Quality{hdr: false, proper: false, repack: false})
    end

    test "a struct with content is not empty" do
      refute Quality.empty?(%Quality{resolution: "1080p"})
      refute Quality.empty?(%Quality{hdr_format: "HDR10"})
    end
  end

  describe "format/1" do
    test "joins resolution, source, codec, audio" do
      q = %Quality{resolution: "1080p", source: "BluRay", codec: "x264", audio: "DTS-HD MA"}
      assert Quality.format(q) == "1080p BluRay x264 DTS-HD MA"
    end

    test "uses hdr_format when hdr is true" do
      q = %Quality{resolution: "2160p", source: "WEB-DL", hdr: true, hdr_format: "DV"}
      assert Quality.format(q) == "2160p WEB-DL DV"
    end

    test "shows HDR when hdr is true but no format" do
      q = %Quality{resolution: "2160p", source: "BluRay", hdr: true}
      assert Quality.format(q) == "2160p BluRay HDR"
    end

    test "appends PROPER and REPACK" do
      assert Quality.format(%Quality{resolution: "1080p", source: "BluRay", proper: true}) ==
               "1080p BluRay PROPER"

      assert Quality.format(%Quality{resolution: "720p", source: "WEB-DL", repack: true}) ==
               "720p WEB-DL REPACK"
    end

    test "empty struct formats to empty string; nil to nil" do
      assert Quality.format(Quality.empty()) == ""
      assert Quality.format(nil) == nil
    end
  end

  describe "from_map/1" do
    test "reconstructs from string-keyed map with flag defaults" do
      q = Quality.from_map(%{"resolution" => "1080p", "source" => "BluRay"})
      assert %Quality{} = q
      assert q.resolution == "1080p"
      assert q.source == "BluRay"
      assert q.hdr == false
      assert q.proper == false
      assert q.repack == false
    end

    test "honors atom keys and explicit flags" do
      q = Quality.from_map(%{resolution: "2160p", hdr: true, hdr_format: "DV", repack: true})
      assert q.hdr == true
      assert q.hdr_format == "DV"
      assert q.repack == true
    end

    test "nil maps to nil" do
      assert Quality.from_map(nil) == nil
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./dev mix test test/mydia/library/structs/quality_test.exs`
Expected: FAIL (e.g. `function Mydia.Library.Structs.Quality.format/1 is undefined` and struct key errors for `:hdr`).

- [ ] **Step 3: Rewrite `lib/mydia/library/structs/quality.ex`**

Replace the entire file with:

```elixir
defmodule Mydia.Library.Structs.Quality do
  @moduledoc """
  Canonical parsed-quality struct.

  Represents quality information parsed either from a release title
  (indexer search results) or extracted from an on-disk media file.
  Provides compile-time safety for quality data, replacing plain map
  access that can silently return nil.

  Boolean release flags (`hdr`, `proper`, `repack`) default to `false`;
  on-disk files simply leave them at the defaults.

  ## HDR Format Tiers (per TRaSH Guides)

  - "DV" (Dolby Vision) - highest quality, includes fallback layer
  - "HDR10+" - dynamic metadata
  - "HDR10" - static metadata HDR
  - nil (SDR) - standard dynamic range
  """

  defstruct resolution: nil,
            source: nil,
            codec: nil,
            audio: nil,
            hdr: false,
            hdr_format: nil,
            proper: false,
            repack: false

  @type t :: %__MODULE__{
          resolution: String.t() | nil,
          source: String.t() | nil,
          codec: String.t() | nil,
          audio: String.t() | nil,
          hdr: boolean(),
          hdr_format: String.t() | nil,
          proper: boolean(),
          repack: boolean()
        }

  @doc """
  Creates a new Quality struct from a keyword list or map.

  ## Examples

      iex> new(resolution: "1080p", source: "BluRay")
      %Quality{resolution: "1080p", source: "BluRay", hdr: false, proper: false, repack: false}
  """
  def new(attrs \\ []) when is_list(attrs) or is_map(attrs) do
    struct(__MODULE__, attrs)
  end

  @doc """
  Returns an empty Quality struct (all content nil, flags false).
  """
  def empty do
    %__MODULE__{}
  end

  @doc """
  Checks if a Quality struct is empty (all content fields are nil).
  Boolean flags are not considered.
  """
  def empty?(%__MODULE__{} = quality) do
    quality.resolution == nil &&
      quality.source == nil &&
      quality.codec == nil &&
      quality.audio == nil &&
      quality.hdr_format == nil
  end

  @doc """
  Formats a Quality struct as a human-readable string.

  ## Examples

      iex> format(%Quality{resolution: "1080p", source: "BluRay", codec: "x264"})
      "1080p BluRay x264"

      iex> format(%Quality{resolution: "2160p", source: "WEB-DL", hdr: true, hdr_format: "DV"})
      "2160p WEB-DL DV"
  """
  def format(%__MODULE__{} = quality) do
    [
      quality.resolution,
      quality.source,
      quality.codec,
      quality.audio,
      if(quality.hdr && quality.hdr_format, do: quality.hdr_format),
      if(quality.hdr && !quality.hdr_format, do: "HDR"),
      if(quality.proper, do: "PROPER"),
      if(quality.repack, do: "REPACK")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  def format(nil), do: nil

  @doc """
  Creates a Quality struct from a plain map with string or atom keys.

  Used to reconstruct a Quality from database-stored JSON data.
  """
  def from_map(nil), do: nil

  def from_map(map) when is_map(map) do
    new(%{
      resolution: map["resolution"] || map[:resolution],
      source: map["source"] || map[:source],
      codec: map["codec"] || map[:codec],
      audio: map["audio"] || map[:audio],
      hdr: map["hdr"] || map[:hdr] || false,
      hdr_format: map["hdr_format"] || map[:hdr_format],
      proper: map["proper"] || map[:proper] || false,
      repack: map["repack"] || map[:repack] || false
    })
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./dev mix test test/mydia/library/structs/quality_test.exs`
Expected: PASS.

- [ ] **Step 5: Verify the release-parser pipeline still compiles/passes (regression check)**

Run: `./dev mix test test/mydia/library/release_parser_test.exs test/mydia/library/release_parser/parity_test.exs`
Expected: PASS (existing `Quality.empty/0`, `empty?/1`, `%Quality{}` callers unaffected).

- [ ] **Step 6: Commit**

```bash
git add lib/mydia/library/structs/quality.ex test/mydia/library/structs/quality_test.exs
git commit -m "feat(quality): extend Library.Structs.Quality to superset shape"
```

---

## Task 2: Replace `QualityInfo` with `Quality`; delete `QualityInfo`

**Files:**
- Modify: `lib/mydia/indexers/search_result.ex`
- Modify: `lib/mydia/downloads/structs/download_metadata.ex`
- Modify: `lib/mydia/indexers/quality_parser.ex`
- Modify: `lib/mydia/library/file_renamer.ex`
- Modify: `lib/mydia_web/live/downloads_live/index.ex`
- Modify: `lib/mydia_web/live/downloads_live/index.html.heex`
- Delete: `lib/mydia/indexers/structs/quality_info.ex`
- Delete: `test/mydia/indexers/quality_info_test.exs`
- Modify tests: `test/mydia/indexers/quality_parser_test.exs`, `test/mydia/indexers_test.exs`, `test/mydia/downloads/download_metadata_test.exs`, `test/mydia/library/file_renamer_test.exs`, `test/mydia/settings/quality_matcher_test.exs`

**Interfaces:**
- Consumes: `Mydia.Library.Structs.Quality` (Task 1), API identical to the deleted `QualityInfo`.
- Produces: `Mydia.Indexers.SearchResult.t()` whose `:quality` field is `Quality.t() | nil`.

Because `Quality` is now a strict superset of `QualityInfo` with identical helper signatures, this is a mechanical alias/struct rename. Everything keeps compiling.

- [ ] **Step 1: Update `lib/mydia/indexers/search_result.ex`**

Replace `alias Mydia.Indexers.Structs.QualityInfo` (line 60) with:

```elixir
  alias Mydia.Library.Structs.Quality
```

Replace the typespec line `quality: QualityInfo.t() | nil,` (line 73) with:

```elixir
          quality: Quality.t() | nil,
```

In the module doc (around lines 34-44), replace the `Mydia.Indexers.Structs.QualityInfo` reference and the `%QualityInfo{` example with `Mydia.Library.Structs.Quality` and `%Quality{` respectively.

- [ ] **Step 2: Update `lib/mydia/downloads/structs/download_metadata.ex`**

Replace `alias Mydia.Indexers.Structs.QualityInfo` (line 10) with:

```elixir
  alias Mydia.Library.Structs.Quality
```

Replace `quality: QualityInfo.t() | nil,` (line 30) with:

```elixir
          quality: Quality.t() | nil,
```

In `to_map/1`, replace the case clause `%QualityInfo{} = qi -> Map.from_struct(qi)` (line 84) with:

```elixir
        %Quality{} = qi -> Map.from_struct(qi)
```

In `from_map/1`, replace the two clauses (lines 125-126):

```elixir
        %QualityInfo{} = qi -> qi
        %{} = m -> QualityInfo.from_map(m)
```

with:

```elixir
        %Quality{} = qi -> qi
        %{} = m -> Quality.from_map(m)
```

Also update the moduledoc line 72 mention of `QualityInfo` to `Quality`.

- [ ] **Step 3: Update `lib/mydia/indexers/quality_parser.ex`**

Replace `alias Mydia.Indexers.Structs.QualityInfo` (line 33) with:

```elixir
  alias Mydia.Library.Structs.Quality
```

Replace `@spec parse(String.t()) :: QualityInfo.t()` (line 149) with `@spec parse(String.t()) :: Quality.t()` and `QualityInfo.new(` (line 153) with `Quality.new(`.

Replace `@spec quality_score(QualityInfo.t()) :: integer()` (line 360) with `@spec quality_score(Quality.t()) :: integer()` and `def quality_score(%QualityInfo{} = quality) do` (line 361) with `def quality_score(%Quality{} = quality) do`.

Update the moduledoc and doc examples (lines 11, 22, 122, 128, 139, 352, 356) replacing `QualityInfo` with `Quality`.

- [ ] **Step 4: Update `lib/mydia/library/file_renamer.ex`**

Replace `alias Mydia.Indexers.Structs.QualityInfo` (line 11) with:

```elixir
  alias Mydia.Library.Structs.Quality
```

Replace `QualityInfo.new(%{` (line 229) with `Quality.new(%{`. Update the docstring (line 215) `Builds a `QualityInfo` struct` → `Builds a `Quality` struct`. (Rename the function too for clarity is optional; keep `build_quality_info/1` to avoid touching callers.)

- [ ] **Step 5: Update the downloads LiveView and template**

In `lib/mydia_web/live/downloads_live/index.ex`, replace `alias Mydia.Indexers.Structs.QualityInfo` (line 5) with:

```elixir
  alias Mydia.Library.Structs.Quality
```

In `lib/mydia_web/live/downloads_live/index.html.heex` (line 221), replace `QualityInfo.format(get_metadata_value(download, "quality"))` with:

```elixir
QualityInfo.format(get_metadata_value(download, "quality"))
```
→
```elixir
Quality.format(get_metadata_value(download, "quality"))
```

- [ ] **Step 6: Delete the `QualityInfo` module and its test**

```bash
git rm lib/mydia/indexers/structs/quality_info.ex test/mydia/indexers/quality_info_test.exs
```

- [ ] **Step 7: Update remaining test references to the unified struct**

In each of these files, replace `alias Mydia.Indexers.Structs.QualityInfo` with `alias Mydia.Library.Structs.Quality` (in `test/mydia/indexers_test.exs` the alias is `alias Mydia.Indexers.{QualityParser, Structs.QualityInfo}` → `alias Mydia.Indexers.QualityParser` plus a separate `alias Mydia.Library.Structs.Quality`), and replace every `%QualityInfo{` → `%Quality{` and `QualityInfo.` → `Quality.`:
- `test/mydia/indexers/quality_parser_test.exs`
- `test/mydia/indexers_test.exs`
- `test/mydia/downloads/download_metadata_test.exs`
- `test/mydia/library/file_renamer_test.exs`
- `test/mydia/settings/quality_matcher_test.exs`

Mechanical helper to find leftovers after editing:

```bash
grep -rn "QualityInfo" lib/ test/
```

Expected after this step: no matches.

- [ ] **Step 8: Run the affected tests**

Run:
```bash
./dev mix test test/mydia/indexers/quality_parser_test.exs test/mydia/indexers_test.exs test/mydia/downloads/download_metadata_test.exs test/mydia/library/file_renamer_test.exs test/mydia/settings/quality_matcher_test.exs
```
Expected: PASS.

- [ ] **Step 9: Compile cleanly (catch stragglers)**

Run: `./dev mix compile --warnings-as-errors`
Expected: no `QualityInfo` undefined/alias warnings.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "refactor(quality): replace QualityInfo with unified Library.Structs.Quality"
```

---

## Task 3: Collapse the dual quality model in consumers + LiveView form

**Files:**
- Modify: `lib/mydia/settings/quality_matcher.ex`
- Modify: `lib/mydia/indexers/search_scorer.ex`
- Modify: `lib/mydia/indexers/ranking_options.ex`
- Modify: `lib/mydia_web/live/admin_quality_profiles_live/components.ex`
- Modify: `lib/mydia_web/live/admin_quality_profiles_live/index.ex`
- Test: `test/mydia/settings/quality_matcher_test.exs`, `test/mydia/indexers/search_scorer_test.exs`, `test/mydia/indexers/release_ranker_test.exs`

**Interfaces:**
- Consumes: `QualityProfile` with `quality_standards.preferred_resolutions` (list of resolution strings). The `profile.qualities` field still exists on the struct at this point but **must no longer be read** by any consumer after this task.
- Produces: a private helper `preferred_resolutions(profile)` semantics — read `quality_standards.preferred_resolutions` accepting both atom and string keys, defaulting to `[]`.

This task stops every consumer from reading `profile.qualities`; the schema field is removed later in Task 5. The resolution allow-list now comes from `quality_standards.preferred_resolutions`.

- [ ] **Step 1: Write the failing test for `QualityMatcher.is_upgrade?` using preferred_resolutions**

In `test/mydia/settings/quality_matcher_test.exs`, the `build_quality_profile`-style fixtures currently set both `qualities:` and `quality_standards.preferred_resolutions`. Add a test that proves the allow-list is read from `quality_standards` even when `qualities` is empty. Add inside the `is_upgrade?/3` describe block:

```elixir
    test "uses preferred_resolutions (not qualities) for the allow-list" do
      profile = %Mydia.Settings.QualityProfile{
        name: "Std",
        upgrades_allowed: true,
        qualities: [],
        quality_standards: %{preferred_resolutions: ["1080p", "720p"]}
      }

      result = %Mydia.Indexers.SearchResult{
        title: "Movie 1080p",
        size: 1_000_000,
        download_url: "magnet:?x",
        indexer: "test",
        quality: %Mydia.Library.Structs.Quality{resolution: "1080p"}
      }

      assert Mydia.Settings.QualityMatcher.is_upgrade?(result, profile, "720p")

      not_allowed = %{result | quality: %Mydia.Library.Structs.Quality{resolution: "480p"}}
      refute Mydia.Settings.QualityMatcher.is_upgrade?(not_allowed, profile, "720p")
    end
```

(Adjust the `SearchResult` required fields to match the struct's `@enforce_keys` if any; mirror an existing fixture in the file.)

- [ ] **Step 2: Run it to verify it fails**

Run: `./dev mix test test/mydia/settings/quality_matcher_test.exs -k "preferred_resolutions"`
Expected: FAIL — current code reads `profile.qualities` (empty), so `is_upgrade?` returns `false` for the allowed `1080p` case.

- [ ] **Step 3: Update `lib/mydia/settings/quality_matcher.ex`**

Add a private helper at the bottom of the `## Private Functions` section:

```elixir
  # Read the resolution allow-list from quality_standards (atom or string key).
  defp preferred_resolutions(%QualityProfile{quality_standards: standards}) when is_map(standards) do
    Map.get(standards, :preferred_resolutions) ||
      Map.get(standards, "preferred_resolutions") || []
  end

  defp preferred_resolutions(_profile), do: []
```

In `is_upgrade?/3`, replace the `result_quality not in profile.qualities ->` clause (line 118) with:

```elixir
      # Check if result quality is in the allowed list
      result_quality not in preferred_resolutions(profile) ->
        false
```

Replace `check_quality_allowed/2` (lines 198-206) so the "allowed" check uses `preferred_resolutions`:

```elixir
  defp check_quality_allowed(%SearchResult{quality: quality} = result, %QualityProfile{} = profile) do
    if quality.resolution in preferred_resolutions(profile) do
      :ok
    else
      {:error, :quality_not_allowed}
    end
  end
```

(Keep the `%SearchResult{quality: nil}` clause at line 194 unchanged.) Update the comment at line 52 (`# Also check legacy qualities field for backward compatibility`) to `# Also check the resolution allow-list from quality_standards`. Update the moduledoc/comment at line 193 similarly.

- [ ] **Step 4: Run the matcher tests**

Run: `./dev mix test test/mydia/settings/quality_matcher_test.exs`
Expected: PASS.

- [ ] **Step 5: Delete the SearchScorer fallback**

In `lib/mydia/indexers/search_scorer.ex`, in `score_quality/3` for the profile clause (lines 183-193), remove the fallback call. Replace:

```elixir
  def score_quality(%SearchResult{} = result, %QualityProfile{} = profile, media_type) do
    # Convert search result to media_attrs format for scoring
    media_attrs = search_result_to_media_attrs(result, media_type)

    # Ensure quality_standards has preferred_resolutions set from the qualities field
    profile_with_resolution_fallback = ensure_preferred_resolutions(profile)

    score_result = QualityProfile.score_media_file(profile_with_resolution_fallback, media_attrs)

    {score_result.score, score_result.breakdown, score_result.violations}
  end
```

with:

```elixir
  def score_quality(%SearchResult{} = result, %QualityProfile{} = profile, media_type) do
    # Convert search result to media_attrs format for scoring
    media_attrs = search_result_to_media_attrs(result, media_type)

    score_result = QualityProfile.score_media_file(profile, media_attrs)

    {score_result.score, score_result.breakdown, score_result.violations}
  end
```

Delete both `ensure_preferred_resolutions/1` clauses entirely (lines 363-409, the two function heads and their bodies including the `# Ensure preferred_resolutions ...` comment).

- [ ] **Step 6: Source `preferred_qualities` from `quality_standards` in RankingOptions**

In `lib/mydia/indexers/ranking_options.ex`, replace `build_quality_options/2` (lines 81-94):

```elixir
  def build_quality_options(%QualityProfile{} = quality_profile, media_type) do
    quality_opts =
      case quality_profile.qualities do
        qualities when is_list(qualities) -> [preferred_qualities: qualities]
        _ -> []
      end

    ratio_opts = extract_min_ratio(quality_profile)
    size_opts = extract_size_range(quality_profile, media_type)

    quality_opts
    |> Keyword.merge(ratio_opts)
    |> Keyword.merge(size_opts)
  end
```

with:

```elixir
  def build_quality_options(%QualityProfile{} = quality_profile, media_type) do
    quality_opts =
      case preferred_resolutions(quality_profile) do
        [] -> []
        resolutions -> [preferred_qualities: resolutions]
      end

    ratio_opts = extract_min_ratio(quality_profile)
    size_opts = extract_size_range(quality_profile, media_type)

    quality_opts
    |> Keyword.merge(ratio_opts)
    |> Keyword.merge(size_opts)
  end

  # Read the resolution allow-list from quality_standards (atom or string key).
  defp preferred_resolutions(%QualityProfile{quality_standards: standards}) when is_map(standards) do
    Map.get(standards, :preferred_resolutions) ||
      Map.get(standards, "preferred_resolutions") || []
  end

  defp preferred_resolutions(_profile), do: []
```

Update the `@doc` for `build_quality_options/2` (lines 76-79) to say it extracts `:preferred_qualities` from `quality_standards.preferred_resolutions`.

- [ ] **Step 7: Remove the "Allowed Qualities" block from the form component**

In `lib/mydia_web/live/admin_quality_profiles_live/components.ex`, delete the entire `<%!-- Allowed Qualities --%>` block (lines 327-355, the `<div class="form-control">` containing the qualities checkboxes through its closing `</div>`). The "Preferred Resolutions" checkboxes inside the Quality Standards tab (around line 521, `quality_profile[quality_standards][preferred_resolutions][]`) remain and become the sole resolution input.

- [ ] **Step 8: Remove `qualities` from the LiveView param transform**

In `lib/mydia_web/live/admin_quality_profiles_live/index.ex`, rewrite `transform_quality_profile_params/1` (lines 376-403) to drop the `qualities` computation and key:

```elixir
  defp transform_quality_profile_params(params) do
    quality_standards =
      if params["quality_standards"] do
        transform_quality_standards(params["quality_standards"])
      else
        nil
      end

    base_params = %{
      "name" => params["name"],
      "description" => params["description"]
    }

    if quality_standards do
      Map.put(base_params, "quality_standards", quality_standards)
    else
      base_params
    end
  end
```

Leave `transform_quality_standards/1` and `transform_quality_standard_value/2` (which already handle `preferred_resolutions`) unchanged.

- [ ] **Step 9: Run the consumer tests**

Run:
```bash
./dev mix test test/mydia/settings/quality_matcher_test.exs test/mydia/indexers/search_scorer_test.exs test/mydia/indexers/release_ranker_test.exs
```
Expected: PASS. The fixtures in these tests still set both `qualities` and `quality_standards.preferred_resolutions`, so they pass while the schema field still exists. (They get cleaned up in Task 5.)

- [ ] **Step 10: Compile cleanly**

Run: `./dev mix compile --warnings-as-errors`
Expected: no unused-function warnings (the `ensure_preferred_resolutions/1` removal must be complete).

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "refactor(quality): drive resolution allow-list from quality_standards.preferred_resolutions"
```

---

## Task 4: Delete dead config (`metadata_preferences` + `customizations`) — code only

**Files:**
- Modify: `lib/mydia/settings/quality_profile.ex`
- Modify: `lib/mydia/settings/quality_profiles.ex`
- Modify: `lib/mydia/settings/quality_profile_engine.ex`
- Modify: `lib/mydia/settings.ex`
- Delete: `lib/mydia/settings/default_metadata_preferences.ex`
- Modify tests: `test/mydia/settings/quality_profile_engine_test.exs`, `test/mydia/settings_test.exs`

**Interfaces:**
- Consumes: nothing new.
- Produces: `QualityProfile.changeset/2` no longer casts or validates `:metadata_preferences`/`:customizations`. The metadata-pref public API (`Settings.get_default_metadata_preferences/0`, `get_metadata_preferences_with_defaults/1`, `validate_metadata_preferences_providers/1`, `get_field_provider/2`; `QualityProfileEngine.get_metadata_preferences/1`) is gone.

The schema `field` definitions for `:metadata_preferences`/`:customizations` (and the corresponding columns) are still present after this task — they are removed in Task 5. This keeps `clone_quality_profile/2`, `export_profile/2`, and `compare_quality_profile_versions/2` (which still read those struct fields) compiling. This task compiles and tests independently.

- [ ] **Step 1: Strip metadata-pref validation from `quality_profile.ex`**

In `lib/mydia/settings/quality_profile.ex`:

In `changeset/2` (lines 97-118), remove `:metadata_preferences` and `:customizations` from the `cast` list, and remove the `|> validate_metadata_preferences()` line. Result:

```elixir
  def changeset(quality_profile, attrs) do
    quality_profile
    |> cast(attrs, [
      :name,
      :upgrades_allowed,
      :upgrade_until_quality,
      :qualities,
      :description,
      :is_system,
      :version,
      :source_url,
      :last_synced_at,
      :quality_standards
    ])
    |> validate_required([:name, :qualities])
    |> validate_length(:qualities, min: 1)
    |> unique_constraint(:name)
    |> validate_quality_standards()
  end
```

(Section A's changeset rewrite — dropping `:qualities` and adding the `preferred_resolutions` requirement — happens in Task 5. Leave `:qualities` here for now so the schema stays consistent.)

Delete `validate_metadata_preferences/1` (lines 220-237, including its `@doc`) and **all** of its sub-validators and helpers that are now unused:
- `validate_provider_priority/2`
- `validate_field_providers/2`
- `validate_language_settings/2`
- `validate_language_code/3`
- `validate_region_code/2`
- `validate_fallback_languages/2`
- `validate_auto_fetch_settings/2`
- `validate_fallback_settings/2`
- `validate_conflict_resolution/2`
- `validate_boolean_pref/3`
- `validate_positive_integer/3`
- `validate_enum_value/4`
- the `@valid_providers` module attribute and `valid_provider_name?/1` clauses
- `valid_language_code?/1` clauses

(These span roughly lines 186-237 and 741-959. Grep after editing to confirm none are referenced.)

- [ ] **Step 2: Delete `DefaultMetadataPreferences` and its callers in `quality_profiles.ex`**

```bash
git rm lib/mydia/settings/default_metadata_preferences.ex
```

In `lib/mydia/settings/quality_profiles.ex`:
- Remove `DefaultMetadataPreferences` from the `alias Mydia.Settings.{...}` block (lines 10-15).
- Delete the entire `## Metadata Preferences` section: `get_default_metadata_preferences/0`, `get_metadata_preferences_with_defaults/1`, `validate_metadata_preferences_providers/1`, and `get_field_provider/2` (lines 197-232).

(`clone_quality_profile/2`, `export_profile/2`, `compare_quality_profile_versions/2`, and `prepare_import_attrs/2` still reference `profile.metadata_preferences`/`:customizations` and the import `metadata_preferences`/`customizations` keys — leave them for Task 5.)

- [ ] **Step 3: Delete `QualityProfileEngine.get_metadata_preferences/1`**

In `lib/mydia/settings/quality_profile_engine.ex`, delete both `get_metadata_preferences/1` clauses and their shared `@doc` (lines ~186-230, the doc block through the `is_binary(profile_id)` clause). Verify `fetch_profile/1` is still used elsewhere in the module before leaving it; if it becomes unused after this deletion, remove it too (grep within the file).

- [ ] **Step 4: Delete the metadata-pref delegates in `settings.ex`**

In `lib/mydia/settings.ex`, delete the four `defdelegate`s and their `@doc`/`@spec` blocks:
- `get_default_metadata_preferences/0` (around lines 199-216)
- `get_metadata_preferences_with_defaults/1` (around lines 218-232)
- `validate_metadata_preferences_providers/1` (around lines 234-249)
- `get_field_provider/2` (around lines 251-271)

- [ ] **Step 5: Remove dead-config tests**

- In `test/mydia/settings/quality_profile_engine_test.exs`, delete the entire `describe "get_metadata_preferences/1"` block (around lines 182-233).
- In `test/mydia/settings_test.exs`, delete:
  - `describe "metadata_preferences validation"` (around lines 1140-1233),
  - `describe "enhanced metadata_preferences validation"` (around line 1693 to its `end`),
  - `describe "get_metadata_preferences_with_defaults/1"` (around lines 1893-1912),
  - `describe "get_field_provider/2"` (around lines 1914-1949).

Leave the clone/compare/export blocks (lines ~897-1062) for Task 5.

- [ ] **Step 6: Compile and grep for stragglers**

Run: `./dev mix compile --warnings-as-errors`
Then:
```bash
grep -rn "DefaultMetadataPreferences\|get_metadata_preferences\|metadata_preferences_with_defaults\|validate_metadata_preferences\|get_field_provider" lib/
```
Expected: only matches in `clone_quality_profile`, `export_profile`, `compare_quality_profile_versions`, `prepare_import_attrs` that reference the `:metadata_preferences`/`:customizations` **fields** (handled in Task 5). No references to the deleted functions/module.

- [ ] **Step 7: Run the touched test suites**

Run:
```bash
./dev mix test test/mydia/settings/quality_profile_engine_test.exs test/mydia/settings_test.exs
```
Expected: PASS (the remaining clone/export tests still set `metadata_preferences` in fixtures, which the schema field still accepts via direct struct construction — they are validated/asserted away in Task 5).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor(quality): delete dead metadata_preferences/customizations config code"
```

---

## Task 5: Clean-break schema change + single data migration

**Files:**
- Modify: `lib/mydia/settings/quality_profile.ex`
- Modify: `lib/mydia/settings/quality_profiles.ex`
- Modify: `lib/mydia/settings.ex`
- Modify: `lib/mydia/settings/default_quality_profiles.ex`
- Modify: `lib/mydia/settings/quality_profile_presets.ex`
- Create: `priv/repo/migrations/20260628000000_unify_quality_profiles.exs`
- Test: `test/mydia/settings_test.exs`, `test/mydia/settings/quality_profile_presets_test.exs`, `test/mydia/indexers/release_ranker_test.exs`, `test/mydia/indexers/search_scorer_test.exs`, `test/mydia/settings/quality_matcher_test.exs`, `test/mydia/settings/quality_profile_engine_test.exs`
- Create: `test/mydia/repo/migrations/unify_quality_profiles_test.exs`

**Interfaces:**
- Consumes: `Mydia.Repo.Migrations.Helpers` (`postgres?/0`, `sqlite?/0`, `recreate_table/1`).
- Produces:
  - `QualityProfile` schema without `:qualities`, `:metadata_preferences`, `:customizations` fields.
  - `QualityProfile.changeset/2` requires only `:name` and a non-empty `quality_standards.preferred_resolutions`.
  - Migration module `Mydia.Repo.Migrations.UnifyQualityProfiles` exposing a **pure** helper `backfilled_standards(qualities :: [String.t()] | nil, standards :: map() | nil) :: map()` for unit testing the backfill.
  - `quality_profiles` table without the three columns.

This is the atomic clean break: the schema stops referencing the columns **and** the migration drops them in the same commit. (Doing only one of the two would break inserts — `qualities` is `NOT NULL` with no default — so they ship together.)

- [ ] **Step 1: Write the failing backfill unit test**

Create `test/mydia/repo/migrations/unify_quality_profiles_test.exs`:

```elixir
defmodule Mydia.Repo.Migrations.UnifyQualityProfilesTest do
  use ExUnit.Case, async: true

  alias Mydia.Repo.Migrations.UnifyQualityProfiles, as: M

  describe "backfilled_standards/2" do
    test "fills preferred_resolutions from qualities when standards lack it" do
      result = M.backfilled_standards(["720p", "1080p"], %{})
      assert result["preferred_resolutions"] == ["720p", "1080p"]
    end

    test "derives min/max resolution from qualities when absent" do
      result = M.backfilled_standards(["720p", "1080p", "2160p"], %{})
      assert result["min_resolution"] == "720p"
      assert result["max_resolution"] == "2160p"
    end

    test "keeps existing non-empty preferred_resolutions untouched" do
      standards = %{"preferred_resolutions" => ["1080p"], "min_resolution" => "1080p"}
      assert M.backfilled_standards(["720p", "2160p"], standards) == standards
    end

    test "handles nil standards" do
      result = M.backfilled_standards(["1080p"], nil)
      assert result["preferred_resolutions"] == ["1080p"]
    end

    test "ignores unknown resolution tokens when deriving min/max but keeps them in the list" do
      result = M.backfilled_standards(["weird", "1080p"], %{})
      assert result["preferred_resolutions"] == ["weird", "1080p"]
      assert result["min_resolution"] == "1080p"
      assert result["max_resolution"] == "1080p"
    end

    test "falls back to a full resolution list when qualities is empty" do
      result = M.backfilled_standards([], %{})
      assert result["preferred_resolutions"] == ["360p", "480p", "576p", "720p", "1080p", "2160p"]
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./dev mix test test/mydia/repo/migrations/unify_quality_profiles_test.exs`
Expected: FAIL — `Mydia.Repo.Migrations.UnifyQualityProfiles` does not exist yet.

- [ ] **Step 3: Write the migration**

Create `priv/repo/migrations/20260628000000_unify_quality_profiles.exs`:

```elixir
defmodule Mydia.Repo.Migrations.UnifyQualityProfiles do
  use Ecto.Migration

  import Mydia.Repo.Migrations.Helpers

  @canonical_resolutions ["360p", "480p", "576p", "720p", "1080p", "2160p", "4320p"]
  @default_resolutions ["360p", "480p", "576p", "720p", "1080p", "2160p"]

  def up do
    backfill_preferred_resolutions()
    drop_dead_columns()
  end

  def down do
    raise Ecto.MigrationError,
      message: "unify_quality_profiles is a one-way clean-break migration and cannot be reverted"
  end

  # --- Backfill ---

  defp backfill_preferred_resolutions do
    %{rows: rows} =
      repo().query!("SELECT id, qualities, quality_standards FROM quality_profiles")

    Enum.each(rows, fn [id, qualities_raw, standards_raw] ->
      qualities = decode_list(qualities_raw)
      standards = decode_map(standards_raw)
      new_standards = backfilled_standards(qualities, standards)

      if new_standards != standards do
        encoded = Jason.encode!(new_standards)

        repo().query!(
          "UPDATE quality_profiles SET quality_standards = $1 WHERE id = $2",
          [encoded, id]
        )
      end
    end)
  end

  # Pure, testable backfill rule. Returns a string-keyed standards map.
  def backfilled_standards(qualities, standards) do
    standards = standards || %{}
    existing = standards["preferred_resolutions"] || standards[:preferred_resolutions]

    if is_list(existing) and existing != [] do
      standards
    else
      resolutions =
        case qualities do
          list when is_list(list) and list != [] -> list
          _ -> @default_resolutions
        end

      standards
      |> Map.put("preferred_resolutions", resolutions)
      |> maybe_put_resolution_bound("min_resolution", resolutions, &Enum.min_by/2, &<=/2)
      |> maybe_put_resolution_bound("max_resolution", resolutions, &Enum.max_by/2, &>=/2)
    end
  end

  defp maybe_put_resolution_bound(standards, key, resolutions, _picker, _cmp)
       when is_map_key(standards, key),
       do: standards

  defp maybe_put_resolution_bound(standards, key, resolutions, picker, _cmp) do
    ranked =
      resolutions
      |> Enum.filter(&(&1 in @canonical_resolutions))

    case ranked do
      [] ->
        standards

      list ->
        bound = picker.(list, fn r -> Enum.find_index(@canonical_resolutions, &(&1 == r)) end)
        Map.put(standards, key, bound)
    end
  end

  defp decode_list(nil), do: []
  defp decode_list(""), do: []

  defp decode_list(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, list} when is_list(list) -> list
      _ -> []
    end
  end

  defp decode_list(list) when is_list(list), do: list
  defp decode_list(_), do: []

  defp decode_map(nil), do: %{}
  defp decode_map(""), do: %{}

  defp decode_map(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp decode_map(map) when is_map(map), do: map
  defp decode_map(_), do: %{}

  # --- Drop columns (adapter-aware) ---

  defp drop_dead_columns do
    if postgres?() do
      execute("ALTER TABLE quality_profiles DROP COLUMN IF EXISTS qualities")
      execute("ALTER TABLE quality_profiles DROP COLUMN IF EXISTS metadata_preferences")
      execute("ALTER TABLE quality_profiles DROP COLUMN IF EXISTS customizations")
    else
      # SQLite: rebuild the table without the three dropped columns.
      recreate_table(
        table: :quality_profiles,
        primary_key: false,
        columns: [
          {:id, :binary_id, [primary_key: true]},
          {:name, :string, [null: false]},
          {:upgrades_allowed, :boolean, [default: true]},
          {:upgrade_until_quality, :string, []},
          {:description, :text, []},
          {:is_system, :boolean, [default: false]},
          {:version, :integer, [default: 1]},
          {:source_url, :string, []},
          {:last_synced_at, :utc_datetime, []},
          {:quality_standards, :text, []}
        ],
        indexes: [
          {[:name], [unique: true]},
          [:is_system],
          [:version]
        ]
      )
    end
  end
end
```

Note on `$1/$2` placeholders: this is correct for PostgreSQL. For SQLite the Exqlite adapter accepts `?`-style placeholders. To stay adapter-agnostic, build the UPDATE per adapter inside `backfill_preferred_resolutions/0`:

```elixir
      if new_standards != standards do
        encoded = Jason.encode!(new_standards)
        {sql, params} = update_sql(encoded, id)
        repo().query!(sql, params)
      end
```

and add:

```elixir
  defp update_sql(encoded, id) do
    if postgres?() do
      {"UPDATE quality_profiles SET quality_standards = $1 WHERE id = $2", [encoded, id]}
    else
      {"UPDATE quality_profiles SET quality_standards = ? WHERE id = ?", [encoded, id]}
    end
  end
```

Use this `update_sql/2` form in `backfill_preferred_resolutions/0` instead of the inline `$1/$2` call.

- [ ] **Step 4: Run the backfill unit test to verify it passes**

Run: `./dev mix test test/mydia/repo/migrations/unify_quality_profiles_test.exs`
Expected: PASS.

- [ ] **Step 5: Update the `QualityProfile` schema (Section A + B field removal)**

In `lib/mydia/settings/quality_profile.ex`:

Remove these lines from `@type t` (lines 19, 26, 27): `qualities:`, `metadata_preferences:`, `customizations:`.

Remove these `field` lines from the `schema` block (lines 77, 86, 87): `field :qualities, StringListType`, `field :metadata_preferences, JsonAtomMapType`, `field :customizations, JsonAtomMapType`. Remove the now-unused `alias Mydia.Settings.StringListType` (line 9) if `StringListType` is no longer referenced anywhere in the module (grep within the file first).

Rewrite `changeset/2` to drop `:qualities` and require a non-empty `preferred_resolutions`:

```elixir
  def changeset(quality_profile, attrs) do
    quality_profile
    |> cast(attrs, [
      :name,
      :upgrades_allowed,
      :upgrade_until_quality,
      :description,
      :is_system,
      :version,
      :source_url,
      :last_synced_at,
      :quality_standards
    ])
    |> validate_required([:name])
    |> unique_constraint(:name)
    |> validate_quality_standards()
    |> validate_preferred_resolutions_present()
  end
```

Add this private validator near `validate_quality_standards/1`:

```elixir
  # A profile must specify at least one preferred resolution. With the
  # standalone `qualities` list gone, the allow-list lives entirely in
  # quality_standards.preferred_resolutions.
  defp validate_preferred_resolutions_present(changeset) do
    standards = get_field(changeset, :quality_standards)

    resolutions =
      case standards do
        %{} = s -> Map.get(s, :preferred_resolutions) || Map.get(s, "preferred_resolutions")
        _ -> nil
      end

    if is_list(resolutions) and resolutions != [] do
      changeset
    else
      add_error(
        changeset,
        :quality_standards,
        "must include at least one preferred resolution"
      )
    end
  end
```

- [ ] **Step 6: Remove dead fields from the context (`quality_profiles.ex`)**

In `lib/mydia/settings/quality_profiles.ex`:

`clone_quality_profile/2` (lines 180-194): remove `qualities:`, `metadata_preferences:`, and `customizations:` from the `attrs` map:

```elixir
    attrs = %{
      name: name,
      upgrades_allowed: profile.upgrades_allowed,
      upgrade_until_quality: profile.upgrade_until_quality,
      description: profile.description,
      is_system: false,
      version: 1,
      source_url: nil,
      quality_standards: profile.quality_standards
    }
```

`compare_quality_profile_versions/2`: remove `:qualities`, `:metadata_preferences`, `:customizations` from the `fields` list (lines 244, 249, 250) and from `optional_fields` (line 266) — leaving `optional_fields = [:quality_standards]`.

`export_profile/2`: remove `qualities:`, `metadata_preferences:`, `customizations:` from `export_data` (lines 312, 314, 315).

`validate_import_schema/1` (schema_version 1): change `required_fields = ["name", "qualities"]` (line 507) to `required_fields = ["name", "quality_standards"]`.

`prepare_import_attrs/2`: remove `qualities:`, `metadata_preferences:`, `customizations:` from the `attrs` map (lines 537, 539, 540).

- [ ] **Step 7: Fix the `settings.ex` doc example**

In `lib/mydia/settings.ex`, in the `compare_quality_profile_versions/2` `@doc` example (line 285), replace `changed: %{qualities: {["720p"], ["1080p"]}, version: {1, 2}},` with a non-`qualities` field, e.g.:

```elixir
        changed: %{upgrade_until_quality: {"720p", "1080p"}, version: {1, 2}},
```

- [ ] **Step 8: Fix the default profiles**

In `lib/mydia/settings/default_quality_profiles.ex`:

Remove the `qualities:` key from each of the 8 profile maps (lines 35, 43, 57, 75, 93, 112, 132, 152).

The **"Any"** profile currently has `quality_standards: %{}` (empty) — this would now fail the `preferred_resolutions` requirement. Give it a non-empty list:

```elixir
      %{
        name: "Any",
        upgrades_allowed: true,
        upgrade_until_quality: "2160p",
        description: "Any quality, no size limits. Maximizes availability.",
        quality_standards: %{
          preferred_resolutions: ["360p", "480p", "576p", "720p", "1080p", "2160p"]
        }
      },
```

Update the moduledoc bullet at line 14 (`- `qualities` - List of allowed quality strings...`) to describe `quality_standards.preferred_resolutions` instead. Verify every remaining default already has a non-empty `preferred_resolutions` (SD, HD-720p, HD-1080p, Full HD, Remux-1080p, 4K/UHD, Remux-2160p all do).

- [ ] **Step 9: Fix the presets**

In `lib/mydia/settings/quality_profile_presets.ex`, remove the `qualities:` key from each of the ~24 preset maps (the lines listed by `grep -n "qualities:" lib/mydia/settings/quality_profile_presets.ex`). Each preset already defines `quality_standards.preferred_resolutions`; confirm with:

```bash
grep -n "preferred_resolutions" lib/mydia/settings/quality_profile_presets.ex | wc -l
```
Expected: matches the number of presets (each has one).

- [ ] **Step 10: Update remaining tests that reference `qualities`**

Search and fix:
```bash
grep -rn "\.qualities\|qualities:" test/ | grep -v preferred_qualities
```

For each fixture map that sets `qualities: [...]`, delete that key and ensure `quality_standards.preferred_resolutions` is present (most fixtures in `quality_matcher_test.exs`, `search_scorer_test.exs`, `release_ranker_test.exs` already set both — just delete the `qualities:` line). Specifically:
- `test/mydia/settings/quality_matcher_test.exs` (lines 14, 182, 299): delete `qualities:` lines.
- `test/mydia/indexers/release_ranker_test.exs` (line 29; and line 539 `build_quality_profile(%{qualities: [...]})` → `%{quality_standards: %{preferred_resolutions: ["2160p", "1080p", "720p"]}}` — check the test helper `build_quality_profile/1` and pass `preferred_resolutions` via `quality_standards`).
- `test/mydia/indexers/search_scorer_test.exs` (line 29): delete `qualities:` line.
- `test/mydia/settings/quality_profile_engine_test.exs` (lines 14, 187, 204, 216, 249, 265): delete `qualities:` lines (and the surrounding metadata-pref fixtures were already removed in Task 4).
- `test/mydia/settings/quality_profile_presets_test.exs` (lines 29, 31, 32, 162): replace assertions on `preset.profile_data.qualities` / `profile_data.qualities` with `preset.profile_data.quality_standards.preferred_resolutions` (assert it is a non-empty list).
- `test/mydia/settings_test.exs`:
  - lines 63, 903, 941, 960, 1005, 1038: delete `qualities:` keys from fixtures (ensure `quality_standards.preferred_resolutions` present).
  - lines 84-98, 164-194: replace `profile.qualities` assertions with `profile.quality_standards.preferred_resolutions` (e.g. `assert "1080p" in hd_profile.quality_standards.preferred_resolutions`).
  - line 982 (`assert cloned.qualities == profile.qualities`): replace with `assert cloned.quality_standards == profile.quality_standards`.
  - lines 985, 991 (`cloned.metadata_preferences`, `cloned.customizations`): delete these assertions.
  - lines 1018, 1045, 1060 (compare assertions on `:qualities` / `:metadata_preferences`): replace the `Map.has_key?(comparison.changed, :qualities)` assertion with one on a surviving field (e.g. `:quality_standards`), and delete the `:metadata_preferences` added/removed assertions.
  - Remove the `metadata_preferences:` / `customizations:` keys from the clone fixture at lines ~915-991.

- [ ] **Step 11: Run the migration against the dev database**

Run: `./dev mix ecto.migrate`
Expected: migration `20260628000000_unify_quality_profiles` runs cleanly (backfill + column drop).

- [ ] **Step 12: Run the full affected test suite**

Run:
```bash
./dev mix test test/mydia/settings_test.exs test/mydia/settings/quality_profile_engine_test.exs test/mydia/settings/quality_profile_presets_test.exs test/mydia/settings/quality_matcher_test.exs test/mydia/indexers/search_scorer_test.exs test/mydia/indexers/release_ranker_test.exs test/mydia/repo/migrations/unify_quality_profiles_test.exs
```
Expected: PASS. (The test database is reset and migrated automatically; confirm the schema has no `qualities`/`metadata_preferences`/`customizations` columns.)

- [ ] **Step 13: Compile cleanly and final straggler grep**

Run: `./dev mix compile --warnings-as-errors`
Then:
```bash
grep -rn "\.qualities\|:qualities\b\|metadata_preferences\|customizations\|QualityInfo\|StringListType\|DefaultMetadataPreferences" lib/ test/ | grep -v preferred_qualities
```
Expected: no matches (other than unrelated `StringListType` uses in other schemas, if any — verify each remaining hit is outside the quality-profile feature).

- [ ] **Step 14: Commit**

```bash
git add -A
git commit -m "feat(quality): clean-break migration dropping qualities/metadata_preferences/customizations"
```

---

## Task 6: Wire `preferred_audio_channels` into search scoring

**Files:**
- Modify: `lib/mydia/indexers/search_scorer.ex`
- Test: `test/mydia/indexers/search_scorer_test.exs`

**Interfaces:**
- Consumes: `SearchResult.quality` (a `Quality.t()` whose `audio` field is a parsed audio string such as `"DDP5.1"`, `"TrueHD 7.1"`, `"DTS-HD MA"`).
- Produces: `search_result_to_media_attrs/2` now includes an `:audio_channels` key (a string like `"5.1"`/`"7.1"`/`"2.0"`, or absent when not derivable), so `QualityProfile.score_media_file/2`'s `score_audio_channels/2` produces a real, non-fallback score for search results.

Currently `score_audio_channels/2` always returns the `50.0` fallback for search results because `SearchScorer` never supplies `:audio_channels` — making the `preferred_audio_channels` UI control inert for download selection. This task makes it real by deriving channels from the parsed audio string (matching the channel notation the library path already uses).

- [ ] **Step 1: Write the failing test**

In `test/mydia/indexers/search_scorer_test.exs`, add a test proving channel preference changes the score:

```elixir
  describe "audio channels affect search score" do
    test "preferred channels score higher than non-preferred" do
      profile = %Mydia.Settings.QualityProfile{
        name: "Chan",
        quality_standards: %{
          preferred_resolutions: ["1080p"],
          preferred_audio_channels: ["7.1", "5.1", "2.0"]
        }
      }

      base = fn audio ->
        %Mydia.Indexers.SearchResult{
          title: "Movie 1080p",
          size: 5_000_000_000,
          seeders: 10,
          download_url: "magnet:?x",
          indexer: "test",
          download_protocol: :torrent,
          quality: %Mydia.Library.Structs.Quality{resolution: "1080p", audio: audio}
        }
      end

      {seven_one, _, _} =
        Mydia.Indexers.SearchScorer.score_quality(base.("TrueHD 7.1"), profile, :movie)

      {two_zero, _, _} =
        Mydia.Indexers.SearchScorer.score_quality(base.("AAC 2.0"), profile, :movie)

      assert seven_one > two_zero
    end
  end
```

(Adjust the `SearchResult` fields to match its `@enforce_keys`/required fields, mirroring an existing fixture in the file.)

- [ ] **Step 2: Run it to verify it fails**

Run: `./dev mix test test/mydia/indexers/search_scorer_test.exs -k "preferred channels"`
Expected: FAIL — both score the same (channels not extracted → both hit the `50.0` fallback).

- [ ] **Step 3: Add channel extraction in `search_scorer.ex`**

In `search_result_to_media_attrs/2`, the non-nil-quality clause (lines 323-347) builds `base_attrs`. Add `audio_channels` derived from the parsed audio string. Replace the `base_attrs = %{...}` map with:

```elixir
    base_attrs = %{
      resolution: quality.resolution,
      source: quality.source,
      video_codec: video_codec,
      audio_codec: audio_codec,
      audio_channels: extract_audio_channels(quality.audio),
      file_size_mb: file_size_mb,
      media_type: media_type
    }
```

Add a private helper near the other `normalize_*` helpers:

```elixir
  # Derive an audio channel layout (e.g. "5.1", "7.1", "7.1.2", "2.0") from the
  # parsed audio string so quality_standards.preferred_audio_channels has a real
  # effect on search ranking. Returns nil when no channel notation is present.
  defp extract_audio_channels(nil), do: nil

  defp extract_audio_channels(audio) when is_binary(audio) do
    case Regex.run(~r/\b(\d\.\d(?:\.\d)?)\b/, audio) do
      [_, channels] -> channels
      _ -> nil
    end
  end
```

`score_audio_channels/2` matches `%{audio_channels: channels} when is_binary(channels)`; when `extract_audio_channels/1` returns `nil`, the map carries `audio_channels: nil`, which falls through to the existing `50.0` fallback clause — so unknown-channel results are unaffected.

- [ ] **Step 4: Run the test to verify it passes**

Run: `./dev mix test test/mydia/indexers/search_scorer_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/mydia/indexers/search_scorer.ex test/mydia/indexers/search_scorer_test.exs
git commit -m "feat(quality): wire preferred_audio_channels into search scoring"
```

---

## Task 7: Remove bitrate preference options entirely

**Files:**
- Modify: `lib/mydia/settings/quality_profile.ex` (validators, scoring, weights, moduledoc)
- Modify: `lib/mydia/settings/quality_profile_engine.ex` (`extract_media_attributes/1`)
- Modify: `lib/mydia_web/live/admin_quality_profiles_live/components.ex` (remove bitrate UI)
- Modify: `lib/mydia_web/live/admin_quality_profiles_live/index.ex` (remove bitrate param keys)
- Modify: `lib/mydia/settings/default_quality_profiles.ex`
- Modify: `lib/mydia/settings/quality_profile_presets.ex`
- Test: `test/mydia/settings_test.exs`

**Interfaces:**
- Produces: `quality_standards` no longer recognizes `min_video_bitrate_mbps`, `max_video_bitrate_mbps`, `preferred_video_bitrate_mbps`, `min_audio_bitrate_kbps`, `max_audio_bitrate_kbps`, `preferred_audio_bitrate_kbps`. `score_media_file/2`'s `breakdown` no longer contains `:video_bitrate` / `:audio_bitrate`; component weights re-normalize to sum to `1.0`.

These six keys have no UI-able real effect: search results carry no bitrate, so they only ever influenced library re-scoring via a crude `bitrate * 0.9 / 0.1` approximation. Removing them satisfies UI⟺effect parity by elimination. `score_from_range/4` is retained (still used by `score_file_size`).

- [ ] **Step 1: Remove bitrate validation from `quality_profile.ex`**

In `validate_quality_standards/1` (lines 163-184), remove the `|> validate_video_bitrates(standards)` and `|> validate_audio_bitrates(standards)` pipeline steps. Delete the `validate_video_bitrates/2` (lines 530-585) and `validate_audio_bitrates/2` (lines 587-646) functions entirely.

In the `validate_quality_standards/1` `@doc` structure example (lines 142-150), delete the `# Video bitrate ranges` and `# Audio bitrate ranges` blocks.

- [ ] **Step 2: Remove bitrate scoring + re-normalize weights**

In `score_media_file/2` (lines 287-361):
- Delete the `video_bitrate_score = score_video_bitrate(standards, media_attrs)` and `audio_bitrate_score = score_audio_bitrate(standards, media_attrs)` lines (294-295).
- In **both** `breakdown:` maps (the violations branch ~306-316 and the normal branch ~347-357), delete the `video_bitrate: video_bitrate_score,` and `audio_bitrate: audio_bitrate_score,` entries.
- Replace the `weights` map (lines 322-332) with re-normalized weights summing to 1.0:

```elixir
      weights = %{
        video_codec: 0.22,
        audio_codec: 0.16,
        audio_channels: 0.12,
        resolution: 0.24,
        source: 0.12,
        file_size: 0.07,
        hdr: 0.07
      }
```

- Replace the `total_score` computation (lines 334-343) to drop the two bitrate terms:

```elixir
      total_score =
        video_codec_score * weights.video_codec +
          audio_codec_score * weights.audio_codec +
          audio_channels_score * weights.audio_channels +
          resolution_score * weights.resolution +
          source_score * weights.source +
          file_size_score * weights.file_size +
          hdr_score * weights.hdr
```

- Delete the `score_video_bitrate/2` (lines 1048-1056) and `score_audio_bitrate/2` (lines 1058-1066) function clauses.

- [ ] **Step 3: Remove bitrate from the engine's media-attrs extraction**

In `lib/mydia/settings/quality_profile_engine.ex` `extract_media_attributes/1` (lines 476-510), delete the `video_bitrate_mbps` and `audio_bitrate_kbps` computations (lines 479-494) and remove the `video_bitrate_mbps:` and `audio_bitrate_kbps:` entries from the attributes map (lines 503-504). Keep `audio_channels`, `file_size_mb`, `extract_audio_channels/1`, and `extract_source/1`. If `generate_recommendations/3` references a bitrate breakdown key, remove that branch (grep `bitrate` in the file after editing — expect zero matches).

- [ ] **Step 4: Remove the bitrate UI block**

In `lib/mydia_web/live/admin_quality_profiles_live/components.ex`, delete the entire `<%!-- Bitrate Ranges --%>` section: from the `<div class="divider">Bitrate Ranges</div>` (line 567) through the close of the Audio Bitrate `form-control` div (line 697). Leave the `<%!-- File Size Constraints --%>` section (line 699+) intact.

- [ ] **Step 5: Remove bitrate keys from the LiveView param transform**

In `lib/mydia_web/live/admin_quality_profiles_live/index.ex`, in `transform_quality_standard_value/2`:
- Remove `"min_video_bitrate_mbps"`, `"max_video_bitrate_mbps"`, `"preferred_video_bitrate_mbps"` from the float-parsing clause's key list (lines 427-430). If that leaves the float clause with no keys, delete the whole clause.
- Remove `"min_audio_bitrate_kbps"`, `"max_audio_bitrate_kbps"`, `"preferred_audio_bitrate_kbps"` from the integer-parsing clause's key list (lines 441-442), leaving the size keys (`movie_*`, `episode_*`).

- [ ] **Step 6: Remove bitrate keys from defaults and presets**

In `lib/mydia/settings/default_quality_profiles.ex`, delete the `min_video_bitrate_mbps:` lines at 103, 123, 164.

In `lib/mydia/settings/quality_profile_presets.ex`, delete every bitrate key line:
```bash
grep -n "bitrate_mbps\|bitrate_kbps" lib/mydia/settings/quality_profile_presets.ex
```
Delete the matched key lines (207, 241, 559, 704, 743, 776, 777, 810, 849, 879, 911). Leave the prose `description:` strings that merely mention "bitrate" (725, 792, 831, 864) unchanged — they are copy, not keys.

- [ ] **Step 7: Update bitrate tests**

In `test/mydia/settings_test.exs`:
- In `describe "quality_standards validation"`, delete the bitrate validation cases that set `min_video_bitrate_mbps`/`max_video_bitrate_mbps` to assert ordering errors (around lines 1117-1132).
- In `describe "enhanced quality_standards validation"` and `describe "quality scoring"`, delete the bitrate-specific cases (around lines 1340-1360 and any `breakdown.video_bitrate`/`breakdown.audio_bitrate` assertions). For scoring tests that assert the full breakdown map shape, remove the `:video_bitrate`/`:audio_bitrate` keys from expectations.

Find every remaining reference:
```bash
grep -rn "bitrate_mbps\|bitrate_kbps\|video_bitrate\|audio_bitrate" lib/ test/
```
Expected after edits: no matches (the remaining `bitrate` hits in `test/mydia/library_test.exs` and `test/mydia/adult_test.exs` are `MediaFile.bitrate`, which is out of scope — verify each is the file column, not a quality-standards key).

- [ ] **Step 8: Run the affected suites**

Run:
```bash
./dev mix test test/mydia/settings_test.exs test/mydia/settings/quality_profile_engine_test.exs
./dev mix compile --warnings-as-errors
```
Expected: PASS, no unused-function warnings (the `score_video_bitrate`/`validate_video_bitrates` removals must be complete).

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor(quality): remove bitrate preference options (no real effect on search)"
```

---

## Task 8: Expose orphaned real controls in the UI (`upgrades_allowed`, `upgrade_until_quality`, `min_ratio`)

**Files:**
- Modify: `lib/mydia/settings/quality_profile.ex` (validate `min_ratio`)
- Modify: `lib/mydia_web/live/admin_quality_profiles_live/components.ex` (add controls)
- Modify: `lib/mydia_web/live/admin_quality_profiles_live/index.ex` (thread params)
- Test: `test/mydia/settings_test.exs`, `test/mydia/indexers/ranking_options_test.exs`

**Interfaces:**
- Consumes: `upgrades_allowed`/`upgrade_until_quality` (cast already; drive `QualityMatcher.is_upgrade?`), `quality_standards.min_ratio` (drives `RankingOptions.extract_min_ratio` → `ReleaseRanker.meets_ratio_minimum?`).
- Produces: a validated, editable `min_ratio` (non-negative number) and Basic-Info-tab controls for upgrade behavior.

These three options have real runtime effects but no UI today. `min_ratio` additionally lacks schema validation. This task closes the missing-from-UI side of parity.

- [ ] **Step 1: Write the failing changeset test for `min_ratio` validation**

In `test/mydia/settings_test.exs`, inside `describe "quality_standards validation"`, add:

```elixir
    test "rejects a negative min_ratio" do
      changeset =
        Mydia.Settings.QualityProfile.changeset(%Mydia.Settings.QualityProfile{}, %{
          name: "R",
          quality_standards: %{preferred_resolutions: ["1080p"], min_ratio: -1.0}
        })

      refute changeset.valid?
      assert changeset.errors[:quality_standards] != nil
    end

    test "accepts a non-negative min_ratio" do
      changeset =
        Mydia.Settings.QualityProfile.changeset(%Mydia.Settings.QualityProfile{}, %{
          name: "R",
          quality_standards: %{preferred_resolutions: ["1080p"], min_ratio: 0.2}
        })

      assert changeset.valid?
    end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./dev mix test test/mydia/settings_test.exs -k "min_ratio"`
Expected: FAIL — `min_ratio: -1.0` is currently accepted (no validation).

- [ ] **Step 3: Add `min_ratio` validation in `quality_profile.ex`**

In `validate_quality_standards/1`, add `|> validate_min_ratio(standards)` to the pipeline (after `validate_hdr_formats`). Add the validator near the other numeric validators:

```elixir
  defp validate_min_ratio(changeset, standards) do
    case Map.get(standards, :min_ratio) || Map.get(standards, "min_ratio") do
      nil ->
        changeset

      value when is_number(value) and value >= 0 ->
        changeset

      _ ->
        add_error(changeset, :quality_standards, "min_ratio must be a non-negative number")
    end
  end
```

Add `min_ratio` to the `validate_quality_standards/1` `@doc` structure example (in the source-preferences area), e.g. `min_ratio: 0.2,  # minimum seeder/leecher ratio for torrents`.

- [ ] **Step 4: Run the validation test to verify it passes**

Run: `./dev mix test test/mydia/settings_test.exs -k "min_ratio"`
Expected: PASS.

- [ ] **Step 5: Add upgrade controls to the Basic Info tab**

In `lib/mydia_web/live/admin_quality_profiles_live/components.ex`, in `quality_profile_basic_tab/1`, after the description input (line 325, before the closing `</div>` at 356 — note the "Allowed Qualities" block was removed in Task 3), add:

```elixir
      <.input
        field={@form[:upgrades_allowed]}
        type="checkbox"
        label="Allow automatic quality upgrades"
      />

      <div class="form-control">
        <label class="label">
          <span class="label-text">Upgrade until quality</span>
        </label>
        <select
          name="quality_profile[upgrade_until_quality]"
          class="select select-bordered w-full"
        >
          <option value="" selected={!Ecto.Changeset.get_field(@form.source, :upgrade_until_quality)}>
            No cap
          </option>
          <%= for res <- ["360p", "480p", "576p", "720p", "1080p", "2160p", "4320p"] do %>
            <option
              value={res}
              selected={Ecto.Changeset.get_field(@form.source, :upgrade_until_quality) == res}
            >
              {res}
            </option>
          <% end %>
        </select>
      </div>
```

- [ ] **Step 6: Add the `min_ratio` control to the Quality Standards tab**

In the same file, inside `quality_profile_standards_tab/1`, within the source/ranking area (near the `preferred_sources` block, around line 564), add a numeric input:

```elixir
      <div class="form-control">
        <label class="label">
          <span class="label-text font-semibold">Minimum seeder ratio (torrents)</span>
        </label>
        <input
          type="number"
          name="quality_profile[quality_standards][min_ratio]"
          placeholder="e.g. 0.2"
          step="0.05"
          min="0"
          value={
            get_in(
              Ecto.Changeset.get_field(@form.source, :quality_standards, %{}),
              [:min_ratio]
            )
          }
          class="input input-bordered w-full"
        />
        <label class="label">
          <span class="label-text-alt">
            Reject torrents whose seeder/leecher ratio is below this value. Leave blank to disable.
          </span>
        </label>
      </div>
```

- [ ] **Step 7: Thread the new params through the LiveView transform**

In `lib/mydia_web/live/admin_quality_profiles_live/index.ex`, update `transform_quality_profile_params/1` to carry the upgrade fields (build on the Task 3 version):

```elixir
  defp transform_quality_profile_params(params) do
    quality_standards =
      if params["quality_standards"] do
        transform_quality_standards(params["quality_standards"])
      else
        nil
      end

    base_params = %{
      "name" => params["name"],
      "description" => params["description"],
      "upgrades_allowed" => params["upgrades_allowed"],
      "upgrade_until_quality" => blank_to_nil(params["upgrade_until_quality"])
    }

    if quality_standards do
      Map.put(base_params, "quality_standards", quality_standards)
    else
      base_params
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
```

Add `min_ratio` parsing to `transform_quality_standard_value/2` (it must be a float). Add a clause alongside the existing float clause:

```elixir
  defp transform_quality_standard_value("min_ratio", value) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> float
      _ -> nil
    end
  end
```

(Place it before the float-list/`require_hdr`/passthrough clauses so it matches first.)

- [ ] **Step 8: Confirm the orphans now reach the engine (regression)**

The `min_ratio` ranking effect is already covered by `test/mydia/indexers/ranking_options_test.exs` (atom + string key cases). Run it to confirm nothing regressed:

Run: `./dev mix test test/mydia/indexers/ranking_options_test.exs test/mydia/settings_test.exs`
Expected: PASS.

- [ ] **Step 9: Add a LiveView smoke test for the new controls (optional but recommended)**

In the admin quality-profiles LiveView test (create `test/mydia_web/live/admin_quality_profiles_live_test.exs` if none exists, mirroring an existing LiveView test for auth/setup), open the new-profile modal and assert the controls render:

```elixir
    assert has_element?(view, "input[name='quality_profile[upgrades_allowed]']")
    assert has_element?(view, "select[name='quality_profile[upgrade_until_quality]']")
    assert has_element?(view, "input[name='quality_profile[quality_standards][min_ratio]']")
    refute has_element?(view, "input[name='quality_profile[quality_standards][min_video_bitrate_mbps]']")
```

(If the LiveView requires an authenticated admin scope, reuse the project's existing test login helper; if standing this test up is non-trivial, skip it and rely on Step 8 plus manual verification in Task 9.)

- [ ] **Step 10: Compile and commit**

Run: `./dev mix compile --warnings-as-errors`
Then:

```bash
git add -A
git commit -m "feat(quality): expose upgrades_allowed, upgrade_until_quality, min_ratio in the UI"
```

---

## Task 9: Full verification and `mix precommit`

**Files:** none (verification only).

- [ ] **Step 1: Run the full test suite**

Run: `./dev mix test`
Expected: all tests pass. Investigate and fix any failures introduced by the refactor (re-open the relevant task if so).

- [ ] **Step 2: Run precommit**

Run: `./dev mix precommit`
Expected: green (format, compile with warnings-as-errors, tests, and any other configured checks).

- [ ] **Step 3: Verify UI⟺effect parity by hand**

Start the app (`./dev up -d`), open the quality-profiles admin page, and create/edit a profile. Confirm:
- Every quality-profile control renders and saves: name, description, `upgrades_allowed`, `upgrade_until_quality`, and all `quality_standards` keys (codecs, audio channels, resolutions/min/max, sources, **min_ratio**, file-size constraints, hdr_formats, require_hdr).
- No bitrate inputs remain.
- Cross-check the rendered control set against the `quality_standards` keys still validated in `quality_profile.ex` and the attrs consumed in `score_media_file/2` / `RankingOptions` / `QualityMatcher`: each UI control maps to a real effect, and no validated/consumed key is missing from the UI.

```bash
# Mechanical cross-check: every quality_standards key the engine validates...
grep -oE "Map.get\(standards, :[a-z_]+\)" lib/mydia/settings/quality_profile.ex | sort -u
# ...should have a matching UI control:
grep -oE "quality_standards\]\[[a-z_]+\]" lib/mydia_web/live/admin_quality_profiles_live/components.ex | sort -u
```

- [ ] **Step 4: Confirm the net effect**

```bash
git diff --stat ec2cb203..HEAD
```
Expected: net deletion of dead/duplicate code (~700+ lines per the design), plus the parity additions (channel wiring, three exposed controls); one new migration, one new struct test, one new migration test.

- [ ] **Step 5: Final commit (only if precommit changed files, e.g. formatting)**

```bash
git add -A
git commit -m "chore(quality): satisfy precommit after quality-profile unification"
```

---

## Self-Review

**Spec coverage:**
- Section A (collapse dual model): schema field drop + new validation (Task 5); `QualityMatcher.is_upgrade?`/`check_quality_allowed`, `SearchScorer.ensure_preferred_resolutions` removal, `RankingOptions.preferred_qualities` source (Task 3); defaults/presets `qualities:` removal (Task 5). The undocumented-in-spec LiveView form (`admin_quality_profiles_live`) that read/wrote `qualities` is handled in Task 3 (its `preferred_resolutions` input already existed). ✓
- Section B (delete dead config): validators + `DefaultMetadataPreferences` + Engine fn + Settings/QualityProfiles functions (Task 4); schema fields + clone/export/import/compare references (Task 5). Metadata language confirmed untouched (Global Constraints). ✓
- Section C (merge structs): Task 1 (extend `Quality`) + Task 2 (replace/delete `QualityInfo`). Both parsers left as-is, emitting `Quality` (`quality_extractor.ex` already builds `%Quality{}`; `quality_parser.ex` switched to `Quality.new`). ✓
- Migration (single, adapter-aware, backfill then drop): Task 5, with a pure `backfilled_standards/2` for the required backfill test. ✓
- Testing: changeset, matcher, scorer, struct/parser, migration backfill, and `mix precommit` all covered (Tasks 1-9). ✓
- **UI⟺effect parity (added requirement):** missing-from-UI side closed by Task 8 (`upgrades_allowed`, `upgrade_until_quality`, `min_ratio` exposed + `min_ratio` validated). Inert-control side closed by Task 6 (audio channels wired into search scoring) and Task 7 (bitrate keys removed from schema/scoring/engine/UI/defaults/presets). Manual + mechanical cross-check in Task 9 Step 3. ✓

**Type consistency:** `Quality` fields/helpers defined in Task 1 (`new/1`, `empty/0`, `empty?/1`, `format/1`, `from_map/1`) are used consistently in Tasks 2/5. `preferred_resolutions/1` helper has identical semantics in `quality_matcher.ex` and `ranking_options.ex`. `backfilled_standards/2` returns string-keyed maps (matching DB JSON), consistent between migration and test.

**Risk note:** Task 5 is intentionally atomic (schema + migration in one commit) because `qualities` is `NOT NULL` with no default — splitting would break inserts. The "Any" default profile's empty `quality_standards` is explicitly fixed so fresh installs pass the new validation.
