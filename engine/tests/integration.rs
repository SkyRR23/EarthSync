//! SYNTHETIC TEST DATA only; no NASA observations or agronomic reference values.
use field_shift_engine::decision::{
    DecisionRequest, Eligibility, EvidenceStatus, FarmerContext, compare_rotations,
};
use field_shift_engine::integration::*;
use field_shift_engine::seasonal::{DataKind, analyze_season};

const FIXTURE: &str = include_str!("fixtures/synthetic_integration_request.json");
fn sample() -> IntegrationRequest {
    serde_json::from_str(FIXTURE).unwrap()
}
fn response(request: &IntegrationRequest) -> serde_json::Value {
    serde_json::from_str(&analyze_integration_json(
        &serde_json::to_string(request).unwrap(),
    ))
    .unwrap()
}
fn has_notice(result: &IntegrationResult, code: &str) -> bool {
    result.notices.iter().any(|n| n.code == code)
}

#[test]
fn complete_synthetic_workflow_matches_existing_engines_without_rotation_claims() {
    let request = sample();
    let result = analyze_integration(&request).unwrap();
    assert_eq!(result.field.field_id, "synthetic-integration-field");
    assert_eq!(result.climate.rainfall_total_mm, Some(100.0));
    assert_eq!(result.climate.calendar_days, 120);
    assert!(
        (result
            .climate
            .calendar_day_weighted_mean_temperature_c
            .unwrap()
            - 24.75)
            .abs()
            < 1e-12
    );
    assert_eq!(result.rotations.baseline_id, "existing");
    assert_eq!(result.rotations.scenarios.len(), 3);
    assert!(
        result
            .rotations
            .scenarios
            .iter()
            .all(|s| s.eligibility == Eligibility::InsufficientInformation
                && s.possible_benefits.is_empty())
    );
    assert!(has_notice(&result, "SYNTHETIC_DATA"));
    assert!(has_notice(&result, "CLIMATE_CONTEXT_ONLY"));
    let expected_climate = analyze_season(&request.environment.seasonal).unwrap();
    assert_eq!(
        serde_json::to_value(&result.climate).unwrap(),
        serde_json::to_value(expected_climate).unwrap()
    );
    let expected_rotations = compare_rotations(&DecisionRequest {
        farmer: FarmerContext {
            irrigation_available: request.field.irrigation_available,
            soil_texture: request.soil.texture,
            drainage: request.soil.drainage,
        },
        sources: request.crop_references.sources.clone(),
        profiles: request.crop_references.profiles.clone(),
        scenarios: request.scenarios.clone(),
    })
    .unwrap();
    assert_eq!(
        serde_json::to_value(&result.rotations).unwrap(),
        serde_json::to_value(expected_rotations).unwrap()
    );
}

#[test]
fn json_success_contract_is_deterministic_and_typed() {
    let output = analyze_integration_json(FIXTURE);
    assert_eq!(output, analyze_integration_json(FIXTURE));
    let typed: IntegrationResponse = serde_json::from_str(&output).unwrap();
    assert!(matches!(typed, IntegrationResponse::Success { .. }));
    let value: serde_json::Value = serde_json::from_str(&output).unwrap();
    assert_eq!(value["status"], "success");
    assert_eq!(value.as_object().unwrap().len(), 2);
    assert!(value.get("error").is_none());
    assert_eq!(value["data"]["data_mode"], "synthetic_demo");
    assert_eq!(
        value["data"]["climate"]["metadata"]["data_kind"],
        "hypothetical"
    );
    assert_eq!(
        value["data"]["rotations"]["sources"][0]["status"],
        "synthetic_test"
    );
    assert_eq!(
        value["data"]["rotations"]["scenarios"][1]["scenario"]["is_baseline"],
        true
    );
}

#[test]
fn preserves_raw_completeness_gaps_and_unknown_soil() {
    let mut request = sample();
    request.environment.seasonal.observations[0].rainfall_complete = false;
    request.environment.seasonal.observations[1].mean_temperature_c = None;
    request.soil.texture = None;
    let result = analyze_integration(&request).unwrap();
    assert_eq!(result.climate.rainfall_total_mm, None);
    assert_eq!(
        result.climate.calendar_day_weighted_mean_temperature_c,
        None
    );
    assert_eq!(
        result.climate.rainfall_gap_months,
        vec![request.environment.seasonal.observations[0].period]
    );
    assert_eq!(
        result.climate.temperature_gap_months,
        vec![request.environment.seasonal.observations[1].period]
    );
    assert!(!result.environment.seasonal.observations[0].rainfall_complete);
    assert_eq!(
        result.environment.seasonal.observations[0].rainfall_mm,
        Some(10.0)
    );
    assert!(has_notice(&result, "INCOMPLETE_CLIMATE"));
    assert!(
        result.rotations.scenarios[1]
            .missing_information
            .iter()
            .any(|e| e.code == "soil_texture")
    );
    let value = response(&request);
    assert!(value["data"]["climate"]["rainfall_total_mm"].is_null());
    assert!(value["data"]["soil"]["texture"].is_null());
}

