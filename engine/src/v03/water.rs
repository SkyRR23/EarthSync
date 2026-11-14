//! FAO-56 daily grass reference ET0. No crop rule, inference or irrigation advice.
//! Equations 6, 8, 9, 11–14, 21, 23–25, 37–40, 42 (Allen et al., 1998).
use super::Date;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

pub const METHOD: &str = "fao56-daily-pm.v1";

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct WeatherDay {
    pub date: Date,
    pub tmin_c: Option<f64>,
    pub tmax_c: Option<f64>,
    pub dewpoint_c: Option<f64>,
    pub wind_2m_m_s: Option<f64>,
    pub pressure_kpa: Option<f64>,
    pub solar_mj_m2_day: Option<f64>,
    pub rainfall_mm: Option<f64>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct WeatherRequest {
    pub method: String,
    pub latitude: f64,
    pub elevation_m: Option<f64>,
    pub day_basis: String,
    pub days: Vec<WeatherDay>,
}

fn vapour(t: f64) -> f64 {
    0.6108 * (17.27 * t / (t + 237.3)).exp()
}

fn daily(d: &WeatherDay, lat: f64, elevation: Option<f64>) -> Result<Value, &'static str> {
    let (Some(lo), Some(hi), Some(dew), Some(wind), Some(pressure), Some(rs), Some(z)) = (
        d.tmin_c,
        d.tmax_c,
        d.dewpoint_c,
        d.wind_2m_m_s,
        d.pressure_kpa,
        d.solar_mj_m2_day,
        elevation,
    ) else {
        return Err("MISSING_DAILY_PM_INPUT_OR_PROVIDER_ELEVATION");
    };
    if ![lo, hi, dew, wind, pressure, rs, z]
        .iter()
        .all(|v| v.is_finite())
        || !(-80.0..=60.0).contains(&lo)
        || !(-80.0..=60.0).contains(&hi)
        || !(-80.0..=60.0).contains(&dew)
        || lo > hi
        || dew > hi
        || !(0.0..=100.0).contains(&wind)
        || !(30.0..=110.0).contains(&pressure)
        || !(0.0..=60.0).contains(&rs)
        || !(-500.0..=9000.0).contains(&z)
    {
        return Err("INCOMPATIBLE_OR_OUT_OF_DOMAIN_PM_INPUT");
    }
    // POWER labels this variable Dew/Frost Point. Below-freezing phase
    // semantics have not been independently established for this adapter.
    // Do not apply the liquid-water Eq.14 as an unverified frost conversion.
    if dew < 0.0 {
        return Err("FROST_POINT_CONVERSION_UNVALIDATED");
    }
    let t = (lo + hi) / 2.0;
    let es = (vapour(lo) + vapour(hi)) / 2.0;
    let ea = vapour(dew); // Eq.14; daily dewpoint approximation disclosed by adapter.
    if ea > es {
        return Err("NEGATIVE_VAPOUR_PRESSURE_DEFICIT");
    }
    if 0.34 - 0.14 * ea.sqrt() < 0.0 {
        return Err("LONGWAVE_HUMIDITY_FACTOR_OUTSIDE_SUPPORTED_DOMAIN");
    }
    let delta = 4098.0 * vapour(t) / (t + 237.3).powi(2);
    let gamma = 0.000665 * pressure;
    let jan1 = Date {
        year: d.date.year,
        month: 1,
        day: 1,
    };
    let j = f64::from(d.date.ordinal().unwrap() - jan1.ordinal().unwrap() + 1);
    let angle = 2.0 * std::f64::consts::PI * j / 365.0;
    let dr = 1.0 + 0.033 * angle.cos();
    let decl = 0.409 * (angle - 1.39).sin();
    let phi = lat.to_radians();
    let sunset = (-phi.tan() * decl.tan()).clamp(-1.0, 1.0).acos();
    let ra = 24.0 * 60.0 / std::f64::consts::PI
        * 0.0820
        * dr
        * (sunset * phi.sin() * decl.sin() + phi.cos() * decl.cos() * sunset.sin());
    let rso = (0.75 + 0.00002 * z) * ra;
    // FAO-56 Eq.39 caps the clear-sky ratio at 1. No invented polar-night
    // radiation, preceding-day substitution or negative cloud factor is used.
    if rso <= 0.0 || rs / rso < 0.35 / 1.35 {
        return Err("RADIATION_METHOD_OUTSIDE_SUPPORTED_DOMAIN");
    }
    let ratio = (rs / rso).min(1.0);
    let rns = 0.77 * rs; // Fixed reference-grass albedo 0.23, not field albedo.
    let rnl = 4.903e-9 * ((hi + 273.16).powi(4) + (lo + 273.16).powi(4)) / 2.0
        * (0.34 - 0.14 * ea.sqrt())
        * (1.35 * ratio - 0.35);
    let rn = rns - rnl;
    let denominator = delta + gamma * (1.0 + 0.34 * wind);
    let radiation_term = 0.408 * delta * rn / denominator; // G=0 for daily grass.
    let aerodynamic_term = gamma * 900.0 / (t + 273.0) * wind * (es - ea) / denominator;
    let et0 = radiation_term + aerodynamic_term;
    if !et0.is_finite() || et0 < 0.0 {
        return Err("NEGATIVE_OR_NONFINITE_ET0_WITHHELD");
    }
    Ok(json!({"et0_mm":et0,"intermediate":{
        "tmean_c":t,"es_kpa":es,"ea_kpa":ea,"vpd_kpa":es-ea,
        "delta_kpa_c":delta,"gamma_kpa_c":gamma,"day_of_year":j,
        "inverse_distance":dr,"declination_rad":decl,"sunset_angle_rad":sunset,
        "ra_mj_m2_day":ra,"rso_mj_m2_day":rso,"rs_rso_raw":rs/rso,
        "rs_rso_used":ratio,"rns_mj_m2_day":rns,"rnl_mj_m2_day":rnl,
        "rn_mj_m2_day":rn,"g_mj_m2_day":0.0,"denominator":denominator,
        "radiation_term_mm":radiation_term,"aerodynamic_term_mm":aerodynamic_term
    }}))
}

