//! All agronomic thresholds here are fictional software fixtures. A test that
//! sets Reviewed exercises a caller assertion; it does not verify a real source.
use field_shift_engine::v03::*;
use serde_json::json;

const FIXTURE: &str = include_str!("fixtures/v03/synthetic_request.json");
fn sample() -> Request {
    let mut r: Request = serde_json::from_str(FIXTURE).unwrap();
    r.candidate_window = None;
    r
}
fn result(r: &Request) -> ResultV03 {
    analyze_v03(r).unwrap()
}
fn finding<'a>(v: &'a ResultV03, id: &str) -> &'a Finding {
    v.findings
        .iter()
        .find(|f| f.rule_id == id && f.scenario_id == "synthetic-baseline")
        .unwrap()
}
fn status(r: &Request, id: &str) -> Status {
    finding(&result(r), id).status
}
fn rule<'a>(r: &'a mut Request, id: &str) -> &'a mut Rule {
    r.catalog
        .iter_mut()
        .flat_map(|p| &mut p.rules)
        .find(|x| x.id == id)
        .unwrap()
}
fn day(year: u16, month: u8, day: u8) -> Date {
    Date { year, month, day }
}
fn set_profile(r: &mut Request, sys: ProductionSystem, id: &str) {
    let p = &mut r.scenarios[0].plans[0];
    p.system = sys;
    p.profile_id = id.into();
}

#[test]
fn synthetic_contract_is_deterministic_traceable_and_not_a_recommendation() {
    let output = analyze_v03_json(FIXTURE);
    assert_eq!(output, analyze_v03_json(FIXTURE));
    let Response::Success { data } = serde_json::from_str(&output).unwrap() else {
        panic!("success expected")
    };
    assert_eq!(data.schema_version, SCHEMA_VERSION);
    assert!(data.software_test_only);
    assert!(
        data.summaries
            .iter()
            .all(|s| s.status == Status::InsufficientInformation)
    );
    assert!(
        data.findings
            .iter()
            .all(|f| f.status == Status::SupportedBySuppliedEvidence && f.software_test_only)
    );
    assert_eq!(finding(&data, "test.gdd").input["gdd"], 60.0);
    assert_eq!(finding(&data, "test.rainfall").input["rainfall_mm"], 10.0);
    assert_eq!(finding(&data, "test.etc").input["total_etc_mm"], 12.0);
    assert_eq!(finding(&data, "test.succession").input["gap_days"], 2);
    assert!(data.findings.iter().all(|f| !f.rule_id.is_empty()
        && !f.requirement.is_null()
        && !f.units.is_empty()
        && !f.explanation.is_empty()
        && !f.source_ids.is_empty()));
    let before = serde_json::to_value(serde_json::from_str::<Request>(FIXTURE).unwrap()).unwrap();
    assert_eq!(serde_json::to_value(data.context).unwrap(), before);
}

#[test]
fn known_and_unknown_crops_and_empty_catalog_do_not_substitute_names() {
    let mut r = sample();
    assert_eq!(
        status(&r, "test.temperature"),
        Status::SupportedBySuppliedEvidence
    );
    r.scenarios[0].plans[0].crop_id = "unknown@1".into();
    assert_eq!(
        status(&r, "catalog.identity"),
        Status::InsufficientInformation
    );
    r = sample();
    r.catalog.clear();
    r.history.clear();
    assert_eq!(
        status(&r, "catalog.identity"),
        Status::InsufficientInformation
    );
    assert!(result(&r).candidates.is_empty());
}

#[test]
fn incompatible_system_and_cultivar_are_not_applicable() {
    let mut r = sample();
    r.scenarios[0].plans[0].system = ProductionSystem::Irrigated;
    assert_eq!(
        status(&r, "catalog.applicability"),
        Status::EvidenceNotApplicable
    );
    r = sample();
    r.scenarios[0].plans[0].cultivar = Some("unmatched".into());
    assert_eq!(
        status(&r, "catalog.applicability"),
        Status::EvidenceNotApplicable
    );
    r = sample();
    rule(&mut r, "test.temperature").applicability.cultivar = Some("unknown".into());
    assert_eq!(
        status(&r, "test.temperature"),
        Status::EvidenceNotApplicable
    );
}

