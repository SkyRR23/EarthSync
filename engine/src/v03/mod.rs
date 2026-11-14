//! Deterministic offline agricultural checks. Reviewed applicability is supplied
//! by catalog owners, never inferred from a citation, coordinates or crop name.
mod assess;
mod types;
mod validate;
pub mod water;
use serde_json::json;
pub use types::*;

fn trusted(review: Review, mode: Mode) -> bool {
    review == Review::Reviewed || (review == Review::Synthetic && mode == Mode::SoftwareTest)
}
fn source_trust(ids: &[String], r: &Request) -> bool {
    !ids.is_empty()
        && ids.iter().all(|id| {
            r.sources
                .iter()
                .any(|s| &s.id == id && trusted(s.review, r.mode))
        })
}
fn scope(a: &Applicability, p: &Plan, r: &Request) -> bool {
    a.systems.contains(&p.system)
        && (a.regions.is_empty()
            || r.region_id
                .as_ref()
                .is_some_and(|id| a.regions.contains(id)))
        && a.cultivar
            .as_ref()
            .is_none_or(|c| Some(c) == p.cultivar.as_ref())
}
fn spatial(p: &Provenance, a: &Applicability, r: &Request) -> bool {
    match &p.spatial {
        SpatialSupport::Field { field_id } => {
            r.farm.as_ref().is_some_and(|f| &f.field_id == field_id)
        }
        SpatialSupport::Regional { region_id, .. } => {
            !a.field_only && r.region_id.as_ref() == Some(region_id)
        }
        SpatialSupport::Unknown => false,
    }
}
fn usable(p: &Provenance, a: &Applicability, r: &Request) -> bool {
    p.quality == Quality::Usable
        && p.kind != Kind::Unavailable
        && (p.kind != Kind::Synthetic || r.mode == Mode::SoftwareTest)
        && source_trust(&p.source_ids, r)
        && spatial(p, a, r)
        && p.period.is_some()
}
fn finding(s: &Scenario, p: &Plan, rule: &Rule, r: &Request) -> Finding {
    let units = match &rule.requirement {
        Requirement::Temperature { .. } => "Celsius".into(),
        Requirement::GrowingDegreeDays { .. } => "Celsius days".into(),
        Requirement::GrowingPeriodRainfall { .. } | Requirement::CropEvapotranspiration { .. } => {
            "mm".into()
        }
        Requirement::Duration { .. } | Requirement::Succession { .. } => "calendar days".into(),
        Requirement::SoilNumeric { unit, .. } => {
            serde_json::to_value(unit).unwrap().as_str().unwrap().into()
        }
        Requirement::PlantingWindow { .. } => "MMDD".into(),
        Requirement::IrrigationRequired => "boolean".into(),
        Requirement::SoilCategory { .. } | Requirement::FloodedManagement { .. } => {
            "category".into()
        }
    };
    let mut limitations = rule.limitations.clone();
    for source in r.sources.iter().filter(|s| rule.source_ids.contains(&s.id)) {
        limitations.extend(
            source
                .limitations
                .iter()
                .map(|l| format!("{}: {l}", source.id)),
        );
    }
    Finding {
        scenario_id: s.id.clone(),
        plan_id: p.id.clone(),
        rule_id: rule.id.clone(),
        status: Status::InsufficientInformation,
        condition:
            serde_json::to_value(&rule.requirement).expect("validated requirement")["condition"]
                .as_str()
                .unwrap()
                .into(),
        input: json!({"growing_period": p.period, "crop_id": p.crop_id, "profile_id": p.profile_id}),
        requirement: serde_json::to_value(&rule.requirement).expect("validated requirement"),
        units,
        source_ids: rule.source_ids.clone(),
        input_ids: vec![],
        explanation: "Required evidence is unavailable or incomplete.".into(),
        unknowns: vec![],
        limitations,
        software_test_only: r.mode == Mode::SoftwareTest,
    }
}
fn builtin(
    s: &Scenario,
    p: &Plan,
    r: &Request,
    id: &str,
    status: Status,
    message: &str,
) -> Finding {
    Finding {
        scenario_id: s.id.clone(),
        plan_id: p.id.clone(),
        rule_id: id.into(),
        status,
        condition: id.into(),
        input: json!({"growing_period":p.period,"crop_id":p.crop_id,"profile_id":p.profile_id}),
        requirement: json!({"contract_rule":id}),
        units: "not_applicable".into(),
        source_ids: vec![],
        input_ids: vec![p.id.clone()],
        explanation: message.into(),
        unknowns: if status == Status::InsufficientInformation {
            vec![message.into()]
        } else {
            vec![]
        },
        limitations: vec![],
        software_test_only: r.mode == Mode::SoftwareTest,
    }
}

