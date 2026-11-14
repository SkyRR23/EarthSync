use super::*;
use std::collections::BTreeMap;

fn range_label(value: &serde_json::Value) -> String {
    format!("{} to {}", value["min"], value["max"])
}

fn compare(f: &mut Finding, yes: bool, input: serde_json::Value, units: &str) {
    f.status = if yes {
        Status::SupportedBySuppliedEvidence
    } else {
        Status::ConflictsWithSuppliedEvidence
    };
    f.input = input;
    f.units = units.into();
    let outcome = if yes { "meets" } else { "conflicts with" };
    let description = match f.condition.as_str() {
        "temperature" => format!(
            "Daily temperature extremes {} to {} °C",
            f.input["minimum_tmin_c"], f.input["maximum_tmax_c"]
        ),
        "growing_degree_days" => format!(
            "Accumulated {} °C days above base {} °C",
            f.input["gdd"], f.input["base_c"]
        ),
        "growing_period_rainfall" => {
            format!("Growing-period rainfall {} mm", f.input["rainfall_mm"])
        }
        "duration" => format!(
            "Planned growing period {} inclusive days",
            f.input["inclusive_days"]
        ),
        "planting_window" => {
            let date = &f.input["planting_date"];
            format!(
                "Planned planting date {:04}-{:02}-{:02}",
                date["year"].as_u64().unwrap(),
                date["month"].as_u64().unwrap(),
                date["day"].as_u64().unwrap()
            )
        }
        "succession" => format!(
            "Preceding crop {} and planting schedule",
            f.input["previous_crop_id"]
        ),
        "schedule.sequential" => "Sequential planting and harvest dates".into(),
        _ => {
            let records: Vec<_> = f
                .input
                .as_array()
                .into_iter()
                .flatten()
                .map(|o| {
                    format!(
                        "{} {} {}",
                        o["id"].as_str().unwrap_or("record"),
                        o["value"]["value"],
                        o["unit"].as_str().unwrap_or("")
                    )
                })
                .collect();
            records.join(", ")
        }
    };
    let required = match f.condition.as_str() {
        "temperature" => range_label(&f.requirement["range_c"]),
        "growing_degree_days" => range_label(&f.requirement["range_c_days"]),
        "growing_period_rainfall" => range_label(&f.requirement["range_mm"]),
        "duration" => range_label(&f.requirement["range_days"]),
        "soil_numeric" => range_label(&f.requirement["range"]),
        "soil_category" => f.requirement["allowed"].to_string(),
        "irrigation_required" => "irrigation available (adequacy unknown)".into(),
        "flooded_management" => f.requirement["required"].to_string(),
        "planting_window" => format!(
            "MMDD {} through {} (inclusive, may wrap New Year)",
            f.requirement["first_mmdd"], f.requirement["last_mmdd"]
        ),
        "succession" => format!(
            "reviewed predecessor and at least {} explicit fallow days",
            f.requirement["minimum_fallow_days"]
        ),
        _ => "next planting strictly after previous harvest".into(),
    };
    f.explanation = format!("{description}; this {outcome} requirement {required} ({units}).");
}
fn within(x: f64, b: &Bounds) -> bool {
    x >= b.min && x <= b.max
}
fn finite(x: f64) -> Result<f64, ValidationError> {
    validate::check(
        x.is_finite(),
        "calculation",
        "Arithmetic overflow; no scientific result produced.",
    )?;
    Ok(x)
}
fn attach(f: &mut Finding, id: &str, p: &Provenance) {
    if !f.input_ids.iter().any(|x| x == id) {
        f.input_ids.push(id.into());
    }
    for s in &p.source_ids {
        if !f.source_ids.contains(s) {
            f.source_ids.push(s.clone());
        }
    }
    if p.kind == Kind::Modeled {
        f.limitations
            .push(format!("{id}: modeled evidence, not a field measurement."));
    }
    if let Some(u) = &p.uncertainty {
        f.limitations.push(format!("{id}: {u}"));
    }
}
fn climate(v: Variable, p: &Plan, rule: &Rule, r: &Request, f: &mut Finding) -> Option<Vec<f64>> {
    let all: Vec<_> = r
        .climate
        .iter()
        .filter(|s| {
            s.variable == v
                && s.provenance
                    .period
                    .as_ref()
                    .is_none_or(|t| t.start <= p.period.end && t.end >= p.period.start)
        })
        .collect();
    if all.len() != 1 {
        f.unknowns.push(format!(
            "Need one explicitly selected {v:?} series; missing or ambiguous overlapping sources."
        ));
        return None;
    }
    let s = all[0];
    attach(f, &s.id, &s.provenance);
    if s.day_basis != r.day_basis {
        f.status = Status::EvidenceNotApplicable;
        f.explanation = "Daily calendar convention does not match the growing-period dates; adapter alignment required.".into();
        return None;
    }
    if v == Variable::Et0
        && s.provenance
            .method
            .as_deref()
            .is_none_or(|m| m.trim().is_empty())
    {
        f.unknowns.push("Reference ET0 method/definition is required; monthly temperature and rainfall cannot substitute for it.".into());
        return None;
    }
    let kind_matches = match r.climate_intent {
        ClimateIntent::Historical => matches!(
            s.provenance.kind,
            Kind::Observed | Kind::Modeled | Kind::Synthetic
        ),
        ClimateIntent::Forecast => s.provenance.kind == Kind::Forecast,
    };
    if !kind_matches || !spatial(&s.provenance, &rule.applicability, r) {
        f.status = Status::EvidenceNotApplicable;
        f.explanation =
            "Climate evidence kind or spatial support does not match the requested assessment."
                .into();
        return None;
    }
    if !usable(&s.provenance, &rule.applicability, r) {
        return None;
    }
    let map: BTreeMap<_, _> = s
        .days
        .iter()
        .map(|d| (d.date.ordinal().unwrap(), d))
        .collect();
    let mut out = Vec::new();
    let mut missing = 0;
    for n in p.period.start.ordinal().unwrap()..=p.period.end.ordinal().unwrap() {
        match map
            .get(&n)
            .filter(|d| d.quality == Quality::Usable)
            .and_then(|d| d.value)
        {
            Some(x) => out.push(x),
            None => missing += 1,
        }
    }
    if missing > 0 {
        f.input = json!({"period":p.period,"expected_days":out.len()+missing,"usable_days":out.len(),"missing_or_unusable_days":missing});
        f.unknowns.push(format!("{missing} growing-period days missing or unusable for {v:?}; no extrapolation or zero filling."));
        None
    } else {
        Some(out)
    }
}
fn observations<'a>(
    prop: Property,
    p: &Plan,
    rule: &Rule,
    r: &'a Request,
    f: &mut Finding,
) -> Vec<&'a Observation> {
    let all: Vec<_> = r
        .observations
        .iter()
        .filter(|o| o.property == prop)
        .collect();
    f.input = json!(all);
    for o in &all {
        attach(f, &o.id, &o.provenance);
    }
    all.into_iter()
        .filter(|o| {
            let temporal = o
                .provenance
                .period
                .as_ref()
                .is_some_and(|t| t.start <= p.period.start && t.end >= p.period.end);
            usable(&o.provenance, &rule.applicability, r)
                && temporal
                && o.provenance.kind != Kind::Forecast
        })
        .collect()
}
fn combine(f: &mut Finding, results: &[bool]) {
    if results.is_empty() {
        return;
    }
    if results.iter().any(|x| *x) && results.iter().any(|x| !*x) {
        f.status = Status::InsufficientInformation;
        f.explanation = "Contradictory supplied records require review; no farmer/model evidence was averaged or preferred.".into();
        f.unknowns.push(
            "Resolve contradictory records and their spatial, temporal and method support.".into(),
        );
    } else {
        let input = f.input.clone();
        let units = f.units.clone();
        compare(f, results[0], input, &units);
    }
}
fn converted(x: f64, from: Unit, to: Unit) -> Option<f64> {
    let v = if from == to {
        x
    } else {
        match (from, to) {
            (Unit::PercentMass, Unit::GPerKg) => x * 10.0,
            (Unit::GPerKg, Unit::PercentMass) => x / 10.0,
            (Unit::GPerCm3, Unit::KgPerM3) => x * 1000.0,
            (Unit::KgPerM3, Unit::GPerCm3) => x / 1000.0,
            (Unit::VolumetricFraction, Unit::VolumetricPercent) => x * 100.0,
            (Unit::VolumetricPercent, Unit::VolumetricFraction) => x / 100.0,
            _ => return None,
        }
    };
    v.is_finite().then_some(v)
}

