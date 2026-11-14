//! Complete-calendar-year summaries only; no crop or forecast interpretation.

use crate::{EngineError, EnvironmentalContext};

pub(crate) fn summarize(
    climate: &EnvironmentalContext,
) -> Result<(Option<f64>, Option<f64>), EngineError> {
    let rain = &climate.monthly_rainfall_mm;
    let temps = &climate.monthly_mean_temp_c;
    if rain.len() != 12 || temps.len() != 12 {
        return Err(EngineError::InvalidMonthlyLength);
    }
    // Check every supplied value, even when another month is missing.
    if rain.iter().flatten().any(|v| !v.is_finite() || *v < 0.0)
        || temps.iter().flatten().any(|v| !v.is_finite())
    {
        return Err(EngineError::InvalidClimateValue);
    }
    let rainfall = rain
        .iter()
        .all(Option::is_some)
        .then(|| rain.iter().flatten().sum::<f64>());
    let temperature = temps.iter().all(Option::is_some).then(|| {
        // Normalize before summing so finite inputs cannot overflow the
        // intermediate sum. This is still an unweighted monthly mean.
        let scale = temps.iter().flatten().map(|v| v.abs()).fold(0.0, f64::max);
        if scale == 0.0 {
            0.0
        } else {
            (temps.iter().flatten().map(|v| v / scale).sum::<f64>() / 12.0) * scale
        }
    });
    // serde_json encodes nonfinite floats as null: do not confuse overflow
    // with legitimately missing observations at the JSON boundary.
    if rainfall
        .into_iter()
        .chain(temperature)
        .any(|v| !v.is_finite())
    {
        return Err(EngineError::InvalidClimateValue);
    }
    Ok((rainfall, temperature))
}
