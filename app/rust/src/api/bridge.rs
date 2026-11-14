//! Thin flutter_rust_bridge surface over the team engine (`engine/`, P1).
//!
//! No agricultural logic lives here: every analysis goes through
//! `field_shift_engine::integration::analyze_integration_json`, which always
//! returns one JSON envelope: `{"status":"success","data":…}` or
//! `{"status":"error","error":{code,message,component,detail,retryable}}`.
//! See docs/INTEGRATION_READINESS.md.

use serde_json::{json, Value};

/// The engine's own synthetic request fixture, embedded at build time so the
/// app and the engine tests share one source. SYNTHETIC — not NASA, not
/// measured, not agronomic advice. Replaced by P2 server data later.
const SYNTHETIC_REQUEST: &str =
    include_str!("../../../../engine/tests/fixtures/synthetic_integration_request.json");

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// Bridge smoke test (H2 gate).
#[flutter_rust_bridge::frb(sync)]
pub fn engine_version() -> String {
    format!(
        "field_shift_bridge {} → field_shift_engine",
        env!("CARGO_PKG_VERSION")
    )
}

/// Full contract path: a complete `IntegrationRequest` JSON (built from
/// farmer input + P2 server data) in, response envelope JSON out.
pub fn analyze_integration_json(request_json: String) -> String {
    // Additive version negotiation through the existing string-in/string-out
    // FRB ABI. Generated bindings and legacy request/response shapes stay stable.
    // v0.3 still deserializes and validates the entire request in its own engine.
    if serde_json::from_str::<Value>(&request_json)
        .ok()
        .and_then(|v| v.get("schema_version").cloned())
        .is_some_and(|version| version == "earthsync.engine.v0.3.0")
    {
        return field_shift_engine::v03::analyze_v03_json(&request_json);
    }
    field_shift_engine::integration::analyze_integration_json(&request_json)
}

/// Demo path until the P2 server exists: takes the engine's synthetic request
/// and applies the farmer's own answers (current crop, irrigation, drainage),
/// then runs the real engine. Location and climate stay synthetic and are
/// labelled `synthetic_demo` by the engine.
///
/// `farmer_json` keys (all optional): `current_crop` (string),
/// `irrigation` ("full" | "partial" | "none" | "unknown"),
/// `drainage` ("poor" | "moderate" | "good" | "unknown").
pub fn analyze_synthetic_demo_json(farmer_json: String) -> String {
    match build_demo_request(&farmer_json) {
        Ok(request) => field_shift_engine::integration::analyze_integration_json(&request),
        Err(message) => json!({
            "status": "error",
            "error": {
                "code": "INVALID_JSON",
                "message": message,
                "component": "bridge",
                "detail": null,
                "retryable": false,
            }
        })
        .to_string(),
    }
}

fn build_demo_request(farmer_json: &str) -> Result<String, String> {
    let farmer: Value = serde_json::from_str(farmer_json)
        .map_err(|_| "Farmer answers could not be read.".to_string())?;
    let mut request: Value = serde_json::from_str(SYNTHETIC_REQUEST)
        .map_err(|_| "Built-in demo request is invalid.".to_string())?;

    if let Some(crop) = farmer
        .get("current_crop")
        .and_then(Value::as_str)
        .filter(|crop| !crop.trim().is_empty())
    {
        request["field"]["current_crop"] = json!(crop);
    } else {
        // Unknown farmer crop must not inherit the fixture's crop identity.
        request["field"]["current_crop"] = json!("");
        request["crop_references"] = json!({"sources": [], "profiles": []});
        request["scenarios"] = json!([]);
    }

    request["field"]["irrigation_available"] =
        match farmer.get("irrigation").and_then(Value::as_str) {
            Some("full") => json!(true),
            Some("none") => json!(false),
            _ => Value::Null,
        };

    request["soil"]["drainage"] = match farmer.get("drainage").and_then(Value::as_str) {
        Some("poor") => json!("poor"),
        Some("moderate") => json!("moderate"),
        Some("good") => json!("well"),
        _ => Value::Null,
    };

    serde_json::to_string(&request).map_err(|_| "Demo request could not be encoded.".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn status(envelope: &str) -> String {
        serde_json::from_str::<Value>(envelope).unwrap()["status"]
            .as_str()
            .unwrap()
            .to_string()
    }

    #[test]
    fn version_names_bridge_and_engine() {
        assert!(engine_version().contains("field_shift_engine"));
    }

    #[test]
    fn demo_with_unknown_answers_succeeds() {
        let out: Value = serde_json::from_str(&analyze_synthetic_demo_json("{}".into())).unwrap();
        assert_eq!(out["status"], "success");
        assert_eq!(out["data"]["field"]["current_crop"], "");
        assert_eq!(out["data"]["rotations"]["scenarios"], json!([]));
    }

    #[test]
    fn farmer_drainage_reaches_engine() {
        let out = analyze_synthetic_demo_json(r#"{"drainage":"poor","irrigation":"none"}"#.into());
        let v: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["status"], "success");
        assert_eq!(v["data"]["soil"]["drainage"], "poor");
        assert_eq!(v["data"]["field"]["irrigation_available"], false);
    }

    #[test]
    fn bad_farmer_json_is_error_envelope() {
        assert_eq!(
            status(&analyze_synthetic_demo_json("not json".into())),
            "error"
        );
    }

    #[test]
    fn passthrough_uses_engine_envelope() {
        assert_eq!(
            status(&analyze_integration_json(SYNTHETIC_REQUEST.into())),
            "success"
        );
    }

    #[test]
    fn versioned_v03_dispatch_uses_real_engine_through_stable_abi() {
        let request = include_str!("../../../../engine/tests/fixtures/v03/synthetic_request.json");
        let output: Value =
            serde_json::from_str(&analyze_integration_json(request.into())).unwrap();
        assert_eq!(output["status"], "success");
        assert_eq!(output["data"]["schema_version"], "earthsync.engine.v0.3.0");
        assert_eq!(output["data"]["software_test_only"], true);
        assert!(!output["data"]["findings"].as_array().unwrap().is_empty());
    }
}
