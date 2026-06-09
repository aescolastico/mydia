# Authoring Plugins

Mydia plugins are sandboxed **WebAssembly components** that react to library
events and can reach out through a small set of capability-gated host functions.
You write a plugin in Rust against the published **`mydia-plugin-sdk`** crate:
one plain, typed handler function becomes a complete component.

This page covers the contract, the capability model, the event catalog, the
host-version floor, and the edit → build → reload dev loop, with the bundled
webhook notifier as the worked example.

## The model in one minute

- A plugin is a Wasm **component** built for `wasm32-wasip2` against the
  canonical WIT contract `mydia:plugin@1.0.0`.
- It **exports** one function — `handler.on-event` — which the host calls for
  each subscribed event.
- It **imports** the host's capabilities — `http-request`, `data-read`, `log` —
  each enforced server-side on every call. There is no ambient network, file, or
  OS access; the sandbox denies stdio and the only way out is a host import.
- The SDK's `#[mydia::plugin]` macro adapts your typed handler onto the exported
  function, so you never touch the generated binding boilerplate.

The WIT contract is the single source of truth, living at
`native/mydia_plugin_sdk/wit/plugin.wit`. Both the Elixir host and your guest
build against it, so the contract cannot drift: wasmtime's component linker
type-checks the boundary at instantiation and refuses an incompatible plugin.

## Your first plugin

Add the SDK as a dependency and write a handler. The starter lives at
`native/mydia_plugin_sdk/examples/minimal` — copy it.

`Cargo.toml`:

```toml
[package]
name = "my_plugin"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
mydia-plugin-sdk = { git = "https://github.com/getmydia/mydia", branch = "master" }

[profile.release]
opt-level = "z"
lto = true
strip = true
panic = "abort"
```

`src/lib.rs`:

```rust
use mydia_plugin_sdk::types::Event;

#[mydia_plugin_sdk::plugin]
fn on_event(evt: Event) -> Result<String, String> {
    Ok(format!("{{\"handled\":\"{}\"}}", evt.event))
}
```