#[test]
fn absent_observations_remain_successful_unknown_information() {
    let mut request = sample();
    request.environment.seasonal.observations.clear();
    let result = analyze_integration(&request).unwrap();
    assert_eq!(result.climate.rainfall_gap_months.len(), 4);
    assert_eq!(result.climate.rainfall_total_mm, None);
    assert!(has_notice(&result, "INCOMPLETE_CLIMATE"));
}

#[test]
fn irrigation_has_one_authority_and_constraints_preserve_sources() {
    let mut request = sample();
    request.field.irrigation_available = Some(false);
    let result = analyze_integration(&request).unwrap();
    let baseline = &result.rotations.scenarios[1];
    assert_eq!(
        baseline.eligibility,
        Eligibility::ConflictsWithSuppliedEvidence
    );
    let conflict = baseline
        .risks
        .iter()
        .find(|e| e.code == "water_management")
        .unwrap();
    assert_eq!(conflict.source_refs, vec!["synthetic-reference"]);
    assert_eq!(result.field.irrigation_available, Some(false));
}

#[test]
fn data_kinds_and_sources_are_never_rewritten_or_used_as_crop_scores() {
    // These are schema-path tests with synthetic values, not real observed/forecast data.
    for kind in [
        DataKind::Observed,
        DataKind::Modeled,
        DataKind::Forecast,
        DataKind::Hypothetical,
    ] {
        let mut request = sample();
        request.environment.seasonal.metadata.data_kind = kind;
        let result = analyze_integration(&request).unwrap();
        assert_eq!(
            result.environment.seasonal.metadata,
            request.environment.seasonal.metadata
        );
        assert_eq!(result.climate.metadata.data_kind, kind);
        assert_eq!(result.data_mode, DataMode::SyntheticDemo);
        assert!(has_notice(&result, "ENVIRONMENT_KIND"));
        assert!(result.rotations.contains_synthetic_references);
        assert!(
            result
                .rotations
                .scenarios
                .iter()
                .all(|s| s.eligibility == Eligibility::InsufficientInformation)
        );
    }
}

#[test]
fn source_labels_completeness_and_reference_only_status_are_preserved() {
    let mut request = sample();
    request.data_mode = DataMode::SuppliedData;
    request.crop_references.sources[0].status = EvidenceStatus::ReferenceOnly;
    request.environment.seasonal.metadata.dataset = "synthetic-independent-dataset".into();
    let result = analyze_integration(&request).unwrap();
    assert_eq!(result.data_mode, DataMode::SuppliedData);
    assert_eq!(
        result.climate.metadata.dataset,
        "synthetic-independent-dataset"
    );
    assert_eq!(
        result.rotations.sources[0].status,
        EvidenceStatus::ReferenceOnly
    );
    assert!(result.rotations.scenarios[1].crops[0].evidence.is_empty());
    assert_eq!(
        result.rotations.scenarios[1].crops[0].eligibility,
        Eligibility::InsufficientInformation
    );
}

#[test]
fn mismatched_crop_windows_are_visible_without_relabeling_climate() {
    let mut request = sample();
    request.scenarios[0].steps[0]
        .growing_window
        .as_mut()
        .unwrap()
        .start
        .year = 2025;
    let result = analyze_integration(&request).unwrap();
    assert!(has_notice(&result, "DISTINCT_GROWING_WINDOWS"));
    assert_eq!(result.climate.window, request.environment.seasonal.window);
    assert_eq!(result.rotations.scenarios[0].scenario, request.scenarios[0]);
}

#[test]
fn field_errors_and_location_mismatch_are_structured() {
    let mut request = sample();
    request.field.latitude = f64::NAN;
    assert_eq!(
        analyze_integration(&request).unwrap_err().code,
        IntegrationErrorCode::InvalidField
    );
    request = sample();
    request.field.field_id = " ".into();
    assert_eq!(
        analyze_integration(&request).unwrap_err().code,
        IntegrationErrorCode::InvalidField
    );
    request = sample();
    request.environment.longitude = 0.0;
    let value = response(&request);
    assert_eq!(value["status"], "error");
    assert_eq!(value["error"]["code"], "LOCATION_MISMATCH");
    assert_eq!(value["error"]["component"], "environment");
    assert_eq!(value["error"]["retryable"], false);
    assert!(value.get("data").is_none());
    request.environment.longitude = f64::INFINITY;
    assert_eq!(
        analyze_integration(&request).unwrap_err().code,
        IntegrationErrorCode::LocationMismatch
    );
}

