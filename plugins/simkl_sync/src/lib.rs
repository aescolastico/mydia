//! Simkl two-way watched-state sync plugin (U9).
//!
//! Proves the 1.1 platform surfaces end to end: per-user connections (the host
//! attaches the bearer token via `connection-request` — the guest never sees a
//! token), KV state for watermarks/cursors/checkpoints, scheduled invocation,
//! list reads, and watched write-back.
//!
//! All per-connection state is keyed under the host-sweepable `conn/<id>/`
//! prefix (R20), so reconnecting a different account starts fresh and a removed
//! connection's state is swept with it.
//!
//! Invariants:
//!   * Pull (R15): each chunk's pulled-set delta is checkpointed to KV *before*
//!     `ensure-watched` is applied, so a kill mid-pull resumes idempotently
//!     without losing the echo guard.
//!   * Push (R16): the pending batch is persisted to KV before POST and cleared
//!     after, so a kill between POST and clear re-sends (a duplicate Simkl
//!     history entry is benign; a lost watch is not). Items pulled this run are
//!     excluded from the push by the pulled-set (no echo).

use mydia_plugin_sdk::host;
use mydia_plugin_sdk::types::{
    Connection, ConnectionStatus, Event, ListItem, ListRequest, OutboundRequest, PlaybackProgress,
    ScheduleTick, WatchTarget,
};
use std::collections::BTreeSet;
use tinyjson::JsonValue;

const DEFAULT_API_BASE: &str = "https://api.simkl.com";

// ── Handlers ────────────────────────────────────────────────────────────────

#[mydia_plugin_sdk::plugin(on_schedule = on_schedule)]
fn on_event(evt: Event) -> Result<String, String> {
    // React only to player-origin finishes. The dispatcher already suppresses
    // our own write-back echoes; skipping non-player origins keeps a sync:* or
    // foreign-plugin write from triggering an immediate re-push loop.
    if evt.event == "playback.finished" && origin_of(&evt).as_deref() == Some("player") {
        if let Some(user_id) = evt.actor_id.clone() {
            let api_base = api_base_from(&config_json_of(&evt));
            if let Some(conn) = connection_for_user(&user_id) {
                let pulled = BTreeSet::new();
                let _ = push(&conn, &api_base, &pulled);
            }
        }
    }

    Ok("{}".to_string())
}

fn on_schedule(tick: ScheduleTick) -> Result<String, String> {
    let api_base = api_base_from(&tick.config_json);

    let conns = match host::connections_list() {
        Ok(c) => c,
        Err(e) => return Err(format!("connections-list failed: {:?}", e)),
    };

    let mut invalid: Vec<String> = Vec::new();
    let mut pulled_total = 0usize;
    let mut pushed_total = 0usize;
    let mut unmatched = 0usize;

    for conn in conns {
        if matches!(conn.status, ConnectionStatus::Error) {
            continue;
        }

        match sync_connection(&conn, &api_base) {
            Ok(counts) => {
                pulled_total += counts.pulled;
                pushed_total += counts.pushed;
                unmatched += counts.unmatched;
            }
            // A 401 invalidates just this connection; other users still sync.
            Err(SyncError::Unauthorized) => invalid.push(conn.user_id.clone()),
            Err(SyncError::Host(msg)) => host::log("warn", &format!("simkl sync error: {msg}")),
        }
    }

    if unmatched > 0 {
        host::log(
            "info",
            &format!("simkl: {unmatched} item(s) had no local match"),
        );
    }

    Ok(result_json(pushed_total, pulled_total, &invalid))
}

// ── Sync engine ─────────────────────────────────────────────────────────────

struct Counts {
    pulled: usize,
    pushed: usize,
    unmatched: usize,
}

enum SyncError {
    Unauthorized,
    Host(String),
}

fn sync_connection(conn: &Connection, api_base: &str) -> Result<Counts, SyncError> {
    let (pulled_keys, pulled, unmatched) = pull(conn, api_base)?;
    let pushed = push(conn, api_base, &pulled_keys)?;
    Ok(Counts {
        pulled,
        pushed,
        unmatched,
    })
}

