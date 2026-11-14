use field_shift_engine::{
    AnalysisRequest, AnalysisResult, EngineError, analyze_field, analyze_field_json,
};

const FIXTURE: &str = include_str!("fixtures/synthetic_field.json");
fn sample() -> AnalysisRequest {
    serde_json::from_str(FIXTURE).unwrap()
}

#[test]
fn synthetic_fixture_has_deterministic_explainable_output() {
    let output = analyze_field_json(FIXTURE).unwrap();
    assert_eq!(output, analyze_field_json(FIXTURE).unwrap());
    let result: AnalysisResult = serde_json::from_str(&output).unwrap();
    assert_eq!(result.field_id, "synthetic-yangon-demo");
    assert_eq!(result.annual_rainfall_mm, Some(1700.0));
    assert!((result.mean_of_monthly_temps_c.unwrap() - 334.0 / 12.0).abs() < 1e-12);
    assert!(result.climate_source.contains("SYNTHETIC"));
    assert_eq!(result.climate_period, sample().environment.period);
    assert_eq!(result.scenarios.len(), 3);
    assert!(
        result
            .scenarios
            .iter()
            .all(|s| s.status == "requires_agronomic_validation")
    );
}

#[test]
fn overflowing_rainfall_is_an_error_in_rust_and_json() {
    let mut request = sample();
    request.environment.monthly_rainfall_mm = vec![Some(f64::MAX); 12];
    let json = serde_json::to_string(&request).unwrap();
    assert_eq!(
        analyze_field(request).unwrap_err(),
        EngineError::InvalidClimateValue
    );
    assert_eq!(
        analyze_field_json(&json).unwrap_err(),
        "InvalidClimateValue"
    );
}

#[test]
fn large_finite_temperatures_do_not_overflow_before_averaging() {
    // Numerical stress case, not plausible climate or a validated measurement.
    for temp in [f64::MAX, -f64::MAX, 0.0] {
        let mut request = sample();
        request.environment.monthly_mean_temp_c = vec![Some(temp); 12];
        assert_eq!(
            analyze_field(request).unwrap().mean_of_monthly_temps_c,
            Some(temp)
        );
    }
}

#[test]
fn every_missing_month_yields_unknown_without_losing_metadata() {
    for month in 0..12 {
        let mut request = sample();
        request.environment.monthly_rainfall_mm[month] = None;
        request.environment.monthly_mean_temp_c[month] = None;
        let result = analyze_field(request).unwrap();
        assert_eq!(result.annual_rainfall_mm, None);
        assert_eq!(result.mean_of_monthly_temps_c, None);
        assert!(
            result
                .warnings
                .iter()
                .any(|w| w.contains("Rainfall data are incomplete"))
        );
        assert!(
            result
                .warnings
                .iter()
                .any(|w| w.contains("Temperature data are incomplete"))
        );
        assert_eq!(result.climate_source, sample().environment.source);
    }
}

#[test]
fn missing_data_does_not_hide_invalid_supplied_values() {
    for value in [-1.0, f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
        let mut request = sample();
        request.environment.monthly_rainfall_mm[0] = None;
        request.environment.monthly_rainfall_mm[1] = Some(value);
        assert_eq!(
            analyze_field(request).unwrap_err(),
            EngineError::InvalidClimateValue
        );
    }
    for value in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
        let mut request = sample();
        request.environment.monthly_mean_temp_c[0] = None;
        request.environment.monthly_mean_temp_c[1] = Some(value);
        assert_eq!(
            analyze_field(request).unwrap_err(),
            EngineError::InvalidClimateValue
        );
    }
}

#[test]
fn validates_month_counts_and_coordinate_boundaries() {
    for count in [0, 11, 13] {
        for rainfall in [true, false] {
            let mut request = sample();
            if rainfall {
                request.environment.monthly_rainfall_mm = vec![None; count];
            } else {
                request.environment.monthly_mean_temp_c = vec![None; count];
            }
            assert_eq!(
                analyze_field(request).unwrap_err(),
                EngineError::InvalidMonthlyLength
            );
        }
    }
    for (lat, lon) in [(-90.0, -180.0), (90.0, 180.0)] {
        let mut request = sample();
        request.field.latitude = lat;
        request.field.longitude = lon;
        assert!(analyze_field(request).is_ok());
    }
    for (lat, lon) in [
        (90.1, 0.0),
        (0.0, -180.1),
        (f64::NAN, 0.0),
        (0.0, f64::INFINITY),
    ] {
        let mut request = sample();
        request.field.latitude = lat;
        request.field.longitude = lon;
        assert_eq!(
            analyze_field(request).unwrap_err(),
            EngineError::InvalidLocation
        );
    }
}

#[test]
fn zero_rainfall_and_freezing_temperatures_are_known_values() {
    let mut request = sample();
    request.environment.monthly_rainfall_mm = vec![Some(0.0); 12];
    request.environment.monthly_mean_temp_c = vec![Some(-5.0); 12];
    let result = analyze_field(request).unwrap();
    assert_eq!(result.annual_rainfall_mm, Some(0.0));
    assert_eq!(result.mean_of_monthly_temps_c, Some(-5.0));
}

#[test]
fn json_errors_and_wrong_scenario_counts_are_not_successes() {
    for input in ["{", "{}", "null"] {
        assert!(analyze_field_json(input).is_err());
    }
    for count in [0, 2, 4] {
        let mut request = sample();
        request.scenarios = vec![request.scenarios[0].clone(); count];
        assert_eq!(
            analyze_field(request).unwrap_err(),
            EngineError::InvalidScenarios
        );
    }
}