#[test]
fn each_missing_climate_day_stays_unknown_without_affecting_other_variables() {
    for variable in 0..4 {
        for date in 0..4 {
            let mut r = sample();
            r.climate[variable].days[date].value = None;
            r.climate[variable].days[date].quality = Quality::Missing;
            let id = [
                "test.temperature",
                "test.temperature",
                "test.rainfall",
                "test.etc",
            ][variable];
            let v = result(&r);
            let f = finding(&v, id);
            assert_eq!(f.status, Status::InsufficientInformation);
            assert_eq!(f.input["missing_or_unusable_days"], 1);
            assert!(!f.unknowns.is_empty());
            if variable < 2 {
                assert_eq!(
                    finding(&v, "test.gdd").status,
                    Status::InsufficientInformation
                );
            }
            if variable != 2 {
                assert_eq!(
                    finding(&v, "test.rainfall").status,
                    Status::SupportedBySuppliedEvidence
                );
            }
        }
    }
}

#[test]
fn absent_day_suspect_quality_and_overlapping_sources_are_unknown() {
    let mut r = sample();
    r.climate[0].days.remove(1);
    assert_eq!(
        status(&r, "test.temperature"),
        Status::InsufficientInformation
    );
    r = sample();
    r.climate[0].days[0].quality = Quality::Suspect;
    assert_eq!(
        status(&r, "test.temperature"),
        Status::InsufficientInformation
    );
    r = sample();
    let mut other = r.climate[0].clone();
    other.id = "other-tmin".into();
    r.climate.push(other);
    assert_eq!(
        status(&r, "test.temperature"),
        Status::InsufficientInformation
    );
}

#[test]
fn historical_and_forecast_are_never_interchangeable() {
    let mut r = sample();
    r.climate[0].provenance.kind = Kind::Forecast;
    r.climate[0].provenance.issued_on = Some(day(2024, 12, 29));
    assert_eq!(
        status(&r, "test.temperature"),
        Status::EvidenceNotApplicable
    );
    r = sample();
    r.climate_intent = ClimateIntent::Forecast;
    assert_eq!(status(&r, "test.rainfall"), Status::EvidenceNotApplicable);
    // Forecast calculations require all requested variables to be forecast and
    // attributed; the summary still never claims future safety.
    for c in &mut r.climate {
        c.provenance.kind = Kind::Forecast;
        c.provenance.issued_on = Some(day(2024, 12, 29));
    }
    assert_eq!(
        status(&r, "test.temperature"),
        Status::SupportedBySuppliedEvidence
    );
    assert_eq!(
        result(&r).summaries[0].status,
        Status::InsufficientInformation
    );
}

#[test]
fn crop_specific_temperature_and_gdd_base_produce_explicit_comparisons() {
    let mut r = sample();
    rule(&mut r, "test.temperature").requirement = Requirement::Temperature {
        range_c: Bounds {
            min: 21.0,
            max: 35.0,
        },
    };
    assert_eq!(
        status(&r, "test.temperature"),
        Status::ConflictsWithSuppliedEvidence
    );
    assert_eq!(status(&r, "test.gdd"), Status::SupportedBySuppliedEvidence);
    rule(&mut r, "test.gdd").requirement = Requirement::GrowingDegreeDays {
        base_c: 30.0,
        range_c_days: Bounds { min: 0.0, max: 0.0 },
    };
    let v = result(&r);
    assert_eq!(finding(&v, "test.gdd").input["gdd"], 0.0);
    assert_eq!(
        finding(&v, "test.gdd").status,
        Status::SupportedBySuppliedEvidence
    );
}

#[test]
fn growing_period_only_excludes_outside_rainfall_and_crosses_years() {
    let mut r = sample();
    r.climate[2].provenance.period.as_mut().unwrap().start = day(2024, 1, 1);
    r.climate[2].days.push(DailyValue {
        date: day(2024, 1, 1),
        value: Some(999.0),
        quality: Quality::Usable,
    });
    let v = result(&r);
    assert_eq!(finding(&v, "test.rainfall").input["rainfall_mm"], 10.0);
    assert_eq!(finding(&v, "test.duration").input["inclusive_days"], 4);
    assert_eq!(
        finding(&v, "test.planting").status,
        Status::SupportedBySuppliedEvidence
    );
    r.scenarios[0].plans[0].period.start = day(2024, 11, 30);
    assert_eq!(
        status(&r, "test.planting"),
        Status::ConflictsWithSuppliedEvidence
    );
}

