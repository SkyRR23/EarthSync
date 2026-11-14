# 7V → 7W integration handoff

Base 7P #25: `940a8aad62da8b188cdd3af4d200f353d907997a`.
Branch: `science/earthsync-crop-rule-validation-v1`.
Independent worktree: `/workspace/EarthSync-7V`. The draft PR records the exact
delivery SHA. No other worktree, existing profile or runtime algorithm was changed.
The draft is stacked against 7P's `data/earthsync-crop-evidence-v1` branch so its
diff contains only 7V additions; it does not merge or retarget 7P.

Use `data/crop-rule-candidates/v1/` as an offline review sidecar. It is **not** a
Rust catalog. All 60 candidates have null executable requirements, no eligibility
and no independent applicability approval. Keep 7P's existing identity-only v0.3
export unchanged; retain empty rules, reference review and false candidate flags.
Neither unit-test success nor `source_fact: verified` authorizes promotion.

Entry points:

- `package.json`: candidate → profile/parameter, claim IDs, new fact IDs and
  specific outstanding evidence. Exact claim/source/profile context is in
  `upstream-evidence.json`; new original-source facts are in `facts.json`.
- `traceability.jsonl`: all 1,950 existing mappings remain blocked; nonpriority
  inherited scope is explicitly marked. `blocked-rules.json` and
  `EVIDENCE_MATRIX.md` give the human/machine acceptance decisions.
- Run `python data/crop-rule-candidates/v1/tools/package.py --check` with the
  pinned 7P Python requirements. For native test commands and receipts, see
  `VERIFICATION.md`. Base input drift intentionally fails closed and needs review.

Integration concerns: FAO-56 development/late stages are linear; four constant
Rust stages would alter the method. A synthetic daily interval encoding works
numerically with unchanged Rust, but no local crop curve is approved. The FAO
HTML sesame Table 11 row totals 110 by stage sum versus stated 100: retain the
disagreement and block conversion. Do not reconcile maize/sweet-corn or
mung/Penauk identities, transfer paddy Kc to upland rice, use annual ecological
rainfall as seasonal rain, or infer fallow from a gap.

Next acceptance requires original evidence, exact crop/cultivar and geography/
system applicability, matching statistics/units/date/depth conventions, resolved
contradictions and an explicit independent agronomist/field validation record.
The v1 schema intentionally rejects all executable promotion. Any future enabled
rule needs a separately reviewed version and integration decision. Keep the PR
draft; no automatic merge, deployment or notification to another chat is performed.
