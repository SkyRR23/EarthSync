//! Fictional inputs test scientific contracts, never agricultural advice.
use field_shift_engine::v03::*;

fn request() -> Request {
    let mut r: Request =
        serde_json::from_str(include_str!("fixtures/v03/synthetic_request.json")).unwrap();
    r.candidate_window = None;
    r
}

fn status(r: &Request, id: &str) -> Status {
    analyze_v03(r)
        .unwrap()
        .findings
        .iter()
        .find(|f| f.rule_id == id && f.scenario_id == "synthetic-baseline")
        .unwrap()
        .status
}

#[test]
fn regional_crop_history_cannot_establish_a_confirmed_fields_predecessor() {
    let mut r = request();
    r.history[0].provenance.spatial = SpatialSupport::Regional {
        region_id: r.region_id.clone().unwrap(),
        resolution_m: Some(1000),
    };
    assert_eq!(
        status(&r, "test.succession"),
        Status::InsufficientInformation
    );
}

#[test]
fn regional_fallow_cannot_establish_a_confirmed_fields_fallow_interval() {
    let mut r = request();
    r.history[1].provenance.spatial = SpatialSupport::Regional {
        region_id: r.region_id.clone().unwrap(),
        resolution_m: Some(1000),
    };
    assert_eq!(
        status(&r, "test.succession"),
        Status::InsufficientInformation
    );
    // Also exercise the later-plan path: its predecessor is a plan, but its
    // fallow evidence still must establish occupancy of this exact field.
    let mut previous = r.scenarios[0].plans[0].clone();
    previous.id = "earlier-plan".into();
    previous.crop_id = r.history[0].crop_id.clone().unwrap();
    previous.profile_id = r.history[0].profile_id.clone().unwrap();
    previous.period = r.history[0].period.clone().unwrap();
    r.scenarios[0].plans.insert(0, previous);
    r.history.retain(|h| h.fallow);
    assert_eq!(
        status(&r, "test.succession"),
        Status::InsufficientInformation
    );
    r.history[0].provenance.spatial = SpatialSupport::Field {
        field_id: r.farm.as_ref().unwrap().field_id.clone(),
    };
    assert_eq!(
        status(&r, "test.succession"),
        Status::SupportedBySuppliedEvidence
    );
}

#[test]
fn a_different_fields_crop_and_fallow_cannot_support_succession() {
    for i in 0..2 {
        let mut r = request();
        r.history[i].provenance.spatial = SpatialSupport::Field {
            field_id: "other-farm".into(),
        };
        assert_eq!(
            status(&r, "test.succession"),
            Status::InsufficientInformation
        );
    }
    assert_eq!(
        status(&request(), "test.succession"),
        Status::SupportedBySuppliedEvidence
    );
}

#[test]
fn incomplete_daily_coverage_cannot_be_promoted_by_a_full_declared_period() {
    for i in 0..4 {
        let mut r = request();
        r.climate[i].days.remove(1);
        let rule = [
            "test.temperature",
            "test.temperature",
            "test.rainfall",
            "test.etc",
        ][i];
        assert_eq!(status(&r, rule), Status::InsufficientInformation);
    }
}

#[test]
fn conflicting_climate_series_are_not_silently_selected_or_averaged() {
    let mut r = request();
    let mut other = r.climate[2].clone();
    other.id = "conflicting-rainfall".into();
    other.days[0].value = Some(999.0);
    r.climate.push(other);
    assert_eq!(status(&r, "test.rainfall"), Status::InsufficientInformation);
}

#[test]
fn irrigation_availability_cannot_fill_missing_rainfall_or_et0() {
    let mut r = request();
    r.observations
        .iter_mut()
        .filter(|o| o.property == Property::IrrigationAvailable)
        .for_each(|o| o.value = Some(Value::Boolean(true)));
    r.climate
        .retain(|c| c.variable != Variable::Rainfall && c.variable != Variable::Et0);
    assert_eq!(status(&r, "test.rainfall"), Status::InsufficientInformation);
    assert_eq!(status(&r, "test.etc"), Status::InsufficientInformation);
}

#[test]
fn unavailable_provider_cannot_supply_a_real_value() {
    let mut r = request();
    r.climate[0].provenance.kind = Kind::Unavailable;
    r.climate[0].provenance.quality = Quality::Unavailable;
    assert!(analyze_v03(&r).is_err());
    for day in &mut r.climate[0].days {
        day.value = None;
        day.quality = Quality::Unavailable;
    }
    assert_ne!(
        status(&r, "test.temperature"),
        Status::SupportedBySuppliedEvidence
    );
}
