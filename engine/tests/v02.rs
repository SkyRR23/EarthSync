//! All thresholds, observations and histories are explicitly SYNTHETIC TEST DATA.
use field_shift_engine::decision::{Drainage, Eligibility, EvidenceStatus, SoilTexture};
use field_shift_engine::integration::{DataMode, analyze_integration};
use field_shift_engine::v02::*;
const FIXTURE: &str = include_str!("fixtures/synthetic_v02_request.json");
fn sample() -> AnalysisRequestV02 {
    serde_json::from_str(FIXTURE).unwrap()
}
fn d(y: u16, m: u8, day: u8) -> Date {
    Date {
        year: y,
        month: m,
        day,
    }
}
fn baseline(result: &AnalysisResultV02) -> &ScenarioAssessmentV02 {
    &result.scenarios[1]
}
fn duration(result: &AnalysisResultV02) -> &FactorAssessment {
    baseline(result)
        .critical_constraints
        .iter()
        .find(|f| f.factor_id == "step_0_duration")
        .unwrap()
}

#[test]
fn preserves_existing_result_and_baseline_order_without_ranking() {
    let r = sample();
    let out = analyze_v02(&r).unwrap();
    assert_eq!(
        serde_json::to_value(&out.integration).unwrap(),
        serde_json::to_value(analyze_integration(&r.integration).unwrap()).unwrap()
    );
    assert_eq!(
        out.scenarios
            .iter()
            .map(|s| s.scenario_id.as_str())
            .collect::<Vec<_>>(),
        vec!["alternative-a", "existing", "alternative-b"]
    );
    assert!(baseline(&out).is_baseline);
    assert_eq!(out.integration.rotations.baseline_id, "existing");
    assert_eq!(duration(&out).status, FactorStatus::Supported);
    assert_eq!(
        baseline(&out).status,
        FactorStatus::RequiresAgronomicValidation
    );
    assert_eq!(
        baseline(&out).legacy_eligibility,
        Eligibility::InsufficientInformation
    );
    assert!(out.integration.rotations.contains_synthetic_references);
    let mut selected = sample();
    selected.integration.field.latitude = 21.95;
    selected.integration.environment.latitude = 21.95;
    let selected = analyze_v02(&selected).unwrap();
    assert_eq!(selected.integration.field.latitude, 21.95);
    assert_eq!(selected.integration.environment.latitude, 21.95);
}
#[test]
fn short_season_and_long_scheduled_duration_conflict() {
    let mut r = sample();
    r.plans[1].season.available_growing_days = Some(30);
    let out = analyze_v02(&r).unwrap();
    assert_eq!(duration(&out).status, FactorStatus::Unsuitable);
    assert_eq!(baseline(&out).status, FactorStatus::Unsuitable);
    r = sample();
    r.plans[1].season.planned_harvest_date = Some(d(2027, 2, 15));
    assert_eq!(
        duration(&analyze_v02(&r).unwrap()).status,
        FactorStatus::Unsuitable
    );
}
#[test]
fn excess_season_capacity_is_not_a_maximum_duration_conflict() {
    let out = analyze_v02(&sample()).unwrap();
    assert_eq!(duration(&out).status, FactorStatus::Supported); // 120-day season, 90-day maximum, 76-day planned crop
}
#[test]
fn unknown_duration_or_schedule_remains_unknown() {
    let mut r = sample();
    r.duration_rules.clear();
    assert_eq!(
        duration(&analyze_v02(&r).unwrap()).status,
        FactorStatus::Unknown
    );
    r = sample();
    r.plans.retain(|p| p.scenario_id != "existing");
    assert_eq!(
        duration(&analyze_v02(&r).unwrap()).status,
        FactorStatus::Unknown
    );
}
#[test]
fn applicability_review_region_and_production_system_gate_rules() {
    for change in 0..4 {
        let mut r = sample();
        r.duration_rules[0].min_days = Some(1000);
        r.duration_rules[0].max_days = None;
        match change {
            0 => r.duration_rules[0].applicability.reviewed_for_context = false,
            1 => r.region_id = None,
            2 => r.duration_rules[0].applicability.region_id = "different_region".into(),
            _ => {
                r.duration_rules[0].applicability.production_system =
                    field_shift_engine::decision::ProductionSystem::Upland
            }
        }
        assert_eq!(
            duration(&analyze_v02(&r).unwrap()).status,
            FactorStatus::Unknown
        );
    }
}
#[test]
fn reference_only_and_synthetic_rules_in_supplied_mode_are_not_trusted() {
    let mut r = sample();
    r.integration.crop_references.sources[0].status = EvidenceStatus::ReferenceOnly;
    assert_eq!(
        duration(&analyze_v02(&r).unwrap()).status,
        FactorStatus::Unknown
    );
    r = sample();
    r.integration.data_mode = DataMode::SuppliedData;
    r.plans[1].season.available_growing_days = Some(1);
    let out = analyze_v02(&r).unwrap();
    assert_eq!(duration(&out).status, FactorStatus::Unknown);
    assert_ne!(baseline(&out).status, FactorStatus::Unsuitable);
}
#[test]
fn missing_crop_identity_cannot_apply_a_duration_rule() {
    let mut r = sample();
    r.integration.scenarios[1].steps[0].crop_id = None;
    r.duration_rules[0].min_days = Some(1000);
    r.duration_rules[0].max_days = None;
    assert_eq!(
        duration(&analyze_v02(&r).unwrap()).status,
        FactorStatus::Unknown
    );
}
#[test]
fn sequential_overlap_requires_explicit_declaration_and_sources() {
    let mut r = sample();
    let out = analyze_v02(&r).unwrap();
    let schedule = |o: &AnalysisResultV02| {
        o.scenarios[2]
            .critical_constraints
            .iter()
            .find(|f| f.factor_id == "schedule")
            .unwrap()
            .status
    };
    assert_eq!(schedule(&out), FactorStatus::Unsuitable);
    r.sequential_only = false;
    assert_eq!(schedule(&analyze_v02(&r).unwrap()), FactorStatus::Unknown);
    r.sequential_only = true;
    r.plans[2].season.provenance.source_refs.clear();
    assert_eq!(schedule(&analyze_v02(&r).unwrap()), FactorStatus::Unknown);
}
#[test]
fn planting_outside_sourced_season_is_a_schedule_conflict() {
    let mut r = sample();
    r.plans[1].season.season_start = Some(d(2026, 11, 15));
    assert_eq!(
        baseline(&analyze_v02(&r).unwrap()).status,
        FactorStatus::Unsuitable
    );
}
#[test]
fn cross_year_and_gregorian_leap_days_use_daily_inclusive_counts() {
    let mut r = sample();
    r.integration.scenarios[1].steps[0].growing_window = None;
    let s = &mut r.plans[1].season;
    s.planned_planting_date = Some(d(2024, 2, 1));
    s.planned_harvest_date = Some(d(2024, 3, 1));
    s.season_start = Some(d(2024, 2, 1));
    s.season_end = Some(d(2024, 3, 1));
    s.available_growing_days = None;
    r.duration_rules[0].min_days = Some(30);
    r.duration_rules[0].max_days = Some(30);
    assert_eq!(
        duration(&analyze_v02(&r).unwrap()).status,
        FactorStatus::Supported
    );
    r.plans[1].season.planned_planting_date = Some(d(2023, 2, 1));
    r.plans[1].season.planned_harvest_date = Some(d(2023, 3, 1));
    r.plans[1].season.season_start = Some(d(2023, 2, 1));
    r.plans[1].season.season_end = Some(d(2023, 3, 1));
    assert_eq!(
        duration(&analyze_v02(&r).unwrap()).status,
        FactorStatus::Unsuitable
    );
}
#[test]
fn modeled_and_farmer_soil_disagreement_is_retained_without_fusion() {
    let mut r = sample();
    let mut other = r.soil_context.texture[0].clone();
    other.id = "modeled-clay".into();
    other.value = Some(SoilTexture::Clay);
    other.provenance.kind = EvidenceKind::Modeled;
    other.provenance.spatial_resolution_m = Some(40000.0);
    r.soil_context.texture.push(other);
    let out = analyze_v02(&r).unwrap();
    let f = baseline(&out)
        .tradeoffs
        .iter()
        .find(|f| f.factor_id == "soil_texture")
        .unwrap();
    assert_eq!(f.status, FactorStatus::Conditional);
    assert!(!f.missing_information.is_empty());
    assert_eq!(out.context.soil_context.texture.len(), 2);
    assert_eq!(out.integration.soil.texture, Some(SoilTexture::Loam));
    assert_eq!(
        out.context.soil_context.texture[1]
            .provenance
            .spatial_resolution_m,
        Some(40000.0)
    );
    assert!(
        out.context.soil_context.texture[1]
            .provenance
            .uncertainty
            .is_some()
    );
}
#[test]
fn disputed_soil_cannot_prove_drainage_incompatibility() {
    let mut r = sample();
    r.integration.soil.drainage = Some(Drainage::Poor);
    // Farmer input conflicts with the independently retained source record (well drained).
    let out = analyze_v02(&r).unwrap();
    assert_ne!(baseline(&out).status, FactorStatus::Unsuitable);
    assert_eq!(
        baseline(&out).tradeoffs[1].status,
        FactorStatus::Conditional
    );
}
#[test]
fn trusted_drainage_and_irrigation_conflicts_cannot_be_averaged_away() {
    for water in [true, false] {
        let mut r = sample();
        r.farmer_intent.priorities = vec!["income".into(), "less_water".into()];
        if water {
            r.integration.field.irrigation_available = Some(false);
        } else {
            r.integration.soil.drainage = Some(Drainage::Poor);
            r.soil_context.drainage[0].value = Some(Drainage::Poor);
        }
        let out = analyze_v02(&r).unwrap();
        assert_eq!(baseline(&out).status, FactorStatus::Unsuitable);
        assert_eq!(
            baseline(&out).legacy_eligibility,
            Eligibility::ConflictsWithSuppliedEvidence
        );
        assert_eq!(duration(&out).status, FactorStatus::Supported);
    }
}
#[test]
fn missing_irrigation_and_soil_are_not_supported_conditions() {
    let mut r = sample();
    r.integration.field.irrigation_available = None;
    r.integration.soil.texture = None;
    r.soil_context.texture.clear();
    let out = analyze_v02(&r).unwrap();
    assert_eq!(
        baseline(&out).critical_constraints[0].status,
        FactorStatus::Unknown
    );
    assert_eq!(baseline(&out).tradeoffs[0].status, FactorStatus::Unknown);
}
#[test]
fn multicycle_history_is_preserved_without_family_benefits_or_current_crop_inference() {
    let r = sample();
    let out = analyze_v02(&r).unwrap();
    assert_eq!(out.context.history.cycles.len(), 2);
    assert_eq!(out.context.history.cycles[1].fallow, Some(true));
    let f = baseline(&out)
        .tradeoffs
        .iter()
        .find(|f| f.factor_id == "family_succession")
        .unwrap();
    assert_eq!(f.status, FactorStatus::Unknown);
    assert_eq!(f.evidence.len(), 2);
    let mut r = sample();
    r.history.cycles.clear();
    r.farmer_intent.recent_rotation = vec!["test_cereal".into()];
    let out = analyze_v02(&r).unwrap();
    assert!(out.context.history.cycles.is_empty());
    assert!(
        out.integration
            .rotations
            .scenarios
            .iter()
            .all(|s| s.possible_benefits.is_empty())
    );
}
#[test]
fn missing_forecasts_do_not_prevent_historical_or_hypothetical_climate_analysis() {
    let out = analyze_v02(&sample()).unwrap();
    assert_eq!(out.integration.climate.rainfall_total_mm, Some(100.0));
    assert!(
        baseline(&out)
            .tradeoffs
            .iter()
            .any(|f| f.factor_id == "weather_and_numeric_soil_rules"
                && f.status == FactorStatus::Unknown)
    );
}
#[test]
fn invalid_dates_ranges_units_and_nonfinite_soil_fail_validation() {
    for which in 0..6 {
        let mut r = sample();
        match which {
            0 => r.plans[1].season.planned_planting_date = Some(d(2026, 2, 29)),
            1 => r.soil_context.moisture[0].observation.value = Some(1.5),
            2 => r.soil_context.ph[0].value = Some(f64::NAN),
            3 => r.soil_context.texture[0].provenance.spatial_resolution_m = Some(-1.0),
            4 => r.history.cycles[0].harvest_date = Some(d(2020, 1, 1)),
            _ => r.duration_rules[0].max_days = Some(1),
        }
        assert!(analyze_v02(&r).is_err());
    }
}
#[test]
fn invalid_reference_and_plan_links_are_errors() {
    for which in 0..4 {
        let mut r = sample();
        match which {
            0 => r.plans[0].step_index = 999,
            1 => r.plans.push(r.plans[0].clone()),
            2 => r.duration_rules[0].source_refs = vec!["missing-source".into()],
            _ => r
                .profile_applicability
                .push(r.profile_applicability[0].clone()),
        };
        assert!(analyze_v02(&r).is_err());
    }
}
#[test]
fn legacy_validation_still_rejects_negative_rainfall_and_coordinates_but_allows_gaps() {
    let mut r = sample();
    r.integration.environment.seasonal.observations[0].rainfall_mm = Some(-1.0);
    assert!(analyze_v02(&r).is_err());
    r = sample();
    r.integration.field.latitude = 91.0;
    assert!(analyze_v02(&r).is_err());
    r = sample();
    r.integration.environment.seasonal.observations[0].rainfall_mm = None;
    let out = analyze_v02(&r).unwrap();
    assert_eq!(out.integration.climate.rainfall_total_mm, None);
}
#[test]
fn json_envelope_roundtrips_and_keeps_existing_api_unchanged() {
    let output = analyze_v02_json(FIXTURE);
    assert_eq!(
        output,
        include_str!("fixtures/synthetic_v02_response.json").trim()
    );
    assert_eq!(output, analyze_v02_json(FIXTURE));
    let response: AnalysisResponseV02 = serde_json::from_str(&output).unwrap();
    assert!(matches!(response, AnalysisResponseV02::Success { .. }));
    let value: serde_json::Value = serde_json::from_str(&output).unwrap();
    assert_eq!(value["status"], "success");
    assert_eq!(value["data"]["schema_version"], "0.2-provisional");
    let legacy = field_shift_engine::integration::analyze_integration_json(
        &serde_json::to_string(&sample().integration).unwrap(),
    );
    let legacy: serde_json::Value = serde_json::from_str(&legacy).unwrap();
    assert!(legacy["data"].get("schema_version").is_none());
    let bad: serde_json::Value = serde_json::from_str(&analyze_v02_json("{}")).unwrap();
    assert_eq!(bad["status"], "error");
    assert_eq!(bad["error"]["code"], "INVALID_JSON");
    let mut invalid_request = sample();
    invalid_request.plans[1].season.planned_planting_date = Some(d(2026, 2, 29));
    let error: serde_json::Value = serde_json::from_str(&analyze_v02_json(
        &serde_json::to_string(&invalid_request).unwrap(),
    ))
    .unwrap();
    assert_eq!(error["error"]["code"], "INVALID_CONTEXT");
    assert!(error.get("data").is_none());
}