// Pull leg — gated by the activities cursor. Returns the pulled-set (for the
// push echo guard), how many items were applied, and how many had no local
// match.
fn pull(conn: &Connection, api_base: &str) -> Result<(BTreeSet<String>, usize, usize), SyncError> {
    let cursor_key = key(conn, "activities");
    let stored = kv_get(&cursor_key);

    let activities_body = simkl_get(conn, &format!("{api_base}/sync/activities"))?;
    let activities = parse_activities(&activities_body);

    // Unchanged cursor → skip the pull leg only (push still runs).
    if activities.is_some() && stored == activities {
        return Ok((load_pulled_set(conn), 0, 0));
    }

    let date_from = stored.clone().unwrap_or_default();
    let items_body = simkl_get(
        conn,
        &format!("{api_base}/sync/all-items?date_from={date_from}"),
    )?;
    let items = parse_all_items(&items_body);

    let mut pulled_keys = load_pulled_set(conn);
    let mut applied = 0usize;
    let mut unmatched = 0usize;

    for item in &items {
        // R15: persist the pulled-set delta BEFORE applying ensure-watched, so a
        // kill after the checkpoint keeps the item out of the push even though
        // the local write has not happened yet (the next run re-applies it
        // idempotently).
        pulled_keys.insert(item.key());
        save_pulled_set(conn, &pulled_keys);

        match host::ensure_watched(&item.to_target(conn)) {
            Ok(_) => applied += 1,
            Err(_) => unmatched += 1,
        }
    }

    // Advance the pull watermark to the Simkl activities timestamp only after the
    // whole page applied.
    if let Some(ts) = activities {
        let _ = host::kv_set(&cursor_key, &ts);
    }

    Ok((pulled_keys, applied, unmatched))
}

// Push leg — always runs, gated only by the push watermark (R16). Items in the
// pulled-set are excluded so a just-pulled watch is never echoed back.
fn push(
    conn: &Connection,
    api_base: &str,
    pulled_keys: &BTreeSet<String>,
) -> Result<usize, SyncError> {
    let watermark_key = key(conn, "push");
    let pending_key = key(conn, "pending");

    // At-least-once: a pending batch from a prior interrupted run is re-sent
    // first (a duplicate history entry is benign; a lost watch is not).
    if let Some(pending) = kv_get(&pending_key) {
        simkl_post(conn, &format!("{api_base}/sync/history"), &pending)?;
        let _ = host::kv_delete(&pending_key);
    }

    let watermark = kv_get(&watermark_key);
    let rows = list_progress(conn, watermark.as_deref());

    let to_push: Vec<PushItem> = rows
        .iter()
        .filter(|r| r.watched && r.user_id == conn.user_id)
        .filter_map(PushItem::from_progress)
        .filter(|p| !pulled_keys.contains(&p.key))
        .collect();

    if to_push.is_empty() {
        // Nothing to push, but still prune the pulled-set so it does not grow.
        clear_pulled_set(conn);
        return Ok(0);
    }

    // Simkl caps a history write at 50 items.
    let mut total = 0usize;
    for batch in to_push.chunks(50) {
        let body = build_history_body(batch);
        // Persist before POST so a kill in-flight re-sends next run.
        let _ = host::kv_set(&pending_key, &body);
        simkl_post(conn, &format!("{api_base}/sync/history"), &body)?;
        let _ = host::kv_delete(&pending_key);
        total += batch.len();
    }

    // Advance the watermark past the items we just pushed, then prune the
    // pulled-set (those items are now behind the watermark).
    if let Some(max_ts) = to_push.iter().map(|p| p.updated_at.clone()).max() {
        let _ = host::kv_set(&watermark_key, &max_ts);
    }
    clear_pulled_set(conn);

    Ok(total)
}

// ── Simkl HTTP (host-attached auth) ──────────────────────────────────────────

fn simkl_get(conn: &Connection, url: &str) -> Result<String, SyncError> {
    let req = OutboundRequest {
        url: url.to_string(),
        method: "GET".to_string(),
        headers: vec![("accept".to_string(), "application/json".to_string())],
        body: None,
    };
    send(conn, &req)
}

fn simkl_post(conn: &Connection, url: &str, body: &str) -> Result<String, SyncError> {
    let req = OutboundRequest {
        url: url.to_string(),
        method: "POST".to_string(),
        headers: vec![("content-type".to_string(), "application/json".to_string())],
        body: Some(body.to_string()),
    };
    send(conn, &req)
}

fn send(conn: &Connection, req: &OutboundRequest) -> Result<String, SyncError> {
    match host::connection_request(&conn.id, req) {
        Ok(resp) if resp.status == 401 => Err(SyncError::Unauthorized),
        Ok(resp) => Ok(resp.body.unwrap_or_default()),
        Err(e) => Err(SyncError::Host(format!("{:?}", e))),
    }
}