#[test]
fn gregorian_leap_and_century_days_are_inclusive() {
    for (year, expected) in [(2024, 3), (2100, 2), (2000, 3)] {
        let mut r = sample();
        r.scenarios[0].plans[0].period = Period {
            start: day(year, 2, 28),
            end: day(year, 3, 1),
        };
        assert_eq!(
            finding(&result(&r), "test.duration").input["inclusive_days"],
            expected
        );
    }
    let mut r = sample();
    r.scenarios[0].plans[0].period.start = day(2100, 2, 29);
    assert!(analyze_v03(&r).is_err());
}

#[test]
fn numerical_soil_converts_supported_units_but_keeps_original_records() {
    let r = sample();
    let v = result(&r);
    assert_eq!(
        finding(&v, "test.carbon").status,
        Status::SupportedBySuppliedEvidence
    );
    assert_eq!(v.context.observations[1].unit, Unit::PercentMass);
    assert_eq!(finding(&v, "test.carbon").input[0]["value"]["value"], 2.0);
    let mut r = sample();
    r.observations[1].unit = Unit::GPerKg;
    assert_eq!(
        status(&r, "test.carbon"),
        Status::ConflictsWithSuppliedEvidence
    );
}

#[test]
fn soil_depth_method_and_validity_mismatches_are_unknown() {
    let mut r = sample();
    r.observations[0].depth.as_mut().unwrap().bottom_cm = 30.0;
    assert_eq!(status(&r, "test.ph"), Status::InsufficientInformation);
    r = sample();
    r.observations[0].provenance.method = Some("calcium_chloride".into());
    assert_eq!(status(&r, "test.ph"), Status::InsufficientInformation);
    r = sample();
    r.observations[0].provenance.period.as_mut().unwrap().end = day(2024, 12, 31);
    assert_eq!(status(&r, "test.ph"), Status::InsufficientInformation);
    r = sample();
    r.observations[0].value = None;
    assert_eq!(status(&r, "test.ph"), Status::InsufficientInformation);
}

#[test]
fn farmer_and_model_contradictions_are_retained_without_fusion() {
    let mut r = sample();
    r.observations[3].provenance.kind = Kind::FarmerReported;
    let mut model = r.observations[3].clone();
    model.id = "model-drainage".into();
    model.provenance.kind = Kind::Modeled;
    model.provenance.spatial = SpatialSupport::Regional {
        region_id: r.region_id.clone().unwrap(),
        resolution_m: Some(250),
    };
    model.value = Some(Value::Category("test_poorly_drained".into()));
    r.observations.push(model);
    let v = result(&r);
    let f = finding(&v, "test.drainage");
    assert_eq!(f.status, Status::InsufficientInformation);
    assert!(f.explanation.contains("Contradictory"));
    assert_eq!(f.input_ids.len(), 2);
    assert!(f.limitations.iter().any(|x| x.contains("modeled")));
    assert_eq!(v.context.observations.len(), 7);
}

#[test]
fn regional_data_cannot_become_field_measurements_or_follow_user_location() {
    let mut r = sample();
    rule(&mut r, "test.temperature").applicability.field_only = true;
    assert_eq!(
        status(&r, "test.temperature"),
        Status::EvidenceNotApplicable
    );
    r = sample();
    r.farm = None;
    assert_eq!(status(&r, "test.ph"), Status::InsufficientInformation);
    // Regional historical climate can still be assessed for regional scope.
    assert_eq!(
        status(&r, "test.temperature"),
        Status::SupportedBySuppliedEvidence
    );
    r = sample();
    r.region_id = Some("another-global-region".into());
    assert_eq!(
        status(&r, "test.temperature"),
        Status::EvidenceNotApplicable
    );
    r = sample();
    rule(&mut r, "test.duration").applicability.regions = vec!["explicitly-reviewed-region".into()];
    assert_eq!(status(&r, "test.duration"), Status::EvidenceNotApplicable);
}

