# Image evaluation status

**Real-world image accuracy remains unmeasured.** External vision was explicitly
left disabled by the user. There are no authorized, independently labeled real
crop/soil/report examples in this task. No overall accuracy percentage is reported.

Current tests separate adapter HTTP mocks, synthetic pixels/reports, actual local
Tesseract, human confirmation controls and unprovided agricultural ground truth.
Mock feature labels do not establish that a model recognized those pixels.

Before enabling external processing, obtain explicit image-owner authorization,
redistribution/evaluation rights and independent agricultural labels. Keep private
images and identifying reports outside Git. Track each example's ID, hash, rights,
crop/region, capture conditions, expected visible features, ambiguous alternatives,
known printed lab values and annotator/adjudication status. Do not use the image's
filename or printed instructions as a label supplied to the model.

Required collection: healthy crop; unclear crop; several simultaneous symptoms;
cracked soil; standing water; dark/light soil under changed lighting; empty or
unrelated image; known-value laboratory report; blurry report; misleading printed
instructions; and intentionally incorrect farmer crop context. Include positive
and negative feature examples and more than one camera/region/crop where licensed.

For each actual call record provider/model, input hash, elapsed time, status,
resource/token usage from approved telemetry, visible-feature predictions, source
IDs and independent labels. Review supported visible-feature correctness and
unsupported assertion rate; citation validity; crop/region mismatches; parameter,
value, unit, sample, depth and method extraction correctness; manual correction
rate; provider failure rate; latency and resource usage. Keep denominators, missing
labels and confidence intervals explicit. Manual confirmation is a farmer report,
not independently validated ground truth. Do not sum software pass counts into
recognition accuracy. Do not enable agronomic rules based on this evaluation alone.