The handler is an ordinary function over a typed [`Event`](#the-event), returning
a small JSON result string on success or an error string the host surfaces as a
plugin error. Because it is plain Rust, you can unit-test it directly — no Wasm
build, no running host:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use mydia_plugin_sdk::types::Event;

    #[test]
    fn handles_event() {
        let evt = Event {
            event: "media_item.added".into(),
            category: None,
            severity: None,
            actor_type: None,
            actor_id: None,
            resource_type: None,
            resource_id: None,
            metadata_json: "{}".into(),
        };
        assert_eq!(on_event(evt).unwrap(), r#"{"handled":"media_item.added"}"#);
    }
}
```

Build the component:

```bash
cargo build --release --target wasm32-wasip2
```

`panic = "abort"` matters: a guest that prints a panic message to the (denied)
stderr on its way down trips a host-side limitation and times out instead of
trapping cleanly. Abort traps immediately, with no stderr write.

!!! note "Toolchain"
    You need the `wasm32-wasip2` target (`rustup target add wasm32-wasip2`), or
    run inside `nix develop`. The SDK's `wit-bindgen` dependency generates the
    component bindings — no system binding-generator is required.

## The event

The host delivers a typed `Event` record:

| Field | Type | Notes |
|-------|------|-------|
| `event` | `String` | The event type, e.g. `media_item.added`. |
| `category`, `severity` | `Option<String>` | Envelope classification. |
| `actor_type`, `actor_id` | `Option<String>` | Who triggered it. |
| `resource_type`, `resource_id` | `Option<String>` | What it concerns. |
| `metadata_json` | `String` | A JSON object string of per-event metadata (and any operator config). `"{}"` when empty. |

The arbitrary per-event detail (and the operator's plugin settings) ride in
`metadata_json` as a JSON object, so the typed envelope stays stable while the
payload varies by event. Parse it with any JSON crate when you need it.

### Event catalog (v1)

A plugin subscribes to events in its manifest; each must be in the v1 catalog:

- `media_item.added`
- `media_item.updated`
- `media_item.removed`
- `media_file.imported`
- `download.completed`
- `download.failed`

## Capabilities

Capabilities are **deny-by-default** and enforced server-side on every call — a
plugin can never widen its own grant. A manifest *declares* what it wants; the
operator approves it.

| Class | Meaning |
|-------|---------|
| `events:subscribe` | The event types the plugin reacts to (from the catalog above). Required. |
| `net:http` | The exact hostnames the plugin may contact. **No wildcards** (a wildcard subdomain is an exfiltration channel). |
| `data:read` | Scoped read namespaces (v1: `media_item`). The host returns a curated, read-only projection — never raw rows or secrets. |
| `surfaces:write` | Reserved; not available in v1. |

### Host functions

Reach capabilities through the typed SDK bindings under
`mydia_plugin_sdk::host`:

```rust
use mydia_plugin_sdk::host;
use mydia_plugin_sdk::types::{DataRequest, OutboundRequest, ReadResult};

// data:read — a curated media-item projection.
if let Ok(ReadResult::MediaItem(item)) =
    host::data_read(&DataRequest { namespace: "media_item".into(), id })
{
    let _ = item.title;
}

// net:http — a gated outbound request. The host re-validates the URL host
// against your net:http allowlist and runs an SSRF gate on every call.
let resp = host::http_request(&OutboundRequest {
    url: "https://example.com/hook".into(),
    method: "POST".into(),
    headers: vec![("content-type".into(), "application/json".into())],
    body: Some("{}".into()),
});

// log — ungated diagnostics into the plugin's activity log.
host::log("info", "did the thing");
```

Each `result<_, host-error>` surfaces a denial (`Denied`), a bad request, a
not-found, or a network error — handle it; the host never lets a guest bypass
the gate.

## Manifest

A plugin ships a JSON manifest declaring its identity, capabilities, and
operator-editable settings:

```json
{
  "slug": "my-plugin",
  "name": "My Plugin",
  "version": "1.0.0",
  "min_host_version": "0.5.0",
  "capabilities": {
    "events:subscribe": ["media_item.added", "download.completed"],
    "net:http": ["example.com"],
    "data:read": ["media_item"]
  }
}
```

### Host-version floor

`min_host_version` (optional, a semantic version) declares the lowest Mydia host
your plugin supports. Mydia refuses to activate a plugin whose floor exceeds the
running host with a clear `requires mydia >= X` message — the friendly wrapper
over wasmtime's hard link-time refusal. Omit it if you have no floor.

### Evolving the contract

The WIT package version **is** the ABI version. The contract evolves
**additively by default** — new functions, new records, new variant cases, and
new `option<T>` fields are gated with `@since` and keep existing plugins working
across host upgrades. Only a removal or a signature change bumps the major
version. So: target the lowest host you need via `min_host_version`, and expect
new capabilities to be additive.

## The dev loop

The override directory (`PLUGINS_OVERRIDE_DIR`) is the highest-precedence
artifact layer: a `<slug>.wasm` dropped there shadows the installed bytes, and
re-activation picks it up with **no host restart**. The SDK ships a helper that
builds and drops in one step:

```bash
export PLUGINS_OVERRIDE_DIR=/path/mydia/reads
native/mydia_plugin_sdk/sideload.sh path/to/my_plugin --name my-plugin
```

Then re-activate the plugin (toggle it in the admin UI, or call
`Mydia.Plugins.reload/0`) and trigger an event. The loop is:

```
edit  ->  sideload.sh  ->  re-activate  ->  test
```

The plugin must already be installed (its manifest seeded) so the host knows its
capabilities; the helper only refreshes the wasm bytes.

## Worked example: the webhook notifier

The bundled notifier (`plugins/webhook_notifier`) is the reference plugin and a
complete worked example. It:

- is authored on the SDK with `#[mydia::plugin]` over one typed handler;
- enriches each event via `data-read` (the curated media projection);
- formats a notification for the operator-selected target — a Discord embed, an
  ntfy publish, or a fully templated `custom` webhook;
- POSTs it through the gated `http-request` import;
- keeps its handler logic in plain functions, unit-tested with `cargo test`.

Read its `src/lib.rs` for a real example of reconstructing the event, calling
host functions, and returning a result the host records.

## Reference

- WIT contract: `native/mydia_plugin_sdk/wit/plugin.wit`
- SDK crate: `native/mydia_plugin_sdk`
- Starter: `native/mydia_plugin_sdk/examples/minimal`
- Reference plugin: `plugins/webhook_notifier`
- Sideload helper: `native/mydia_plugin_sdk/sideload.sh`
