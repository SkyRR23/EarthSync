# EarthSync 7V crop rule candidates v1.0.0

Independent scientific desk review of 7P PR #25 at
`940a8aad62da8b188cdd3af4d200f353d907997a`, informed by completed 7J PR #22
at `7b27699f13c94461a9d3d6596c47debfcfb9fed6`. English is authoritative.
Global species evidence comes first; regional evidence retains its original scope.

**60 candidate dossiers, zero approved executable rules.** Rice, maize, mung bean,
sesame and groundnut each have 12 reviewed domains. These are research candidates
for future Rust v0.3 constraints, not Rust `Rule` objects or crop recommendations.
The package also accounts for all 1,950 parameter mappings in 75 existing profiles.
Coverage of an inherited mapping is not a claim of fresh scientific source review.

The separate sidecar avoids changing 7P's evidence, live catalogs or runtime. It
has no adapter that exports agricultural rules. Every `proposed_requirement` is
null; executable lists stay empty and eligibility/approval flags stay false.
Validation rejects promotion even after all software tests pass.

| Artifact | Purpose |
| --- | --- |
| `package.json` / `package.schema.json` | Versioned candidate dossiers, strict schema, five separate review dimensions |
| `review.json` | Authored domain decisions, per-crop contradictions, explicitly rechecked upstream claim IDs |
| `facts.json` | 27 bounded source facts: original section/table/row, value, statistic, units, cultivar unknowns, geographic/system scope and limitations |
| `sources.json` / `source-receipts.json` | Original FAO authorities, versions/dates/rights, seven successful fresh retrievals with response-byte SHA-256 and exact request/completion times |
| `upstream-evidence.json` | Exact unchanged copies of 164 relevant 7P claims, 13 source records and 73 profile contexts; each tied to the base SHA |
| `traceability.jsonl` | All 1,950 source-claim → profile/parameter → candidate/blocked mappings; nonpriority inherited scope is explicit |
| `blocked-rules.json` | Candidate target condition, block reason, contradictions and evidence needed for acceptance |
| `EVIDENCE_MATRIX.md` | Accepted factual/numerical evidence versus blocked execution for every candidate |
| `input-pins.json` / `integrity.json` | Base input hashes and deterministic package-byte hashes; integrity is not scientific approval |
| `tests/` | Negative acceptance tests, published numerical checks and actual unchanged Rust arithmetic with synthetic ETo |

The upstream source-claim graph remains authoritative for retained facts. Profile
parameter links resolve into the pinned `data/crop-knowledge/v2/catalog.json`;
claims/source details are also available in this package's evidence sidecar.
Do not combine the regions, systems or cultivars of different linked claims into
one applicability envelope. Different profiles are alternatives for review.

## Status meanings

| Dimension | Meaning |
| --- | --- |
| Source fact verified | A bounded transcription/claim was checked against an original institutional source, including retained original bytes where present. This does not verify the underlying experiment, applicability or agricultural truth. Partial/not-rechecked evidence is explicitly distinguished. |
| Method numerically verified | FAO-56 equations 56/58 and 66 and Example 28 arithmetic were reproduced; synthetic constant ETo was tested against unchanged Rust. This does not verify a local Kc curve, ETo provider or water balance. |
| Applicable rule independently reviewed | Acceptance of a particular executable constraint for a crop/cultivar, place, system, statistic and period. **False for every candidate.** The independent desk review is complete with execution blocked. |
| Needs agronomist/field validation | Outstanding crop-specific applicability and exposure validation. True for every candidate; no credentialed agronomist or trial reviewer was supplied. |
| Unsupported | No linked source fact supports the proposed domain in the reviewed package. Missing evidence remains null, rather than a guessed threshold. Evidence in a neighboring domain does not make a rule executable. |

`method_numerically_verified` is true only on the five Kc dossiers, referring to
the common method demonstration, not to independent validation of those crops.
The 7V reviewer is an independent Codex desk-review session relative to 7P, not
an independent human agronomist. No agricultural safety certification is claimed.

## Reproduce offline

From the repository root, Python 3.12+ and the existing pinned 7P requirements:

```sh
python -m pip install -r data/crop-knowledge/v2/requirements.txt
python data/crop-rule-candidates/v1/tools/package.py --check
cargo build --locked --manifest-path engine/Cargo.toml --example v03_demo
python -m unittest discover -s data/crop-rule-candidates/v1/tests -v
```

`--check` is read-only and verifies original inputs, the complete upstream graph,
strict schemas, review boundaries and deterministic outputs. Without `--check`,
the tool regenerates outputs from authored review inputs after checking base
pins. Review inputs must be reviewed as data changes; hashing is not approval.
Native tests fail if the executable is absent; they never silently skip. Set
`EARTHSYNC_V03_BIN` only to a source-built executable of the pinned engine.

Full FAO documents and API bodies fetched by 7V are deliberately not redistributed.
Only selected facts, short quotes and original-body receipts are committed.
Existing 7P original files retain their established rights. Calendar bulk rights
remain unresolved; no imagery/logos are copied. The source-comparison receipt
records the 55 exact calendar-session matches and 28 ecological claim matches.
Fresh body hashes allow comparison after refetching; they do not make unavailable
full text reproducible offline. Offline tests verify stored evidence/contracts.

Read the [scientific review](../../../docs/integration/7v/SCIENTIFIC_REVIEW.md),
[validation receipts](../../../docs/integration/7v/VERIFICATION.md), and
[7W handoff](../../../docs/integration/7v/HANDOFF_7W.md).
