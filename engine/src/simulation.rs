//! Explicit exploratory simulation; never enables the reviewed agronomic rules.
use serde_json::{Value, json};

fn number(value: &Value) -> Option<f64> {
    value.as_f64().filter(|v| v.is_finite())
}

fn range_conflict(profile: &Value, key: &str, value: f64) -> Option<bool> {
    let range = &profile[key]["absolute"];
    let lo = number(&range["min"])?;
    let hi = number(&range["max"])?;
    Some(value < lo || value > hi)
}

fn evaluate(crops: &[String], req: &Value, profiles: &[Value]) -> Value {
    let months = req["months"].as_array().cloned().unwrap_or_default();
    let start = req["start_month"].as_u64().unwrap_or(1).clamp(1, 12) as usize;
    let length = req["season_months"].as_u64().unwrap_or(4).clamp(1, 12) as usize;
    let year = req["data_year"].as_i64().unwrap_or(0);
    let complete_year = (1..=12).all(|month| {
        months
            .iter()
            .any(|m| m["month"].as_i64() == Some(month) && number(&m["rain_mm"]).is_some())
    });
    let rainfall: f64 = months.iter().filter_map(|m| number(&m["rain_mm"])).sum();
    let mut flags = 0;
    let mut known = 0;
    let mut family_breaks = 0;
    let mut previous_family = String::new();
    let mut findings = Vec::new();
    for (index, crop) in crops.iter().enumerate() {
        let Some(p) = profiles
            .iter()
            .find(|p| p["crop_id"].as_str() == Some(crop.as_str()))
        else {
            findings.push(json!({"crop":crop,"reason":"No packaged ecological reference for this crop; its fit remains unknown."}));
            previous_family.clear();
            continue;
        };
        let family = p["family"].as_str().unwrap_or("");
        if !family.is_empty() && !previous_family.is_empty() && family != previous_family {
            family_breaks += 1;
        }
        previous_family = family.to_string();
        let selected: Vec<&Value> = (0..length)
            .filter_map(|offset| {
                let month = ((start - 1 + index * length + offset) % 12 + 1) as i64;
                months
                    .iter()
                    .find(|m| m["month"].as_i64() == Some(month) && number(&m["temp_c"]).is_some())
            })
            .collect();
        if selected.len() == length {
            // Exploratory comparison of a historical monthly average against a
            // global ecological envelope, explicitly not a daily-extreme test.
            let mean = selected
                .iter()
                .filter_map(|m| number(&m["temp_c"]))
                .sum::<f64>()
                / length as f64;
            if let Some(conflict) = range_conflict(p, "temperature", mean) {
                known += 1;
                if conflict {
                    flags += 1;
                }
                findings.push(json!({"crop":crop,"reason":format!("Historical analog {}: average temperature {:.1} °C in the assumed season is {} the global ecological reference envelope. This is an exploratory comparison, not a local crop threshold.",year,mean,if conflict {"outside"} else {"inside"}),"source_ids":p["source_ids"],"months":selected.iter().map(|m|m["month"].clone()).collect::<Vec<_>>()}));
            }
        } else {
            findings.push(json!({"crop":crop,"reason":"Monthly temperature data are incomplete for this assumed season; temperature fit is unknown."}));
        }
        if complete_year && req["irrigated"].as_bool() == Some(false) {
            if let Some(conflict) = range_conflict(p, "annual_rainfall", rainfall) {
                known += 1;
                if conflict {
                    flags += 1;
                }
                findings.push(json!({"crop":crop,"reason":format!("The historical analog year has {:.0} mm rainfall, {} the global annual reference envelope. Annual rainfall is not crop-season water supply; irrigation and timing can change the interpretation.",rainfall,if conflict {"outside"} else {"inside"}),"source_ids":p["source_ids"]}));
            }
        }
    }
    let repeats = crops.windows(2).filter(|w| w[0] == w[1]).count();
    json!({"crops":crops,"reference_conflicts":flags,"known_comparisons":known,"family_breaks":family_breaks,"consecutive_repeats":repeats,"findings":findings})
}

