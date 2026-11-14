//! Supplied categorical evidence checks, not crop recommendations.
//! See docs/CROP_ROTATION_FOUNDATION.md for scope and evidence responsibilities.

use crate::seasonal::SeasonalWindow;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

macro_rules! categories {
    ($name:ident { $($variant:ident),+ }) => {
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
        #[serde(rename_all = "snake_case")]
        pub enum $name { $($variant),+ }
    };
}
categories!(ProductionSystem {
    IrrigatedLowland,
    RainfedLowland,
    Upland,
    Other
});
categories!(SoilTexture {
    Sand,
    SandyLoam,
    Loam,
    Silt,
    ClayLoam,
    Clay,
    Other
});
categories!(Drainage {
    Poor,
    Moderate,
    Well,
    Other
});
categories!(WaterRequirement {
    IrrigationRequired,
    IrrigationNotRequired
});
categories!(EvidenceStatus {
    VerifiedForSuppliedContext,
    ReferenceOnly,
    SyntheticTest
});
categories!(Eligibility {
    SupportedBySuppliedEvidence,
    ConflictsWithSuppliedEvidence,
    InsufficientInformation
});

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SourceReference {
    pub id: String,
    pub citation: String,
    /// Caller-reviewed geographic/production-system applicability, not inferred here.
    pub scope: String,
    pub status: EvidenceStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Fact<T> {
    pub value: T,
    pub source_refs: Vec<String>,
}

/// Each None is explicitly unknown, never an unconstrained suitability rule.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CropProfile {
    pub profile_id: String,
    pub crop_id: String,
    pub common_name: Option<String>,
    pub production_system: Option<Fact<ProductionSystem>>,
    pub crop_family: Option<Fact<String>>,
    /// Allowed planting months only; not a harvest calendar or climate window.
    pub planting_months: Option<Fact<Vec<u8>>>,
    pub soil_textures: Option<Fact<Vec<SoilTexture>>>,
    pub drainage: Option<Fact<Vec<Drainage>>>,
    /// Management prerequisite only, not a seasonal water balance.
    pub water_requirement: Option<Fact<WaterRequirement>>,
    /// Requirements not yet implemented, such as sourced temperature/pH bounds.
    /// None means catalog completeness unknown; Some([]) declares none supplied.
    pub unsupported_requirements: Option<Vec<Fact<String>>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FarmerContext {
    pub irrigation_available: Option<bool>,
    pub soil_texture: Option<SoilTexture>,
    pub drainage: Option<Drainage>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CropStep {
    pub crop_id: Option<String>,
    pub profile_id: Option<String>,
    pub production_system: Option<ProductionSystem>,
    pub growing_window: Option<SeasonalWindow>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RotationCandidate {
    pub id: String,
    pub label: String,
    pub is_baseline: bool,
    pub steps: Vec<CropStep>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DecisionRequest {
    pub farmer: FarmerContext,
    pub sources: Vec<SourceReference>,
    pub profiles: Vec<CropProfile>,
    pub scenarios: Vec<RotationCandidate>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Explanation {
    pub code: String,
    pub message: String,
    pub source_refs: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CropAssessment {
    pub step: CropStep,
    pub eligibility: Eligibility,
    pub evidence: Vec<Explanation>,
    pub risks: Vec<Explanation>,
    pub missing_information: Vec<Explanation>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RotationAssessment {
    pub scenario: RotationCandidate,
    pub eligibility: Eligibility,
    pub crops: Vec<CropAssessment>,
    pub evidence: Vec<Explanation>,
    pub possible_benefits: Vec<Explanation>,
    pub risks: Vec<Explanation>,
    pub missing_information: Vec<Explanation>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DecisionResult {
    pub baseline_id: String,
    pub scenarios: Vec<RotationAssessment>,
    pub sources: Vec<SourceReference>,
    pub contains_synthetic_references: bool,
    pub limitations: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DecisionError(pub String);
impl std::fmt::Display for DecisionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for DecisionError {}

fn require(ok: bool, message: &str) -> Result<(), DecisionError> {
    if ok {
        Ok(())
    } else {
        Err(DecisionError(message.into()))
    }
}
fn nonblank(s: &str) -> bool {
    !s.trim().is_empty()
}
fn identifier(s: &str) -> bool {
    s.bytes().next().is_some_and(|c| c.is_ascii_lowercase())
        && s.bytes()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_' || c == b'-')
}
fn validate_fact<T>(
    fact: &Option<Fact<T>>,
    sources: &BTreeMap<&str, &SourceReference>,
) -> Result<(), DecisionError> {
    if let Some(fact) = fact {
        require(
            fact.source_refs
                .iter()
                .all(|id| sources.contains_key(id.as_str())),
            "Unknown source reference",
        )?;
    }
    Ok(())
}
fn validate_window(window: SeasonalWindow) -> Result<(), DecisionError> {
    require(
        [window.start, window.end]
            .iter()
            .all(|d| (1..=9999).contains(&d.year) && (1..=12).contains(&d.month)),
        "Invalid growing-window date",
    )?;
    require(window.start <= window.end, "Reversed growing window")
}

fn explanation(code: &str, message: &str, refs: &[String]) -> Explanation {
    Explanation {
        code: code.into(),
        message: message.into(),
        source_refs: refs.to_vec(),
    }
}

fn check<T>(
    assessment: &mut CropAssessment,
    code: &str,
    fact: &Option<Fact<T>>,
    sources: &BTreeMap<&str, &SourceReference>,
    matches: impl FnOnce(&T) -> Option<bool>,
) {
    let Some(fact) = fact else {
        assessment.missing_information.push(explanation(
            code,
            "Crop attribute or requirement is unknown.",
            &[],
        ));
        return;
    };
    if fact.source_refs.is_empty()
        || fact
            .source_refs
            .iter()
            .any(|id| sources[id.as_str()].status == EvidenceStatus::ReferenceOnly)
    {
        assessment.missing_information.push(explanation(
            code,
            "Requirement lacks reviewed evidence for the supplied context.",
            &fact.source_refs,
        ));
        return;
    }
    match matches(&fact.value) {
        Some(true) => assessment.evidence.push(explanation(
            code,
            if code == "crop_family" {
                "Crop family metadata is documented; no rotation-family effect is inferred."
            } else {
                "Supplied inputs satisfy this documented categorical constraint only."
            },
            &fact.source_refs,
        )),
        Some(false) => assessment.risks.push(explanation(
            code,
            "Supplied inputs conflict with this documented constraint.",
            &fact.source_refs,
        )),
        None => assessment.missing_information.push(explanation(
            code,
            "Farmer input or an implemented rule is unavailable.",
            &fact.source_refs,
        )),
    }
}

fn assess_step(
    step: &CropStep,
    farmer: &FarmerContext,
    profiles: &BTreeMap<&str, &CropProfile>,
    sources: &BTreeMap<&str, &SourceReference>,
) -> CropAssessment {
    let mut result = CropAssessment {
        step: step.clone(),
        eligibility: Eligibility::InsufficientInformation,
        evidence: vec![],
        risks: vec![],
        missing_information: vec![],
    };
    let Some(profile) = step.profile_id.as_deref().and_then(|id| profiles.get(id)) else {
        result.missing_information.push(explanation(
            "profile",
            "No matching crop production-system profile was supplied.",
            &[],
        ));
        return result;
    };
    match &step.crop_id {
        None => result.missing_information.push(explanation(
            "crop_id",
            "Selected crop identity is unknown.",
            &[],
        )),
        Some(id) if id != &profile.crop_id => {
            result.risks.push(explanation(
                "crop_id",
                "Selected crop ID differs from the referenced profile.",
                &[],
            ));
            result.eligibility = Eligibility::ConflictsWithSuppliedEvidence;
            return result;
        }
        _ => {}
    }
    check(
        &mut result,
        "production_system",
        &profile.production_system,
        sources,
        |system| {
            step.production_system
                .filter(|s| *s != ProductionSystem::Other)
                .and_then(|selected| {
                    if *system == ProductionSystem::Other {
                        None
                    } else {
                        Some(selected == *system)
                    }
                })
        },
    );
    check(
        &mut result,
        "planting_month",
        &profile.planting_months,
        sources,
        |months| step.growing_window.map(|w| months.contains(&w.start.month)),
    );
    check(
        &mut result,
        "soil_texture",
        &profile.soil_textures,
        sources,
        |textures| {
            farmer
                .soil_texture
                .filter(|v| *v != SoilTexture::Other)
                .map(|v| textures.contains(&v))
        },
    );
    check(
        &mut result,
        "drainage",
        &profile.drainage,
        sources,
        |allowed| {
            farmer
                .drainage
                .filter(|v| *v != Drainage::Other)
                .map(|v| allowed.contains(&v))
        },
    );
    check(
        &mut result,
        "water_management",
        &profile.water_requirement,
        sources,
        |water| match water {
            WaterRequirement::IrrigationRequired => farmer.irrigation_available,
            WaterRequirement::IrrigationNotRequired => Some(true),
        },
    );
    check(
        &mut result,
        "crop_family",
        &profile.crop_family,
        sources,
        |_| Some(true),
    );
    match &profile.unsupported_requirements {
        None => result.missing_information.push(explanation(
            "requirements_catalog",
            "Additional crop requirements are unknown.",
            &[],
        )),
        Some(requirements) => {
            for requirement in requirements {
                result.missing_information.push(explanation(
                    "unsupported_requirement",
                    &requirement.value,
                    &requirement.source_refs,
                ));
            }
        }
    }
    result.eligibility = if !result.risks.is_empty() {
        Eligibility::ConflictsWithSuppliedEvidence
    } else if !result.missing_information.is_empty() {
        Eligibility::InsufficientInformation
    } else {
        Eligibility::SupportedBySuppliedEvidence
    };
    result
}

/// Compare one explicit baseline and at least two alternatives; retain all sequences.
/// Rotation transitions/benefits are deliberately unevaluated until sourced rules exist.
pub fn compare_rotations(request: &DecisionRequest) -> Result<DecisionResult, DecisionError> {
    let mut sources = BTreeMap::new();
    for source in &request.sources {
        require(
            identifier(&source.id) && nonblank(&source.citation) && nonblank(&source.scope),
            "Invalid source metadata",
        )?;
        require(
            sources.insert(source.id.as_str(), source).is_none(),
            "Duplicate source ID",
        )?;
    }
    let mut profiles = BTreeMap::new();
    for profile in &request.profiles {
        require(
            identifier(&profile.profile_id)
                && identifier(&profile.crop_id)
                && !profile.crop_id.contains('-'),
            "Invalid crop/profile identifier",
        )?;
        require(
            profile.common_name.as_ref().is_none_or(|s| nonblank(s)),
            "Blank crop name",
        )?;
        require(
            profiles
                .insert(profile.profile_id.as_str(), profile)
                .is_none(),
            "Duplicate profile ID",
        )?;
        validate_fact(&profile.production_system, &sources)?;
        validate_fact(&profile.crop_family, &sources)?;
        require(
            profile
                .crop_family
                .as_ref()
                .is_none_or(|f| nonblank(&f.value)),
            "Blank crop family",
        )?;
        validate_fact(&profile.planting_months, &sources)?;
        require(
            profile.planting_months.as_ref().is_none_or(|f| {
                !f.value.is_empty() && f.value.iter().all(|m| (1..=12).contains(m))
            }),
            "Invalid planting months",
        )?;
        validate_fact(&profile.soil_textures, &sources)?;
        validate_fact(&profile.drainage, &sources)?;
        require(
            profile
                .soil_textures
                .as_ref()
                .is_none_or(|f| !f.value.is_empty() && !f.value.contains(&SoilTexture::Other)),
            "Empty or unsupported soil constraint",
        )?;
        require(
            profile
                .drainage
                .as_ref()
                .is_none_or(|f| !f.value.is_empty() && !f.value.contains(&Drainage::Other)),
            "Empty or unsupported drainage constraint",
        )?;
        validate_fact(&profile.water_requirement, &sources)?;
        if let Some(requirements) = &profile.unsupported_requirements {
            for fact in requirements {
                require(nonblank(&fact.value), "Blank unsupported requirement")?;
                validate_fact(&Some(fact.clone()), &sources)?;
            }
        }
    }
    require(
        request.scenarios.len() >= 3,
        "Require baseline and at least two alternatives",
    )?;
    require(
        request.scenarios.iter().filter(|s| s.is_baseline).count() == 1,
        "Require exactly one baseline",
    )?;
    let mut ids = BTreeSet::new();
    for scenario in &request.scenarios {
        require(
            identifier(&scenario.id) && nonblank(&scenario.label) && ids.insert(&scenario.id),
            "Invalid or duplicate scenario ID/label",
        )?;
        require(!scenario.steps.is_empty(), "Empty crop sequence")?;
        for step in &scenario.steps {
            require(
                step.crop_id
                    .as_ref()
                    .is_none_or(|id| identifier(id) && !id.contains('-'))
                    && step.profile_id.as_ref().is_none_or(|id| identifier(id)),
                "Invalid selected crop/profile ID",
            )?;
            if let Some(window) = step.growing_window {
                validate_window(window)?;
            }
        }
    }
    let mut assessments = Vec::new();
    for scenario in &request.scenarios {
        let crops: Vec<_> = scenario
            .steps
            .iter()
            .map(|s| assess_step(s, &request.farmer, &profiles, &sources))
            .collect();
        let risks: Vec<_> = crops.iter().flat_map(|c| c.risks.clone()).collect();
        let evidence = crops.iter().flat_map(|c| c.evidence.clone()).collect();
        let mut missing_information: Vec<_> = crops
            .iter()
            .flat_map(|c| c.missing_information.clone())
            .collect();
        missing_information.push(explanation("rotation_rules", "Transition, duration, harvest-calendar, water-budget and soil-health rules have not been supplied or implemented.", &[]));
        assessments.push(RotationAssessment {
            scenario: scenario.clone(),
            eligibility: if risks.is_empty() {
                Eligibility::InsufficientInformation
            } else {
                Eligibility::ConflictsWithSuppliedEvidence
            },
            crops,
            evidence,
            possible_benefits: vec![],
            risks,
            missing_information,
        });
    }
    Ok(DecisionResult {
        baseline_id: request.scenarios.iter().find(|s| s.is_baseline).expect("validated baseline").id.clone(),
        scenarios: assessments, sources: request.sources.clone(),
        contains_synthetic_references: request.sources.iter().any(|s| s.status == EvidenceStatus::SyntheticTest),
        limitations: vec![
            "Categorical supplied-evidence checks only; no agronomic recommendation, score or ranking.".into(),
            "Evidence review and applicability are caller assertions; no regional validity is inferred from citations.".into(),
            "Planting-month membership does not establish growing duration or climate suitability; irrigation access does not establish adequate water.".into(),
            "Synthetic-reference results describe test rules only, not validated agriculture.".into(),
        ],
    })
}

pub fn compare_rotations_json(input: &str) -> Result<String, String> {
    let request: DecisionRequest = serde_json::from_str(input).map_err(|e| e.to_string())?;
    let result = compare_rotations(&request).map_err(|e| e.to_string())?;
    serde_json::to_string(&result).map_err(|e| e.to_string())
}
