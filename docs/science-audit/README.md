# Milestone 7J: historical and scientific audit

The independent software/data audit is complete for the supplied archive and
pinned milestones. Scientific acceptance of farming advice is **not** complete
or claimed. Keep the PR draft; 7N owns integration and merge decisions.

Branch `fix/earthsync-science-audit-v1` starts at final 7H
`a7c33cc6b58703501bbba0ceba1bad1d6d42004b`. Other milestone pins are in
[the source manifest](evidence/source-manifest.json). No main FastAPI app,
Flutter router, central database integration or 7N branch was overwritten.

## Verified original archive

The supplied restore helpers were fully read before authorized execution. All
nine retry segment wrapper/payload hashes, restored part 03, all seven original
wrapper/payload pairs, and the complete original ZIP were verified.

Original size: **55,057,221 bytes**. Verified SHA-256:

`241cdcfac1df62b7608b403e8cbcb48d0b8ba9ca9fddc8cce766279016327788`

Original: `/workspace/shared/downloads/nasa_space_challenges.zip`, read-only.
Extracted originals: `/workspace/shared/earthsync-science-original/`, read-only.
[Integrity receipt](evidence/reassembly-verified.json). The earlier failure record
in `split-transfer.json` is superseded by this successful receipt.

All **743 members / 600 files** were read, CRC checked and SHA-256 inventoried.
The **487 generated build files** were rejected as a class and never executed.
All 113 non-build original files remain byte-identical. Fourteen Rust files,
two Python scripts, contract JSON/CSV data, metadata/logs, methods, citations,
tests and asset roles were inspected. Sixty environmental files match PR #11;
its README/API notes differ. New crop/raw/source artifacts were audited separately.

- [Current defects and fixes](DEFECTS.md)
- [Contributed historical findings and reproductions](ARCHIVE_FINDINGS.md)
- [All 20 requested historical/current decisions](ISSUE_MATRIX.md)
- [Crop source quality and acceptance limits](CROP_KNOWLEDGE.md)
- [Inventory and reuse/rejection matrix](SOURCES.md)
- [Tests, provider checks and limitations](VERIFICATION.md)
- [Precise 7N handoff](HANDOFF_7N.md)

The modern path has five focused repairs and one isolated 7I handoff patch.
The archived engine's original 13 tests pass, but 12 new desired-property
regressions fail against it. No old weighted engine was imported. All 12 Myanmar
profiles stay in research quarantine, with zero executable rules and
`recommendation_eligible=false`. Tests do not independently validate farming advice.