#[test]
fn irrigated_rainfed_dryland_and_flooded_profiles_remain_distinct() {
    let mut r = sample();
    assert!(
        result(&r)
            .findings
            .iter()
            .all(|f| f.rule_id != "test.irrigation")
    );
    set_profile(&mut r, ProductionSystem::Irrigated, "test.crop.irrigated@1");
    assert_eq!(
        status(&r, "test.irrigation"),
        Status::ConflictsWithSuppliedEvidence
    );
    r.observations[4].value = None;
    assert_eq!(
        status(&r, "test.irrigation"),
        Status::InsufficientInformation
    );
    r.observations[4].value = Some(Value::Boolean(true));
    assert_eq!(
        status(&r, "test.irrigation"),
        Status::SupportedBySuppliedEvidence
    );
    set_profile(&mut r, ProductionSystem::Dryland, "test.crop.dryland@1");
    assert_eq!(
        status(&r, "test.dryland.duration"),
        Status::SupportedBySuppliedEvidence
    );
    set_profile(
        &mut r,
        ProductionSystem::FloodedLowland,
        "test.crop.flooded_lowland@1",
    );
    assert_eq!(
        status(&r, "test.flood"),
        Status::SupportedBySuppliedEvidence
    );
    r.observations[5].value = None;
    assert_eq!(status(&r, "test.flood"), Status::InsufficientInformation);
}

#[test]
fn etc_requires_complete_aligned_et0_and_every_day_of_sourced_kc() {
    let mut r = sample();
    r.climate.retain(|x| x.variable != Variable::Et0);
    assert_eq!(status(&r, "test.etc"), Status::InsufficientInformation);
    r = sample();
    if let Requirement::CropEvapotranspiration { stages } =
        &mut rule(&mut r, "test.etc").requirement
    {
        stages[0].last_day = 1;
    }
    let v = result(&r);
    let f = finding(&v, "test.etc");
    assert_eq!(f.status, Status::InsufficientInformation);
    assert!(f.input.get("total_etc_mm").is_none());
    r = sample();
    r.climate[3].days[0].date = day(2024, 12, 29);
    assert!(analyze_v03(&r).is_err());
    // Monthly T2M and precipitation alone cannot be parsed into this daily contract.
    let mut json = serde_json::to_value(sample()).unwrap();
    json["climate"][0]["unit"] = json!("monthly_mean_c");
    assert!(matches!(
        serde_json::from_str::<Response>(&analyze_v03_json(&json.to_string())).unwrap(),
        Response::Error { .. }
    ));
}

#[test]
fn succession_checks_explicit_fallow_not_just_an_empty_calendar_gap() {
    let mut r = sample();
    assert_eq!(
        status(&r, "test.succession"),
        Status::SupportedBySuppliedEvidence
    );
    r.history.retain(|h| !h.fallow);
    assert_eq!(
        status(&r, "test.succession"),
        Status::InsufficientInformation
    );
    r = sample();
    r.history_complete = false;
    assert_eq!(
        status(&r, "test.succession"),
        Status::InsufficientInformation
    );
    r = sample();
    r.history[0].crop_id = Some("other@1".into());
    r.history[0].profile_id = None;
    assert_eq!(
        status(&r, "test.succession"),
        Status::InsufficientInformation
    ); // unknown family
    if let Requirement::Succession {
        previous_family, ..
    } = &mut rule(&mut r, "test.succession").requirement
    {
        *previous_family = None;
    }
    assert_eq!(status(&r, "test.succession"), Status::EvidenceNotApplicable);
    r = sample();
    if let Requirement::Succession {
        minimum_fallow_days,
        ..
    } = &mut rule(&mut r, "test.succession").requirement
    {
        *minimum_fallow_days = 3;
    }
    assert_eq!(
        status(&r, "test.succession"),
        Status::ConflictsWithSuppliedEvidence
    );
}

#[test]
fn sequence_order_overlap_and_unknown_crop_do_not_hide_schedule_conflicts() {
    let mut r = sample();
    let mut next = r.scenarios[0].plans[0].clone();
    next.id = "second".into();
    next.period.start = day(2025, 1, 2);
    next.period.end = day(2025, 1, 5);
    next.crop_id = "unknown@1".into();
    r.scenarios[0].plans.push(next);
    assert_eq!(
        status(&r, "schedule.sequential"),
        Status::ConflictsWithSuppliedEvidence
    );
    r.scenarios[0].plans[1].period.start = day(2025, 1, 3);
    assert_eq!(
        status(&r, "schedule.sequential"),
        Status::SupportedBySuppliedEvidence
    );
    r.scenarios[0].plans.swap(0, 1);
    assert_eq!(
        status(&r, "schedule.sequential"),
        Status::ConflictsWithSuppliedEvidence
    );
    r.sequential_field = false;
    assert!(
        result(&r)
            .findings
            .iter()
            .all(|f| f.rule_id != "schedule.sequential")
    );
}

