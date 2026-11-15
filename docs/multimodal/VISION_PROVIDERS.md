# Actual image-capable integrations

Official documentation checked 2026-11-15:

| Route | Verified capability / access | EarthSync setting |
|---|---|---|
| [Groq vision](https://console.groq.com/docs/vision) | Meta `meta-models/muse-spark-open` accepts images, limited preview; five images maximum. Preview account access required, no generally available free quota established. | `EARTHSYNC_VISION_PROVIDER=groq`, separate `EARTHSYNC_VISION_MODEL=meta-models/muse-spark-open`, backend `GROQ_API_KEY` |
| [OpenAI vision](https://developers.openai.com/api/docs/guides/images-vision) | `gpt-4.1-mini` accepts actual image input. Account/key and API billing authorization required; ChatGPT subscription is not an API allowance. | `EARTHSYNC_VISION_PROVIDER=openai`, model `gpt-4.1-mini` or pinned `gpt-4.1-mini-2025-04-14`, backend `OPENAI_API_KEY` |

Groq's current vision guide lists Qwen 3.8 and Meta preview. Qwen is excluded from
this implementation to respect the user's preference. [Groq deprecations](https://console.groq.com/docs/deprecations)
retires Scout on 2026-07-17. Historical Scout examples/model pages are not current
access evidence. `openai/gpt-oss-20b` is not accepted as an image model.
[Groq limits](https://console.groq.com/docs/rate-limits) are account/model-specific;
Meta preview has no general free quota promised here. Do not silently change model,
use another account, enable a paid plan or fall back to another provider.

EarthSync sends exactly one private, sanitized PNG as a base64 image input to the
fixed official HTTPS Chat Completions endpoint. Its own limits are 10 MiB of PNG,
2,400 output tokens and 64,000 response bytes; no remote image URL is created.
OpenAI uses automatic image detail; documented sizing for this model includes a
2,048-pixel dimension limit. Provider-side resizing can hide small symptoms/text.
Provider limits and account availability may change: validate before rollout.

`EARTHSYNC_VISION_ENABLED=1` explicitly enables a configured backend adapter;
`EARTHSYNC_VISION_TIMEOUT_SECONDS` defaults to 20 (accepted 1–30 seconds).
Missing/invalid settings leave vision unavailable and the app working. Leave
`EARTHSYNC_VISION_ENABLED=0` for the authorized delivery in this chat. Keys belong
in the server process environment or a secret manager, never Flutter definitions,
source files, API responses, Firebase assets, request URLs or chat.

Each request also requires explicit image consent. Image pixels can contain
personal text despite EXIF stripping. No farmer context, coordinates, stored
records, retrieved passages or OCR text are sent to the vision adapter. The image
itself remains untrusted. There are no model tools, arbitrary URLs or file reads.
No redirects or retries occur. Timeout, network, authentication, access, rate,
truncated/oversized/malformed output and schema failures return minimized status.
The overall research admission deadline remains 45 seconds; a slow combined OCR
and AI request can exceed the client deadline. Refresh saved reports before any
retry; mutations are never replayed automatically.

Verification is offline using `httpx.MockTransport` around the **actual adapter**;
tests inspect encoded image bytes, model, host and request shape. No live call has
been made, by user choice. Provider wire compatibility is supported by official
contracts and mocked tests, not a claimed successful account-specific inference.
