# EarthSync image evidence assistant

Additive extension of PR #34 at `64ee5c625cbeb8ecf66d7ef2e4377f9a28c10448`.
Branch: `feat/earthsync-multimodal-rag-v1`. No changes to other workstreams or main.
PR #34 and PR #29 heads were rechecked on 2026-11-15; all five and eleven
respectively triggered workflows at those heads had succeeded.

The existing farmer photo/report panel now supports Crop / Leaf, Soil Appearance
and Soil Laboratory Report. Choose a camera/gallery image, inspect its sanitized
preview and press Analyze. Crop identity, symptoms, growth stage and weather are
explicitly farmer-provided. Appearance findings remain unverified. Saving history
requires a separate date and personally written observation. Core workflow labels
have Burmese translations; scientific prose and many detailed controls remain
English pending language/agricultural review.

External vision stays **disabled**, as explicitly selected by the user in this
chat. Actual adapters are implemented for image input to OpenAI and Groq Meta
preview. No live inference or real-world recognition accuracy is claimed.
Local OCR, manual corrections, deterministic crop comparison and saved evidence
remain usable without external vision. A new image-kind request returns
`vision_unavailable`, never fabricated analysis.

Read [providers](VISION_PROVIDERS.md), [pipeline](IMAGE_RAG_PIPELINE.md),
[crop limitations](CROP_IMAGE_ANALYSIS.md), [soil limitations](SOIL_IMAGE_LIMITATIONS.md),
[evaluation](IMAGE_EVALUATION.md), [API/startup](TEAMMATE_API.md),
[verification](VERIFICATION.md), [source rights](SOURCES_AND_RIGHTS.md) and
[human actions](USER_ACTIONS_REQUIRED.md).
