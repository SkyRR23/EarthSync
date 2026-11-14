# Milestone 7J: historical and scientific audit

Status: **repository repairs verified; contributed archive audit BLOCKED**.
This is an independent draft on `fix/earthsync-science-audit-v1`, based on final
7H `a7c33cc6b58703501bbba0ceba1bad1d6d42004b`. No merge into 7N is authorized.

The attachment `nasa_space_challenges.zip` could not be transferred: the downloader
rejects attachments above 32 MiB. The subsequently supplied release URL was the
literal placeholder `[PASTE ACTUAL GITHUB ASSET URL]`; the EarthSync releases API
returned an empty list. Six of seven subsequently supplied split wrappers and
their chunks match the supplied manifest. Part 03 still fails transfer with the
32 MiB error, although the manifest expects an 8,388,772-byte wrapper. The six
verified wrappers are preserved read-only under
`/workspace/shared/downloads/nasa_space_challenges_parts/`.
The user-supplied **expected**, not verified, original SHA-256 is
`241cdcfac1df62b7608b403e8cbcb48d0b8ba9ca9fddc8cce766279016327788`.
The split manifest/helper source were read and the available chunks hashed;
the original archive's content has not been opened, executed, accepted or imported.
Its Myanmar profiles, Rust/Python code, binaries, raw provider bodies and assets
remain unreviewed. Do not confuse the older PR #11 inventory with this archive.
Per the user's integrity gate, full archive audit resumes only after SHA-256
verification succeeds. A mismatch must stop archive processing.

The available PR #11 archive was independently inventoried before that gate was
supplied. All 62 original file members were read and hashed without extraction
or execution; see [inventory](evidence/pr11-inventory.json). This establishes
byte identity with PR #11, not identity with the new archive or scientific truth.

- [Confirmed current defects and reproduction](DEFECTS.md)
- [Historical versus current issue matrix](ISSUE_MATRIX.md)
- [Crop knowledge quality and original-source checks](CROP_KNOWLEDGE.md)
- [Inventory and reuse/rejection decisions](SOURCES.md)
- [Verification and limitations](VERIFICATION.md)
- [Precise 7N handoff](HANDOFF_7N.md)

No recommendation eligibility flag, production crop threshold, score, financial
estimate, irrigation credit or nitrogen/pest benefit was introduced. Passing
software tests does not independently validate farming advice.