/// Pure typed entrypoint. No I/O, clock access, LLM, default crop thresholds or scores.
pub fn analyze_v03(r: &Request) -> Result<ResultV03, ValidationError> {
    validate::validate(r)?;
    let candidates = candidates(r);
    let mut findings = Vec::new();
    let mut summaries = Vec::new();
    for s in r.scenarios.iter().chain(candidates.iter()) {
        let start = findings.len();
        for (i, p) in s.plans.iter().enumerate() {
            assess::schedule(s, i, p, r, &mut findings);
            let Some(profile) = r
                .catalog
                .iter()
                .find(|x| x.id == p.profile_id && x.crop_id == p.crop_id)
            else {
                findings.push(builtin(
                    s,
                    p,
                    r,
                    "catalog.identity",
                    Status::InsufficientInformation,
                    "Unknown crop or profile; no name-based substitution is permitted.",
                ));
                continue;
            };
            if profile.system != p.system || profile.cultivar != p.cultivar {
                findings.push(builtin(
                    s,
                    p,
                    r,
                    "catalog.applicability",
                    Status::EvidenceNotApplicable,
                    "Profile production system or cultivar does not match the plan.",
                ));
                continue;
            }
            if profile.rules.is_empty() {
                findings.push(builtin(
                    s,
                    p,
                    r,
                    "catalog.rules",
                    Status::InsufficientInformation,
                    "Profile has no requirements.",
                ));
            }
            for rule in &profile.rules {
                let mut f = finding(s, p, rule, r);
                if !scope(&rule.applicability, p, r) {
                    f.status = Status::EvidenceNotApplicable;
                    f.explanation =
                        "Rule scope does not match region, production system or cultivar.".into();
                } else if !trusted(profile.review, r.mode)
                    || !trusted(rule.review, r.mode)
                    || !source_trust(&rule.source_ids, r)
                {
                    f.unknowns.push("Reviewed profile, per-rule review and reviewed source citations are required.".into());
                    f.explanation = "Unreviewed, reference-only or uncited rules cannot determine agricultural support or conflict.".into();
                } else {
                    assess::evaluate(&mut f, rule, s, i, p, r)?;
                }
                if f.status == Status::InsufficientInformation && f.unknowns.is_empty() {
                    f.unknowns.push(
                        "Complete, applicable, dated evidence with usable quality is required."
                            .into(),
                    );
                }
                findings.push(f);
            }
        }
        let slice = &findings[start..];
        let status = if r.mode == Mode::EvidenceAssessment
            && slice
                .iter()
                .any(|f| f.status == Status::ConflictsWithSuppliedEvidence)
        {
            Status::ConflictsWithSuppliedEvidence
        } else {
            Status::InsufficientInformation
        };
        summaries.push(Summary { scenario_id: s.id.clone(), status,
            findings: slice.iter().map(|f| FarmerFinding { plan_id: f.plan_id.clone(), rule_id: f.rule_id.clone(), status: f.status, message: f.explanation.clone() }).collect(),
            unknowns: vec!["These supplied rules are not an exhaustive crop recommendation or future safety assessment.".into()] });
    }
    Ok(ResultV03 { schema_version: SCHEMA_VERSION.into(), software_test_only: r.mode == Mode::SoftwareTest,
        summaries, findings, candidates, context: r.clone(), limitations: vec![
            "No calibrated suitability score, yield prediction, pest benefit or forecast safety claim is produced.".into(),
            "Reviewed/source/applicability flags are caller assertions requiring catalog-owner review; citations alone do not verify a rule.".into(),
            "Regional, modeled, reported and observed evidence remain separate in the retained context. Photos and approximate user location are not field measurements.".into(),
            "ETc is standard-condition crop evapotranspiration arithmetic, not irrigation requirement, effective rainfall, actual soil moisture or a water balance.".into(),
        ] })
}

fn candidates(r: &Request) -> Vec<Scenario> {
    let Some(w) = &r.candidate_window else {
        return vec![];
    };
    r.catalog
        .iter()
        .filter(|p| p.approved_for_candidates && trusted(p.review, r.mode) && p.system == w.system)
        .filter_map(|p| {
            let plan = Plan {
                id: "candidate-plan".into(),
                crop_id: p.crop_id.clone(),
                profile_id: p.id.clone(),
                system: p.system,
                cultivar: p.cultivar.clone(),
                period: w.period.clone(),
            };
            // Evidence-backed scenarios only; no candidate from a blank/reference-only catalog.
            let applicable: Vec<_> = p
                .rules
                .iter()
                .filter(|x| scope(&x.applicability, &plan, r))
                .collect();
            (!applicable.is_empty()
                && applicable
                    .iter()
                    .all(|x| trusted(x.review, r.mode) && source_trust(&x.source_ids, r)))
            .then(|| Scenario {
                id: format!("candidate:{}", p.id),
                plans: vec![plan],
            })
        })
        .collect()
}

/// Versioned success/error JSON envelope. Invalid JSON never becomes a successful assessment.
pub fn analyze_v03_json(input: &str) -> String {
    let response = match serde_json::from_str::<Request>(input) {
        Ok(r) => match analyze_v03(&r) {
            Ok(data) => Response::Success {
                data: Box::new(data),
            },
            Err(error) => Response::Error {
                schema_version: SCHEMA_VERSION.into(),
                error,
            },
        },
        Err(_) => Response::Error {
            schema_version: SCHEMA_VERSION.into(),
            error: ValidationError {
                status: Status::InputOrSourceValidationFailure,
                path: "request".into(),
                message: "Invalid JSON or payload shape for earthsync.engine.v0.3.0.".into(),
            },
        },
    };
    serde_json::to_string(&response).expect("validated finite output")
}