// ── KV helpers ────────────────────────────────────────────────────────────────

fn key(conn: &Connection, name: &str) -> String {
    format!("conn/{}/{}", conn.id, name)
}

fn kv_get(k: &str) -> Option<String> {
    host::kv_get(k).ok().flatten()
}

fn load_pulled_set(conn: &Connection) -> BTreeSet<String> {
    match kv_get(&key(conn, "pulled")) {
        Some(raw) => parse_string_array(&raw).into_iter().collect(),
        None => BTreeSet::new(),
    }
}

fn save_pulled_set(conn: &Connection, set: &BTreeSet<String>) {
    let _ = host::kv_set(&key(conn, "pulled"), &string_array_json(set));
}

fn clear_pulled_set(conn: &Connection) {
    let _ = host::kv_delete(&key(conn, "pulled"));
}

// ── data-list (paginated) ─────────────────────────────────────────────────────

fn list_progress(conn: &Connection, updated_since: Option<&str>) -> Vec<PlaybackProgress> {
    let mut out = Vec::new();
    let mut cursor: Option<String> = None;

    loop {
        let req = ListRequest {
            namespace: "playback_progress".to_string(),
            cursor: cursor.clone(),
            updated_since: updated_since.map(|s| s.to_string()),
            limit: Some(200),
        };

        let result = match host::data_list(&req) {
            Ok(r) => r,
            Err(_) => break,
        };

        for item in result.items {
            if let ListItem::PlaybackProgress(p) = item {
                out.push(p);
            }
        }

        match result.next_cursor {
            Some(c) => cursor = Some(c),
            None => break,
        }
    }

    let _ = conn;
    out
}

// ── Pure helpers (unit-tested) ────────────────────────────────────────────────

/// A watched item pulled from Simkl.
struct PulledItem {
    imdb: Option<String>,
    tmdb: Option<i64>,
    tvdb: Option<i64>,
    season: Option<u32>,
    episode: Option<u32>,
    watched_at: Option<String>,
}

impl PulledItem {
    /// A stable dedupe key for the echo guard.
    fn key(&self) -> String {
        item_key(
            self.imdb.as_deref(),
            self.tmdb,
            self.tvdb,
            self.season,
            self.episode,
        )
    }

    fn to_target(&self, conn: &Connection) -> WatchTarget {
        WatchTarget {
            user_id: conn.user_id.clone(),
            imdb_id: self.imdb.clone(),
            tmdb_id: self.tmdb,
            tvdb_id: self.tvdb,
            season_number: self.season,
            episode_number: self.episode,
            watched_at: self.watched_at.clone(),
        }
    }
}

/// A local watch to push to Simkl.
struct PushItem {
    imdb: Option<String>,
    tmdb: Option<i64>,
    tvdb: Option<i64>,
    season: Option<u32>,
    episode: Option<u32>,
    updated_at: String,
    key: String,
}

impl PushItem {
    fn from_progress(p: &PlaybackProgress) -> Option<PushItem> {
        let (season, episode) = if p.item_type == "episode" {
            (p.season_number, p.episode_number)
        } else {
            (None, None)
        };

        let key = item_key(p.imdb_id.as_deref(), p.tmdb_id, p.tvdb_id, season, episode);

        Some(PushItem {
            imdb: p.imdb_id.clone(),
            tmdb: p.tmdb_id,
            tvdb: p.tvdb_id,
            season,
            episode,
            updated_at: p.updated_at.clone(),
            key,
        })
    }
}

/// A stable key over external ids + episode coordinates. Used both as the
/// pulled-set membership key and the push dedupe key, so the two sides line up.
fn item_key(
    imdb: Option<&str>,
    tmdb: Option<i64>,
    tvdb: Option<i64>,
    season: Option<u32>,
    episode: Option<u32>,
) -> String {
    let id = if let Some(i) = imdb {
        format!("imdb:{i}")
    } else if let Some(t) = tmdb {
        format!("tmdb:{t}")
    } else if let Some(t) = tvdb {
        format!("tvdb:{t}")
    } else {
        "unknown".to_string()
    };

    match (season, episode) {
        (Some(s), Some(e)) => format!("{id}:s{s}e{e}"),
        _ => id,
    }
}

