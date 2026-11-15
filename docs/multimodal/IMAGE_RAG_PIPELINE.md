# Pipeline and deterministic policy

1. Existing owned photo APIs decode bounded JPEG/PNG, strip metadata and re-encode
   private PNG pixels. Images are never static/public assets.
2. Authorize farm and operation before reading pixels. Require external consent
   before calling a configured image provider. Default provider is unavailable.
3. Strict Pydantic schemas reject unexpected fields. The model classifies image
   kind and returns only enumerated visible/uncertain features and limitations.
   It cannot supply species, chemistry, causes, treatment, probabilities or URLs.
4. Farmer-provided crop context resolves through the **existing** crop catalog.
   No image species guess overrides it. Identity remains unverified. Only visible
   findings from a non-inconclusive image select explanation evidence.
5. The existing SQLite connection has a separate `plant_health` FTS5 collection,
   loaded from a small vetted local dossier. It is not another database. Crop,
   image kind, actual feature intersection and optional exact documented region
   filter every hit. Question text cannot manufacture absent symptom evidence.
   The original 965-claim crop corpus and its hash remain independent and unchanged.
6. Exact dossier claims, citations, alternative possibilities and safe observation
   questions form the explanation. No second generative model invents synthesis.
   The original crop-reference packet is separate from symptom references.
7. A deterministic gate compares returned claims, source metadata, citations and
   explanations against retrieved immutable records. It fixes eligibility false,
   empty measurements/rules, null ranking and human confirmation false. Unsupported
   schema fields are rejected before synthesis; changed references fail closed.
8. The farmer sees possible explanations to investigate, not a diagnosis. Unknown
   crop, region mismatch, unsupported features, uncertain findings and unclear or
   unrelated images produce no inferred cause. All 60 agronomic candidates stay blocked.

For the local app only, owned saved SoilGrids jobs, other source jobs, evidence
records (including saved NASA records), farmer reports and lab transcriptions
retain distinct provenance and original timestamps. Regional grids are not station
or field observations and are not automatically considered contemporaneous.
No verified station measurements are supplied by this workflow. Saved context is
returned separately; it is neither sent to vision nor used to assert a visual cause.
The separate research tenant has no farmer database linkage and returns an explicit
unavailable context rather than fetching another user's records.

Images, user context, printed instructions, OCR and reference text are data. They
never execute code, provision credentials, approve rules, call arbitrary URLs,
write model findings to history or bypass ownership. Corpus hashes identify the
local reference snapshots, not an independent agronomic applicability approval.
