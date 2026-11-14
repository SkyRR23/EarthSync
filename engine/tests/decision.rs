//! All crop rules and farmer inputs here are SYNTHETIC TEST DATA, not crop advice.
use field_shift_engine::decision::*;
const FIXTURE: &str = include_str!("fixtures/synthetic_rotations.json");
fn sample() -> DecisionRequest {
    serde_json::from_str(FIXTURE).unwrap()
}
fn baseline(result: &DecisionResult) -> &RotationAssessment {
    &result.scenarios[1]
}
fn has_code(items: &[Explanation], code: &str) -> bool {
    items.iter().any(|e| e.code == code)
}

#[test]
fn synthetic_categorical_checks_support_steps_but_not_unimplemented_rotations() {
    let request = sample();
    let result = compare_rotations(&request).unwrap();
    assert_eq!(result.baseline_id, "existing");
    assert!(result.contains_synthetic_references);
    assert!(result.sources[0].citation.contains("SYNTHETIC TEST"));
    for (input, output) in request.scenarios.iter().zip(&result.scenarios) {
        assert_eq!(*input, output.scenario);
        assert_eq!(output.eligibility, Eligibility::InsufficientInformation);
        assert!(
            output
                .crops
                .iter()
                .all(|c| c.eligibility == Eligibility::SupportedBySuppliedEvidence)
        );
        assert!(output.possible_benefits.is_empty());
        assert!(has_code(&output.missing_information, "rotation_rules"));
        assert!(!output.evidence.is_empty());
        assert!(
            output
                .evidence
                .iter()
                .all(|e| e.source_refs == vec!["synthetic-reference"])
        );
    }
}

#[test]
fn production_systems_are_not_interchangeable() {
    let mut request = sample();
    request.scenarios[1].steps[0].production_system = Some(ProductionSystem::Upland);
    let result = compare_rotations(&request).unwrap();
    assert_eq!(
        baseline(&result).crops[0].eligibility,
        Eligibility::ConflictsWithSuppliedEvidence
    );
    assert!(has_code(&baseline(&result).risks, "production_system"));
    assert!(result.scenarios[0].risks.is_empty());
}

#[test]
fn planting_month_conflict_has_sources_and_is_not_climate_suitability() {
    let mut request = sample();
    request.scenarios[1].steps[0]
        .growing_window
        .as_mut()
        .unwrap()
        .start
        .month = 10;
    let result = compare_rotations(&request).unwrap();
    assert!(has_code(&baseline(&result).risks, "planting_month"));
    assert_eq!(
        baseline(&result).eligibility,
        Eligibility::ConflictsWithSuppliedEvidence
    );
}

#[test]
fn missing_soil_is_unknown_and_drainage_mismatch_is_a_conflict() {
    let mut request = sample();
    request.farmer.soil_texture = None;
    let result = compare_rotations(&request).unwrap();
    assert_eq!(
        baseline(&result).crops[0].eligibility,
        Eligibility::InsufficientInformation
    );
    assert!(has_code(
        &baseline(&result).missing_information,
        "soil_texture"
    ));
    request.farmer.drainage = Some(Drainage::Poor);
    let result = compare_rotations(&request).unwrap();
    assert_eq!(
        baseline(&result).crops[0].eligibility,
        Eligibility::ConflictsWithSuppliedEvidence
    );
    assert!(has_code(
        &baseline(&result).missing_information,
        "soil_texture"
    ));
    assert!(has_code(&baseline(&result).risks, "drainage"));
}

#[test]
fn irrigation_access_is_a_prerequisite_not_a_water_balance() {
    let mut request = sample();
    request.farmer.irrigation_available = None;
    let result = compare_rotations(&request).unwrap();
    assert!(has_code(
        &baseline(&result).missing_information,
        "water_management"
    ));
    assert_eq!(
        result.scenarios[0].crops[0].eligibility,
        Eligibility::SupportedBySuppliedEvidence
    );
    request.farmer.irrigation_available = Some(false);
    let result = compare_rotations(&request).unwrap();
    assert!(has_code(&baseline(&result).risks, "water_management"));
}