#[test]
fn environment_attribution_cannot_relabel_a_series_or_duplicate_farmer_answers() {
    let mut r = sample();
    let mut p = r.soil_context.ph[0].provenance.clone();
    p.kind = EvidenceKind::Hypothetical;
    r.environmental_provenance = Some(p.clone());
    assert!(analyze_v02(&r).is_ok());
    r.environmental_provenance.as_mut().unwrap().kind = EvidenceKind::Observed;
    assert!(analyze_v02(&r).is_err());
    r = sample();
    r.farmer_intent.current_crop = Some("different_crop".into());
    assert!(analyze_v02(&r).is_err());
}
#[test]
fn unavailable_records_and_invalid_depth_are_not_usable_observations() {
    let mut r = sample();
    r.soil_context.ph[0].provenance.kind = EvidenceKind::Unavailable;
    assert!(analyze_v02(&r).is_err());
    r.soil_context.ph[0].value = None;
    assert!(analyze_v02(&r).is_ok());
    r = sample();
    r.soil_context.moisture[0].depth_cm.as_mut().unwrap().bottom = 0.0;
    assert!(analyze_v02(&r).is_err());
    r = sample();
    r.plans[1].season.provenance.kind = EvidenceKind::Unavailable;
    r.plans[1].season.available_growing_days = Some(1);
    assert_eq!(
        duration(&analyze_v02(&r).unwrap()).status,
        FactorStatus::Unknown
    );
}
