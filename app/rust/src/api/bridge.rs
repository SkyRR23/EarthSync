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
    format!("field_shift_bridge {} → field_shift_engine", env!("CARGO_PKG_VERSION"))
}

/// Full contract path: a complete `IntegrationRequest` JSON (built from
/// farmer input + P2 server data) in, response envelope JSON out.
pub fn analyze_integration_json(request_json: String) -> String {
    field_shift_engine::integration::analyze_integration_json(&request_json)
}

/// Demo path until the P2 server exists: takes the engine's synthetic request
/// and applies the farmer's own answers (current crop, irrigation, drainage),
/// then runs the real engine. Location and climate stay synthetic and are
/// labelled `synthetic_demo` by the engine.
///
/// `farmer_json` keys (all optional): `latitude`/`longitude` (the farm centre,
/// applied to both `field` and `environment` so the engine checks this farm),
/// `current_crop` (string),
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

    let lat = farmer.get("latitude").and_then(Value::as_f64);
    let lon = farmer.get("longitude").and_then(Value::as_f64);
    if let (Some(lat), Some(lon)) = (lat, lon) {
        request["field"]["latitude"] = json!(lat);
        request["field"]["longitude"] = json!(lon);
        request["environment"]["latitude"] = json!(lat);
        request["environment"]["longitude"] = json!(lon);
    }

    if let Some(crop) = farmer.get("current_crop").and_then(Value::as_str) {
        request["field"]["current_crop"] = json!(crop);
    }

    request["field"]["irrigation_available"] = match farmer.get("irrigation").and_then(Value::as_str) {
        Some("full") | Some("partial") => json!(true),
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
        assert_eq!(status(&analyze_synthetic_demo_json("{}".into())), "success");
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
    fn farm_centre_reaches_engine() {
        let out = analyze_synthetic_demo_json(r#"{"latitude":17.1,"longitude":95.9}"#.into());
        let v: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["status"], "success", "{out}");
        assert_eq!(v["data"]["field"]["latitude"], 17.1);
        assert_eq!(v["data"]["field"]["longitude"], 95.9);
    }

    #[test]
    fn bad_farmer_json_is_error_envelope() {
        assert_eq!(status(&analyze_synthetic_demo_json("not json".into())), "error");
    }

    #[test]
    fn passthrough_uses_engine_envelope() {
        assert_eq!(status(&analyze_integration_json(SYNTHETIC_REQUEST.into())), "success");
    }
}
