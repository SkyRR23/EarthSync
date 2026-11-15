"""Independent validation arithmetic, never imported by production code.

Equations: Allen et al. (1998), FAO Irrigation and Drainage Paper 56,
chapters 3/4. This computes reference-grass demand, not irrigation or ETc.
"""

import math
from datetime import date


def reference_et0(latitude, elevation, weather):
    def saturation(t):
        return 0.6108 * math.exp(17.27 * t / (237.3 + t))

    minimum, maximum = weather["tmin_c"], weather["tmax_c"]
    mean = (minimum + maximum) / 2
    actual_vapour = saturation(weather["dewpoint_c"])
    saturated_vapour = (saturation(minimum) + saturation(maximum)) / 2
    slope = 4098 * saturation(mean) / (237.3 + mean) ** 2
    psychrometric = 0.000665 * weather["pressure_kpa"]
    day = date(**weather["date"]).timetuple().tm_yday
    solar_angle = 2 * math.pi * day / 365
    declination = 0.409 * math.sin(solar_angle - 1.39)
    distance_factor = 1 + 0.033 * math.cos(solar_angle)
    radians = math.radians(latitude)
    sunset = math.acos(max(-1, min(1, -math.tan(radians) * math.tan(declination))))
    extraterrestrial = (
        (1440 / math.pi)
        * 0.0820
        * distance_factor
        * (
            sunset * math.sin(radians) * math.sin(declination)
            + math.cos(radians) * math.cos(declination) * math.sin(sunset)
        )
    )
    clear_sky = (0.75 + 2e-5 * elevation) * extraterrestrial
    ratio = min(1, weather["solar_mj_m2_day"] / clear_sky)
    net_shortwave = 0.77 * weather["solar_mj_m2_day"]
    net_longwave = (
        4.903e-9
        * ((maximum + 273.16) ** 4 + (minimum + 273.16) ** 4)
        / 2
        * (0.34 - 0.14 * math.sqrt(actual_vapour))
        * (1.35 * ratio - 0.35)
    )
    radiation_component = 0.408 * slope * (net_shortwave - net_longwave)
    aerodynamic_component = (
        psychrometric
        * 900
        / (mean + 273)
        * weather["wind_2m_m_s"]
        * (saturated_vapour - actual_vapour)
    )
    return (radiation_component + aerodynamic_component) / (
        slope + psychrometric * (1 + 0.34 * weather["wind_2m_m_s"])
    )


def metrics(pairs):
    if not pairs:
        return {"n": 0, "mae": None, "rmse": None, "bias": None}
    differences = [model - observed for model, observed in pairs]
    if any(not math.isfinite(d) for d in differences):
        raise ValueError("Nonfinite matched sample")
    return {
        "n": len(pairs),
        "mae": sum(map(abs, differences)) / len(pairs),
        "rmse": math.sqrt(sum(d * d for d in differences) / len(pairs)),
        "bias": sum(differences) / len(pairs),
    }


def match_observations(model, observed):
    """Only exact source-period/unit matches with declared independent QA pass.

    Import format is deliberately explicit. UTC station days, unverified soil
    training membership and depth/method mismatches never become accuracy pairs.
    """
    pairs, excluded = [], []
    seen = set()
    for row in observed:
        key = (
            row["site_id"],
            row["variable"],
            row["start"],
            row["end"],
            row["unit"],
            row["time_standard"],
        )
        if key in seen:
            raise ValueError("Duplicate reference observation")
        seen.add(key)
        if (
            row.get("quality") != "accepted"
            or row.get("independence") != "held_out_verified"
            or not row.get("source_url")
            or not row.get("license")
        ):
            excluded.append("QA_OR_INDEPENDENCE_UNVERIFIED")
            continue
        matches = [
            m
            for m in model
            if tuple(
                m[k]
                for k in [
                    "site_id",
                    "variable",
                    "start",
                    "end",
                    "unit",
                    "time_standard",
                ]
            )
            == key
        ]
        if len(matches) != 1:
            excluded.append("NO_EXACT_TIME_UNIT_SITE_MATCH")
            continue
        if row["variable"] == "ph" and any(
            row.get(k) is None or row.get(k) != matches[0].get(k)
            for k in ["top_cm", "bottom_cm", "measurement_method"]
        ):
            excluded.append("SOIL_DEPTH_OR_METHOD_MISMATCH")
            continue
        pairs.append((float(matches[0]["value"]), float(row["value"])))
    return metrics(pairs), excluded
