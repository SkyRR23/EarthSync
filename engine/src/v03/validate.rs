use super::*;
use std::collections::BTreeSet;

pub(super) fn check(ok: bool, path: &str, message: &str) -> Result<(), ValidationError> {
    if ok {
        Ok(())
    } else {
        Err(ValidationError {
            status: Status::InputOrSourceValidationFailure,
            path: path.into(),
            message: message.into(),
        })
    }
}
fn text(s: &str) -> bool {
    !s.trim().is_empty()
}
fn unique<'a>(ids: impl Iterator<Item = &'a str>, path: &str) -> Result<(), ValidationError> {
    let mut seen = BTreeSet::new();
    check(
        ids.into_iter().all(|id| text(id) && seen.insert(id)),
        path,
        "IDs must be nonblank and unique.",
    )
}
pub(super) fn period(p: &Period) -> Result<(), ValidationError> {
    check(
        p.start.ordinal().is_some() && p.end.ordinal().is_some() && p.start <= p.end,
        "period",
        "Expected ordered Gregorian dates in years 1..9999.",
    )
}
fn refs(ids: &[String], r: &Request) -> Result<(), ValidationError> {
    unique(ids.iter().map(String::as_str), "source_ids")?;
    check(
        ids.iter().all(|id| r.sources.iter().any(|s| &s.id == id)),
        "source_ids",
        "Unknown source ID.",
    )
}
fn point(p: &Point) -> Result<(), ValidationError> {
    check(
        p.latitude.is_finite()
            && p.longitude.is_finite()
            && (-90.0..=90.0).contains(&p.latitude)
            && (-180.0..=180.0).contains(&p.longitude),
        "location",
        "Coordinates outside valid finite bounds.",
    )
}
fn depth(d: &Depth) -> Result<(), ValidationError> {
    check(
        d.top_cm.is_finite()
            && d.bottom_cm.is_finite()
            && d.top_cm >= 0.0
            && d.bottom_cm > d.top_cm,
        "depth",
        "Depth must be a positive thickness in finite nonnegative cm.",
    )
}
pub(super) fn provenance(p: &Provenance, r: &Request) -> Result<(), ValidationError> {
    refs(&p.source_ids, r)?;
    if let Some(d) = p.retrieved_on {
        check(d.ordinal().is_some(), "retrieved_on", "Invalid date.")?;
    }
    if let Some(d) = p.issued_on {
        check(d.ordinal().is_some(), "issued_on", "Invalid date.")?;
    }
    if let Some(d) = &p.period {
        period(d)?;
        if p.kind == Kind::Forecast {
            check(
                p.issued_on.is_some_and(|issue| issue <= d.start)
                    && p.retrieved_on.is_none_or(|retrieved| {
                        p.issued_on.is_some_and(|issue| issue <= retrieved)
                    }),
                "issued_on",
                "Forecast issue must precede its valid period and retrieval.",
            )?;
        }
        if p.kind != Kind::Forecast {
            check(
                p.retrieved_on.is_none_or(|x| x >= d.end),
                "retrieved_on",
                "Retrieval precedes historical period end.",
            )?;
        }
    }
    check(
        p.kind != Kind::Forecast || p.issued_on.is_some(),
        "issued_on",
        "Forecasts require an issue date.",
    )?;
    match &p.spatial {
        SpatialSupport::Field { field_id } => {
            check(text(field_id), "spatial.field_id", "Blank field ID.")?
        }
        SpatialSupport::Regional {
            region_id,
            resolution_m,
        } => check(
            text(region_id) && resolution_m.is_none_or(|x| x > 0),
            "spatial",
            "Invalid region or resolution.",
        )?,
        SpatialSupport::Unknown => (),
    }
    check(
        p.kind != Kind::Unavailable || p.quality == Quality::Unavailable,
        "provenance",
        "Unavailable evidence must have unavailable quality.",
    )
}
fn bounds(b: &Bounds, nonnegative: bool) -> Result<(), ValidationError> {
    check(
        b.min.is_finite() && b.max.is_finite() && b.min <= b.max && (!nonnegative || b.min >= 0.0),
        "requirement.range",
        "Bounds must be finite, ordered and in the property's domain.",
    )
}
pub(super) fn numeric_unit(property: Property, unit: Unit) -> bool {
    matches!(
        (property, unit),
        (Property::Ph, Unit::Ph)
            | (Property::OrganicCarbon, Unit::GPerKg | Unit::PercentMass)
            | (Property::BulkDensity, Unit::KgPerM3 | Unit::GPerCm3)
            | (
                Property::SoilMoisture,
                Unit::VolumetricFraction | Unit::VolumetricPercent
            )
    )
}
fn domain(p: Property, u: Unit, x: f64) -> bool {
    x.is_finite()
        && match (p, u) {
            // pH has no universal 0..14 domain; crop limits belong to sourced rules.
            (Property::Ph, Unit::Ph) => true,
            (Property::OrganicCarbon, Unit::GPerKg) => (0.0..=1000.0).contains(&x),
            (Property::OrganicCarbon, Unit::PercentMass)
            | (Property::SoilMoisture, Unit::VolumetricPercent) => (0.0..=100.0).contains(&x),
            (Property::SoilMoisture, Unit::VolumetricFraction) => (0.0..=1.0).contains(&x),
            (Property::BulkDensity, Unit::KgPerM3 | Unit::GPerCm3) => x > 0.0,
            _ => false,
        }
}
fn mmdd(x: u16) -> bool {
    Date {
        year: 2000,
        month: (x / 100) as u8,
        day: (x % 100) as u8,
    }
    .ordinal()
    .is_some()
        && x <= 1231
}
fn rule(rule: &Rule, r: &Request) -> Result<(), ValidationError> {
    refs(&rule.source_ids, r)?;
    let a = &rule.applicability;
    unique(
        a.regions.iter().map(String::as_str),
        "applicability.regions",
    )?;
    check(
        !a.systems.is_empty()
            && a.systems
                .iter()
                .enumerate()
                .all(|(i, s)| !a.systems[..i].contains(s)),
        "applicability.systems",
        "At least one distinct production system required.",
    )?;
    check(
        a.cultivar.as_deref().is_none_or(text),
        "applicability.cultivar",
        "Blank cultivar.",
    )?;
    match &rule.requirement {
        Requirement::Temperature { range_c } => bounds(range_c, false)?,
        Requirement::GrowingDegreeDays {
            base_c,
            range_c_days,
        } => {
            check(
                base_c.is_finite(),
                "base_c",
                "Base temperature must be finite.",
            )?;
            bounds(range_c_days, true)?;
        }
        Requirement::GrowingPeriodRainfall { range_mm } => bounds(range_mm, true)?,
        Requirement::Duration { range_days } => {
            bounds(range_days, true)?;
            check(
                range_days.min >= 1.0
                    && range_days.min.fract() == 0.0
                    && range_days.max.fract() == 0.0,
                "duration",
                "Duration bounds must be positive whole inclusive days.",
            )?;
        }
        Requirement::PlantingWindow {
            first_mmdd,
            last_mmdd,
        } => {
            check(
                mmdd(*first_mmdd) && mmdd(*last_mmdd),
                "planting_window",
                "Invalid MMDD date.",
            )?;
        }
        Requirement::SoilNumeric {
            property,
            range,
            unit,
            depth: d,
            ..
        } => {
            depth(d)?;
            bounds(range, false)?;
            check(
                numeric_unit(*property, *unit)
                    && domain(*property, *unit, range.min)
                    && domain(*property, *unit, range.max),
                "soil_rule",
                "Invalid property/unit/range combination.",
            )?;
        }
        Requirement::SoilCategory { property, allowed } => {
            check(
                matches!(property, Property::Texture | Property::Drainage)
                    && !allowed.is_empty()
                    && allowed.iter().all(|s| text(s)),
                "soil_category",
                "Expected texture/drainage categories.",
            )?;
        }
        Requirement::CropEvapotranspiration { stages } => {
            unique(stages.iter().map(|s| s.id.as_str()), "stages")?;
            check(!stages.is_empty(), "stages", "At least one stage required.")?;
            for (i, s) in stages.iter().enumerate() {
                check(
                    s.kc.is_finite()
                        && s.kc >= 0.0
                        && s.first_day >= 1
                        && s.last_day >= s.first_day
                        && (i == 0 || stages[i - 1].last_day < s.first_day),
                    "stages",
                    "Stages must be ordered, nonoverlapping, with positive day offsets and finite nonnegative Kc.",
                )?;
            }
        }
        Requirement::Succession {
            previous_crop_id,
            previous_family,
            ..
        } => {
            check(
                previous_crop_id.is_some() || previous_family.is_some(),
                "succession",
                "An explicit predecessor identity or family is required.",
            )?;
            check(
                previous_crop_id.as_deref().is_none_or(|s| s.contains('@'))
                    && previous_family.as_deref().is_none_or(text),
                "succession",
                "Invalid versioned crop ID or family.",
            )?;
        }
        Requirement::FloodedManagement { required } => check(
            text(required),
            "flooded_management",
            "Blank management requirement.",
        )?,
        Requirement::IrrigationRequired => (),
    }
    Ok(())
}
pub(super) fn validate(r: &Request) -> Result<(), ValidationError> {
    check(
        r.schema_version == SCHEMA_VERSION,
        "schema_version",
        "Unsupported schema version.",
    )?;
    check(
        text(&r.day_basis),
        "day_basis",
        "Explicit analysis day convention required.",
    )?;
    check(
        r.region_id.as_deref().is_none_or(text),
        "region_id",
        "Blank region.",
    )?;
    if let Some(p) = &r.approximate_user_location {
        point(p)?;
    }
    if let Some(f) = &r.farm {
        check(
            text(&f.field_id)
                && f.confirmed_on.ordinal().is_some()
                && (f.point.is_some() || f.boundary.is_some()),
            "farm",
            "A confirmed farm needs an ID, confirmation date and point or boundary.",
        )?;
        if let Some(p) = &f.point {
            point(p)?;
        }
        if let Some(b) = &f.boundary {
            for p in b {
                point(p)?;
            }
            check(
                b.len() >= 3
                    && b.iter().enumerate().all(|(i, p)| {
                        b[..i]
                            .iter()
                            .all(|q| p.latitude != q.latitude || p.longitude != q.longitude)
                    }),
                "farm.boundary",
                "Boundary needs at least three distinct unclosed vertices.",
            )?;
        }
    }
    unique(r.sources.iter().map(|s| s.id.as_str()), "sources")?;
    for s in &r.sources {
        check(
            text(&s.title)
                && text(&s.citation)
                && s.published_on.is_none_or(|d| d.ordinal().is_some())
                && s.reviewed_on.is_none_or(|d| d.ordinal().is_some())
                && (s.review != Review::Reviewed || s.reviewed_on.is_some()),
            "source",
            "Sources need citation/title, valid dates and review date when reviewed.",
        )?;
    }
    unique(r.photos.iter().map(|p| p.id.as_str()), "photos")?;
    for p in &r.photos {
        refs(&p.source_ids, r)?;
        if let Some(pt) = &p.location {
            point(pt)?;
        }
        check(
            p.captured_on.is_none_or(|d| d.ordinal().is_some()),
            "photo.captured_on",
            "Invalid date.",
        )?;
    }
    unique(r.catalog.iter().map(|p| p.id.as_str()), "catalog")?;
    let mut rule_ids = BTreeSet::new();
    for p in &r.catalog {
        check(
            p.crop_id
                .split_once('@')
                .is_some_and(|(id, v)| text(id) && text(v))
                && text(&p.family)
                && p.cultivar.as_deref().is_none_or(text),
            "catalog",
            "Versioned crop ID, family and nonblank cultivar required.",
        )?;
        check(
            r.catalog
                .iter()
                .filter(|other| other.crop_id == p.crop_id)
                .all(|other| other.family == p.family),
            "catalog.family",
            "Profiles for one versioned crop must agree on crop family.",
        )?;
        for x in &p.rules {
            check(
                text(&x.id)
                    && !x.id.starts_with("catalog.")
                    && !x.id.starts_with("schedule.")
                    && rule_ids.insert(&x.id),
                "rule.id",
                "Rule IDs must be globally unique; catalog.* and schedule.* are reserved contract IDs.",
            )?;
            rule(x, r)?;
        }
    }
    unique(
        r.observations
            .iter()
            .map(|o| o.id.as_str())
            .chain(r.climate.iter().map(|s| s.id.as_str()))
            .chain(r.history.iter().map(|h| h.id.as_str())),
        "input_ids",
    )?;
    for o in &r.observations {
        provenance(&o.provenance, r)?;
        if let Some(d) = &o.depth {
            depth(d)?;
        }
        let valid = match &o.value {
            Some(Value::Number(x)) => {
                numeric_unit(o.property, o.unit) && domain(o.property, o.unit, *x)
            }
            Some(Value::Category(s)) => {
                text(s)
                    && o.unit == Unit::Category
                    && matches!(
                        o.property,
                        Property::Texture | Property::Drainage | Property::FloodManagement
                    )
            }
            Some(Value::Boolean(_)) => {
                o.property == Property::IrrigationAvailable && o.unit == Unit::Boolean
            }
            None => {
                numeric_unit(o.property, o.unit)
                    || matches!(
                        (o.property, o.unit),
                        (
                            Property::Texture | Property::Drainage | Property::FloodManagement,
                            Unit::Category
                        ) | (Property::IrrigationAvailable, Unit::Boolean)
                    )
            }
        };
        check(
            valid
                && (o.provenance.quality == Quality::Usable
                    || o.provenance.quality == Quality::Suspect
                    || o.value.is_none()),
            "observation",
            "Invalid property, value, units or missing/unavailable value state.",
        )?;
    }
    for s in &r.climate {
        check(
            text(&s.day_basis),
            "climate.day_basis",
            "Explicit daily calendar convention required.",
        )?;
        provenance(&s.provenance, r)?;
        check(
            s.unit
                == if matches!(s.variable, Variable::Tmin | Variable::Tmax) {
                    Unit::Celsius
                } else {
                    Unit::MmPerDay
                },
            "climate.unit",
            "Daily temperatures require Celsius; rainfall/ET0 require mm_per_day.",
        )?;
        let mut dates = BTreeSet::new();
        for d in &s.days {
            check(
                d.date.ordinal().is_some() && dates.insert(d.date),
                "climate.days",
                "Invalid or duplicate day.",
            )?;
            check(
                s.provenance
                    .period
                    .as_ref()
                    .is_none_or(|p| d.date >= p.start && d.date <= p.end),
                "climate.days",
                "Day outside declared provenance period.",
            )?;
            check(
                d.value.is_none_or(|v| {
                    v.is_finite()
                        && (matches!(s.variable, Variable::Tmin | Variable::Tmax) || v >= 0.0)
                }) && (matches!(d.quality, Quality::Usable | Quality::Suspect)
                    || d.value.is_none())
                    && (s.provenance.kind != Kind::Unavailable || d.value.is_none()),
                "climate.value",
                "Invalid daily value or quality.",
            )?;
        }
    }
    // Check paired supplied extremes even when another missing day prevents a
    // complete GDD or temperature result. Do not mask invalid values with gaps.
    for lo in r.climate.iter().filter(|s| s.variable == Variable::Tmin) {
        for hi in r.climate.iter().filter(|s| {
            s.variable == Variable::Tmax
                && s.day_basis == lo.day_basis
                && s.provenance.spatial == lo.provenance.spatial
                && s.provenance.source_ids == lo.provenance.source_ids
                && s.provenance.kind == lo.provenance.kind
        }) {
            let highs: std::collections::BTreeMap<_, _> =
                hi.days.iter().map(|d| (d.date, d.value)).collect();
            check(
                lo.days
                    .iter()
                    .all(|d| match (d.value, highs.get(&d.date).copied().flatten()) {
                        (Some(l), Some(h)) => l <= h,
                        _ => true,
                    }),
                "climate",
                "Supplied daily Tmin exceeds Tmax.",
            )?;
        }
    }
    for h in &r.history {
        provenance(&h.provenance, r)?;
        if let Some(p) = &h.period {
            period(p)?;
            check(
                h.provenance
                    .period
                    .as_ref()
                    .is_none_or(|t| t.start <= p.start && t.end >= p.end),
                "history.period",
                "History dates extend beyond their provenance support.",
            )?;
        }
        check(
            !h.fallow || (h.crop_id.is_none() && h.profile_id.is_none()),
            "history",
            "Fallow cannot identify a crop/profile.",
        )?;
        if let Some(id) = &h.profile_id {
            check(
                r.catalog
                    .iter()
                    .any(|p| &p.id == id && Some(&p.crop_id) == h.crop_id.as_ref()),
                "history.profile_id",
                "History profile/crop identity mismatch.",
            )?;
        }
    }
    unique(r.scenarios.iter().map(|s| s.id.as_str()), "scenarios")?;
    for s in &r.scenarios {
        check(
            !s.id.starts_with("candidate:") && !s.plans.is_empty(),
            "scenario",
            "Reserved candidate prefix or empty scenario.",
        )?;
        unique(s.plans.iter().map(|p| p.id.as_str()), "plans")?;
        for p in &s.plans {
            period(&p.period)?;
        }
    }
    if let Some(w) = &r.candidate_window {
        period(&w.period)?;
    }
    Ok(())
}
