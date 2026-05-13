# Upstream Test Data Attribution

The regression corpora in this directory contain test cases derived from
external open-source projects. This file records the upstream sources and
license terms.

## Sonarr

- **Project**: Sonarr — https://github.com/Sonarr/Sonarr
- **License**: GNU General Public License version 3 (GPL-3.0-only)
- **Derived files**: `sonarr_corpus.exs`
- **Source path**: `src/NzbDrone.Core.Test/ParserTests/*.cs`

## Radarr

- **Project**: Radarr — https://github.com/Radarr/Radarr
- **License**: GNU General Public License version 3 (GPL-3.0-only)
- **Derived files**: `radarr_corpus.exs`
- **Source path**: `src/NzbDrone.Core.Test/ParserTests/*.cs`

## License Compatibility

mydia is distributed under the GNU Affero General Public License version 3
or later (AGPL-3.0-or-later). Per GPL Section 13, code under GPL-3.0 may be
combined with AGPL-3.0 code provided that the resulting work is licensed
under AGPL-3.0. mydia distributes these derivative test fixtures under
AGPL-3.0-or-later, satisfying both upstream licenses.

The fixture files contain only the `[TestCase(...)]` inputs and expected
outputs from each parser test method — no Sonarr/Radarr executable code is
included. Each generated file includes the upstream commit SHA at its head
for reproducibility.

## Bitmagnet

- **Project**: Bitmagnet — https://github.com/bitmagnet-io/bitmagnet
- **Derived files**: `bitmagnet_sample.exs`
- **Source**: GraphQL API of a locally-run Bitmagnet instance

Bitmagnet samples are DHT-crawled release names (publicly broadcast on the
BitTorrent DHT) plus Bitmagnet's own classification of those names. They
are used as a soft-truth corpus for sanity checks, not for strict
assertions.
