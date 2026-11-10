# Architecture Decision Record index

Do not delete or rewrite adopted decisions silently. For each material change add a new ADR superseding prior one and update Windows Portability Ledger in same PR.

## ADR-0001 — Stage platforms iPadOS/macOS/Android before Windows
- Date: 2026-11-10
- Status: PROPOSED
- Context: Tablet capture and on-device translation require substantial hardware qualification. Windows is desired later, not within initial shipping releases.
- Decision: Build and release iPadOS, macOS, Android tablet first; keep adapters/serialized contracts platform-agnostic and maintain Windows ledger.
- Alternatives: all-four-platform launch; Apple-only launch.
- Consequences: avoids Windows execution workload initially; adds documentation and build-contract maintenance.
- Review gate: R0, architecture owner.

## ADR-0002 — Offline-first AI and opt-in cloud BYOK
- Date: 2026-11-10
- Status: PROPOSED
- Context: Avoid paying recurring cloud tokens centrally; support private/offline use after model installation.
- Decision: local OCR+local MT/LLM by default; cloud disabled unless user explicitly opts in, using secure key storage and approved provider auth path.
- Alternatives: cloud-first; server-mediated paid subscription.
- Consequences: device-specific inference benchmarking, model licensing/download complexity; optional BYOK provider policy review.
- Windows portability: shared TranslationProvider interface and native secret store adapter.

## ADR-0003 — Permanent File Input Mode
- Date: 2026-11-10
- Status: ACCEPTED PRODUCT REQUIREMENT
- Decision: File Input is a permanent top-level input mode on every target, with play/pause/seek, 1080p video where supported, offline translation and native file permissions.
- Consequences: video player timing and decoder tests are production criteria; not developer-only tooling.
- Windows portability: Media Foundation file adapter can implement identical contract.

## ADR-0004 — Flutter UI + Rust shared core + native platform media adapters
- Date: 2026-11-10
- Status: PROPOSED; FEASIBILITY GATE R0
- Decision: Cross-platform Flutter app shell and pure portable Rust session/translation state; use Swift/Kotlin/native implementations for media/accelerator/secure key and output.
- Alternatives: fully native Swift+Kotlin; pure Flutter plugins; Tauri desktop plus native tablet apps.
- Validation: benchmark native texture zero-copy properties, FFI calls, memory ownership, file and UVC render throughput across devices.
- Windows portability: Direct3D/Media Foundation platform adapters, no Rust core rewrite.

## ADR-0005 — Monorepo skeleton and minimal core dependency set
- Date: 2026-11-10
- Status: PROPOSED
- Context: README §22.2 Day-1 requires skeleton contracts + Flutter shell + stubbed adapters before R0.
- Decision: Adopt README §18.1 layout. `core/rust` crate `subtitle_core` depends only on serde, serde_json, sha2; epoch-tagged results and the §6.4 FSM live in core. Flutter shell is source-only until runners are generated.
- Alternatives: generate full Flutter runners now (needs Flutter SDK; deferred); add tokio/async runtime in core (deferred until FFI decision D-003).
- Consequences: async/texture plumbing is still open; FSM is pure and deterministic for golden tests.
- Windows impact: WIN-CHANGE-20261110-001; core tested on windows-latest in CI.
- Related FR/AC: FR-007, FR-010, AC-004, AC-010, AC-018, AC-021, AC-022.

## New ADR template

```markdown
# ADR-NNNN — Decision title
Date: YYYY-MM-DD
Status: PROPOSED | ACCEPTED | SUPERSEDED
Owners:
Context:
Decision:
Alternatives considered:
Benefits and drawbacks:
Privacy/security/license considerations:
Platform-specific implications:
Windows impact (ledger record):
Migration/rollback:
Validation evidence:
Related FR/AC:
```