pub fn analyze(req: &Value) -> Value {
    if req["operation"] == "tasks" {
        return tasks(req);
    }
    let Some(profiles) = req["profiles"].as_array() else {
        return json!({"status":"error","message":"Crop reference context is missing."});
    };
    let Some(baseline) = req["baseline"].as_array() else {
        return json!({"status":"error","message":"Enter your existing crop sequence."});
    };
    if profiles.len() > 20
        || baseline.len() != 3
        || req["months"].as_array().map_or(0, Vec::len) > 12
    {
        return json!({"status":"error","message":"Use three seasons and one historical year."});
    }
    let crops: Vec<String> = baseline
        .iter()
        .map(|c| c.as_str().unwrap_or("").to_string())
        .collect();
    if crops.iter().any(String::is_empty) {
        return json!({"status":"error","message":"Fill in all three crops in your existing plan first. We will generate the alternatives."});
    }
    let base = evaluate(&crops, req, profiles);
    let ids: Vec<String> = profiles
        .iter()
        .filter_map(|p| p["crop_id"].as_str().map(str::to_string))
        .collect();
    let mut options = Vec::new();
    for a in &ids {
        for b in &ids {
            for c in &ids {
                let candidate = vec![a.clone(), b.clone(), c.clone()];
                if a == b || b == c || candidate == crops {
                    continue;
                }
                options.push(evaluate(&candidate, req, profiles));
            }
        }
    }
    options.sort_by_key(|p| {
        (
            p["reference_conflicts"].as_u64().unwrap_or(0),
            std::cmp::Reverse(p["known_comparisons"].as_u64().unwrap_or(0)),
            std::cmp::Reverse(if req["prefer_diversity"] == true {
                p["family_breaks"].as_u64().unwrap_or(0)
            } else {
                0
            }),
            p["crops"].to_string(),
        )
    });
    let mut alternatives: Vec<Value> = Vec::new();
    for option in options {
        if alternatives
            .iter()
            .any(|p| p["crops"][0] == option["crops"][0])
        {
            continue;
        }
        alternatives.push(option);
        if alternatives.len() == 2 {
            break;
        }
    }
    let recommendation = alternatives.first().map(|best| {
        let evidence = best["known_comparisons"].as_u64().unwrap_or(0);
        let fewer = best["reference_conflicts"].as_u64() < base["reference_conflicts"].as_u64();
        if evidence > 0 && fewer && best["known_comparisons"].as_u64() == base["known_comparisons"].as_u64() {
            "Consider Alternative 1 instead of the existing plan in this simulation because it has fewer conflicts with the supplied ecological reference envelopes over the historical analog. Review its findings and missing inputs before applying it to a real field."
        } else if evidence > 0 && req["prefer_diversity"] == true && best["reference_conflicts"] == base["reference_conflicts"] && best["known_comparisons"] == base["known_comparisons"] && best["family_breaks"].as_u64() > base["family_breaks"].as_u64() {
            "Consider Alternative 1 instead in this simulation because it changes crop families more often, matching your selected diversity objective, without adding reference-envelope conflicts in the supplied climate data. This does not prove reduced pests, improved soil or higher yield."
        } else if evidence == 0 {
            "The engine generated alternatives, but historical climate evidence is missing. No data-based preference can be established yet. Load the selected historical year, then compare again."
        } else {
            "These alternatives are worth exploring, but the supplied evidence does not establish a better option than the existing plan. Family breaks describe sequence diversity only, not a verified pest or soil benefit."
        }
    }).unwrap_or("No alternative could be generated from the supplied crop references.");
    json!({"status":"success","engine":"rust-exploratory-simulation-v1","simulation_date":req["simulation_date"],"data_year":req["data_year"],"season_months":req["season_months"],"start_month":req["start_month"],"climate_source":req["climate_source"],"climate_source_hash":req["climate_source_hash"],"baseline":base,"alternatives":alternatives,"recommendation":recommendation,"sources":req["sources"],"limitations":["Uses a historical year as an analog repeated over proposed seasons, not future weather.","Season lengths are user-declared assumptions, not crop maturity predictions.","Global ecological references are not locally validated thresholds. No blocked crop rule is enabled.","No yield, profit, pesticide, fertilizer or irrigation amount is predicted."]})
}

