//! Field Shift: deterministic, offline-testable environmental analysis foundation.
//! This module does not recommend crops: agricultural rules must be validated separately.

mod climate;

/// Provisional date-aware API, separate from the existing field analysis contract.
pub mod seasonal;

/// Provisional crop-reference and rotation foundation, independent of field analysis.
pub mod decision;

/// Provisional orchestration for backend/Flutter integration; existing APIs unchanged.
pub mod integration;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FieldInput {
    pub field_id: String,
    pub latitude: f64,
    pub longitude: f64,
    pub current_crop: String,
    pub irrigation_available: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnvironmentalContext {
    /// One entry for each calendar month (January through December).
    /// None means data are missing; do not silently replace them with zero.
    pub monthly_rainfall_mm: Vec<Option<f64>>,
    pub monthly_mean_temp_c: Vec<Option<f64>>,
    pub source: String,
    pub period: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RotationScenario {
    pub id: String,
    pub label: String,
    pub crop_sequence: Vec<String>,
    /// Notes provided by the crop-reference team. Not independently verified by this engine.
    pub supporting_notes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnalysisRequest {
    pub field: FieldInput,
    pub environment: EnvironmentalContext,
    /// Existing rotation plus two alternatives for the NASA challenge comparison.
    pub scenarios: Vec<RotationScenario>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScenarioAssessment {
    pub id: String,
    pub label: String,
    pub crop_sequence: Vec<String>,
    pub supporting_notes: Vec<String>,
    /// Crop suitability cannot be determined until validated agronomic constraints are supplied.
    pub status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnalysisResult {
    pub field_id: String,
    /// Sum of all 12 monthly rainfall values, or None if any month is missing.
    pub annual_rainfall_mm: Option<f64>,
    /// Simple average of the 12 monthly means, not a day-weighted annual temperature.
    pub mean_of_monthly_temps_c: Option<f64>,
    pub climate_source: String,
    pub climate_period: String,
    pub scenarios: Vec<ScenarioAssessment>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EngineError {
    InvalidLocation,
    InvalidMonthlyLength,
    InvalidClimateValue,
    InvalidScenarios,
}

impl std::fmt::Display for EngineError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{self:?}")
    }
}

impl std::error::Error for EngineError {}

/// Pure calculation function. Suitable for Rust unit tests and later Flutter bridge wrappers.
pub fn analyze_field(request: AnalysisRequest) -> Result<AnalysisResult, EngineError> {
    let field = &request.field;
    if !field.latitude.is_finite()
        || !field.longitude.is_finite()
        || !(-90.0..=90.0).contains(&field.latitude)
        || !(-180.0..=180.0).contains(&field.longitude)
    {
        return Err(EngineError::InvalidLocation);
    }

    let climate = &request.environment;
    let (annual_rainfall_mm, mean_of_monthly_temps_c) = climate::summarize(climate)?;
    if request.scenarios.len() != 3
        || request
            .scenarios
            .iter()
            .any(|s| s.id.is_empty() || s.crop_sequence.is_empty())
    {
        return Err(EngineError::InvalidScenarios);
    }

    let mut warnings = Vec::new();
    if annual_rainfall_mm.is_none() {
        warnings.push("Rainfall data are incomplete; annual rainfall is unknown.".into());
    }
    if mean_of_monthly_temps_c.is_none() {
        warnings
            .push("Temperature data are incomplete; annual temperature summary is unknown.".into());
    }
    warnings.push(
        "Crop suitability and rotation risks require validated crop rules and local context."
            .into(),
    );
    if field.irrigation_available.is_none() {
        warnings.push("Irrigation availability was not provided.".into());
    }

    Ok(AnalysisResult {
        field_id: field.field_id.clone(),
        annual_rainfall_mm,
        mean_of_monthly_temps_c,
        climate_source: climate.source.clone(),
        climate_period: climate.period.clone(),
        scenarios: request
            .scenarios
            .into_iter()
            .map(|s| ScenarioAssessment {
                id: s.id,
                label: s.label,
                crop_sequence: s.crop_sequence,
                supporting_notes: s.supporting_notes,
                status: "requires_agronomic_validation".to_string(),
            })
            .collect(),
        warnings,
    })
}

/// JSON boundary for backend/Flutter prototyping. Can later be wrapped by flutter_rust_bridge.
pub fn analyze_field_json(input_json: &str) -> Result<String, String> {
    let request: AnalysisRequest = serde_json::from_str(input_json).map_err(|e| e.to_string())?;
    let result = analyze_field(request).map_err(|e| e.to_string())?;
    serde_json::to_string(&result).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> AnalysisRequest {
        AnalysisRequest {
            field: FieldInput {
                field_id: "demo-field".into(),
                latitude: 16.8,
                longitude: 96.15,
                current_crop: "rice".into(),
                irrigation_available: None,
            },
            environment: EnvironmentalContext {
                monthly_rainfall_mm: vec![Some(10.0); 12],
                monthly_mean_temp_c: vec![Some(28.0); 12],
                source: "MOCK DATA — NOT NASA".into(),
                period: "illustrative".into(),
            },
            scenarios: (0..3)
                .map(|i| RotationScenario {
                    id: format!("scenario-{i}"),
                    label: format!("Example {i}"),
                    crop_sequence: vec!["unverified_crop".into()],
                    supporting_notes: vec![],
                })
                .collect(),
        }
    }

    #[test]
    fn summarizes_complete_climate_without_claiming_crop_suitability() {
        let result = analyze_field(sample()).unwrap();
        assert_eq!(result.annual_rainfall_mm, Some(120.0));
        assert_eq!(result.mean_of_monthly_temps_c, Some(28.0));
        assert_eq!(result.scenarios.len(), 3);
        assert!(
            result
                .scenarios
                .iter()
                .all(|s| s.status == "requires_agronomic_validation")
        );
    }

    #[test]
    fn missing_month_is_unknown_not_zero() {
        let mut request = sample();
        request.environment.monthly_rainfall_mm[0] = None;
        assert!(analyze_field(request).unwrap().annual_rainfall_mm.is_none());
    }

    #[test]
    fn rejects_invalid_rainfall() {
        let mut request = sample();
        request.environment.monthly_rainfall_mm[0] = Some(-1.0);
        assert_eq!(
            analyze_field(request).unwrap_err(),
            EngineError::InvalidClimateValue
        );
    }

    #[test]
    fn json_boundary_roundtrip() {
        let input = serde_json::to_string(&sample()).unwrap();
        let output = analyze_field_json(&input).unwrap();
        let result: AnalysisResult = serde_json::from_str(&output).unwrap();
        assert_eq!(result.field_id, "demo-field");
    }
}
