//! Deliberately failing acceptance checks for the contributed v0.1 source only.
//! Copy into a CLEAN source-only reconstruction's engine/tests, never v0.3.
//! All mutations below are synthetic software probes, not agricultural facts.
use fieldshift_engine::{analyze_field, climate, decision::crops::evaluate, models::*};

fn context() -> FieldContext {
    serde_json::from_str(include_str!(
        "../../contracts/data/field-context.hlegu.v1.json"
    ))
    .unwrap()
}
fn library() -> CropLibrary {
    serde_json::from_str(include_str!("../../contracts/data/crop-profiles.v1.json")).unwrap()
}
fn rules() -> RotationRules {
    serde_json::from_str(include_str!("../../contracts/data/rotation-rules.v1.json")).unwrap()
}
fn farmer() -> FarmerInput {
    let mut f: FarmerInput = serde_json::from_str(include_str!(
        "../../contracts/examples/farmer-input.example.json"
    ))
    .unwrap();
    f.current_crop = Some("black_gram".into());
    f.recent_rotation.clear();
    f.planting_month = Some(10);
    f.drainage = Drainage::Good;
    f.irrigation = Irrigation::Rainfed;
    f
}
fn wet() -> FieldContext {
    let mut c = context();
    for m in &mut c.monthly {
        m.precip_mm = Some(200.0);
        m.tmax_c = Some(32.0);
        m.tmin_c = Some(22.0);
        m.t2m_c = Some(27.0);
    }
    c
}
fn one_crop() -> CropLibrary {
    let mut lib = library();
    lib.crops.retain(|c| c.crop_id == "black_gram");
    lib
}

#[test]
fn unverified_parameters_cannot_establish_support() {
    let mut crop = one_crop().crops.remove(0);
    crop.unverified = vec!["water_mm".into(), "temp_c".into()];
    assert_ne!(
        evaluate(&crop, &wet().monthly, &farmer(), &rules()).eligibility,
        Eligibility::Supported
    );
}

#[test]
fn irrigation_category_cannot_establish_delivered_water() {
    let mut c = wet();
    for m in &mut c.monthly {
        m.precip_mm = Some(0.0);
    }
    let mut f = farmer();
    f.irrigation = Irrigation::Full;
    assert_ne!(
        evaluate(&one_crop().crops[0], &c.monthly, &f, &rules()).eligibility,
        Eligibility::Supported
    );
}

#[test]
fn farm_and_context_geometry_must_agree() {
    let mut f = farmer();
    f.field.as_mut().unwrap().lat = 42.03;
    f.field.as_mut().unwrap().lon = -93.62;
    assert!(analyze_field(&f, &context(), &library(), &rules(), "SYNTHETIC").is_err());
}

#[test]
fn month_thirteen_cannot_replace_december() {
    let mut c = context();
    c.monthly[11].month = 13;
    assert!(analyze_field(&farmer(), &c, &library(), &rules(), "SYNTHETIC").is_err());
}

#[test]
fn public_annual_aggregate_must_not_accept_one_month() {
    assert_eq!(climate::annual_precip(&context().monthly[..1]), None);
}

#[test]
fn repeated_baseline_crops_must_not_be_deduplicated() {
    let mut f = farmer();
    f.current_crop = None;
    f.recent_rotation = vec![
        "rice_paddy".into(),
        "black_gram".into(),
        "rice_paddy".into(),
    ];
    let result = analyze_field(&f, &wet(), &library(), &rules(), "SYNTHETIC").unwrap();
    let ids: Vec<_> = result.scenarios[0]
        .steps
        .iter()
        .map(|s| s.crop_id.clone())
        .collect();
    assert_eq!(ids, f.recent_rotation);
}

#[test]
fn missing_nitrogen_evidence_must_not_be_a_positive_nitrogen_score() {
    let mut lib = one_crop();
    lib.crops[0].n_fixation_kg_ha = Span::default();
    let result = analyze_field(&farmer(), &wet(), &lib, &rules(), "SYNTHETIC").unwrap();
    assert_eq!(result.scenarios[0].scores.soil_n, None);
}

#[test]
fn market_use_labels_cannot_establish_income() {
    let mut lib = one_crop();
    lib.crops[0].market_use = vec!["pulse".into(), "export".into()];
    let result = analyze_field(&farmer(), &wet(), &lib, &rules(), "SYNTHETIC").unwrap();
    assert_eq!(result.scenarios[0].scores.income, None);
}

#[test]
fn fixture_context_cannot_support_live_crop_findings() {
    let mut c = wet();
    c.data_status = "fixture".into();
    let result = analyze_field(&farmer(), &c, &one_crop(), &rules(), "SYNTHETIC").unwrap();
    assert!(result.scenarios[0]
        .steps
        .iter()
        .all(|s| s.eligibility != Eligibility::Supported));
}

#[test]
fn negative_rainfall_must_fail_source_validation() {
    let mut c = wet();
    c.monthly[0].precip_mm = Some(-100.0);
    assert!(analyze_field(&farmer(), &c, &library(), &rules(), "SYNTHETIC").is_err());
}

#[test]
fn reported_shift_must_compare_the_two_declared_five_year_halves() {
    let c = context();
    let expected = climate::annual_precip(&c.recent_monthly).unwrap()
        - climate::annual_precip(&c.prior_monthly).unwrap();
    let result = analyze_field(&farmer(), &c, &library(), &rules(), "SYNTHETIC").unwrap();
    let actual = result
        .climate_summary
        .shift_vs_prior
        .unwrap()
        .rain_change_mm
        .unwrap();
    assert!(
        (actual - expected).abs() < 0.1,
        "actual {actual}, declared comparison {expected}"
    );
}

#[test]
fn baseline_planting_month_must_not_be_replaced_by_a_crop_default() {
    let mut f = farmer();
    f.planting_month = Some(6); // Contributed black-gram window is October/November.
    let result = analyze_field(&f, &wet(), &one_crop(), &rules(), "SYNTHETIC").unwrap();
    assert!(result.scenarios[0].steps[0]
        .reason_codes
        .iter()
        .any(|c| c == "WINDOW_MISMATCH"));
}