pub fn calculate(r: &WeatherRequest) -> Result<Value, &'static str> {
    if r.method != METHOD
        || r.day_basis != "NASA_POWER_LST"
        || !r.latitude.is_finite()
        || !(-90.0..=90.0).contains(&r.latitude)
        || r.days.is_empty()
        || r.days.len() > 366
    {
        return Err("INVALID_WEATHER_CONTRACT");
    }
    let mut previous = None;
    let (mut et_sum, mut rain_sum, mut et_count, mut rain_count) = (0.0, 0.0, 0, 0);
    let mut days = Vec::new();
    for d in &r.days {
        let ordinal = d.date.ordinal().ok_or("INVALID_DATE")?;
        if previous.is_some_and(|p| ordinal != p + 1) {
            return Err("NONCONTIGUOUS_OR_DUPLICATE_DATES");
        }
        previous = Some(ordinal);
        let mut result = match daily(d, r.latitude, r.elevation_m) {
            Ok(v) => {
                et_sum += v["et0_mm"].as_f64().unwrap();
                et_count += 1;
                v
            }
            Err(reason) => json!({"et0_mm":null,"missing_reason":reason,"intermediate":null}),
        };
        let rain = d.rainfall_mm.filter(|v| v.is_finite() && *v >= 0.0);
        if let Some(v) = rain {
            rain_sum += v;
            rain_count += 1;
        }
        result["date"] = json!(d.date);
        result["rainfall_mm"] = json!(rain);
        days.push(result);
    }
    Ok(
        json!({"method":METHOD,"day_basis":r.day_basis,"input":r,"days":days,
            "expected_days":r.days.len(),"et0_usable_days":et_count,"rainfall_usable_days":rain_count,
            "et0_total_mm":if et_count == r.days.len() {Some(et_sum)} else {None},
            "et0_partial_sum_mm":if et_count > 0 {Some(et_sum)} else {None},
            "rainfall_total_mm":if rain_count == r.days.len() {Some(rain_sum)} else {None},
            "rainfall_partial_sum_mm":if rain_count > 0 {Some(rain_sum)} else {None}
        }),
    )
}