fn tasks(req: &Value) -> Value {
    let date = req["simulation_date"].as_str().unwrap_or("unknown");
    let mut output = Vec::new();
    if let Some(rain) = number(&req["reference_rain7_mm"]) {
        output.push(json!({"id":"reference","title":"Review the dated reference rainfall before your field visit","reason":format!("Seven days ending {}: {:.2} mm rain at the archived Yangon reference point. This is not a field measurement or an irrigation requirement. Use it to plan a soil-moisture/drainage check, then confirm with your own observation.",date,rain),"done":false}));
    }
    if let Some(wetness) = number(&req["reference_root_wetness"]) {
        output.push(json!({"id":"reference_soil","title":"Compare the regional wetness reference with your soil check","reason":format!("Dated model root-zone wetness index: {:.3}. It is a regional model index, not a measured soil-moisture percentage or a healthy/unhealthy score.",wetness),"done":false}));
    }
    let heat = number(&req["heat_trigger_c"]).unwrap_or(30.0);
    if req["watered_today"] == true {
        output.push(json!({"id":"water","title":"Watering already recorded for this simulation day","reason":"Review the soil before adding more water; no extra irrigation amount is inferred.","done":true}));
    } else if req["soil_wet_today"] == true {
        output.push(json!({"id":"water","title":"Soil reported wet: avoid automatically adding water","reason":"Your observation is the reason for this check. Recheck later if conditions change.","done":true}));
    } else {
        let reason = if let Some(temp) = number(&req["month_mean_temp_c"]) {
            if temp >= heat {
                format!(
                    "The selected historical month's mean is {:.1} °C, above the simulation trigger {:.1} °C. Check soil moisture and plant appearance more often in this simulation. This is not a measured hot day and does not establish an irrigation dose.",
                    temp, heat
                )
            } else {
                format!(
                    "Historical monthly mean {:.1} °C is context only. Check the soil at crop-root depth before deciding whether to irrigate; the app has no daily field-moisture reading.",
                    temp
                )
            }
        } else {
            "Historical temperature and daily field moisture are unknown. Check the soil rather than assuming the field needs water.".into()
        };
        output.push(json!({"id":"water","title":"Check soil moisture before deciding on water","reason":reason,"done":false}));
    }
    if req["pest_report"] == true {
        output.push(json!({"id":"pests","title":"Inspect the plants you reported insects on","reason":"Compare affected and unaffected leaves, record the crop stage and photograph the insects. Seek identification before choosing treatment; this is not a pesticide schedule.","done":false}));
    } else {
        output.push(json!({"id":"pests","title":"Inspect leaves and their undersides","reason":"Routine crop scouting in the simulation. No dated pest forecast or reviewed pesticide calendar was supplied.","done":false}));
    }
    if let Some(wind) = number(&req["wind_kmh"]) {
        if wind >= 30.0 {
            output.push(json!({"id":"wind","title":"Check crop supports and avoid spray drift","reason":format!("Supplied historical wind is {:.1} km/h. The 30 km/h trigger is a simulation assumption, not a pesticide-label limit. Inspect supports and follow local guidance.",wind),"done":false}));
        }
    }
    output.push(json!({"id":"record","title":"Record what you find in the field","reason":"Add a note with the simulation date so the next advice can use your observation.","done":false}));
    json!({"status":"success","engine":"rust-simulation-advice-v1","simulation_date":date,"tasks":output,"limitations":["Historical monthly context is not today's actual weather.","No wind-specific advice is triggered without a supplied dated wind value.","Heat triggers are disclosed simulation assumptions; recommendations are checks, not irrigation or chemical prescriptions."]})
}