#[test]
fn history_overlap_is_visible_and_unknown_history_cannot_prove_succession() {
    let mut r = sample();
    r.history[0].period.as_mut().unwrap().end = day(2024, 12, 30);
    r.history[0].provenance.period = r.history[0].period.clone();
    assert_eq!(
        status(&r, "schedule.history_overlap"),
        Status::ConflictsWithSuppliedEvidence
    );
    r = sample();
    r.history[0].period = None;
    assert_eq!(
        status(&r, "test.succession"),
        Status::InsufficientInformation
    );
    r = sample();
    r.history.reverse(); // caller order never selects a different predecessor
    assert_eq!(
        status(&r, "test.succession"),
        Status::SupportedBySuppliedEvidence
    );
}

#[test]
fn unreviewed_reference_only_and_missing_sources_cannot_decide() {
    for review in [Review::Unreviewed, Review::ReferenceOnly] {
        let mut r = sample();
        r.sources[0].review = review;
        assert_eq!(
            status(&r, "test.temperature"),
            Status::InsufficientInformation
        );
        r = sample();
        rule(&mut r, "test.temperature").review = review;
        assert_eq!(
            status(&r, "test.temperature"),
            Status::InsufficientInformation
        );
        r = sample();
        r.catalog[0].review = review;
        assert_eq!(
            status(&r, "test.temperature"),
            Status::InsufficientInformation
        );
    }
    let mut r = sample();
    rule(&mut r, "test.temperature").source_ids.clear();
    assert_eq!(
        status(&r, "test.temperature"),
        Status::InsufficientInformation
    );
    r = sample();
    r.sources.clear();
    for p in &mut r.catalog {
        for x in &mut p.rules {
            x.source_ids.clear();
        }
    }
    for x in &mut r.climate {
        x.provenance.source_ids.clear();
    }
    for x in &mut r.observations {
        x.provenance.source_ids.clear();
    }
    for x in &mut r.history {
        x.provenance.source_ids.clear();
    }
    assert_eq!(
        status(&r, "test.temperature"),
        Status::InsufficientInformation
    );
}

#[test]
fn synthetic_and_reference_profiles_cannot_create_real_recommendations() {
    let mut r = sample();
    r.mode = Mode::EvidenceAssessment;
    assert_eq!(
        status(&r, "test.temperature"),
        Status::InsufficientInformation
    );
    assert_eq!(
        result(&r).summaries[0].status,
        Status::InsufficientInformation
    );
    // Exercise a reviewed-source caller assertion with explicitly fictional test
    // values; this is software verification, never source/scientific validation.
    r.sources[0].review = Review::Reviewed;
    r.sources[0].reviewed_on = Some(day(2025, 1, 3));
    r.catalog[0].review = Review::Reviewed;
    for x in &mut r.catalog[0].rules {
        x.review = Review::Reviewed;
    }
    assert_eq!(
        status(&r, "test.temperature"),
        Status::InsufficientInformation
    ); // synthetic inputs
    for x in &mut r.climate {
        x.provenance.kind = Kind::Modeled;
    }
    assert_eq!(
        status(&r, "test.temperature"),
        Status::SupportedBySuppliedEvidence
    );
    r.climate[0].days[0].value = Some(1.0);
    assert_eq!(
        result(&r).summaries[0].status,
        Status::ConflictsWithSuppliedEvidence
    );
}

#[test]
fn candidate_generation_is_catalog_only_unranked_and_evidence_gated() {
    let mut r: Request = serde_json::from_str(FIXTURE).unwrap();
    let v = result(&r);
    assert_eq!(v.candidates.len(), 1);
    assert_eq!(v.candidates[0].plans[0].crop_id, "test.crop@1");
    r.catalog[0].approved_for_candidates = false;
    assert!(result(&r).candidates.is_empty());
    r.catalog[0].approved_for_candidates = true;
    rule(&mut r, "test.temperature").review = Review::ReferenceOnly;
    assert!(result(&r).candidates.is_empty());
    r = sample();
    r.candidate_window = Some(CandidateWindow {
        period: r.scenarios[0].plans[0].period.clone(),
        system: ProductionSystem::Irrigated,
    });
    assert_eq!(
        result(&r).candidates[0].plans[0].profile_id,
        "test.crop.irrigated@1"
    );
    assert_eq!(
        result(&r).summaries[1].status,
        Status::InsufficientInformation
    );
}

