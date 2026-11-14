# 7N verification

Work in progress: the combined implementation and initial verification are
reviewable. Final regression, browser, Android and CI receipts are being completed
on this draft branch. No release or public deployment is authorized by this report.

Already measured: backend 359 passed / 3 explicit live skips; Rust engine 111 and
FRB bridge 6 passed; catalog 39 passed / 32 subtests; a full Flutter run passed 108
with 3 explicit live skips before the additional farm-link widget test; live monthly
native/Web tests passed. A live daily repeat-cache failure was fixed and its
regression plus the previously failing live platform test now pass.

Final exact results, CI URLs, artifact hashes, browser stages and release gates
will replace this provisional report after the remaining checks finish.
