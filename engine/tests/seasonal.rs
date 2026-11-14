//! All inputs in this file are synthetic test data, including numeric stress cases.
use field_shift_engine::seasonal::*;

const FIXTURE: &str = include_str!("fixtures/synthetic_season.json");
fn sample() -> SeasonalRequest {
    serde_json::from_str(FIXTURE).unwrap()
}
fn ym(year: u16, month: u8) -> YearMonth {
    YearMonth { year, month }
}
fn close(actual: f64, expected: f64) {
    assert!((actual - expected).abs() < 1e-12, "{actual} != {expected}");
}

#[test]
fn november_to_february_includes_leap_day_and_preserves_metadata() {
    let request = sample();
    let result = analyze_season(&request).unwrap();
    assert_eq!(result.window, request.window);
    assert_eq!(result.metadata, request.metadata);
    assert_eq!(result.month_count, 4);
    assert_eq!(result.calendar_days, 121);
    assert_eq!(result.rainfall_total_mm, Some(100.0));
    close(
        result.calendar_day_weighted_mean_temperature_c.unwrap(),
        3010.0 / 121.0,
    );
    assert!(result.rainfall_gap_months.is_empty());
    assert!(result.temperature_gap_months.is_empty());
}

#[test]
fn selected_complete_season_excludes_outside_records() {
    let mut request = sample();
    request.window.start = ym(2023, 12);
    request.window.end = ym(2024, 1);
    let result = analyze_season(&request).unwrap();
    assert_eq!(result.month_count, 2);
    assert_eq!(result.calendar_days, 62);
    assert_eq!(result.rainfall_total_mm, Some(50.0));
    close(
        result.calendar_day_weighted_mean_temperature_c.unwrap(),
        25.0,
    );
}

#[test]
fn nonleap_cross_year_window_uses_28_days_in_february() {
    let mut request = sample();
    request.window.start.year -= 1;
    request.window.end.year -= 1;
    for record in &mut request.observations {
        record.period.year -= 1;
    }
    let result = analyze_season(&request).unwrap();
    assert_eq!(result.calendar_days, 120);
    close(
        result.calendar_day_weighted_mean_temperature_c.unwrap(),
        2970.0 / 120.0,
    );
}

#[test]
fn gregorian_century_rules_and_single_month_seasons() {
    for (year, days) in [(1900, 28), (2000, 29), (2024, 29), (2100, 28)] {
        let mut request = sample();
        let mut record = request.observations[0].clone();
        record.period = ym(year, 2);
        request.window = SeasonalWindow {
            start: record.period,
            end: record.period,
        };
        request.observations = vec![record];
        let result = analyze_season(&request).unwrap();
        assert_eq!(result.calendar_days, days);
        assert_eq!(result.rainfall_total_mm, Some(10.0));
        assert_eq!(result.calendar_day_weighted_mean_temperature_c, Some(10.0));
    }
}

#[test]
fn absent_month_and_empty_series_are_explicit_unknowns() {
    let mut request = sample();
    request.observations.remove(1);
    let result = analyze_season(&request).unwrap();
    assert_eq!(result.rainfall_total_mm, None);
    assert_eq!(result.calendar_day_weighted_mean_temperature_c, None);
    assert_eq!(result.rainfall_gap_months, vec![ym(2023, 12)]);
    assert_eq!(result.temperature_gap_months, vec![ym(2023, 12)]);
    request.observations.clear();
    let result = analyze_season(&request).unwrap();
    assert_eq!(result.rainfall_gap_months.len(), 4);
    assert_eq!(result.temperature_gap_months.len(), 4);
    assert_eq!(result.rainfall_total_mm, None);
    assert_eq!(result.calendar_day_weighted_mean_temperature_c, None);
}

