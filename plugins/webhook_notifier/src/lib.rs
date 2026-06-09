//! Mydia bundled webhook notifier (U10) — the reference WASM guest.
//!
//! Demonstrates the v1 plugin ABI end to end:
//!   * `mydia_alloc(len) -> ptr` — the host writes the event JSON here before
//!     calling `handle`.
//!   * `handle(ptr, len) -> i64` — reads the event, formats a notification for
//!     the operator-selected target (`config.target`: a Discord embed, or an
//!     ntfy publish), enriches it via the `data_read` host function, POSTs it
//!     through the gated `http_request` host function, and returns a packed
//!     `(out_ptr << 32) | out_len` pointing at a small JSON result the host
//!     reads (`{"delivered": bool, "status": n}`).
//!
//! All egress goes through the imported host functions — the guest has no
//! ambient network or filesystem access. The destination URL arrives in the
//! event payload under `config.webhook_url`; the gate re-validates its host
//! against the plugin's granted `net:http` allowlist on every call. For ntfy
//! that host is granted from the operator's configured URL (a host-granting
//! setting), so Mydia never needs ntfy-specific knowledge.

use std::collections::HashMap;
use tinyjson::JsonValue;

// Host-provided imports (Mydia namespace). Each takes a JSON request buffer and
// a caller-provided response buffer, returning the response length (or < 0). The
// `wasm_import_module` attribute puts these under the host's "mydia" namespace
// rather than the default "env".
#[link(wasm_import_module = "mydia")]
extern "C" {
    fn http_request(req_ptr: *const u8, req_len: usize, resp_ptr: *mut u8, resp_cap: usize) -> i32;
    fn data_read(req_ptr: *const u8, req_len: usize, resp_ptr: *mut u8, resp_cap: usize) -> i32;
}

/// The host calls this to reserve guest memory for the event payload. The buffer
/// is intentionally leaked; the store is fresh per invocation (KTD9), so nothing
/// accumulates across calls.
#[no_mangle]
pub extern "C" fn mydia_alloc(len: usize) -> *mut u8 {
    let mut buf = vec![0u8; len.max(1)];
    let ptr = buf.as_mut_ptr();
    std::mem::forget(buf);
    ptr
}

/// # Safety
/// The host writes a valid UTF-8 JSON payload of `len` bytes at `ptr` (returned
/// by a prior `mydia_alloc`) before calling this.
#[no_mangle]
pub unsafe extern "C" fn handle(ptr: *const u8, len: usize) -> i64 {
    let input = std::slice::from_raw_parts(ptr, len);
    let text = String::from_utf8_lossy(input);
    let event: JsonValue = text.parse().unwrap_or(JsonValue::Null);
    write_out(process(&event))
}

fn process(event: &JsonValue) -> JsonValue {
    let config = get(event, "config");

    let webhook_url = config
        .and_then(|c| get(c, "webhook_url"))
        .and_then(as_str)
        .unwrap_or("")
        .to_string();

    if webhook_url.is_empty() {
        return object(vec![
            ("delivered", JsonValue::Boolean(false)),
            ("error", string("no webhook_url configured")),
        ]);
    }

    // The operator picks the target service; Mydia stays target-agnostic and only
    // grants the host of the configured URL. Default to discord for back-compat.
    let target = config
        .and_then(|c| get(c, "target"))
        .and_then(as_str)
        .unwrap_or("discord");

    let title = get(event, "metadata")
        .and_then(|m| get(m, "title"))
        .and_then(as_str)
        .unwrap_or("Mydia")
        .to_string();
    let verb = describe(get(event, "event").and_then(as_str).unwrap_or(""));

    // Enrich with library data via the data:read host function when possible.
    let enriched = read_media(event);
    let overview = enriched
        .as_ref()
        .and_then(|v| get(v, "overview"))
        .and_then(as_str)
        .unwrap_or("")
        .to_string();

    let req = match target {
        "ntfy" => ntfy_request(&webhook_url, config, &title, verb, &overview),
        _ => discord_request(&webhook_url, &title, verb, &overview, enriched.as_ref()),
    };

    let resp = call(true, &req);
    object(vec![
        (
            "delivered",
            JsonValue::Boolean(get(&resp, "ok").and_then(as_bool).unwrap_or(false)),
        ),
        (
            "status",
            JsonValue::Number(get(&resp, "status").and_then(as_num).unwrap_or(0.0)),
        ),
    ])
}

// Discord webhook: a JSON embed POSTed to the configured webhook URL.
fn discord_request(
    webhook_url: &str,
    title: &str,
    verb: &str,
    overview: &str,
    enriched: Option<&JsonValue>,
) -> JsonValue {
    let poster = enriched
        .and_then(|v| get(v, "poster_path"))
        .and_then(as_str)
        .unwrap_or("");

    let description = if overview.is_empty() {
        verb.to_string()
    } else {
        format!("{verb}\n\n{overview}")
    };

    let mut embed = vec![
        ("title", string(title)),
        ("description", string(&description)),
    ];
    if !poster.is_empty() {
        embed.push((
            "thumbnail",
            object(vec![("url", string(&poster_url(poster)))]),
        ));
    }

    let discord = object(vec![
        ("content", string(&format!("{verb}: {title}"))),
        ("embeds", JsonValue::Array(vec![object(embed)])),
    ]);

    object(vec![
        ("url", string(webhook_url)),
        ("method", string("POST")),
        (
            "headers",
            object(vec![("content-type", string("application/json"))]),
        ),
        ("body", string(&stringify(&discord))),
    ])
}