pub(super) fn evaluate(
    f: &mut Finding,
    rule: &Rule,
    s: &Scenario,
    index: usize,
    p: &Plan,
    r: &Request,
) -> Result<(), ValidationError> {
    match &rule.requirement {
        Requirement::Duration { range_days } => {
            let days = p.period.end.ordinal().unwrap() - p.period.start.ordinal().unwrap() + 1;
            compare(
                f,
                within(f64::from(days), range_days),
                json!({"period":p.period,"inclusive_days":days}),
                "days",
            );
        }
        Requirement::PlantingWindow {
            first_mmdd,
            last_mmdd,
        } => {
            let date = u16::from(p.period.start.month) * 100 + u16::from(p.period.start.day);
            let yes = if first_mmdd <= last_mmdd {
                date >= *first_mmdd && date <= *last_mmdd
            } else {
                date >= *first_mmdd || date <= *last_mmdd
            };
            compare(f, yes, json!({"planting_date":p.period.start}), "MMDD");
        }
        Requirement::Temperature { range_c }
        | Requirement::GrowingDegreeDays {
            range_c_days: range_c,
            ..
        } => {
            let lo = climate(Variable::Tmin, p, rule, r, f);
            let hi = climate(Variable::Tmax, p, rule, r, f);
            if let (Some(lo), Some(hi)) = (lo, hi) {
                validate::check(
                    lo.iter().zip(&hi).all(|(l, h)| l <= h),
                    "climate",
                    "Daily Tmin exceeds Tmax.",
                )?;
                if let Requirement::GrowingDegreeDays { base_c, .. } = &rule.requirement {
                    let mut gdd = 0.0;
                    for (l, h) in lo.iter().zip(&hi) {
                        gdd = finite(gdd + finite(l / 2.0 + h / 2.0 - base_c)?.max(0.0))?;
                    }
                    compare(
                        f,
                        within(gdd, range_c),
                        json!({"period":p.period,"gdd":gdd,"days":lo.len(),"base_c":base_c,"method":"uncapped_daily_mean"}),
                        "Celsius days",
                    );
                } else {
                    let min = lo.iter().copied().reduce(f64::min).unwrap();
                    let max = hi.iter().copied().reduce(f64::max).unwrap();
                    compare(
                        f,
                        within(min, range_c) && within(max, range_c),
                        json!({"period":p.period,"minimum_tmin_c":min,"maximum_tmax_c":max,"days":lo.len()}),
                        "Celsius",
                    );
                }
            }
        }
        Requirement::GrowingPeriodRainfall { range_mm } => {
            if let Some(days) = climate(Variable::Rainfall, p, rule, r, f) {
                let sum = finite(days.iter().sum())?;
                compare(
                    f,
                    within(sum, range_mm),
                    json!({"period":p.period,"rainfall_mm":sum,"days":days.len()}),
                    "mm",
                );
                f.limitations.push("Rainfall is not effective rainfall, irrigation supply, soil moisture or crop water sufficiency.".into());
            }
        }
        Requirement::SoilNumeric {
            property,
            range,
            unit,
            depth,
            method,
        } => {
            let obs = observations(*property, p, rule, r, f);
            f.units = format!("{unit:?}");
            let mut results = vec![];
            for o in obs {
                // Exact depth/method support: never infer a root-zone value from another layer.
                if o.depth.as_ref() != Some(depth)
                    || method
                        .as_ref()
                        .is_some_and(|m| o.provenance.method.as_ref() != Some(m))
                {
                    f.unknowns.push(format!(
                        "{}: depth or measurement method mismatch; record not compared.",
                        o.id
                    ));
                    continue;
                }
                if let Some(Value::Number(x)) = o.value {
                    let v = converted(x, o.unit, *unit).ok_or_else(|| ValidationError {
                        status: Status::InputOrSourceValidationFailure,
                        path: o.id.clone(),
                        message: "Unit conversion failed or overflowed.".into(),
                    })?;
                    results.push(within(v, range));
                }
            }
            combine(f, &results);
        }
        Requirement::SoilCategory { property, allowed } => {
            let obs = observations(*property, p, rule, r, f);
            let results: Vec<_> = obs
                .iter()
                .filter_map(|o| match &o.value {
                    Some(Value::Category(x)) => Some(allowed.contains(x)),
                    _ => None,
                })
                .collect();
            f.units = "category".into();
            combine(f, &results);
        }
        Requirement::IrrigationRequired => {
            let obs = observations(Property::IrrigationAvailable, p, rule, r, f);
            let results: Vec<_> = obs
                .iter()
                .filter_map(|o| match o.value {
                    Some(Value::Boolean(x)) => Some(x),
                    _ => None,
                })
                .collect();
            f.units = "boolean".into();
            combine(f, &results);
            f.limitations.push("Availability is not irrigation adequacy, delivery, water quality or applied volume.".into());
        }
        Requirement::FloodedManagement { required } => {
            if p.system != ProductionSystem::FloodedLowland {
                f.status = Status::EvidenceNotApplicable;
                f.explanation = "Flooded-lowland management requirements do not apply to this production system.".into();
            } else {
                let obs = observations(Property::FloodManagement, p, rule, r, f);
                let results: Vec<_> = obs
                    .iter()
                    .filter_map(|o| match &o.value {
                        Some(Value::Category(x)) => Some(x == required),
                        _ => None,
                    })
                    .collect();
                f.units = "category".into();
                combine(f, &results);
            }
        }
        Requirement::CropEvapotranspiration { stages } => {
            if let Some(et0) = climate(Variable::Et0, p, rule, r, f) {
                let mut values = Vec::new();
                let mut total = 0.0;
                for (i, et) in et0.iter().enumerate() {
                    let day = (i + 1) as u32;
                    let Some(stage) = stages
                        .iter()
                        .find(|x| x.first_day <= day && x.last_day >= day)
                    else {
                        f.unknowns.push(format!(
                            "No sourced Kc stage for growing-period day {day}; total ETc unknown."
                        ));
                        return Ok(());
                    };
                    let etc = finite(et * stage.kc)?;
                    total = finite(total + etc)?;
                    values.push(json!({"day_offset":day,"stage_id":stage.id,"et0_mm":et,"kc":stage.kc,"etc_mm":etc}));
                }
                f.status = Status::SupportedBySuppliedEvidence;
                f.input = json!({"period":p.period,"daily":values,"total_etc_mm":total});
                f.units = "mm".into();
                f.explanation = "Calculated standard-condition ETc = Kc × ET0 for every aligned day; this is not a water-balance or irrigation-sufficiency finding.".into();
            }
        }
        Requirement::Succession {
            previous_crop_id,
            previous_family,
            minimum_fallow_days,
        } => {
            succession(
                f,
                rule,
                s,
                index,
                p,
                r,
                previous_crop_id.as_deref(),
                previous_family.as_deref(),
                *minimum_fallow_days,
            );
        }
    }
    Ok(())
}

