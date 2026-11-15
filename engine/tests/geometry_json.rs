//! Software-test geometry only; no agricultural threshold or source is approved.
use field_shift_engine::v03::*;
use serde_json::Value;

#[test]
fn confirmed_geometry_survives_exact_json_context_roundtrip() {
    let mut request: Request =
        serde_json::from_str(include_str!("fixtures/v03/synthetic_request.json")).unwrap();
    let farm = request.farm.as_mut().unwrap();
    farm.point = Some(Point {
        latitude: 42.032,
        longitude: -93.63,
    });
    farm.boundary = Some(vec![
        Point {
            latitude: 42.0308,
            longitude: -93.64,
        },
        Point {
            latitude: 42.0308,
            longitude: -93.62675015869141,
        },
        Point {
            latitude: 42.04,
            longitude: -93.62675015869141,
        },
        Point {
            latitude: 42.04,
            longitude: -93.64,
        },
    ]);
    let expected = serde_json::to_value(&request.farm).unwrap();
    let input = serde_json::to_string(&request).unwrap();
    let response: Value = serde_json::from_str(&analyze_v03_json(&input)).unwrap();
    assert_eq!(response["status"], "success");
    assert_eq!(response["data"]["context"]["farm"], expected);
}