#[test]
fn null_and_incomplete_values_gate_each_variable_independently() {
    let mut request = sample();
    request.observations[0].rainfall_mm = None;
    request.observations[1].rainfall_complete = false;
    let result = analyze_season(&request).unwrap();
    assert_eq!(result.rainfall_gap_months, vec![ym(2023, 11), ym(2023, 12)]);
    assert_eq!(result.rainfall_total_mm, None);
    assert!(result.calendar_day_weighted_mean_temperature_c.is_some());
    request = sample();
    request.observations[0].mean_temperature_c = None;
    request.observations[1].temperature_complete = false;
    let result = analyze_season(&request).unwrap();
    assert_eq!(
        result.temperature_gap_months,
        vec![ym(2023, 11), ym(2023, 12)]
    );
    assert_eq!(result.calendar_day_weighted_mean_temperature_c, None);
    assert_eq!(result.rainfall_total_mm, Some(100.0));
}

#[test]
fn rejects_invalid_values_even_when_incomplete_or_outside_window() {
    for value in [-1.0, f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
        let mut request = sample();
        request.window.start = ym(2024, 1);
        request.observations[0].rainfall_complete = false;
        request.observations[0].rainfall_mm = Some(value);
        assert_eq!(
            analyze_season(&request).unwrap_err(),
            SeasonalError::InvalidRainfall(ym(2023, 11))
        );
    }
    for value in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
        let mut request = sample();
        request.observations[0].temperature_complete = false;
        request.observations[0].mean_temperature_c = Some(value);
        assert_eq!(
            analyze_season(&request).unwrap_err(),
            SeasonalError::InvalidTemperature(ym(2023, 11))
        );
    }
}

#[test]
fn overflowing_rainfall_is_an_error_not_json_null_even_with_another_gap() {
    for gap in [false, true] {
        let mut request = sample();
        request.observations[0].rainfall_mm = Some(f64::MAX);
        request.observations[1].rainfall_mm = Some(f64::MAX);
        if gap {
            request.observations[2].rainfall_mm = None;
        }
        assert_eq!(
            analyze_season(&request).unwrap_err(),
            SeasonalError::NonfiniteAggregate
        );
        let json = serde_json::to_string(&request).unwrap();
        assert_eq!(
            analyze_season_json(&json).unwrap_err(),
            "NonfiniteAggregate"
        );
    }
}

#[test]
fn large_signed_temperatures_have_finite_weighted_means() {
    for value in [f64::MAX, -f64::MAX, 0.0] {
        let mut request = sample();
        for record in &mut request.observations {
            record.mean_temperature_c = Some(value);
        }
        assert_eq!(
            analyze_season(&request)
                .unwrap()
                .calendar_day_weighted_mean_temperature_c,
            Some(value)
        );
    }
    let mut request = sample();
    request.window.end = ym(2024, 1);
    request.observations[1].mean_temperature_c = Some(f64::MAX);
    request.observations[2].mean_temperature_c = Some(-f64::MAX);
    request.observations[0].mean_temperature_c = Some(0.0);
    assert_eq!(
        analyze_season(&request)
            .unwrap()
            .calendar_day_weighted_mean_temperature_c,
        Some(0.0)
    );
}

#[test]
fn rejects_reversed_windows_duplicates_and_unsorted_records() {
    let mut request = sample();
    std::mem::swap(&mut request.window.start, &mut request.window.end);
    assert_eq!(
        analyze_season(&request).unwrap_err(),
        SeasonalError::ReversedWindow
    );
    request = sample();
    request.observations[1].period = request.observations[0].period;
    assert_eq!(
        analyze_season(&request).unwrap_err(),
        SeasonalError::UnorderedOrDuplicateMonth(ym(2023, 11))
    );
    request = sample();
    request.observations.swap(0, 1);
    assert_eq!(
        analyze_season(&request).unwrap_err(),
        SeasonalError::UnorderedOrDuplicateMonth(ym(2023, 11))
    );
}