// ntfy publish: a plain-text body POSTed to the operator's configured URL (the
// topic is in the URL path), with metadata in headers. See
// https://docs.ntfy.sh/publish/ ("Shape A"). The host canonicalizes header case.
fn ntfy_request(
    webhook_url: &str,
    config: Option<&JsonValue>,
    title: &str,
    verb: &str,
    overview: &str,
) -> JsonValue {
    let body = if overview.is_empty() {
        verb.to_string()
    } else {
        format!("{verb}\n\n{overview}")
    };

    let mut headers = vec![
        ("content-type", string("text/plain")),
        ("title", string(title)),
    ];

    push_setting_header(&mut headers, config, "ntfy_priority", "priority", |v| {
        v.to_string()
    });
    push_setting_header(&mut headers, config, "ntfy_tags", "tags", |v| v.to_string());
    push_setting_header(&mut headers, config, "ntfy_token", "authorization", |v| {
        format!("Bearer {v}")
    });

    object(vec![
        ("url", string(webhook_url)),
        ("method", string("POST")),
        ("headers", object(headers)),
        ("body", string(&body)),
    ])
}

// Appends `header` from a non-empty `config[key]` string, transformed by `f`.
fn push_setting_header<'a>(
    headers: &mut Vec<(&'a str, JsonValue)>,
    config: Option<&JsonValue>,
    key: &str,
    header: &'a str,
    f: impl Fn(&str) -> String,
) {
    if let Some(value) = config.and_then(|c| get(c, key)).and_then(as_str) {
        if !value.is_empty() {
            headers.push((header, string(&f(value))));
        }
    }
}

fn read_media(event: &JsonValue) -> Option<JsonValue> {
    if get(event, "resource_type").and_then(as_str) != Some("media_item") {
        return None;
    }
    let id = get(event, "resource_id").and_then(as_str)?;
    let req = object(vec![("resource", string("media_item")), ("id", string(id))]);
    let resp = call(false, &req);
    if get(&resp, "error").is_some() {
        None
    } else {
        Some(resp)
    }
}

fn call(is_http: bool, req: &JsonValue) -> JsonValue {
    let body = stringify(req);
    let bytes = body.as_bytes();
    let mut resp = vec![0u8; 16_384];

    let n = unsafe {
        if is_http {
            http_request(bytes.as_ptr(), bytes.len(), resp.as_mut_ptr(), resp.len())
        } else {
            data_read(bytes.as_ptr(), bytes.len(), resp.as_mut_ptr(), resp.len())
        }
    };

    if n < 0 {
        return object(vec![("error", string("host call failed"))]);
    }

    let text = String::from_utf8_lossy(&resp[..n as usize]);
    text.parse()
        .unwrap_or_else(|_| object(vec![("error", string("bad response"))]))
}

fn write_out(v: JsonValue) -> i64 {
    let bytes = stringify(&v).into_bytes();
    let boxed = bytes.into_boxed_slice();
    let len = boxed.len() as i64;
    let ptr = Box::leak(boxed).as_ptr() as i64;
    (ptr << 32) | len
}

// ── tinyjson helpers ────────────────────────────────────────────────────────

fn get<'a>(v: &'a JsonValue, key: &str) -> Option<&'a JsonValue> {
    match v {
        JsonValue::Object(m) => m.get(key),
        _ => None,
    }
}

fn as_str(v: &JsonValue) -> Option<&str> {
    match v {
        JsonValue::String(s) => Some(s.as_str()),
        _ => None,
    }
}

fn as_bool(v: &JsonValue) -> Option<bool> {
    match v {
        JsonValue::Boolean(b) => Some(*b),
        _ => None,
    }
}

fn as_num(v: &JsonValue) -> Option<f64> {
    match v {
        JsonValue::Number(n) => Some(*n),
        _ => None,
    }
}

fn string(s: &str) -> JsonValue {
    JsonValue::String(s.to_string())
}

fn object(pairs: Vec<(&str, JsonValue)>) -> JsonValue {
    let mut m: HashMap<String, JsonValue> = HashMap::new();
    for (k, v) in pairs {
        m.insert(k.to_string(), v);
    }
    JsonValue::Object(m)
}

fn stringify(v: &JsonValue) -> String {
    v.stringify().unwrap_or_else(|_| "{}".to_string())
}

fn describe(event_type: &str) -> &'static str {
    match event_type {
        "media_item.added" => "Added to library",
        "media_item.updated" => "Updated",
        "media_item.removed" => "Removed from library",
        "media_file.imported" => "File imported",
        "download.completed" => "Download completed",
        "download.failed" => "Download failed",
        _ => "Event",
    }
}

fn poster_url(poster: &str) -> String {
    if poster.starts_with("http") {
        poster.to_string()
    } else {
        format!("https://image.tmdb.org/t/p/w500{poster}")
    }
}
