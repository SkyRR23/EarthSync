use crate::decision::{Drainage, ProductionSystem, SoilTexture};
use serde::{Deserialize, Serialize};

/// Gregorian calendar day; validated before any arithmetic. Years 1..=9999.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Date {
    pub year: u16,
    pub month: u8,
    pub day: u8,
}
impl Date {
    pub(super) fn ordinal(self) -> Option<u32> {
        let leap = self.year.rem_euclid(4) == 0
            && (self.year.rem_euclid(100) != 0 || self.year.rem_euclid(400) == 0);
        let lengths = [
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
        if !(1..=9999).contains(&self.year)
            || !(1..=12).contains(&self.month)
            || self.day == 0
            || u32::from(self.day) > lengths[usize::from(self.month - 1)]
        {
            return None;
        }
        let years = u32::from(self.year - 1);
        Some(
            years * 365 + years / 4 - years / 100
                + years / 400
                + lengths[..usize::from(self.month - 1)].iter().sum::<u32>()
                + u32::from(self.day),
        )
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EvidenceKind {
    Observed,
    Modeled,
    Forecast,
    Hypothetical,
    FarmerReported,
    Unavailable,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Provenance {
    pub kind: EvidenceKind,
    pub source_refs: Vec<String>,
    pub provider: Option<String>,
    pub dataset: Option<String>,
    pub observed_on: Option<Date>,
    pub retrieved_on: Option<Date>,
    pub spatial_resolution_m: Option<f64>,
    pub uncertainty: Option<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Observation<T> {
    pub id: String,
    pub value: Option<T>,
    pub provenance: Provenance,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SurfaceCondition {
    StandingWater,
    Wet,
    Dry,
    Other,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MoistureUnit {
    VolumetricFraction,
    VolumetricPercent,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MoistureZone {
    Surface,
    RootZone,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DepthCm {
    pub top: f64,
    pub bottom: f64,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SoilMoisture {
    pub observation: Observation<f64>,
    pub unit: MoistureUnit,
    pub zone: Option<MoistureZone>,
    pub depth_cm: Option<DepthCm>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SoilContext {
    pub texture: Vec<Observation<SoilTexture>>,
    pub drainage: Vec<Observation<Drainage>>,
    pub ph: Vec<Observation<f64>>,
    pub organic_carbon_g_kg: Vec<Observation<f64>>,
    pub moisture: Vec<SoilMoisture>,
    pub surface_condition: Vec<Observation<SurfaceCondition>>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HistoryCycle {
    pub id: String,
    /// None means crop/fallow identity unknown. Fallow is explicitly Some(true).
    pub fallow: Option<bool>,
    pub crop_id: Option<String>,
    pub crop_family: Option<String>,
    pub production_system: Option<ProductionSystem>,
    pub planting_date: Option<Date>,
    pub harvest_date: Option<Date>,
    pub irrigation_available: Option<bool>,
    pub amendments: Option<Vec<String>>,
    pub provenance: Provenance,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FarmHistory {
    pub complete: bool,
    pub cycles: Vec<HistoryCycle>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SeasonContext {
    pub planned_planting_date: Option<Date>,
    pub planned_harvest_date: Option<Date>,
    pub regional_label: Option<String>,
    pub season_start: Option<Date>,
    pub season_end: Option<Date>,
    pub available_growing_days: Option<u32>,
    pub provenance: Provenance,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct StepPlan {
    pub scenario_id: String,
    pub step_index: usize,
    pub season: SeasonContext,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Applicability {
    pub region_id: String,
    pub production_system: ProductionSystem,
    /// Explicit P2 review assertion, not inferred from a citation or region name.
    pub reviewed_for_context: bool,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DurationRule {
    pub profile_id: String,
    pub min_days: Option<u32>,
    pub max_days: Option<u32>,
    pub applicability: Applicability,
    pub source_refs: Vec<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FarmerIntent {
    pub current_crop: Option<String>,
    /// Crop-ID-only questionnaire answers remain undated/unverified history.
    pub recent_rotation: Vec<String>,
    pub planting_month: Option<u8>,
    /// Presentation context only: income, less_water, soil_health, lower_risk, etc.
    pub priorities: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ProfileApplicability {
    pub profile_id: String,
    pub applicability: Applicability,
}