#[test]
fn validates_dates_before_calendar_arithmetic() {
    for invalid in [ym(0, 1), ym(10000, 1), ym(2024, 0), ym(2024, 13)] {
        let mut request = sample();
        request.window.start = invalid;
        assert_eq!(
            analyze_season(&request).unwrap_err(),
            SeasonalError::InvalidDate(invalid)
        );
        request = sample();
        request.window.end = invalid;
        assert_eq!(
            analyze_season(&request).unwrap_err(),
            SeasonalError::InvalidDate(invalid)
        );
        request = sample();
        request.observations[0].period = invalid;
        assert_eq!(
            analyze_season(&request).unwrap_err(),
            SeasonalError::InvalidDate(invalid)
        );
    }
}

#[test]
fn zero_rainfall_and_negative_temperature_are_known_not_missing() {
    let mut request = sample();
    for record in &mut request.observations {
        record.rainfall_mm = Some(0.0);
        record.mean_temperature_c = Some(-5.0);
    }
    let result = analyze_season(&request).unwrap();
    assert_eq!(result.rainfall_total_mm, Some(0.0));
    assert_eq!(result.calendar_day_weighted_mean_temperature_c, Some(-5.0));
}

#[test]
fn json_roundtrip_is_deterministic_and_preserves_unknowns_and_kind() {
    let mut request = sample();
    request.observations[0].mean_temperature_c = None;
    let json = serde_json::to_string(&request).unwrap();
    let output = analyze_season_json(&json).unwrap();
    assert_eq!(output, analyze_season_json(&json).unwrap());
    let value: serde_json::Value = serde_json::from_str(&output).unwrap();
    assert_eq!(
        value["calendar_day_weighted_mean_temperature_c"],
        serde_json::Value::Null
    );
    let result: SeasonalSummary = serde_json::from_str(&output).unwrap();
    assert_eq!(result.metadata.data_kind, DataKind::Hypothetical);
    assert!(result.metadata.source.contains("SYNTHETIC TEST DATA"));
    assert!(!result.limitations.is_empty());
}

#[test]
fn json_rejects_rates_wrong_units_partial_months_and_nonfinite_numbers() {
    for (from, to) in [
        ("\"mm\"", "\"mm/day\""),
        ("\"deg_c\"", "\"kelvin\""),
        ("\"month\": 11", "\"month\": 11, \"day\": 15"),
        ("\"rainfall_mm\": 10", "\"rainfall_mm\": 1e400"),
    ] {
        let bad = FIXTURE.replacen(from, to, 1);
        assert_ne!(bad, FIXTURE);
        assert!(analyze_season_json(&bad).is_err());
    }
    assert!(analyze_season_json("{}").is_err());
}

#[test]
fn rejects_blank_provenance_and_requires_explicit_completeness() {
    let mut request = sample();
    request.metadata.source = " ".into();
    assert_eq!(
        analyze_season(&request).unwrap_err(),
        SeasonalError::InvalidMetadata
    );
    request = sample();
    request.metadata.dataset.clear();
    assert_eq!(
        analyze_season(&request).unwrap_err(),
        SeasonalError::InvalidMetadata
    );
    let mut json: serde_json::Value = serde_json::from_str(FIXTURE).unwrap();
    json["observations"][0]
        .as_object_mut()
        .unwrap()
        .remove("temperature_complete");
    assert!(analyze_season_json(&json.to_string()).is_err());
}

#[test]
fn calendar_boundaries_do_not_wrap_and_all_month_lengths_are_accounted_for() {
    for year in [1, 2024, 9999] {
        let mut request = sample();
        request.window = SeasonalWindow {
            start: ym(year, 1),
            end: ym(year, 12),
        };
        request.observations = (1..=12)
            .map(|month| MonthlyObservation {
                period: ym(year, month),
                rainfall_mm: Some(1.0),
                mean_temperature_c: Some(0.0),
                rainfall_complete: true,
                temperature_complete: true,
            })
            .collect();
        let result = analyze_season(&request).unwrap();
        assert_eq!(result.calendar_days, if year == 2024 { 366 } else { 365 });
        assert_eq!(result.rainfall_total_mm, Some(12.0));
    }
}