#[test]
fn numerical_overflow_nonfinite_and_physical_errors_fail_closed() {
    let mut r = sample();
    r.climate[2]
        .days
        .iter_mut()
        .for_each(|d| d.value = Some(f64::MAX));
    assert!(analyze_v03(&r).is_err());
    r = sample();
    r.climate[3]
        .days
        .iter_mut()
        .for_each(|d| d.value = Some(f64::MAX));
    assert!(analyze_v03(&r).is_err());
    for x in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY, -1.0] {
        r = sample();
        r.climate[2].days[0].value = Some(x);
        assert!(analyze_v03(&r).is_err());
    }
    r = sample();
    r.climate[0].days[0].value = Some(40.0);
    assert!(analyze_v03(&r).is_err());
    r = sample();
    r.observations[0].value = Some(Value::Number(f64::NAN));
    assert!(analyze_v03(&r).is_err());
    r = sample();
    r.observations[0].depth.as_mut().unwrap().top_cm = f64::NAN;
    assert!(analyze_v03(&r).is_err());
}

#[test]
fn zero_rain_and_et0_are_known_and_finite_large_temperatures_do_not_overflow_mean() {
    let mut r = sample();
    for c in &mut r.climate[2..] {
        for d in &mut c.days {
            d.value = Some(0.0);
        }
    }
    assert_eq!(finding(&result(&r), "test.etc").input["total_etc_mm"], 0.0);
    assert_eq!(
        status(&r, "test.rainfall"),
        Status::ConflictsWithSuppliedEvidence
    );
    for c in &mut r.climate[..2] {
        for d in &mut c.days {
            d.value = Some(f64::MAX);
        }
    }
    rule(&mut r, "test.gdd").requirement = Requirement::GrowingDegreeDays {
        base_c: f64::MAX,
        range_c_days: Bounds { min: 0.0, max: 0.0 },
    };
    assert_eq!(finding(&result(&r), "test.gdd").input["gdd"], 0.0);
}

#[test]
fn invalid_contract_shapes_sources_duplicates_units_and_dates_are_errors() {
    for input in ["{", "{}", "null", r#"{"schema_version":"v0.2"}"#] {
        let Response::Error { error, .. } = serde_json::from_str(&analyze_v03_json(input)).unwrap()
        else {
            panic!("error expected")
        };
        assert_eq!(error.status, Status::InputOrSourceValidationFailure);
    }
    let mut r = sample();
    r.schema_version = "0.2".into();
    assert!(analyze_v03(&r).is_err());
    r = sample();
    r.sources[0].id = "dangling".into();
    assert!(analyze_v03(&r).is_err());
    r = sample();
    r.observations.push(r.observations[0].clone());
    assert!(analyze_v03(&r).is_err());
    r = sample();
    let duplicate = r.climate[0].days[0].clone();
    r.climate[0].days.push(duplicate);
    assert!(analyze_v03(&r).is_err());
    r = sample();
    r.climate[0].unit = Unit::MmPerDay;
    assert!(analyze_v03(&r).is_err());
    r = sample();
    r.observations[0].unit = Unit::GPerKg;
    assert!(analyze_v03(&r).is_err());
    r = sample();
    r.scenarios[0].plans[0].period.end = day(2024, 1, 1);
    assert!(analyze_v03(&r).is_err());
    r = sample();
    r.climate[0].provenance.kind = Kind::Unavailable;
    assert!(analyze_v03(&r).is_err());
    r = sample();
    r.history[0].fallow = true;
    assert!(analyze_v03(&r).is_err());
    r = sample();
    r.catalog[1].family = "ContradictoryFamily".into();
    assert!(analyze_v03(&r).is_err());
    r = sample();
    rule(&mut r, "test.temperature").id = "schedule.sequential".into();
    assert!(analyze_v03(&r).is_err());
    r = sample();
    if let Requirement::CropEvapotranspiration { stages } =
        &mut rule(&mut r, "test.etc").requirement
    {
        stages[1].first_day = 2;
    }
    assert!(analyze_v03(&r).is_err());
    let mut v = serde_json::to_value(sample()).unwrap();
    v["unrecognized"] = json!(true);
    assert!(matches!(
        serde_json::from_str::<Response>(&analyze_v03_json(&v.to_string())).unwrap(),
        Response::Error { .. }
    ));
}

