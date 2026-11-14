use serde::{Deserialize, Serialize};

pub const SCHEMA_VERSION: &str = "earthsync.engine.v0.3.0";

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Date {
    pub year: u16,
    pub month: u8,
    pub day: u8,
}
impl Date {
    pub(crate) fn ordinal(self) -> Option<u32> {
        let y = u32::from(self.year);
        let leap = y.is_multiple_of(4) && (!y.is_multiple_of(100) || y.is_multiple_of(400));
        let months = [
            31,
            if leap { 29 } else { 28 },
            31,
            30,
            31,
            30,
            31,
            31,
            30,
            31,
            30,
            31,
        ];
        if !(1..=9999).contains(&y)
            || !(1..=12).contains(&self.month)
            || self.day == 0
            || u32::from(self.day) > months[usize::from(self.month - 1)]
        {
            return None;
        }
        let p = y - 1;
        Some(
            p * 365 + p / 4 - p / 100
                + p / 400
                + months[..usize::from(self.month - 1)].iter().sum::<u32>()
                + u32::from(self.day),
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Period {
    pub start: Date,
    pub end: Date,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Status {
    SupportedBySuppliedEvidence,
    ConflictsWithSuppliedEvidence,
    InsufficientInformation,
    EvidenceNotApplicable,
    InputOrSourceValidationFailure,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Mode {
    EvidenceAssessment,
    SoftwareTest,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Review {
    Reviewed,
    Unreviewed,
    ReferenceOnly,
    Synthetic,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Kind {
    Observed,
    Modeled,
    Forecast,
    FarmerReported,
    Synthetic,
    Unavailable,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Quality {
    Usable,
    Missing,
    Suspect,
    Unavailable,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ClimateIntent {
    Historical,
    Forecast,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProductionSystem {
    Dryland,
    Rainfed,
    Irrigated,
    FloodedLowland,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Source {
    pub id: String,
    pub title: String,
    pub citation: String,
    pub url: Option<String>,
    pub published_on: Option<Date>,
    pub reviewed_on: Option<Date>,
    pub review: Review,
    pub limitations: Vec<String>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "scope", rename_all = "snake_case", deny_unknown_fields)]
pub enum SpatialSupport {
    Field {
        field_id: String,
    },
    Regional {
        region_id: String,
        resolution_m: Option<u32>,
    },
    Unknown,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Provenance {
    pub kind: Kind,
    pub source_ids: Vec<String>,
    pub period: Option<Period>,
    pub retrieved_on: Option<Date>,
    pub issued_on: Option<Date>,
    pub spatial: SpatialSupport,
    pub quality: Quality,
    pub uncertainty: Option<String>,
    pub method: Option<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Point {
    pub latitude: f64,
    pub longitude: f64,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ConfirmedFarm {
    pub field_id: String,
    pub point: Option<Point>,
    /// Unclosed vertex ring; at least three distinct vertices. No area inferred.
    pub boundary: Option<Vec<Point>>,
    pub confirmed_on: Date,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Photo {
    pub id: String,
    pub captured_on: Option<Date>,
    pub location: Option<Point>,
    pub source_ids: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Property {
    Ph,
    OrganicCarbon,
    BulkDensity,
    SoilMoisture,
    Texture,
    Drainage,
    IrrigationAvailable,
    FloodManagement,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Unit {
    Ph,
    GPerKg,
    PercentMass,
    KgPerM3,
    GPerCm3,
    VolumetricFraction,
    VolumetricPercent,
    Category,
    Boolean,
    Celsius,
    MmPerDay,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Depth {
    pub top_cm: f64,
    pub bottom_cm: f64,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(
    tag = "type",
    content = "value",
    rename_all = "snake_case",
    deny_unknown_fields
)]
pub enum Value {
    Number(f64),
    Category(String),
    Boolean(bool),
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Observation {
    pub id: String,
    pub property: Property,
    pub value: Option<Value>,
    pub unit: Unit,
    pub depth: Option<Depth>,
    pub provenance: Provenance,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Variable {
    Tmin,
    Tmax,
    Rainfall,
    Et0,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DailyValue {
    pub date: Date,
    pub value: Option<f64>,
    pub quality: Quality,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DailySeries {
    pub id: String,
    /// Explicit daily calendar convention; no timezone or LST/UTC conversion is inferred.
    pub day_basis: String,
    pub variable: Variable,
    pub unit: Unit,
    pub provenance: Provenance,
    pub days: Vec<DailyValue>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Applicability {
    /// Empty regions means explicitly global applicability, never inferred from coordinates.
    pub regions: Vec<String>,
    pub systems: Vec<ProductionSystem>,
    pub cultivar: Option<String>,
    pub field_only: bool,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Bounds {
    pub min: f64,
    pub max: f64,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Stage {
    pub id: String,
    pub first_day: u32,
    pub last_day: u32,
    pub kc: f64,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "condition", rename_all = "snake_case", deny_unknown_fields)]
pub enum Requirement {
    /// Every daily Tmin and Tmax must be within these supplied bounds.
    Temperature {
        range_c: Bounds,
    },
    /// Uncapped GDD = sum(max(0, (Tmax + Tmin)/2 - base)); not a maturity prediction.
    GrowingDegreeDays {
        base_c: f64,
        range_c_days: Bounds,
    },
    GrowingPeriodRainfall {
        range_mm: Bounds,
    },
    Duration {
        range_days: Bounds,
    },
    /// Inclusive MMDD interval, wraps through New Year when start > end.
    PlantingWindow {
        first_mmdd: u16,
        last_mmdd: u16,
    },
    SoilNumeric {
        property: Property,
        range: Bounds,
        unit: Unit,
        depth: Depth,
        method: Option<String>,
    },
    SoilCategory {
        property: Property,
        allowed: Vec<String>,
    },
    IrrigationRequired,
    FloodedManagement {
        required: String,
    },
    /// FAO-56 single-coefficient arithmetic only; no soil-water balance.
    CropEvapotranspiration {
        stages: Vec<Stage>,
    },
    Succession {
        previous_crop_id: Option<String>,
        previous_family: Option<String>,
        minimum_fallow_days: u32,
    },
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Rule {
    pub id: String,
    pub review: Review,
    pub source_ids: Vec<String>,
    pub applicability: Applicability,
    pub requirement: Requirement,
    pub limitations: Vec<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Profile {
    pub id: String,
    /// Version is part of identity, e.g. rice.oryza_sativa@1. No name matching.
    pub crop_id: String,
    pub family: String,
    pub cultivar: Option<String>,
    pub system: ProductionSystem,
    pub approved_for_candidates: bool,
    pub review: Review,
    pub rules: Vec<Rule>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Cycle {
    pub id: String,
    /// None means unknown crop; fallow is an independent explicit assertion.
    pub crop_id: Option<String>,
    pub profile_id: Option<String>,
    pub fallow: bool,
    pub period: Option<Period>,
    pub provenance: Provenance,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Plan {
    pub id: String,
    pub crop_id: String,
    pub profile_id: String,
    pub system: ProductionSystem,
    pub cultivar: Option<String>,
    pub period: Period,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Scenario {
    pub id: String,
    pub plans: Vec<Plan>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CandidateWindow {
    pub period: Period,
    pub system: ProductionSystem,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Request {
    pub schema_version: String,
    pub day_basis: String,
    pub mode: Mode,
    pub region_id: Option<String>,
    pub approximate_user_location: Option<Point>,
    pub farm: Option<ConfirmedFarm>,
    pub photos: Vec<Photo>,
    pub climate_intent: ClimateIntent,
    pub sources: Vec<Source>,
    pub catalog: Vec<Profile>,
    pub observations: Vec<Observation>,
    pub climate: Vec<DailySeries>,
    pub history_complete: bool,
    pub history: Vec<Cycle>,
    pub scenarios: Vec<Scenario>,
    /// Explicit sequential use of one confirmed field; no intercropping inference.
    pub sequential_field: bool,
    pub candidate_window: Option<CandidateWindow>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Finding {
    pub scenario_id: String,
    pub plan_id: String,
    pub rule_id: String,
    pub status: Status,
    pub condition: String,
    pub input: serde_json::Value,
    pub requirement: serde_json::Value,
    pub units: String,
    pub source_ids: Vec<String>,
    pub input_ids: Vec<String>,
    pub explanation: String,
    pub unknowns: Vec<String>,
    pub limitations: Vec<String>,
    pub software_test_only: bool,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FarmerFinding {
    pub plan_id: String,
    pub rule_id: String,
    pub status: Status,
    pub message: String,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Summary {
    pub scenario_id: String,
    pub status: Status,
    pub findings: Vec<FarmerFinding>,
    pub unknowns: Vec<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResultV03 {
    pub schema_version: String,
    pub software_test_only: bool,
    pub summaries: Vec<Summary>,
    pub findings: Vec<Finding>,
    pub candidates: Vec<Scenario>,
    /// Full provenance, original units, depths, dates and contradictory inputs.
    pub context: Request,
    pub limitations: Vec<String>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ValidationError {
    pub status: Status,
    pub path: String,
    pub message: String,
}
impl std::fmt::Display for ValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}: {}", self.path, self.message)
    }
}
impl std::error::Error for ValidationError {}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum Response {
    Success {
        data: Box<ResultV03>,
    },
    Error {
        schema_version: String,
        error: ValidationError,
    },
}