#[test]
fn missing_profile_unknown_identity_and_crop_mismatch_are_distinct() {
    let mut request = sample();
    request.scenarios[1].steps[0].profile_id = Some("absent_profile".into());
    let result = compare_rotations(&request).unwrap();
    assert_eq!(
        baseline(&result).crops[0].eligibility,
        Eligibility::InsufficientInformation
    );
    assert!(has_code(&baseline(&result).missing_information, "profile"));
    request = sample();
    request.scenarios[1].steps[0].crop_id = None;
    let result = compare_rotations(&request).unwrap();
    assert!(has_code(&baseline(&result).missing_information, "crop_id"));
    request.scenarios[1].steps[0].crop_id = Some("different_crop".into());
    let result = compare_rotations(&request).unwrap();
    assert!(has_code(&baseline(&result).risks, "crop_id"));
    assert!(baseline(&result).evidence.is_empty());
}

#[test]
fn unreviewed_or_uncited_constraints_never_establish_support_or_conflict() {
    let mut request = sample();
    request.sources[0].status = EvidenceStatus::ReferenceOnly;
    request.farmer.irrigation_available = Some(false);
    let result = compare_rotations(&request).unwrap();
    assert_eq!(
        baseline(&result).crops[0].eligibility,
        Eligibility::InsufficientInformation
    );
    assert!(baseline(&result).risks.is_empty());
    request = sample();
    request.profiles[0]
        .planting_months
        .as_mut()
        .unwrap()
        .source_refs
        .clear();
    let result = compare_rotations(&request).unwrap();
    assert!(has_code(
        &baseline(&result).missing_information,
        "planting_month"
    ));
}

#[test]
fn unsupported_requirements_and_unknown_catalog_are_never_silently_skipped() {
    let mut request = sample();
    request.profiles[0].unsupported_requirements = Some(vec![Fact {
        value: "SYNTHETIC unsupported soil chemistry requirement".into(),
        source_refs: vec!["synthetic-reference".into()],
    }]);
    let result = compare_rotations(&request).unwrap();
    assert_eq!(
        baseline(&result).crops[0].eligibility,
        Eligibility::InsufficientInformation
    );
    assert!(has_code(
        &baseline(&result).missing_information,
        "unsupported_requirement"
    ));
    request.profiles[0].unsupported_requirements = None;
    let result = compare_rotations(&request).unwrap();
    assert!(has_code(
        &baseline(&result).missing_information,
        "requirements_catalog"
    ));
}

#[test]
fn optional_profile_attributes_and_farmer_season_can_all_be_unknown() {
    let mut request = sample();
    let profile = &mut request.profiles[0];
    profile.common_name = None;
    profile.crop_family = None;
    profile.production_system = None;
    profile.planting_months = None;
    profile.soil_textures = None;
    profile.drainage = None;
    profile.water_requirement = None;
    profile.unsupported_requirements = None;
    request.scenarios[1].steps[0].growing_window = None;
    request.scenarios[1].steps[0].production_system = None;
    let result = compare_rotations(&request).unwrap();
    assert_eq!(
        baseline(&result).crops[0].eligibility,
        Eligibility::InsufficientInformation
    );
    assert!(baseline(&result).evidence.is_empty());
    assert!(baseline(&result).missing_information.len() >= 6);
}

#[test]
fn baseline_counts_duplicate_ids_and_empty_sequences_are_errors() {
    for count in [0, 2] {
        let mut request = sample();
        for (i, scenario) in request.scenarios.iter_mut().enumerate() {
            scenario.is_baseline = i < count;
        }
        assert!(compare_rotations(&request).is_err());
    }
    let mut request = sample();
    request.scenarios.pop();
    assert!(compare_rotations(&request).is_err());
    request = sample();
    request.scenarios[0].id = "existing".into();
    assert!(compare_rotations(&request).is_err());
    request = sample();
    request.scenarios[0].steps.clear();
    assert!(compare_rotations(&request).is_err());
}

