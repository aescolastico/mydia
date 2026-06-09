//! Host-function test fixture (U4) — see Cargo.toml for the behavior table.
//!
//! Exercises the typed mydia:plugin/host imports through the SDK's generated
//! bindings, so it validates the host-import callback protocol end to end.

use mydia_plugin_sdk::host;
use mydia_plugin_sdk::types::{DataRequest, Event, OutboundRequest, ReadResult};

#[mydia_plugin_sdk::plugin]
fn on_event(evt: Event) -> Result<String, String> {
    match evt.event.as_str() {
        "log" => {
            host::log("info", "hello from guest");
            Ok("{\"logged\":true}".to_string())
        }

        "http" => {
            let req = OutboundRequest {
                url: "https://example.test/hook".to_string(),
                method: "POST".to_string(),
                headers: vec![("content-type".to_string(), "application/json".to_string())],
                body: Some("{\"x\":1}".to_string()),
            };

            match host::http_request(&req) {
                Ok(resp) => Ok(format!("{{\"status\":{},\"ok\":{}}}", resp.status, resp.ok)),
                Err(e) => Err(format!("http error: {:?}", e)),
            }
        }

        "data" => {
            let id = evt.resource_id.clone().unwrap_or_default();
            let req = DataRequest {
                namespace: "media_item".to_string(),
                id,
            };

            match host::data_read(&req) {
                Ok(ReadResult::MediaItem(item)) => Ok(format!("{{\"title\":{:?}}}", item.title)),
                Err(e) => Err(format!("data error: {:?}", e)),
            }
        }

        _ => Ok("{}".to_string()),
    }
}
