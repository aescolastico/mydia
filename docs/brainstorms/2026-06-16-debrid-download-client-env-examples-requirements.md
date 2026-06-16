---
date: 2026-06-16
topic: debrid-download-client-env-examples
---

# Debrid Download Client Environment-Variable Examples

## Summary

Document how to configure debrid download clients (Real-Debrid, AllDebrid,
Premiumize, TorBox) via environment variables, and fill the remaining
per-type example gaps for other download clients. Updates land across the
env-var reference, the user guide, and `.env.example`.

## Problem Frame

Debrid is a fully supported client type in code (`download_client_config.ex:62`)
with provider validation and a dedicated env-var (`DOWNLOAD_CLIENT_<N>_PROVIDER`,
parsed at `loader.ex:308-313`), but it is invisible in the docs. An env-var-only
operator has no way to discover that `debrid` is a valid type, that `PROVIDER`
exists, or which four provider strings are accepted — they would have to read
the source. Separately, the per-type examples are uneven: the user guide shows
five clients but the reference doc shows only one (rqbit), and three types
(`blackhole`, `http`, `rtorrent`) have no env-var example anywhere.

## Key Decisions

- **Scope is debrid + general fill-in.** Close the debrid documentation gap
  completely, and add worked env-var examples for the client types that lack
  one. Not a structural overhaul of the download-clients docs.
- **Surfaces get role-appropriate depth.** The reference doc
  (`docs/reference/environment-variables.md`) and user guide
  (`docs/user-guide/download-clients.md`) become exhaustive — debrid plus every
  client type. `.env.example` gets a debrid sample added but stays a curated
  quick-start, not an exhaustive list of all nine types.
- **Debrid examples omit HOST/PORT.** Debrid clients ignore `HOST`/`PORT` by
  design — the provider base URL is hardcoded per provider module
  (`download_client_config.ex:212-214`). Examples must show only `NAME`,
  `TYPE`, `API_KEY`, and `PROVIDER`, so readers don't add meaningless host
  config.
- **Runtime base-URL overrides are out of scope.** Provider base URLs are
  overridable only at compile time today (`Application.get_env(:mydia,
  :real_debrid_base_url, ...)`). Adding runtime env-var equivalents is a
  feature, not documentation, and is deferred.

## Requirements

**Debrid documentation**

- R1. Add `debrid` to the documented client-type list in the reference doc
  (`environment-variables.md:110`) and confirm it appears in the user guide's
  supported-clients overview.
- R2. Document the `DOWNLOAD_CLIENT_<N>_PROVIDER` variable in the reference
  doc's Download Clients table, including that it is required for debrid clients
  and that its value must be one of `real_debrid`, `all_debrid`, `premiumize`,
  `tor_box`.
- R3. Add a worked debrid env-var example to the reference doc, the user guide,
  and `.env.example`, each showing `NAME`, `TYPE=debrid`, `API_KEY`, and
  `PROVIDER`, and showing no `HOST`/`PORT`.
- R4. Note in the debrid documentation that debrid clients default to a longer
  stall grace period (24 hours / 1440 minutes vs. 60 minutes for other clients;
  `download_client_config.ex:133`), so operators understand the differing
  behavior.

**General example fill-in**

- R5. Add a worked env-var example for each client type that currently has none
  — `blackhole`, `http`, and `rtorrent` — placed at least in the user guide
  alongside the existing examples.
- R6. Bring the reference doc's example coverage up from the single rqbit block
  so it is not the thinnest of the three surfaces, without duplicating the user
  guide wholesale (link rather than copy where appropriate).

**Consistency and discoverability**

- R7. Every example must include `DOWNLOAD_CLIENT_<N>_NAME`, since the loader
  discovers a client only when its `_NAME` var is set (`loader.ex:269-271`).
  An example missing `NAME` would silently register nothing.
- R8. The documented client-type list must match the code's `@client_types`
  exactly (`qbittorrent`, `transmission`, `rqbit`, `rtorrent`, `blackhole`,
  `http`, `sabnzbd`, `nzbget`, `debrid`) so no supported type is omitted.

## Acceptance Examples

- AE1. **Covers R3, R7.** A reader copies the debrid example, sets
  `DOWNLOAD_CLIENT_1_NAME`, `DOWNLOAD_CLIENT_1_TYPE=debrid`,
  `DOWNLOAD_CLIENT_1_API_KEY=<key>`, `DOWNLOAD_CLIENT_1_PROVIDER=real_debrid`,
  starts the container, and a working Real-Debrid client appears — no host/port
  needed, no validation error.
- AE2. **Covers R2.** A reader who sets `PROVIDER` to an unsupported value (e.g.
  `realdebrid` without the underscore) can find, from the docs alone, the list
  of the four valid strings to correct it — matching the validation error the
  app would emit (`download_client_config.ex:228`).
- AE3. **Covers R8.** A reader scanning the reference doc's client-type list
  sees all nine supported types, including `blackhole`, `http`, `rtorrent`, and
  `debrid`, which are currently absent from that list.

## Scope Boundaries

- **In scope:** documentation edits to `docs/reference/environment-variables.md`,
  `docs/user-guide/download-clients.md`, and `.env.example`.
- **Deferred:** runtime env-var overrides for provider base URLs (compile-time
  config only today); a structural overhaul of the download-clients user guide
  (per-type sections, troubleshooting, UI-vs-env decision guidance).
- **Not building:** any code change to download client config, validation, or
  loading. This is documentation only.

## Sources / Research

- `lib/mydia/settings/download_client_config.ex:52-62` — `@client_types` and
  `@debrid_providers` (the source of truth the docs must match).
- `lib/mydia/settings/download_client_config.ex:212-241` — debrid validation:
  requires `api_key` + `provider`; ignores `host`/`port`.
- `lib/mydia/settings/download_client_config.ex:133-146` — debrid 1440-minute
  grace default.
- `lib/mydia/config/loader.ex:261-313` — env-var parsing; index discovery keys
  on `_NAME`; `PROVIDER` → `connection_settings["provider"]`.
- `docs/reference/environment-variables.md:91-122` — current Download Clients
  table and the single rqbit example.
- `docs/user-guide/download-clients.md` — current per-type examples (5 clients);
  notes debrid exists in the Admin UI but gives no env-var example.
- `.env.example:163-191` — current commented examples (qBittorrent,
  Transmission only).
