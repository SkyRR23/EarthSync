//! Pure full-month seasonal statistics. See docs/SEASONAL_CLIMATE.md for assumptions.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct YearMonth {
    pub year: u16,
    pub month: u8,
}

impl YearMonth {
    fn validate(self) -> Result<(), SeasonalError> {
        if !(1..=9999).contains(&self.year) || !(1..=12).contains(&self.month) {
            return Err(SeasonalError::InvalidDate(self));
        }
        Ok(())
    }

    fn days(self) -> u32 {
        match self.month {
            4 | 6 | 9 | 11 => 30,
            2 if self.year % 4 == 0 && (self.year % 100 != 0 || self.year % 400 == 0) => 29,
            2 => 28,
            _ => 31,
        }
    }

    fn index(self) -> u32 {
        u32::from(self.year - 1) * 12 + u32::from(self.month - 1)
    }

    fn from_index(index: u32) -> Self {
        Self {
            year: (index / 12 + 1) as u16,
            month: (index % 12 + 1) as u8,
        }
    }
}

/// Inclusive endpoints; days and partial-month windows are intentionally unsupported.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SeasonalWindow {
    pub start: YearMonth,
    pub end: YearMonth,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RainfallUnit {
    #[serde(rename = "mm")]
    Millimeters,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TemperatureUnit {
    #[serde(rename = "deg_c")]
    Celsius,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DataKind {
    Observed,
    Modeled,
    Forecast,
    Hypothetical,
}

/// One homogeneous normalized series. The adapter must establish comparability.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SeasonalMetadata {
    pub source: String,
    pub dataset: String,
    pub data_kind: DataKind,
    pub rainfall_unit: RainfallUnit,
    pub temperature_unit: TemperatureUnit,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MonthlyObservation {
    pub period: YearMonth,
    /// Full-month accumulation, not a daily rate.
    pub rainfall_mm: Option<f64>,
    /// Mean of daily mean temperatures over the entire month when complete.
    pub mean_temperature_c: Option<f64>,
    pub rainfall_complete: bool,
    /// Set true only when the backend can justify the documented mean semantics.
    pub temperature_complete: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SeasonalRequest {
    pub window: SeasonalWindow,
    pub metadata: SeasonalMetadata,
    /// Strict chronological order, no duplicates. Gaps are legal.
    pub observations: Vec<MonthlyObservation>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SeasonalSummary {
    pub window: SeasonalWindow,
    pub metadata: SeasonalMetadata,
    pub month_count: u32,
    pub calendar_days: u32,
    pub rainfall_total_mm: Option<f64>,
    pub calendar_day_weighted_mean_temperature_c: Option<f64>,
    /// Absent, null or declared incomplete observations, in calendar order.
    pub rainfall_gap_months: Vec<YearMonth>,
    pub temperature_gap_months: Vec<YearMonth>,
    pub limitations: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SeasonalError {
    InvalidDate(YearMonth),
    ReversedWindow,
    UnorderedOrDuplicateMonth(YearMonth),
    InvalidRainfall(YearMonth),
    InvalidTemperature(YearMonth),
    InvalidMetadata,
    NonfiniteAggregate,
}

impl std::fmt::Display for SeasonalError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{self:?}")
    }
}

impl std::error::Error for SeasonalError {}

/// Validate all records, then summarize only the selected inclusive month window.
/// Missingness is independent for rainfall and temperature. No network or imputation.
pub fn analyze_season(request: &SeasonalRequest) -> Result<SeasonalSummary, SeasonalError> {
    let window = request.window;
    window.start.validate()?;
    window.end.validate()?;
    if window.start > window.end {
        return Err(SeasonalError::ReversedWindow);
    }
    if request.metadata.source.trim().is_empty() || request.metadata.dataset.trim().is_empty() {
        return Err(SeasonalError::InvalidMetadata);
    }
    let mut records = BTreeMap::new();
    let mut previous = None;
    for record in &request.observations {
        record.period.validate()?;
        if previous.is_some_and(|p| record.period <= p) {
            return Err(SeasonalError::UnorderedOrDuplicateMonth(record.period));
        }
        previous = Some(record.period);
        if record
            .rainfall_mm
            .is_some_and(|v| !v.is_finite() || v < 0.0)
        {
            return Err(SeasonalError::InvalidRainfall(record.period));
        }
        if record.mean_temperature_c.is_some_and(|v| !v.is_finite()) {
            return Err(SeasonalError::InvalidTemperature(record.period));
        }
        records.insert(record.period, record);
    }

    let mut rainfall_gap_months = Vec::new();
    let mut temperature_gap_months = Vec::new();
    let mut rainfall_total = 0.0;
    let mut temperatures = Vec::new();
    let mut calendar_days = 0;
    for index in window.start.index()..=window.end.index() {
        let month = YearMonth::from_index(index);
        let days = month.days();
        calendar_days += days;
        let record = records.get(&month);
        match record
            .filter(|r| r.rainfall_complete)
            .and_then(|r| r.rainfall_mm)
        {
            Some(value) => {
                rainfall_total += value;
                if !rainfall_total.is_finite() {
                    return Err(SeasonalError::NonfiniteAggregate);
                }
            }
            None => rainfall_gap_months.push(month),
        }
        match record
            .filter(|r| r.temperature_complete)
            .and_then(|r| r.mean_temperature_c)
        {
            Some(value) => temperatures.push((value, days)),
            None => temperature_gap_months.push(month),
        }
    }

    let temperature = if temperature_gap_months.is_empty() {
        let scale = temperatures
            .iter()
            .map(|(v, _)| v.abs())
            .fold(0.0, f64::max);
        let mean = if scale == 0.0 {
            0.0
        } else {
            let normalized_sum = temperatures
                .iter()
                .map(|(value, days)| (value / scale) * f64::from(*days))
                .sum::<f64>();
            // A weighted mean is a convex combination. Clamp only normalization
            // roundoff to its mathematical bounds before restoring scale.
            (normalized_sum / f64::from(calendar_days)).clamp(-1.0, 1.0) * scale
        };
        if !mean.is_finite() {
            return Err(SeasonalError::NonfiniteAggregate);
        }
        Some(mean)
    } else {
        None
    };
    Ok(SeasonalSummary {
        window,
        metadata: request.metadata.clone(),
        month_count: window.end.index() - window.start.index() + 1,
        calendar_days,
        rainfall_total_mm: rainfall_gap_months.is_empty().then_some(rainfall_total),
        calendar_day_weighted_mean_temperature_c: temperature,
        rainfall_gap_months,
        temperature_gap_months,
        limitations: vec![
            "Full calendar months only; no partial-month estimates or gap filling.".into(),
            "Day weighting assumes complete monthly means of daily mean temperatures; completeness is supplied by the caller, not verified against daily data.".into(),
            "Source comparability and spatial representativeness require upstream review; these statistics do not establish crop suitability or forecast skill.".into(),
        ],
    })
}

/// Separate provisional JSON boundary. The existing field-analysis adapter is unchanged.
pub fn analyze_season_json(input_json: &str) -> Result<String, String> {
    let request: SeasonalRequest = serde_json::from_str(input_json).map_err(|e| e.to_string())?;
    let summary = analyze_season(&request).map_err(|e| e.to_string())?;
    serde_json::to_string(&summary).map_err(|e| e.to_string())
}