#[test]
fn invalid_catalog_identifiers_duplicates_and_dangling_sources_are_errors() {
    let mut request = sample();
    request.profiles[0].crop_id = "Not a stable ID".into();
    assert!(compare_rotations(&request).is_err());
    request = sample();
    request.profiles.push(request.profiles[0].clone());
    assert!(compare_rotations(&request).is_err());
    request = sample();
    request.sources.push(request.sources[0].clone());
    assert!(compare_rotations(&request).is_err());
    request = sample();
    request.profiles[0]
        .production_system
        .as_mut()
        .unwrap()
        .source_refs
        .push("missing".into());
    assert!(compare_rotations(&request).is_err());
    request = sample();
    request.sources[0].scope = " ".into();
    assert!(compare_rotations(&request).is_err());
}

#[test]
fn invalid_planting_months_dates_and_unsupported_categories_are_errors() {
    let mut request = sample();
    request.profiles[0].planting_months.as_mut().unwrap().value = vec![13];
    assert!(compare_rotations(&request).is_err());
    request = sample();
    request.profiles[0].drainage.as_mut().unwrap().value.clear();
    assert!(compare_rotations(&request).is_err());
    request = sample();
    request.profiles[0].soil_textures.as_mut().unwrap().value = vec![SoilTexture::Other];
    assert!(compare_rotations(&request).is_err());
    for month in [0, 13] {
        request = sample();
        request.scenarios[0].steps[0]
            .growing_window
            .as_mut()
            .unwrap()
            .start
            .month = month;
        assert!(compare_rotations(&request).is_err());
    }
    request = sample();
    request.scenarios[0].steps[0]
        .growing_window
        .as_mut()
        .unwrap()
        .end
        .year = 2025;
    assert!(compare_rotations(&request).is_err());
}

#[test]
fn other_categories_are_unknown_inputs_not_positive_matches() {
    let mut request = sample();
    request.farmer.soil_texture = Some(SoilTexture::Other);
    request.scenarios[1].steps[0].production_system = Some(ProductionSystem::Other);
    let result = compare_rotations(&request).unwrap();
    assert_eq!(
        baseline(&result).crops[0].eligibility,
        Eligibility::InsufficientInformation
    );
    assert!(has_code(
        &baseline(&result).missing_information,
        "production_system"
    ));
    assert!(has_code(
        &baseline(&result).missing_information,
        "soil_texture"
    ));
}

#[test]
fn json_is_deterministic_and_preserves_unknowns_sequences_and_synthetic_labels() {
    let mut request = sample();
    request.scenarios[0].steps[0].profile_id = None;
    let input = serde_json::to_string(&request).unwrap();
    let output = compare_rotations_json(&input).unwrap();
    assert_eq!(output, compare_rotations_json(&input).unwrap());
    let result: DecisionResult = serde_json::from_str(&output).unwrap();
    assert_eq!(result.scenarios[0].scenario, request.scenarios[0]);
    assert_eq!(result.scenarios[0].scenario.steps[0].profile_id, None);
    assert!(result.contains_synthetic_references);
    assert!(compare_rotations_json("{}").is_err());
}

#[test]
fn additional_alternatives_are_allowed_without_reordering() {
    let mut request = sample();
    let mut extra = request.scenarios[0].clone();
    extra.id = "alternative-c".into();
    request.scenarios.push(extra);
    let result = compare_rotations(&request).unwrap();
    assert_eq!(result.scenarios.len(), 4);
    assert_eq!(result.scenarios[3].scenario, request.scenarios[3]);
    assert_eq!(result.baseline_id, "existing");
}

#[test]
fn repeated_families_and_overlapping_windows_do_not_invent_rotation_rules() {
    // The fixture's two-step alternative overlaps and shares a synthetic family.
    // Neither a benefit nor a penalty follows without an implemented sourced rule.
    let result = compare_rotations(&sample()).unwrap();
    let alternative = &result.scenarios[2];
    assert_eq!(
        alternative.scenario.steps[0].growing_window,
        alternative.scenario.steps[1].growing_window
    );
    assert!(alternative.possible_benefits.is_empty());
    assert!(alternative.risks.is_empty());
    assert_eq!(
        alternative.eligibility,
        Eligibility::InsufficientInformation
    );
    assert!(has_code(&alternative.missing_information, "rotation_rules"));
}