/// Builds the Simkl `/sync/history` POST body from a batch of push items,
/// splitting movies and episodes (each episode carries its show's ids plus
/// coordinates).
fn build_history_body(items: &[PushItem]) -> String {
    let mut movies = Vec::new();
    let mut episodes = Vec::new();

    for it in items {
        match (it.season, it.episode) {
            (Some(s), Some(e)) => {
                episodes.push(format!(
                    "{{\"ids\":{},\"season\":{},\"episode\":{}}}",
                    ids_json(it.imdb.as_deref(), it.tmdb, it.tvdb),
                    s,
                    e
                ));
            }
            _ => {
                movies.push(format!(
                    "{{\"ids\":{}}}",
                    ids_json(it.imdb.as_deref(), it.tmdb, it.tvdb)
                ));
            }
        }
    }

    format!(
        "{{\"movies\":[{}],\"episodes\":[{}]}}",
        movies.join(","),
        episodes.join(",")
    )
}

fn ids_json(imdb: Option<&str>, tmdb: Option<i64>, tvdb: Option<i64>) -> String {
    let mut parts = Vec::new();
    if let Some(i) = imdb {
        parts.push(format!("\"imdb\":{:?}", i));
    }
    if let Some(t) = tmdb {
        parts.push(format!("\"tmdb\":{t}"));
    }
    if let Some(t) = tvdb {
        parts.push(format!("\"tvdb\":{t}"));
    }
    format!("{{{}}}", parts.join(","))
}

/// Parses `/sync/activities` to the single `all` timestamp used as the cursor.
fn parse_activities(body: &str) -> Option<String> {
    let json: JsonValue = body.parse().ok()?;
    let obj = json.get::<std::collections::HashMap<String, JsonValue>>()?;
    obj.get("all").and_then(|v| v.get::<String>()).cloned()
}

/// Parses `/sync/all-items` into pulled items. Expects the simplified shape the
/// host integration test produces and the production Simkl categories map onto:
///   {"movies":[{"ids":{...},"watched_at":...}],
///    "episodes":[{"ids":{...show ids...},"season":n,"episode":n,"watched_at":...}]}
fn parse_all_items(body: &str) -> Vec<PulledItem> {
    let mut out = Vec::new();

    let json: JsonValue = match body.parse() {
        Ok(j) => j,
        Err(_) => return out,
    };
    let obj = match json.get::<std::collections::HashMap<String, JsonValue>>() {
        Some(o) => o,
        None => return out,
    };

    if let Some(JsonValue::Array(movies)) = obj.get("movies") {
        for m in movies {
            if let Some(item) = parse_item(m, false) {
                out.push(item);
            }
        }
    }

    if let Some(JsonValue::Array(episodes)) = obj.get("episodes") {
        for e in episodes {
            if let Some(item) = parse_item(e, true) {
                out.push(item);
            }
        }
    }

    out
}

fn parse_item(value: &JsonValue, episode: bool) -> Option<PulledItem> {
    let obj = value.get::<std::collections::HashMap<String, JsonValue>>()?;
    let ids = obj
        .get("ids")?
        .get::<std::collections::HashMap<String, JsonValue>>()?;

    let imdb = ids.get("imdb").and_then(|v| v.get::<String>()).cloned();
    let tmdb = ids.get("tmdb").and_then(num_i64);
    let tvdb = ids.get("tvdb").and_then(num_i64);

    let (season, episode_num) = if episode {
        (
            obj.get("season").and_then(num_i64).map(|n| n as u32),
            obj.get("episode").and_then(num_i64).map(|n| n as u32),
        )
    } else {
        (None, None)
    };

    let watched_at = obj
        .get("watched_at")
        .and_then(|v| v.get::<String>())
        .cloned();

    Some(PulledItem {
        imdb,
        tmdb,
        tvdb,
        season,
        episode: episode_num,
        watched_at,
    })
}

fn num_i64(v: &JsonValue) -> Option<i64> {
    v.get::<f64>().map(|n| *n as i64)
}

fn parse_string_array(body: &str) -> Vec<String> {
    match body.parse::<JsonValue>() {
        Ok(JsonValue::Array(arr)) => arr
            .iter()
            .filter_map(|v| v.get::<String>().cloned())
            .collect(),
        _ => Vec::new(),
    }
}

fn string_array_json(set: &BTreeSet<String>) -> String {
    let parts: Vec<String> = set.iter().map(|s| format!("{:?}", s)).collect();
    format!("[{}]", parts.join(","))
}

