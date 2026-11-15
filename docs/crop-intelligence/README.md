# Crop Intelligence and Soil Research v1

Independent workstream based on PR #29, exact combined source
`660b479c3ffb714cd1d489e1241c026ceae6ed67`. GitHub PRs #26/#28/#29/#30 and
their current heads were inspected before editing on 2026-11-15.
Branch: `feat/earthsync-crop-intelligence-rag-v1`.

The Crops reference cards now include **Crop intelligence**: ask about a crop,
retrieve cited claims, filter exact documented region/cultivar scope, inspect
contradictions, identify missing field inputs and read the blocked rule dossiers.
Select up to four existing reference cards for comparison; no scores or ranking.
The farm photo screen offers separate **Ordinary soil photo** and **Laboratory
report** workflows. Original OCR and user corrections remain separate.

| Capability | Actual status |
|---|---|
| Reference retrieval | Deterministic SQLite FTS5; 708 identities, 965 claims, 48 source metadata records |
| Agricultural approval | Zero executable rules; all 60 candidates remain blocked |
| Soil photos | Existing bounded sanitizer and private farm storage reused |
| Vision | Unavailable by default; strict optional adapter contract, mocked boundary tests only |
| Lab extraction | Local Tesseract when installed; conservative single-sample parser; explicit user correction/confirmation |
| Separate teammate API | Scoped, revocable, expiring credentials; dedicated private SQLite store; tested on loopback |
| Hosted teammate integration | Pending URL, approved host, TLS and explicit deployment authorization |
| External LLM | None configured or called; extractive integration contract only |

The existing Rust engine, NASA/SoilGrids ingestion and historical/realtime/Groq
branches are unchanged. One additive local migration stores report transcriptions;
no farmer records are migrated between workstreams. No merge or public deployment.

Start with [TEAMMATE_API.md](TEAMMATE_API.md), [WINDOWS_TESTING.md](WINDOWS_TESTING.md)
and [VERIFICATION.md](VERIFICATION.md). Scientific review is separate from passing
software tests: [SCIENTIFIC_RULE_STATUS.md](SCIENTIFIC_RULE_STATUS.md).

## Explicit product answers

1. **What can the app explain about a crop?** Verified identity/aliases, original
   ecological characteristics, regional calendar references, scoped water/soil
   facts, source conflicts, limitations, missing inputs and required review.
   Many catalog species have identity only; unavailable characteristics stay unknown.
2. **What does farm evidence establish?** What each saved source reports at its
   original date, depth, method and spatial support. It can expose missing or
   incomparable evidence. It does not establish field suitability, irrigation
   needs, fertilizer doses, yield or profit.
3. **What can a soil photo reveal?** With a verified vision adapter, limited visible
   features such as possible cracking or standing water, always unverified.
   Without one, analysis is unavailable. A photo cannot measure pH, NPK, salinity,
   CEC, carbon, moisture percentage, laboratory texture or crop suitability.
4. **Can a lab report supply measurements?** It can supply a transcription of values
   actually reported for that sample, after checking/correction/confirmation.
   Software does not authenticate the laboratory or extrapolate the sample to a field.
5. **Why remain blocked?** The eight scientific gates are unmet: cultivar, local
   applicability, compatible statistics/depth/method, contradictions, field validation
   and independent qualified review remain outstanding.
6. **Can the teammate test images securely?** Yes in the implemented dedicated test
   API with a scoped test key and exact farm grant. Hosted compatibility is untested.
7. **What remains before recommending a crop?** Representative local inputs and
   separately versioned executable rules with original-source traceability,
   compatible measurements, contradiction review, field validation and documented
   independent applicability approval. No endpoint in this package promotes rules.
