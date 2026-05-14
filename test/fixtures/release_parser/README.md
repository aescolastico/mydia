# Release Parser Regression Corpora

This directory holds harvested release-name fixtures that drive the
`Mydia.Library.ReleaseParser` regression suite (see
`test/mydia/library/release_parser/corpus_test.exs`).

## Files

- `sonarr_corpus.exs` — extracted from Sonarr's `ParserTests/*.cs`
- `radarr_corpus.exs` — extracted from Radarr's `ParserTests/*.cs`
- `bitmagnet_sample.exs` — soft-truth sample from a local Bitmagnet instance

Each file is a checked-in Elixir term consumed via `Code.eval_file/1` from
the corpus runner. They are **generated artifacts** — do not edit by hand.

## Regenerating

```bash
./dev mix mydia.parser.harvest
```

Or run the underlying scripts directly:

```bash
./dev mix run scripts/harvest_sonarr_fixtures.exs --target test/fixtures/release_parser
./dev mix run scripts/sample_bitmagnet_corpus.exs --target test/fixtures/release_parser
```

The Sonarr/Radarr harvest hits the GitHub API (60 unauth / 5000 with a
`GITHUB_TOKEN` env var). The Bitmagnet sampler hits a local Bitmagnet's
GraphQL endpoint (default `http://localhost:3333/graphql`). If Bitmagnet
isn't running, the script writes an empty fixture with the unreachable flag
set — that's fine, the Sonarr/Radarr corpus is the load-bearing set.

For CI determinism (no network), pass `--bitmagnet-mock` to generate a
tiny static fixture instead.

## Pinning to specific upstream commits

The Sonarr/Radarr commit SHA is captured at the top of each generated file
as `source_ref:`. To pin a regeneration to a specific commit:

```bash
./dev mix run scripts/harvest_sonarr_fixtures.exs \
  --sonarr-ref abc123def \
  --radarr-ref 456789abc
```

By default the harvester resolves the `develop` branch HEAD of each repo.

## Field convention

Sonarr/Radarr `[TestCase(...)]` arguments map to fields via the test
method's parameter names (e.g. `seasonNumber` → `:season`,
`releaseGroup` → `:release_group`). The mapping table is in the harvest
script. Methods that use parameter names we don't model are logged in the
`:exclusions` list of each fixture file.

## License

Sonarr and Radarr are GPL-3.0-only. mydia distributes under
AGPL-3.0-or-later, which is one-way compatible with GPL-3.0 per GPL
Section 13. The fixture files are derivative test data; the upstream
copyright is attributed in `UPSTREAM_LICENSE.md`.