fn result_json(pushed: usize, pulled: usize, invalid: &[String]) -> String {
    let ids: Vec<String> = invalid.iter().map(|s| format!("{:?}", s)).collect();
    format!(
        "{{\"pushed\":{pushed},\"pulled\":{pulled},\"connections_invalid\":[{}]}}",
        ids.join(",")
    )
}

fn connection_for_user(user_id: &str) -> Option<Connection> {
    host::connections_list()
        .ok()?
        .into_iter()
        .find(|c| c.user_id == user_id && matches!(c.status, ConnectionStatus::Connected))
}

fn origin_of(evt: &Event) -> Option<String> {
    let json: JsonValue = evt.metadata_json.parse().ok()?;
    let obj = json.get::<std::collections::HashMap<String, JsonValue>>()?;
    obj.get("origin").and_then(|v| v.get::<String>()).cloned()
}

fn config_json_of(evt: &Event) -> String {
    // The host injects "config" into the event metadata bag on every path.
    if let Ok(JsonValue::Object(obj)) = evt.metadata_json.parse::<JsonValue>() {
        if let Some(JsonValue::Object(_)) = obj.get("config") {
            // Re-encode just the config object for api_base extraction.
            return evt.metadata_json.clone();
        }
    }
    "{}".to_string()
}

fn api_base_from(config_json: &str) -> String {
    let parsed: Result<JsonValue, _> = config_json.parse();
    let base = match parsed {
        Ok(JsonValue::Object(obj)) => {
            let cfg = match obj.get("config") {
                Some(JsonValue::Object(c)) => Some(c),
                _ => obj.get("api_base").map(|_| &obj),
            };

            cfg.and_then(|c| c.get("api_base"))
                .and_then(|v| v.get::<String>())
                .cloned()
        }
        _ => None,
    };

    base.unwrap_or_else(|| DEFAULT_API_BASE.to_string())
}

// ── Unit tests ────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn item_key_prefers_imdb_then_tmdb_then_tvdb() {
        assert_eq!(
            item_key(Some("tt1"), Some(2), Some(3), None, None),
            "imdb:tt1"
        );
        assert_eq!(item_key(None, Some(2), Some(3), None, None), "tmdb:2");
        assert_eq!(item_key(None, None, Some(3), None, None), "tvdb:3");
    }

    #[test]
    fn item_key_includes_episode_coordinates() {
        assert_eq!(
            item_key(None, None, Some(555), Some(1), Some(2)),
            "tvdb:555:s1e2"
        );
    }

    #[test]
    fn build_history_body_splits_movies_and_episodes() {
        let items = vec![
            PushItem {
                imdb: Some("tt100".into()),
                tmdb: None,
                tvdb: None,
                season: None,
                episode: None,
                updated_at: "t".into(),
                key: "imdb:tt100".into(),
            },
            PushItem {
                imdb: None,
                tmdb: None,
                tvdb: Some(555),
                season: Some(1),
                episode: Some(2),
                updated_at: "t".into(),
                key: "tvdb:555:s1e2".into(),
            },
        ];

        let body = build_history_body(&items);
        assert!(body.contains("\"movies\":[{\"ids\":{\"imdb\":\"tt100\"}}]"));
        assert!(body.contains("\"episodes\":[{\"ids\":{\"tvdb\":555},\"season\":1,\"episode\":2}]"));
    }

    #[test]
    fn parse_activities_reads_the_all_timestamp() {
        assert_eq!(
            parse_activities(r#"{"all":"2024-01-01T00:00:00Z"}"#),
            Some("2024-01-01T00:00:00Z".to_string())
        );
        assert_eq!(parse_activities("{}"), None);
    }

    #[test]
    fn parse_all_items_reads_movies_and_episodes() {
        let body = r#"{"movies":[{"ids":{"imdb":"tt100"}}],
                       "episodes":[{"ids":{"tvdb":555},"season":1,"episode":2}]}"#;
        let items = parse_all_items(body);
        assert_eq!(items.len(), 2);
        assert_eq!(items[0].key(), "imdb:tt100");
        assert_eq!(items[1].key(), "tvdb:555:s1e2");
    }

    #[test]
    fn string_array_round_trips() {
        let mut set = BTreeSet::new();
        set.insert("a".to_string());
        set.insert("b".to_string());
        let json = string_array_json(&set);
        let back: BTreeSet<String> = parse_string_array(&json).into_iter().collect();
        assert_eq!(set, back);
    }
}
