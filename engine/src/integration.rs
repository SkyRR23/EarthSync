//! Deterministic orchestration only. No transport, normalization or new crop rules.

use serde::{Deserialize, Serialize};

use crate::FieldInput;
use crate::decision::{
    CropProfile, DecisionRequest, DecisionResult, Drainage, FarmerContext, RotationCandidate,
    SoilTexture, SourceReference, compare_rotations,
};
use crate::seasonal::{DataKind, SeasonalRequest, SeasonalSummary, analyze_season};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DataMode {
    SyntheticDemo,
    /// Supplied by caller, not a claim of live retrieval or independent verification.
    SuppliedData,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SoilInput {
    pub texture: Option<SoilTexture>,
    pub drainage: Option<Drainage>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EnvironmentInput {
    /// Representative point requested from the backend, not a grid cell centroid.
    pub latitude: f64,
    pub longitude: f64,
    pub seasonal: SeasonalRequest,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CropReferences {
    pub sources: Vec<SourceReference>,
    pub profiles: Vec<CropProfile>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct IntegrationRequest {
    pub data_mode: DataMode,
    pub field: FieldInput,
    pub soil: SoilInput,
    pub environment: EnvironmentInput,
    pub crop_references: CropReferences,
    pub scenarios: Vec<RotationCandidate>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntegrationNotice {
    pub code: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntegrationResult {
    pub data_mode: DataMode,
    pub field: FieldInput,
    pub soil: SoilInput,
    /// Retain supplied observations, explicit completeness and data-kind metadata.
    pub environment: EnvironmentInput,
    pub climate: SeasonalSummary,
    pub rotations: DecisionResult,
    pub notices: Vec<IntegrationNotice>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum IntegrationErrorCode {
    InvalidJson,
    InvalidField,
    LocationMismatch,
    InvalidClimate,
    InvalidRotations,
    SerializationFailed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct IntegrationError {
    pub code: IntegrationErrorCode,
    pub message: String,
    pub component: String,
    /// Technical domain error only; no raw payloads, coordinates or parser value dumps.
    pub detail: Option<String>,
    pub retryable: bool,
}

impl std::fmt::Display for IntegrationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}
impl std::error::Error for IntegrationError {}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum IntegrationResponse {
    Success { data: Box<IntegrationResult> },
    Error { error: IntegrationError },
}

fn failure(
    code: IntegrationErrorCode,
    component: &str,
    message: &str,
    detail: Option<String>,
) -> IntegrationError {
    IntegrationError {
        code,
        message: message.into(),
        component: component.into(),
        detail,
        retryable: false,
    }
}
fn notice(code: &str, message: &str) -> IntegrationNotice {
    IntegrationNotice {
        code: code.into(),
        message: message.into(),
    }
}
fn valid_location(lat: f64, lon: f64) -> bool {
    lat.is_finite()
        && lon.is_finite()
        && (-90.0..=90.0).contains(&lat)
        && (-180.0..=180.0).contains(&lon)
}

/// One series and one explicit climate window per request. No silent merging or fallback.
/// Seasonal statistics are contextual output, not inputs to unimplemented climate crop rules.
pub fn analyze_integration(
    request: &IntegrationRequest,
) -> Result<IntegrationResult, IntegrationError> {
    if request.field.field_id.trim().is_empty()
        || !valid_location(request.field.latitude, request.field.longitude)
    {
        return Err(failure(
            IntegrationErrorCode::InvalidField,
            "field",
            "Provide a field ID and valid latitude/longitude.",
            None,
        ));
    }
    if !valid_location(request.environment.latitude, request.environment.longitude)
        || request.field.latitude != request.environment.latitude
        || request.field.longitude != request.environment.longitude
    {
        return Err(failure(
            IntegrationErrorCode::LocationMismatch,
            "environment",
            "Environmental context must identify the same requested representative point as the field.",
            None,
        ));
    }
    let climate = analyze_season(&request.environment.seasonal).map_err(|error| {
        failure(
            IntegrationErrorCode::InvalidClimate,
            "climate",
            "Environmental data are invalid. Check dates, ordering, units, completeness and numeric values.",
            Some(error.to_string()),
        )
    })?;
    // Climate-only requests carry no crop evidence or scenarios. Do not invent a
    // baseline/alternatives to satisfy the independent decision API's contract.
    let climate_only = request.scenarios.is_empty()
        && request.crop_references.sources.is_empty()
        && request.crop_references.profiles.is_empty();
    let rotations = if climate_only {
        DecisionResult {
            baseline_id: String::new(),
            scenarios: Vec::new(),
            sources: Vec::new(),
            contains_synthetic_references: false,
            limitations: vec![
                "Crop suitability is unknown: no crop constraints or scenarios supplied.".into(),
            ],
        }
    } else {
        compare_rotations(&DecisionRequest {
        farmer: FarmerContext {
            irrigation_available: request.field.irrigation_available,
            soil_texture: request.soil.texture,
            drainage: request.soil.drainage,
        },
        sources: request.crop_references.sources.clone(),
        profiles: request.crop_references.profiles.clone(),
        scenarios: request.scenarios.clone(),
    }).map_err(|error| {
        failure(
            IntegrationErrorCode::InvalidRotations,
            "rotations",
            "Crop references or rotation inputs are invalid. Check identifiers, source references, dates and the baseline.",
            Some(error.to_string()),
        )
    })?
    };
    let mut notices = vec![
        notice(
            "CLIMATE_CONTEXT_ONLY",
            "Climate statistics are shown separately; no water/temperature suitability rules are implemented or inferred.",
        ),
        notice(
            "ROTATION_RULES_UNAVAILABLE",
            "Rotation transitions, calendar feasibility and benefits remain unevaluated. Read per-step and rotation missing information.",
        ),
        notice(
            "SOURCE_APPLICABILITY_UNVERIFIED",
            "Dataset comparability, spatial scale and crop-reference applicability require upstream review; supplied data does not imply live or validated data.",
        ),
    ];
    notices.push(notice("ENVIRONMENT_KIND", match climate.metadata.data_kind {
        DataKind::Observed => "Caller labels this environmental series observed; that label is not independently verified by the engine.",
        DataKind::Modeled => "Caller labels this environmental series modeled; do not display it as direct field measurements.",
        DataKind::Forecast => "Caller labels this environmental series forecast; do not display it as historical observations.",
        DataKind::Hypothetical => "Caller labels this environmental series hypothetical; do not display it as observed or forecast data.",
    }));
    if request.data_mode == DataMode::SyntheticDemo || rotations.contains_synthetic_references {
        notices.push(notice("SYNTHETIC_DATA", "This workflow contains declared synthetic data or crop references. Do not present its results as observed agriculture or recommendations."));
    }
    if !climate.rainfall_gap_months.is_empty() || !climate.temperature_gap_months.is_empty() {
        notices.push(notice("INCOMPLETE_CLIMATE", "One or more climate summaries are unknown. Display the per-variable gap months; do not replace null with zero."));
    }
    if request
        .scenarios
        .iter()
        .flat_map(|s| &s.steps)
        .any(|step| step.growing_window != Some(climate.window))
    {
        notices.push(notice("DISTINCT_GROWING_WINDOWS", "Some crop windows differ from the selected climate window or are unknown. Climate data are not automatically applied to these steps."));
    }
    Ok(IntegrationResult {
        data_mode: request.data_mode,
        field: request.field.clone(),
        soil: request.soil.clone(),
        environment: request.environment.clone(),
        climate,
        rotations,
        notices,
    })
}

/// Proposed JSON bridge boundary: always a success/error JSON envelope.
/// Parse errors do not echo input values. Existing JSON adapters are unchanged.
pub fn analyze_integration_json(input: &str) -> String {
    let response = match serde_json::from_str::<IntegrationRequest>(input) {
        Ok(request) => match analyze_integration(&request) {
            Ok(data) => IntegrationResponse::Success {
                data: Box::new(data),
            },
            Err(error) => IntegrationResponse::Error { error },
        },
        Err(_) => IntegrationResponse::Error {
            error: failure(
                IntegrationErrorCode::InvalidJson,
                "request",
                "Request JSON does not match the provisional integration contract. Check required fields, units and enum values.",
                None,
            ),
        },
    };
    serde_json::to_string(&response).unwrap_or_else(|_| {
        // Literal fallback cannot fail serialization and contains no user data.
        r#"{"status":"error","error":{"code":"SERIALIZATION_FAILED","message":"The engine could not encode the result.","component":"output","detail":null,"retryable":false}}"#.into()
    })
}