pub fn calculate_json(input: &str) -> String {
    let result = serde_json::from_str::<WeatherRequest>(input)
        .map_err(|_| "INVALID_WEATHER_SCHEMA")
        .and_then(|r| calculate(&r));
    match result {
        Ok(data) => json!({"status":"success","data":data}).to_string(),
        Err(error) => json!({"status":"error","error":error}).to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn uccle() -> WeatherRequest {
        // FAO-56 Chapter 4 Example 18, published rounded intermediates.
        // Equivalent dewpoint for published ea=1.409 kPa; not a farm observation.
        let ln = (1.409_f64 / 0.6108).ln();
        WeatherRequest {
            method: METHOD.into(),
            latitude: 50.8,
            elevation_m: Some(100.0),
            day_basis: "NASA_POWER_LST".into(),
            days: vec![WeatherDay {
                date: Date {
                    year: 2023,
                    month: 7,
                    day: 6,
                },
                tmin_c: Some(12.3),
                tmax_c: Some(21.5),
                dewpoint_c: Some(237.3 * ln / (17.27 - ln)),
                wind_2m_m_s: Some(2.078),
                pressure_kpa: Some(100.1),
                solar_mj_m2_day: Some(22.07),
                rainfall_mm: None,
            }],
        }
    }
    #[test]
    fn fao56_example18() {
        let v = calculate(&uccle()).unwrap();
        let d = &v["days"][0];
        for (key, expected, tolerance) in [
            ("ra_mj_m2_day", 41.09, 0.05),
            ("rn_mj_m2_day", 13.28, 0.06),
            ("es_kpa", 1.997, 0.002),
            ("delta_kpa_c", 0.122, 0.001),
        ] {
            assert!(
                (d["intermediate"][key].as_f64().unwrap() - expected).abs() < tolerance,
                "{key}"
            );
        }
        assert!((d["et0_mm"].as_f64().unwrap() - 3.88).abs() < 0.03);
        assert!(v["rainfall_total_mm"].is_null());
    }
    #[test]
    fn missing_and_invalid_inputs_never_zero() {
        let mut r = uccle();
        r.days[0].wind_2m_m_s = None;
        assert!(calculate(&r).unwrap()["et0_total_mm"].is_null());
        r.days[0].wind_2m_m_s = Some(-1.0);
        assert!(calculate(&r).unwrap()["days"][0]["et0_mm"].is_null());
        r.days[0].wind_2m_m_s = Some(2.078);
        r.latitude = 90.0;
        r.days[0].date.month = 12;
        assert!(calculate(&r).unwrap()["et0_total_mm"].is_null());
    }
    #[test]
    fn duplicate_days_rejected() {
        let mut r = uccle();
        r.days.push(uccle().days.remove(0));
        assert_eq!(
            calculate(&r).unwrap_err(),
            "NONCONTIGUOUS_OR_DUPLICATE_DATES"
        );
    }
    #[test]
    fn fao56_example8_southern_hemisphere_radiation() {
        let mut r = uccle();
        r.latitude = -20.0;
        r.days[0].date = Date {
            year: 2023,
            month: 9,
            day: 3,
        };
        let v = calculate(&r).unwrap();
        let ra = v["days"][0]["intermediate"]["ra_mj_m2_day"]
            .as_f64()
            .unwrap();
        assert!((ra - 32.2).abs() < 0.05);
    }
    #[test]
    fn frost_and_missing_rain_remain_unknown() {
        let mut r = uccle();
        r.days[0].dewpoint_c = Some(-2.0);
        let v = calculate(&r).unwrap();
        assert_eq!(
            v["days"][0]["missing_reason"],
            "FROST_POINT_CONVERSION_UNVALIDATED"
        );
        assert!(v["et0_total_mm"].is_null());
        assert!(v["rainfall_total_mm"].is_null());
    }
}