#[test]
fn climate_errors_and_overflow_do_not_return_partial_success() {
    let mut request = sample();
    request.environment.seasonal.observations[0].rainfall_mm = Some(-1.0);
    let value = response(&request);
    assert_eq!(value["error"]["code"], "INVALID_CLIMATE");
    assert_eq!(value["error"]["component"], "climate");
    assert!(
        value["error"]["detail"]
            .as_str()
            .unwrap()
            .contains("InvalidRainfall")
    );
    request = sample();
    request.environment.seasonal.observations[0].rainfall_mm = Some(f64::MAX);
    request.environment.seasonal.observations[1].rainfall_mm = Some(f64::MAX);
    assert_eq!(response(&request)["error"]["code"], "INVALID_CLIMATE");
    request = sample();
    request.environment.seasonal.observations[0].rainfall_mm = Some(f64::NAN);
    assert_eq!(
        analyze_integration(&request).unwrap_err().code,
        IntegrationErrorCode::InvalidClimate
    );
}

#[test]
fn rotation_errors_do_not_become_success_or_hide_the_baseline_problem() {
    let mut request = sample();
    request.scenarios[1].is_baseline = false;
    let value = response(&request);
    assert_eq!(value["error"]["code"], "INVALID_ROTATIONS");
    assert_eq!(value["error"]["component"], "rotations");
    assert_eq!(value["error"]["detail"], "Require exactly one baseline");
    assert!(value.get("data").is_none());
}

#[test]
fn malformed_json_wrong_units_and_multiple_series_are_rejected_without_echo() {
    for input in ["{", "{}", "null"] {
        let value: serde_json::Value =
            serde_json::from_str(&analyze_integration_json(input)).unwrap();
        assert_eq!(value["error"]["code"], "INVALID_JSON");
    }
    let mut value: serde_json::Value = serde_json::from_str(FIXTURE).unwrap();
    value["environment"]["seasonal"]["metadata"]["rainfall_unit"] = "mm/day".into();
    let output = analyze_integration_json(&value.to_string());
    assert!(!output.contains("mm/day"));
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&output).unwrap()["error"]["code"],
        "INVALID_JSON"
    );
    value = serde_json::from_str(FIXTURE).unwrap();
    value["environment"] =
        serde_json::json!([value["environment"].clone(), value["environment"].clone()]);
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&analyze_integration_json(&value.to_string()))
            .unwrap()["error"]["code"],
        "INVALID_JSON"
    );
}

// Captured NASA response: real modeled climate, no crop constraints.
fn captured_climate_only() -> IntegrationRequest {
    let capture: serde_json::Value = serde_json::from_str(include_str!(
        "../../app/assets/fixtures/nasa_power_real.json"
    ))
    .unwrap();
    let mut request = sample();
    request.data_mode = DataMode::SuppliedData;
    request.field.latitude = 16.85;
    request.field.longitude = 96.15;
    request.field.current_crop.clear(); // Legacy string representation of unreported crop.
    request.environment = serde_json::from_value(capture["environment"].clone()).unwrap();
    request.crop_references.sources.clear();
    request.crop_references.profiles.clear();
    request.scenarios.clear();
    request
}

#[test]
fn real_capture_climate_only_never_invents_a_crop_or_suitability() {
    let result = analyze_integration(&captured_climate_only()).unwrap();
    assert_eq!(result.climate.rainfall_total_mm, Some(0.04));
    assert!(
        (result
            .climate
            .calendar_day_weighted_mean_temperature_c
            .unwrap()
            - 28.03655172413793)
            .abs()
            < 1e-12
    );
    assert_eq!(result.climate.calendar_days, 29);
    assert!(result.field.current_crop.is_empty());
    assert!(result.rotations.scenarios.is_empty());
    assert!(!result.rotations.contains_synthetic_references);
    assert!(has_notice(&result, "CLIMATE_CONTEXT_ONLY"));
}

#[test]
fn climate_only_missing_month_is_successful_unknown_not_zero() {
    let mut request = captured_climate_only();
    request.environment.seasonal.observations.clear();
    let result = analyze_integration(&request).unwrap();
    assert_eq!(result.climate.rainfall_total_mm, None);
    assert_eq!(
        result.climate.calendar_day_weighted_mean_temperature_c,
        None
    );
    assert_eq!(result.climate.rainfall_gap_months.len(), 1);
    assert!(has_notice(&result, "INCOMPLETE_CLIMATE"));
}

#[test]
fn climate_only_still_validates_field_and_exact_point() {
    let mut request = captured_climate_only();
    request.field.latitude = 91.0;
    assert_eq!(
        analyze_integration(&request).unwrap_err().code,
        IntegrationErrorCode::InvalidField
    );
    request.field.latitude = 16.86;
    assert_eq!(
        analyze_integration(&request).unwrap_err().code,
        IntegrationErrorCode::LocationMismatch
    );
}

#[test]
fn empty_scenarios_with_crop_evidence_still_rejects_invalid_rotations() {
    let mut request = captured_climate_only();
    request.crop_references = sample().crop_references;
    assert_eq!(
        analyze_integration(&request).unwrap_err().code,
        IntegrationErrorCode::InvalidRotations
    );
}
