import copy

import pytest

from earthsync.environmental.common import SourceError
from earthsync.environmental.soil import PROPERTIES, read_soil

from .conftest import capture


def test_all_documented_conversions_and_provenance(query, soil_payload):
    evidence = read_soil(capture(soil_payload), query)
    means = {v.variable: v for v in evidence.values if v.statistic == "mean"}
    expected = {
        "phh2o": 6.3,
        "clay": 33.4,
        "sand": 20.1,
        "silt": 46.5,
        "soc": 12,
        "nitrogen": 2.74,
        "cec": 15.5,
        "bdod": 1.26,
    }
    assert {k: v.value for k, v in means.items()} == expected
    assert {k: v.unit for k, v in means.items()} == {
        k: p[2] for k, p in PROPERTIES.items()
    }
    assert evidence.quality.expected == evidence.quality.present == 32
    assert evidence.quality.uncertainty_status == "provider_quantiles"
    assert all(
        v.depth_cm == (0, 5) and not v.usable_for_analysis for v in evidence.values
    )
    assert evidence.source.release is None
    assert (
        evidence.retrieval.response_sha256
        == capture(soil_payload).retrieval.response_sha256
    )
    assert evidence.availability == "reference_only"
    assert not evidence.spatial_support.on_farm_measurement
    assert evidence.spatial_support.native_footprint is None
    assert evidence.temporal_support.valid_start is None


@pytest.mark.parametrize(
    "coordinates", [[96.2, 17.0], [16.87, 96.2], [0, 0], [96.2], [True, False]]
)
def test_spatial_mismatch(query, soil_payload, coordinates):
    soil_payload["geometry"]["coordinates"] = coordinates
    with pytest.raises(SourceError, match="SPATIAL_MISMATCH"):
        read_soil(capture(soil_payload), query)


@pytest.mark.parametrize(
    "field,value", [("mapped_units", "g/100g"), ("d_factor", 1000), ("d_factor", True)]
)
def test_unit_revision_fails_closed(query, soil_payload, field, value):
    soil_payload["properties"]["layers"][1]["unit_measure"][field] = value
    with pytest.raises(SourceError, match="UNIT_REVISION_MISMATCH"):
        read_soil(capture(soil_payload), query)


def test_layer_revision_and_duplicates(query, soil_payload):
    layers = soil_payload["properties"]["layers"]
    layers.append(copy.deepcopy(layers[0]))
    with pytest.raises(SourceError, match="SOURCE_REVISION_MISMATCH"):
        read_soil(capture(soil_payload), query)
    layers[-1]["name"] = "unverified_property"
    with pytest.raises(SourceError, match="SOURCE_REVISION_MISMATCH"):
        read_soil(capture(soil_payload), query)


def test_absent_property_null_and_zero_are_separate(query, soil_payload):
    layers = soil_payload["properties"]["layers"]
    layers.pop()
    layers[0]["depths"][0]["values"] = {"mean": None}
    layers[1]["depths"][0]["values"]["mean"] = 0
    result = read_soil(capture(soil_payload), query)
    means = {v.variable: v for v in result.values if v.statistic == "mean"}
    assert means["phh2o"].value is None and means["phh2o"].reason == "NULL_VALUE"
    assert means["bdod"].value is None and means["bdod"].reason == "ABSENT_VARIABLE"
    assert means["bdod"].original_unit is None
    assert means["clay"].value == 0 and means["clay"].quality == "present"
    assert result.availability == "partial"


def test_missing_depth_is_not_interpolated(query, soil_payload):
    query.soil_depths.append("15-30cm")
    result = read_soil(capture(soil_payload), query)
    deeper = [v for v in result.values if v.depth_cm == (15, 30)]
    assert len(deeper) == 32
    assert all(v.value is None and v.reason == "ABSENT_VARIABLE" for v in deeper)


def test_depth_metadata_mismatch(query, soil_payload):
    soil_payload["properties"]["layers"][0]["depths"][0]["range"]["bottom_depth"] = 15
    with pytest.raises(SourceError, match="DEPTH_MISMATCH"):
        read_soil(capture(soil_payload), query)


@pytest.mark.parametrize("raw", [-9999, "63", True, {}, 10**500])
def test_invalid_mean_stays_null(query, soil_payload, raw):
    soil_payload["properties"]["layers"][0]["depths"][0]["values"]["mean"] = raw
    value = read_soil(capture(soil_payload), query).values[0]
    assert value.value is None and value.quality == "rejected"


def test_missing_quantiles_and_inverted_interval(query, soil_payload):
    stats = soil_payload["properties"]["layers"][0]["depths"][0]["values"]
    stats.update({"Q0.05": 80, "Q0.5": 63, "Q0.95": 50})
    result = read_soil(capture(soil_payload), query)
    assert all(
        v.value is None and v.reason == "QUANTILE_ORDER" for v in result.values[1:4]
    )
    for layer in soil_payload["properties"]["layers"]:
        layer["depths"][0]["values"] = {"mean": None}
    result = read_soil(capture(soil_payload), query)
    assert result.availability == "unavailable"
    assert result.quality.uncertainty_status == "not_supplied"
    assert all(v.value is None for v in result.values)
