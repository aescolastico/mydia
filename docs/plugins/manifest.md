# Manifest & Settings

Every plugin ships a JSON manifest declaring its identity, the events it
subscribes to, the capabilities it wants, and any operator-editable settings.
This page is a practical reference, using the bundled webhook notifier
(`priv/plugins/webhook_notifier.json`) as the worked example.

## A complete manifest

```json
{
  "slug": "webhook-notifier",
  "name": "Webhook Notifier",
  "version": "1.1.0",
  "description": "Posts a notification when media is added or a download completes.",
  "author": "Mydia",
  "entrypoint": "handle",
  "delivery": "durable",
  "capabilities": {
    "events:subscribe": ["media_item.added", "download.completed"],
    "net:http": ["discord.com"],
    "data:read": ["media_item"]
  },
  "settings_schema": [
    { "key": "target", "type": "enum", "label": "Target service", "required": true,
      "options": ["discord", "ntfy", "custom"] },
    { "key": "webhook_url", "type": "url", "label": "Webhook / server URL",
      "required": true, "grants_host": true }
  ]
}
```

## Top-level fields

| Field | Required | Notes |
|-------|----------|-------|
| `slug` | yes | Stable identifier, hyphenated (e.g. `webhook-notifier`). Also the override filename stem. |
| `name` | yes | Human-readable name shown in the admin UI. |
| `version` | yes | Semantic version of the plugin. |
| `description` | no | One-line summary shown in the UI. |
| `author` | no | Plugin author. |
| `entrypoint` | no | Exported handler name. Defaults to the SDK handler; leave unset unless you know you need it. |
| `delivery` | no | `durable` (retried, at-least-once) or `best-effort`. Defaults to best-effort. |
| `min_host_version` | no | Lowest Mydia version that can run this plugin. See below. |
| `capabilities` | yes | What the plugin subscribes to and is allowed to do. See below. |
| `settings_schema` | no | Operator-editable configuration fields. See below. |

## Capabilities

Capabilities are **deny-by-default** and enforced server-side on every host
call. The manifest *declares* what the plugin wants; the operator approves it at
install time. A plugin can never widen its own grant at runtime.

| Capability | Meaning |
|------------|---------|
| `events:subscribe` | The event types the plugin reacts to. Required. Each must be in the v1 catalog. |
| `net:http` | The exact hostnames the plugin may contact. No wildcards. |
| `data:read` | Read namespaces the plugin may query (v1: `media_item`). Returns a curated, read-only projection. |
| `surfaces:write` | Reserved; not available in v1. |

The v1 event catalog for `events:subscribe`:

- `media_item.added`
- `media_item.updated`
- `media_item.removed`
- `media_file.imported`
- `download.completed`
- `download.failed`

!!! warning "`net:http` is an exact-host allowlist"
    List each host you contact (`discord.com`, `api.example.com`). Wildcard
    subdomains are rejected because they would be a data-exfiltration channel.
    For services where the operator brings their own host (a self-hosted ntfy,
    a personal webhook), use a host-granting setting instead (see `grants_host`
    below) so you do not have to know the host in advance.

## Settings schema

`settings_schema` is an array of field definitions. Mydia renders them as a form
in the admin UI, and the operator's values arrive at runtime inside the event's
`metadata_json` under the `config` key (see
[Read operator settings](cookbook.md#read-operator-settings)).

### Field types

| `type` | UI | Use for |
|--------|----|---------|
| `string` | single-line text | short values, IDs, comma-separated lists |
| `text` | multi-line text | templates, long bodies |
| `url` | URL input | endpoints; pair with `grants_host` |
| `secret` | masked input | tokens, passwords (never logged, never in plugin bytes) |
| `enum` | select | a fixed set of choices via `options` |

### Field attributes

| Attribute | Applies to | Meaning |
|-----------|------------|---------|
| `key` | all | The config key your handler reads. |
| `label` | all | Form label shown to the operator. |
| `required` | all | Operator must provide a value. |
| `options` | `enum` | The allowed choices (array of strings). |
| `grants_host` | `url` | The host of the operator's value is added to the plugin's `net:http` allowlist at config time. |
| `visible_when` | all | Show the field only when another field has a given value. |

### Host-granting URL fields

A `url` field with `"grants_host": true` is how a plugin contacts a host the
operator chooses without hard-coding it. When the operator saves the value, the
host parses out its hostname and adds it to the plugin's effective `net:http`
allowlist. The plugin computes nothing; Mydia stays target-agnostic.

```json
{ "key": "webhook_url", "type": "url", "label": "Webhook / server URL",
  "required": true, "grants_host": true }
```

This is why the notifier can POST to any ntfy server or custom webhook the
operator points it at, while still declaring only `discord.com` statically.

### Conditional visibility

`visible_when` gates a field on another field's value, so the form only shows
what is relevant to the current selection:

```json
{ "key": "ntfy_priority", "type": "string", "label": "Priority (1-5)",
  "visible_when": { "target": "ntfy" } }
```

Here `ntfy_priority` only appears when the operator has set `target` to `ntfy`.

## Host-version floor

`min_host_version` (optional, a semantic version) declares the lowest Mydia host
your plugin supports. If you rely on a capability, event, or contract feature
added in a specific release, set the floor to that release. Mydia refuses to
activate a plugin whose floor exceeds the running host, with a clear
`requires mydia >= X` message. Omit it if you have no floor.

The plugin contract evolves additively: new functions, records, variant cases,
and optional fields are added without breaking existing plugins. Only a removal
or a signature change bumps the major ABI version. For the full contract and
versioning rules, see the [Reference](authoring.md#evolving-the-contract).
