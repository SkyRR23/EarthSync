//! Incremental v0.2 P0 boundary. Existing integration and decision models are unchanged.
mod context;
use crate::decision::{Eligibility, EvidenceStatus};
use crate::integration::{DataMode, IntegrationRequest, IntegrationResult, analyze_integration};
pub use context::*;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AnalysisRequestV02 {
    pub integration: IntegrationRequest,
    pub region_id: Option<String>,
    pub farmer_intent: FarmerIntent,
    pub soil_context: SoilContext,
    pub history: FarmHistory,
    /// Whether the supplied plans explicitly describe sequential use of ONE field.
    pub sequential_only: bool,
    pub plans: Vec<StepPlan>,
    pub duration_rules: Vec<DurationRule>,
    pub profile_applicability: Vec<ProfileApplicability>,
    /// Attribution for the existing homogeneous environmental series; optional/unknown.
    pub environmental_provenance: Option<Provenance>,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FactorStatus {
    Supported,
    Conditional,
    Unsuitable,
    Unknown,
    RequiresAgronomicValidation,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FactorAssessment {
    pub factor_id: String,
    pub status: FactorStatus,
    pub explanation: String,
    pub evidence: Vec<String>,
    pub source_refs: Vec<String>,
    pub limitations: Vec<String>,
    pub missing_information: Vec<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScenarioAssessmentV02 {
    pub scenario_id: String,
    pub is_baseline: bool,
    pub status: FactorStatus,
    pub legacy_eligibility: Eligibility,
    pub critical_constraints: Vec<FactorAssessment>,
    pub tradeoffs: Vec<FactorAssessment>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnalysisResultV02 {
    pub schema_version: String,
    /// Existing result including unchanged sequence order, evidence, climate and notices.
    pub integration: IntegrationResult,
    pub context: AnalysisRequestV02,
    pub scenarios: Vec<ScenarioAssessmentV02>,
    pub limitations: Vec<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnalysisErrorV02 {
    pub code: String,
    pub message: String,
    pub component: String,
    pub detail: Option<String>,
    pub retryable: bool,
}
impl std::fmt::Display for AnalysisErrorV02 {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}
impl std::error::Error for AnalysisErrorV02 {}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum AnalysisResponseV02 {
    Success { data: Box<AnalysisResultV02> },
    Error { error: AnalysisErrorV02 },
}
fn invalid(ok: bool, message: &str) -> Result<(), AnalysisErrorV02> {
    if ok {
        Ok(())
    } else {
        Err(AnalysisErrorV02 {
            code: "INVALID_CONTEXT".into(),
            message: message.into(),
            component: "v02_context".into(),
            detail: None,
            retryable: false,
        })
    }
}
fn date(date: Option<Date>) -> Result<Option<u32>, AnalysisErrorV02> {
    date.map(|d| {
        d.ordinal().ok_or_else(|| AnalysisErrorV02 {
            code: "INVALID_CONTEXT".into(),
            message: "Invalid Gregorian calendar date.".into(),
            component: "v02_context".into(),
            detail: None,
            retryable: false,
        })
    })
    .transpose()
}
fn validate_refs(refs: &[String], request: &AnalysisRequestV02) -> Result<(), AnalysisErrorV02> {
    invalid(
        refs.iter().all(|id| {
            request
                .integration
                .crop_references
                .sources
                .iter()
                .any(|s| &s.id == id)
        }),
        "Unknown context source reference.",
    )
}
fn provenance(p: &Provenance, r: &AnalysisRequestV02) -> Result<(), AnalysisErrorV02> {
    validate_refs(&p.source_refs, r)?;
    date(p.observed_on)?;
    date(p.retrieved_on)?;
    invalid(
        p.spatial_resolution_m
            .is_none_or(|v| v.is_finite() && v > 0.0),
        "Spatial resolution must be positive finite meters.",
    )?;
    if let (Some(a), Some(b)) = (p.observed_on, p.retrieved_on) {
        invalid(a <= b, "Retrieval date precedes observation date.")?;
    }
    Ok(())
}
fn observation<T>(
    o: &Observation<T>,
    ids: &mut BTreeSet<String>,
    r: &AnalysisRequestV02,
) -> Result<(), AnalysisErrorV02> {
    invalid(
        !o.id.trim().is_empty() && ids.insert(o.id.clone()),
        "Observation IDs must be nonempty and unique.",
    )?;
    invalid(
        o.provenance.kind != EvidenceKind::Unavailable || o.value.is_none(),
        "Unavailable observations must have null values.",
    )?;
    provenance(&o.provenance, r)
}
fn trusted(refs: &[String], r: &AnalysisRequestV02) -> bool {
    !refs.is_empty()
        && refs.iter().all(|id| {
            r.integration.crop_references.sources.iter().any(|s| {
                &s.id == id
                    && (s.status == EvidenceStatus::VerifiedForSuppliedContext
                        || (s.status == EvidenceStatus::SyntheticTest
                            && r.integration.data_mode == DataMode::SyntheticDemo))
            })
        })
}
fn validate_context(r: &AnalysisRequestV02) -> Result<(), AnalysisErrorV02> {
    invalid(
        r.farmer_intent
            .planting_month
            .is_none_or(|m| (1..=12).contains(&m)),
        "Invalid questionnaire planting month.",
    )?;
    invalid(
        r.region_id.as_ref().is_none_or(|s| !s.trim().is_empty()),
        "Region ID must be nonblank or null.",
    )?;
    if let Some(current) = &r.farmer_intent.current_crop {
        invalid(
            current == &r.integration.field.current_crop,
            "Questionnaire current crop disagrees with the legacy field input.",
        )?;
    }
    if let Some(p) = &r.environmental_provenance {
        provenance(p, r)?;
        let expected = match r.integration.environment.seasonal.metadata.data_kind {
            crate::seasonal::DataKind::Observed => EvidenceKind::Observed,
            crate::seasonal::DataKind::Modeled => EvidenceKind::Modeled,
            crate::seasonal::DataKind::Forecast => EvidenceKind::Forecast,
            crate::seasonal::DataKind::Hypothetical => EvidenceKind::Hypothetical,
        };
        invalid(
            p.kind == expected,
            "Environmental provenance kind disagrees with the normalized series.",
        )?;
    }
    let mut ids = BTreeSet::new();
    for o in &r.soil_context.texture {
        observation(o, &mut ids, r)?;
    }
    for o in &r.soil_context.drainage {
        observation(o, &mut ids, r)?;
    }
    for o in &r.soil_context.ph {
        observation(o, &mut ids, r)?;
        invalid(
            o.value.is_none_or(f64::is_finite),
            "Soil pH must be finite or null.",
        )?;
    }
    for o in &r.soil_context.organic_carbon_g_kg {
        observation(o, &mut ids, r)?;
        invalid(
            o.value
                .is_none_or(|v| v.is_finite() && (0.0..=1000.0).contains(&v)),
            "Organic carbon must be 0..1000 g/kg or null.",
        )?;
    }
    for o in &r.soil_context.surface_condition {
        observation(o, &mut ids, r)?;
    }
    for m in &r.soil_context.moisture {
        observation(&m.observation, &mut ids, r)?;
        let max = if m.unit == MoistureUnit::VolumetricFraction {
            1.0
        } else {
            100.0
        };
        invalid(
            m.observation
                .value
                .is_none_or(|v| v.is_finite() && (0.0..=max).contains(&v)),
            "Soil moisture is outside its declared volumetric unit range.",
        )?;
        if let Some(d) = &m.depth_cm {
            invalid(
                d.top.is_finite() && d.bottom.is_finite() && d.top >= 0.0 && d.bottom > d.top,
                "Invalid soil moisture depth interval in cm.",
            )?;
        }
    }
    let mut history_ids = BTreeSet::new();
    for c in &r.history.cycles {
        invalid(
            !c.id.trim().is_empty() && history_ids.insert(&c.id),
            "Duplicate or empty history cycle ID.",
        )?;
        provenance(&c.provenance, r)?;
        let a = date(c.planting_date)?;
        let b = date(c.harvest_date)?;
        if let (Some(a), Some(b)) = (a, b) {
            invalid(a <= b, "History harvest precedes planting.")?;
        }
        invalid(
            c.fallow != Some(true)
                || (c.crop_id.is_none()
                    && c.crop_family.is_none()
                    && c.production_system.is_none()),
            "Fallow history must not identify a grown crop.",
        )?;
    }
    let mut plans = BTreeSet::new();
    for p in &r.plans {
        let scenario = r
            .integration
            .scenarios
            .iter()
            .find(|s| s.id == p.scenario_id);
        invalid(
            scenario.is_some_and(|s| p.step_index < s.steps.len()),
            "Plan references an unknown scenario or step.",
        )?;
        invalid(
            plans.insert((&p.scenario_id, p.step_index)),
            "Duplicate step plan.",
        )?;
        let s = &p.season;
        provenance(&s.provenance, r)?;
        let a = date(s.planned_planting_date)?;
        let b = date(s.planned_harvest_date)?;
        let start = date(s.season_start)?;
        let end = date(s.season_end)?;
        if let (Some(a), Some(b)) = (a, b) {
            invalid(a <= b, "Planned harvest precedes planting.")?;
        }
        if let (Some(a), Some(b)) = (start, end) {
            invalid(a <= b, "Reversed growing-season boundaries.")?;
        }
        invalid(
            s.available_growing_days != Some(0),
            "Available growing days must be positive or null.",
        )?;
        // Monthly planting checks must not contradict a known daily plan.
        if let Some(d) = s.planned_planting_date {
            let step = &scenario.expect("validated scenario").steps[p.step_index];
            if let Some(w) = step.growing_window {
                invalid(
                    d.year == w.start.year && d.month == w.start.month,
                    "Daily planting date disagrees with the legacy step's start month.",
                )?;
            }
        }
    }
    let mut scopes = BTreeSet::new();
    for scope in &r.profile_applicability {
        invalid(
            r.integration
                .crop_references
                .profiles
                .iter()
                .any(|p| p.profile_id == scope.profile_id)
                && scopes.insert(&scope.profile_id)
                && !scope.applicability.region_id.trim().is_empty(),
            "Invalid or duplicate profile applicability.",
        )?;
    }
    let mut rule_ids = BTreeSet::new();
    for rule in &r.duration_rules {
        invalid(
            r.integration
                .crop_references
                .profiles
                .iter()
                .any(|p| p.profile_id == rule.profile_id),
            "Unknown duration profile.",
        )?;
        invalid(
            rule_ids.insert(&rule.profile_id),
            "Multiple duration rules per profile require a future rule-selection contract.",
        )?;
        validate_refs(&rule.source_refs, r)?;
        invalid(
            !rule.applicability.region_id.trim().is_empty(),
            "Blank rule applicability region.",
        )?;
        invalid(
            rule.min_days != Some(0) && rule.max_days != Some(0),
            "Crop duration must be positive or null.",
        )?;
        if let (Some(a), Some(b)) = (rule.min_days, rule.max_days) {
            invalid(a <= b, "Reversed crop duration range.")?;
        }
    }
    Ok(())
}
fn factor(id: &str, status: FactorStatus, why: &str, refs: Vec<String>) -> FactorAssessment {
    FactorAssessment {
        factor_id: id.into(),
        status,
        explanation: why.into(),
        evidence: vec![],
        source_refs: refs,
        limitations: vec![],
        missing_information: if status == FactorStatus::Unknown
            || status == FactorStatus::Conditional
        {
            vec![why.into()]
        } else {
            vec![]
        },
    }
}
fn soil_factor<T: Copy + PartialEq>(
    id: &str,
    items: &[Observation<T>],
    selected: Option<T>,
) -> FactorAssessment {
    let values: Vec<_> = items.iter().filter_map(|o| o.value).collect();
    let conflict = values
        .first()
        .is_some_and(|first| values.iter().any(|v| v != first))
        || selected.is_some_and(|v| values.iter().any(|o| *o != v));
    let mut result = factor(
        id,
        if conflict {
            FactorStatus::Conditional
        } else {
            FactorStatus::Unknown
        },
        if conflict {
            "Soil records disagree; no value was averaged or selected automatically."
        } else {
            "Soil attribution is retained; field representativeness and selection need review."
        },
        items
            .iter()
            .flat_map(|o| o.provenance.source_refs.clone())
            .collect(),
    );
    result.evidence = items.iter().map(|o| o.id.clone()).collect();
    result.limitations=vec!["Farmer observations, modeled grids and samples are distinct. Resolution is disclosed as supplied; no field-precision cutoff is invented.".into()];
    result
}
fn duration_factor(
    r: &AnalysisRequestV02,
    scenario: &str,
    index: usize,
    profile: Option<&str>,
    system: Option<crate::decision::ProductionSystem>,
) -> FactorAssessment {
    let id = format!("step_{index}_duration");
    let Some(plan) = r
        .plans
        .iter()
        .find(|p| p.scenario_id == scenario && p.step_index == index)
    else {
        return factor(
            &id,
            FactorStatus::Unknown,
            "Daily schedule is unknown.",
            vec![],
        );
    };
    let rule = r
        .duration_rules
        .iter()
        .find(|rule| Some(rule.profile_id.as_str()) == profile);
    let Some(rule) = rule else {
        return factor(
            &id,
            FactorStatus::Unknown,
            "No crop-duration constraint supplied.",
            vec![],
        );
    };
    let selected_crop = r
        .integration
        .scenarios
        .iter()
        .find(|s| s.id == scenario)
        .and_then(|s| s.steps.get(index))
        .and_then(|s| s.crop_id.as_ref());
    let profile_crop = r
        .integration
        .crop_references
        .profiles
        .iter()
        .find(|p| Some(p.profile_id.as_str()) == profile)
        .map(|p| &p.crop_id);
    let applicable = selected_crop.is_some()
        && selected_crop == profile_crop
        && plan.season.provenance.kind != EvidenceKind::Unavailable
        && rule.applicability.reviewed_for_context
        && r.region_id.as_ref() == Some(&rule.applicability.region_id)
        && system == Some(rule.applicability.production_system)
        && system != Some(crate::decision::ProductionSystem::Other)
        && trusted(&rule.source_refs, r)
        && trusted(&plan.season.provenance.source_refs, r);
    if !applicable {
        return factor(
            &id,
            FactorStatus::Unknown,
            "Duration rule or schedule lacks reviewed evidence/applicability for this context.",
            rule.source_refs.clone(),
        );
    }
    let s = &plan.season;
    let plant = s.planned_planting_date.and_then(Date::ordinal);
    let end = s.season_end.and_then(Date::ordinal);
    let harvest = s.planned_harvest_date.and_then(Date::ordinal);
    let capacity = match (plant, end, s.available_growing_days) {
        (Some(a), Some(b), days) if b >= a => Some(days.map_or(b - a + 1, |d| d.min(b - a + 1))),
        (_, _, days) => days,
    };
    let elapsed = plant.zip(harvest).map(|(a, b)| b - a + 1);
    let conflict = rule.min_days.is_some_and(|min| {
        capacity.is_some_and(|days| days < min) || elapsed.is_some_and(|days| days < min)
    }) || rule
        .max_days
        .is_some_and(|max| elapsed.is_some_and(|days| days > max));
    let known = (rule.min_days.is_some() && capacity.is_some())
        || (elapsed.is_some() && (rule.min_days.is_some() || rule.max_days.is_some()));
    let mut result = factor(
        &id,
        if conflict {
            FactorStatus::Unsuitable
        } else if known {
            FactorStatus::Supported
        } else {
            FactorStatus::Unknown
        },
        if conflict {
            "Supplied daily schedule conflicts with the applicable duration constraint."
        } else if known {
            "Supplied daily capacity satisfies the evaluated duration bound(s) only."
        } else {
            "Duration bounds or available schedule are incomplete."
        },
        rule.source_refs
            .iter()
            .chain(&s.provenance.source_refs)
            .cloned()
            .collect(),
    );
    result.evidence = vec![format!(
        "capacity_days={capacity:?}; scheduled_crop_days={elapsed:?}; min_days={:?}; max_days={:?}",
        rule.min_days, rule.max_days
    )];
    result.limitations.push("Inclusive calendar days; excess season capacity is not a maximum-duration conflict. No phenology prediction.".into());
    result
}

/// Additive P0 analysis. Critical conflicts dominate; unresolved rotation rules prevent a suitability claim.
pub fn analyze_v02(r: &AnalysisRequestV02) -> Result<AnalysisResultV02, AnalysisErrorV02> {
    let integration = analyze_integration(&r.integration).map_err(|e| AnalysisErrorV02 {
        code: serde_json::to_value(e.code)
            .ok()
            .and_then(|v| v.as_str().map(str::to_owned))
            .unwrap_or_else(|| "INTEGRATION_ERROR".into()),
        message: e.message,
        component: e.component,
        detail: e.detail,
        retryable: e.retryable,
    })?;
    validate_context(r)?;
    let mut scenarios = Vec::new();
    for sc in &integration.rotations.scenarios {
        let mut critical = Vec::new();
        let soil_disagrees = soil_factor(
            "texture",
            &r.soil_context.texture,
            r.integration.soil.texture,
        )
        .status
            == FactorStatus::Conditional
            || soil_factor(
                "drainage",
                &r.soil_context.drainage,
                r.integration.soil.drainage,
            )
            .status
                == FactorStatus::Conditional;
        for (i, step) in sc.scenario.steps.iter().enumerate() {
            let crop = &sc.crops[i];
            let scope = r
                .profile_applicability
                .iter()
                .find(|a| Some(a.profile_id.as_str()) == step.profile_id.as_deref());
            let applicable = scope.is_some_and(|s| {
                s.applicability.reviewed_for_context
                    && r.region_id.as_ref() == Some(&s.applicability.region_id)
                    && step.production_system == Some(s.applicability.production_system)
                    && step.production_system != Some(crate::decision::ProductionSystem::Other)
            });
            let decisive = crop.risks.iter().any(|e| {
                applicable
                    && trusted(&e.source_refs, r)
                    && !(soil_disagrees && (e.code == "soil_texture" || e.code == "drainage"))
            });
            let all_refs: Vec<_> = crop
                .evidence
                .iter()
                .flat_map(|e| e.source_refs.clone())
                .collect();
            let status = if decisive {
                FactorStatus::Unsuitable
            } else if applicable
                && !soil_disagrees
                && crop.eligibility == Eligibility::SupportedBySuppliedEvidence
                && trusted(&all_refs, r)
            {
                FactorStatus::Supported
            } else {
                FactorStatus::Unknown
            };
            let mut f = factor(
                &format!("step_{i}_categorical_constraints"),
                status,
                "Existing categorical findings require explicit profile applicability and reviewed references; disputed soil records cannot prove a soil incompatibility.",
                crop.risks
                    .iter()
                    .chain(&crop.evidence)
                    .flat_map(|e| e.source_refs.clone())
                    .collect(),
            );
            f.evidence = crop
                .risks
                .iter()
                .chain(&crop.evidence)
                .map(|e| e.message.clone())
                .collect();
            critical.push(f);
            critical.push(duration_factor(
                r,
                &sc.scenario.id,
                i,
                step.profile_id.as_deref(),
                step.production_system,
            ));
        }
        let plans: Vec<_> = r
            .plans
            .iter()
            .filter(|p| p.scenario_id == sc.scenario.id)
            .collect();
        let mut schedule = factor(
            "schedule",
            FactorStatus::Unknown,
            "Sequential calendar feasibility is incomplete or not declared.",
            vec![],
        );
        if r.sequential_only
            && plans.len() == sc.scenario.steps.len()
            && plans.iter().all(|p| {
                p.season.provenance.kind != EvidenceKind::Unavailable
                    && trusted(&p.season.provenance.source_refs, r)
            })
        {
            let mut overlap = false;
            let mut known = true;
            let ordered: BTreeMap<_, _> = plans.iter().map(|p| (p.step_index, &p.season)).collect();
            for s in ordered.values() {
                if let Some(p) = s.planned_planting_date {
                    overlap |= s.season_start.is_some_and(|a| p < a)
                        || s.season_end.is_some_and(|b| p > b);
                } else {
                    known = false;
                }
                if let Some(h) = s.planned_harvest_date {
                    overlap |= s.season_end.is_some_and(|e| h > e);
                } else {
                    known = false;
                }
            }
            for pair in ordered.values().collect::<Vec<_>>().windows(2) {
                match (pair[0].planned_harvest_date, pair[1].planned_planting_date) {
                    (Some(a), Some(b)) => overlap |= b <= a,
                    _ => known = false,
                }
            }
            schedule.status = if overlap {
                FactorStatus::Unsuitable
            } else if known {
                FactorStatus::Supported
            } else {
                FactorStatus::Unknown
            };
            schedule.explanation = if overlap {
                "The reviewed single-field sequential dates overlap, are out of order, or cross a supplied season boundary."
            } else if known {
                "The reviewed dates fit the supplied sequential calendar and season boundaries only."
            } else {
                "The reviewed daily schedule is incomplete."
            }.into();
            schedule.evidence=plans.iter().map(|p|format!("step_index={}; planting={:?}; harvest={:?}; season_start={:?}; season_end={:?}",p.step_index,p.season.planned_planting_date,p.season.planned_harvest_date,p.season.season_start,p.season.season_end)).collect();
            schedule.source_refs = plans
                .iter()
                .flat_map(|p| p.season.provenance.source_refs.clone())
                .collect();
            if schedule.status != FactorStatus::Unknown {
                schedule.missing_information.clear();
            }
        }
        critical.push(schedule);
        let mut tradeoffs = vec![
            soil_factor(
                "soil_texture",
                &r.soil_context.texture,
                r.integration.soil.texture,
            ),
            soil_factor(
                "soil_drainage",
                &r.soil_context.drainage,
                r.integration.soil.drainage,
            ),
        ];
        let mut history = factor(
            "family_succession",
            FactorStatus::Unknown,
            "History/family records do not define a sourced succession restriction or benefit.",
            r.history
                .cycles
                .iter()
                .flat_map(|c| c.provenance.source_refs.clone())
                .collect(),
        );
        history.evidence = r
            .history
            .cycles
            .iter()
            .map(|c| {
                format!(
                    "cycle_id={}; crop={:?}; family={:?}; fallow={:?}",
                    c.id, c.crop_id, c.crop_family, c.fallow
                )
            })
            .collect();
        history.limitations.push("Current crop is not a history. Repeated families do not automatically imply risk or benefit.".into());
        tradeoffs.push(history);
        tradeoffs.push(factor("weather_and_numeric_soil_rules",FactorStatus::Unknown,"Forecast risks, temperature/water bounds, pH, carbon and moisture constraints are not evaluated in this P0 increment.",vec![]));
        let status = if critical
            .iter()
            .any(|f| f.status == FactorStatus::Unsuitable)
        {
            FactorStatus::Unsuitable
        } else {
            FactorStatus::RequiresAgronomicValidation
        };
        scenarios.push(ScenarioAssessmentV02 {
            scenario_id: sc.scenario.id.clone(),
            is_baseline: sc.scenario.is_baseline,
            status,
            legacy_eligibility: if status == FactorStatus::Unsuitable {
                Eligibility::ConflictsWithSuppliedEvidence
            } else {
                Eligibility::InsufficientInformation
            },
            critical_constraints: critical,
            tradeoffs,
        });
    }
    Ok(AnalysisResultV02 {schema_version:"0.2-provisional".into(),integration,context:r.clone(),scenarios,limitations:vec![
        "No rankings, forecasts, numerical soil/climate thresholds or rotation benefits implemented. Farmer priorities do not override critical constraints.".into(),
        "Provenance, applicability and review status are caller assertions. Synthetic rules are test-only; output is not production agronomic validation.".into(),
        "Soil records are preserved independently, never fused; the legacy integration's selected soil values are not silently replaced.".into(),
    ]})
}

/// JSON envelope remains status/data or status/error; only the new function opts into v0.2.
pub fn analyze_v02_json(input: &str) -> String {
    let response = match serde_json::from_str::<AnalysisRequestV02>(input) {
        Ok(request) => match analyze_v02(&request) {
            Ok(data) => AnalysisResponseV02::Success {
                data: Box::new(data),
            },
            Err(error) => AnalysisResponseV02::Error { error },
        },
        Err(_) => AnalysisResponseV02::Error {
            error: AnalysisErrorV02 {
                code: "INVALID_JSON".into(),
                message: "Request does not match the provisional v0.2 contract.".into(),
                component: "request".into(),
                detail: None,
                retryable: false,
            },
        },
    };
    serde_json::to_string(&response).unwrap_or_else(|_|r#"{"status":"error","error":{"code":"SERIALIZATION_FAILED","message":"Could not encode v0.2 result.","component":"output","detail":null,"retryable":false}}"#.into())
}