pub(super) fn schedule(s: &Scenario, i: usize, p: &Plan, r: &Request, findings: &mut Vec<Finding>) {
    if !r.sequential_field || r.farm.is_none() {
        return;
    }
    if i > 0 {
        let previous = &s.plans[i - 1];
        let yes = previous.period.end < p.period.start;
        let mut f = builtin(
            s,
            p,
            r,
            "schedule.sequential",
            Status::InsufficientInformation,
            "Sequential calendar check.",
        );
        compare(
            &mut f,
            yes,
            json!({"previous":previous,"next":p}),
            "calendar days",
        );
        f.requirement =
            json!({"next_planting":"strictly after preceding harvest","inclusive_dates":true});
        findings.push(f);
    }
    // Every attributed history interval is checked, including explicit fallow.
    for h in &r.history {
        let field = Applicability {
            regions: vec![],
            systems: vec![p.system],
            cultivar: None,
            field_only: true,
        };
        if !usable(&h.provenance, &field, r) || h.provenance.kind == Kind::Forecast {
            continue;
        }
        if let Some(t) = &h.period
            && t.start <= p.period.end
            && t.end >= p.period.start
        {
            let mut f = builtin(
                s,
                p,
                r,
                "schedule.history_overlap",
                Status::ConflictsWithSuppliedEvidence,
                "Plan overlaps an attributed field-history interval.",
            );
            f.input = json!({"history":h,"plan":p});
            f.units = "calendar days".into();
            attach(&mut f, &h.id, &h.provenance);
            findings.push(f);
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn succession(
    f: &mut Finding,
    rule: &Rule,
    s: &Scenario,
    index: usize,
    p: &Plan,
    r: &Request,
    crop: Option<&str>,
    family: Option<&str>,
    min_fallow: u32,
) {
    f.units = "calendar days".into();
    if !r.sequential_field || r.farm.is_none() {
        f.unknowns
            .push("Confirmed field and explicit sequential-use assertion required.".into());
        return;
    }
    // A region-wide rule may apply to this field, but regional crop/fallow
    // history cannot establish what actually occupied the confirmed field.
    let field = Applicability {
        field_only: true,
        ..rule.applicability.clone()
    };
    let (prev_crop, prev_family, end, id) = if index > 0 {
        let prev = &s.plans[index - 1];
        let family = r
            .catalog
            .iter()
            .find(|x| x.id == prev.profile_id && x.crop_id == prev.crop_id)
            .map(|x| x.family.as_str());
        (
            Some(prev.crop_id.as_str()),
            family,
            prev.period.end,
            prev.id.as_str(),
        )
    } else {
        if !r.history_complete {
            f.unknowns.push(
                "Complete field history required to select the immediate preceding crop.".into(),
            );
            return;
        }
        if r.history.iter().any(|h| {
            h.period.is_none()
                || (!h.fallow && h.crop_id.is_none())
                || !usable(&h.provenance, &field, r)
                || h.provenance.kind == Kind::Forecast
        }) {
            f.unknowns
                .push("History contains undated, unidentified or unusable entries.".into());
            return;
        }
        let previous: Vec<_> = r
            .history
            .iter()
            .filter(|h| !h.fallow && h.period.as_ref().unwrap().start < p.period.start)
            .collect();
        let Some(h) = previous
            .iter()
            .max_by_key(|h| h.period.as_ref().unwrap().end)
        else {
            f.unknowns.push("Preceding crop identity unknown.".into());
            return;
        };
        // Overlapping crop history cannot establish an unambiguous single-field succession.
        if previous.iter().any(|other| {
            other.id != h.id
                && other.period.as_ref().unwrap().end >= h.period.as_ref().unwrap().start
        }) {
            f.unknowns
                .push("Overlapping history prevents predecessor selection.".into());
            return;
        }
        attach(f, &h.id, &h.provenance);
        let family = h
            .profile_id
            .as_ref()
            .and_then(|id| r.catalog.iter().find(|x| &x.id == id))
            .map(|x| x.family.as_str());
        (
            h.crop_id.as_deref(),
            family,
            h.period.as_ref().unwrap().end,
            h.id.as_str(),
        )
    };
    f.input = json!({"previous_id":id,"previous_crop_id":prev_crop,"previous_family":prev_family,"previous_harvest":end,"next_planting":p.period.start});
    if crop.is_some() && prev_crop.is_none() || family.is_some() && prev_family.is_none() {
        return;
    }
    if crop.is_some_and(|x| Some(x) != prev_crop) || family.is_some_and(|x| Some(x) != prev_family)
    {
        f.status = Status::EvidenceNotApplicable;
        f.explanation = "Succession rule does not match the preceding crop identity/family.".into();
        return;
    }
    let end = end.ordinal().unwrap();
    let start = p.period.start.ordinal().unwrap();
    if start <= end {
        compare(f, false, f.input.clone(), "calendar days");
        return;
    }
    let gap = start - end - 1;
    if gap == 0 && min_fallow == 0 {
        compare(f, true, f.input.clone(), "calendar days");
        return;
    }
    // A calendar gap is not evidence that land was fallow. Require an attributed
    // explicit fallow interval covering the whole gap, and no crop in that gap.
    let fallow = r.history.iter().find(|h| {
        h.fallow
            && h.period.as_ref().is_some_and(|t| {
                t.start.ordinal().unwrap() <= end + 1 && t.end.ordinal().unwrap() >= start - 1
            })
            && usable(&h.provenance, &field, r)
            && h.provenance.kind != Kind::Forecast
    });
    let crop_in_gap = r.history.iter().any(|h| {
        !h.fallow
            && h.period.as_ref().is_some_and(|t| {
                t.start.ordinal().unwrap() < start && t.end.ordinal().unwrap() > end
            })
    });
    if min_fallow > 0 && fallow.is_none() {
        f.unknowns.push("Calendar gap alone cannot establish fallow; explicit attributed fallow coverage required.".into());
        return;
    }
    if let Some(h) = fallow {
        attach(f, &h.id, &h.provenance);
    }
    if crop_in_gap {
        f.unknowns
            .push("Crop records contradict the proposed fallow interval.".into());
        return;
    }
    let mut input = f.input.clone();
    input["gap_days"] = json!(gap);
    compare(f, gap >= min_fallow, input, "calendar days");
}