#[test]
fn legacy_v02_and_integration_json_remain_byte_for_byte_compatible() {
    let input = include_str!("fixtures/synthetic_v02_request.json");
    let actual = field_shift_engine::v02::analyze_v02_json(input);
    let expected: serde_json::Value =
        serde_json::from_str(include_str!("fixtures/synthetic_v02_response.json")).unwrap();
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&actual).unwrap(),
        expected
    );
    let original = field_shift_engine::integration::analyze_integration_json(include_str!(
        "fixtures/synthetic_integration_request.json"
    ));
    result(&sample());
    assert_eq!(
        original,
        field_shift_engine::integration::analyze_integration_json(include_str!(
            "fixtures/synthetic_integration_request.json"
        ))
    );
}

#[test]
fn day_alignment_and_reference_et0_method_are_explicit() {
    let mut r = sample();
    r.climate[0].day_basis = "utc".into();
    assert_eq!(
        status(&r, "test.temperature"),
        Status::EvidenceNotApplicable
    );
    r = sample();
    r.climate[3].provenance.method = None;
    assert_eq!(status(&r, "test.etc"), Status::InsufficientInformation);
    r = sample();
    r.climate[0].provenance.kind = Kind::Forecast;
    r.climate[0].provenance.issued_on = Some(day(2025, 1, 1));
    assert!(analyze_v03(&r).is_err());
}

#[test]
fn invalid_supplied_extremes_are_not_hidden_by_missing_climate_days() {
    let mut r = sample();
    r.climate[0].days[0].value = None;
    r.climate[0].days[1].value = Some(31.0);
    assert!(analyze_v03(&r).is_err());
    r = sample();
    r.climate[0].days[0].value = None;
    r.climate[2].days[0].value = Some(-1.0);
    assert!(analyze_v03(&r).is_err());
}

#[test]
fn density_and_volumetric_moisture_convert_without_becoming_modeled_wetness() {
    for (property, from, to, value, min, max) in [
        (
            Property::BulkDensity,
            Unit::GPerCm3,
            Unit::KgPerM3,
            1.2,
            1100.0,
            1300.0,
        ),
        (
            Property::BulkDensity,
            Unit::KgPerM3,
            Unit::GPerCm3,
            1200.0,
            1.1,
            1.3,
        ),
        (
            Property::SoilMoisture,
            Unit::VolumetricFraction,
            Unit::VolumetricPercent,
            0.2,
            19.0,
            21.0,
        ),
        (
            Property::SoilMoisture,
            Unit::VolumetricPercent,
            Unit::VolumetricFraction,
            20.0,
            0.19,
            0.21,
        ),
    ] {
        let mut r = sample();
        let x = &mut r.observations[0];
        x.property = property;
        x.unit = from;
        x.value = Some(Value::Number(value));
        rule(&mut r, "test.ph").requirement = Requirement::SoilNumeric {
            property,
            unit: to,
            range: Bounds { min, max },
            depth: Depth {
                top_cm: 0.0,
                bottom_cm: 15.0,
            },
            method: None,
        };
        assert_eq!(status(&r, "test.ph"), Status::SupportedBySuppliedEvidence);
    }
    let mut v = serde_json::to_value(sample()).unwrap();
    v["observations"][0]["unit"] = json!("modeled_wetness");
    assert!(matches!(
        serde_json::from_str::<Response>(&analyze_v03_json(&v.to_string())).unwrap(),
        Response::Error { .. }
    ));
}

#[test]
fn unknown_contract_example_matches_exact_versioned_envelope() {
    let output = analyze_v03_json(include_str!("fixtures/v03/unknown_request.json"));
    let expected: serde_json::Value =
        serde_json::from_str(include_str!("fixtures/v03/unknown_response.json")).unwrap();
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&output).unwrap(),
        expected
    );
}
