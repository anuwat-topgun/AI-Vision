# Windows Portability Ledger — MANDATORY

**Status:** Windows deferred (R5); portability actively tracked from first commit.  
**Owner:** Architecture Lead (assign at kickoff).  
**Rule:** Every PR with cross-platform ramifications appends a record or explicitly documents `Windows impact: NONE` with reviewable reason in PR description. Never replace historical records.

## Windows adapter backlog

| ID | Boundary | Planned Windows equivalent | Known risks | Validation |
|---|---|---|---|---|
| WIN-001 | File video decode/player | Media Foundation / reviewed cross-platform media engine | codec availability/MKV | MP4 1080p60 seek/audio tests |
| WIN-002 | Live UVC | Media Foundation device enumeration and capture | negotiated formats/USB quirks | same UVC test kit |
| WIN-003 | Video composition | Direct3D native texture path | frame sharing and swapchain vs Flutter | no frame copies on Dart thread |
| WIN-004 | OCR | portable ONNX OCR backend | model binary and acceleration | EN/JA golden corpus |
| WIN-005 | Offline AI | Windows local runtime, possible ONNX DirectML/CPU/GPU | memory/driver model packaging | same Thai evaluation fixtures |
| WIN-006 | Secure secrets | Windows Credential Manager / DPAPI-backed store | key lifecycle | no plaintext artifact tests |
| WIN-007 | Local files | Windows picker + safe identity/permissions | filesystem assumptions | seek/reopen fixtures |
| WIN-008 | TV | Windows display management + audio routing | HDR/audio/display timing | processed video to secondary display |
| WIN-009 | Packaging | code-signed installer/updater | signing/version | install/uninstall/rollback |
| WIN-010 | UI | Flutter Windows mouse/keyboard | touch assumptions | accessibility/fullscreen |

## Initial impact baseline: 2026-11-10

- **Reference:** Handoff v2.0 initial architecture.
- **Decision:** iPadOS/macOS/Android first; Windows after mobile production-ready; Flutter UI + platform-neutral Rust translation/session core; native media/AI/display adapters.
- **Windows impact:** Requires media, display, inference, secrets and packaging adapters; shared logic remains portable.
- **Blocking items:** Evidence on native Flutter texture performance and model portability pending R0.
- **Acceptance:** Shared Rust core contract tests target Windows MSVC; Windows deferred adapter stubs maintained.
- **Owner:** Architecture Lead / TBD.
- **Related ADR:** ADR-0001, ADR-0002.

### WIN-CHANGE-20261110-001 — Day-1 repository skeleton
- Date / author / PR: 2026-11-10 / initial commit (Claude Code on behalf of repo owner) / initial push to main
- Requirement and AC IDs: README §22.2 steps 2–3; AC-004, AC-010, AC-018, AC-021, AC-022
- Current decision and motivation: create monorepo layout (README §18.1); portable Rust `subtitle_core` (contracts, session epoch, subtitle FSM, cache key); Flutter Home shell with permanent File tile; CI with Windows MSVC core job and ledger check.
- Changed modules / contracts / formats: `core/rust` (CORE_API_VERSION=1, SCHEMA_VERSION=1, mirrors `schemas/*.json` v1); `app/flutter_ui`; `scripts/check_windows_impact.sh`; `.github/workflows/ci.yml`.
- iPadOS/macOS behavior: stub only (`platform/apple`), no AVFoundation code yet.
- Android behavior: stub only (`platform/android`).
- Windows future equivalent and required adapter: core uses only serde/serde_json/sha2 (pure Rust); CI compiles + tests core on `windows-latest` (MSVC). Flutter shell uses no platform-specific navigation; `flutter create --platforms=...,windows` planned.
- Compatibility/ABI/API/schema implications: platform frame handles are opaque in contracts; no FFI layer yet (D-003).
- Dependency and licensing impact: serde, serde_json (MIT/Apache-2.0), sha2 (MIT/Apache-2.0); dev-only jsonschema (MIT). All support Windows MSVC.
- Risks/unknowns and experiment needed: windows-latest CI result not yet observed; Flutter toolchain absent on authoring machine so Dart shell is unverified.
- Windows tasks with priority, owner and due milestone: keep `windows-latest` core job green (P1, Architecture Lead, every PR).
- Tests / fixtures / evidence: `cargo test` 9/9 pass locally on macOS arm64 (seek-race stale drop, source-switch stale, FSM, schema round-trip, cache key).
- ADR link: ADR-0005
- Status: IMPLEMENTED

## Change entry template (append, do not overwrite)

```markdown
### WIN-CHANGE-YYYYMMDD-NNN — <title>
- Date / author / PR:
- Requirement and AC IDs:
- Current decision and motivation:
- Changed modules / contracts / formats:
- iPadOS/macOS behavior:
- Android behavior:
- Windows future equivalent and required adapter:
- Compatibility/ABI/API/schema implications:
- Dependency and licensing impact:
- Risks/unknowns and experiment needed:
- Windows tasks with priority, owner and due milestone:
- Tests / fixtures / evidence:
- ADR link:
- Status: OPEN | BLOCKED | READY | IMPLEMENTED
```

## Weekly Windows-readiness review

1. Confirm all merged PRs have ledger entries or justified no-impact declarations.
2. List unresolved Windows blockers by impact and owner.
3. Confirm shared contract unit tests run on Windows MSVC runner (when available).
4. Track platform-specific code accidental leakage into `core/rust`.
5. Record new model/dependency licenses and Windows compatible artifacts.
6. On planned Windows milestone, convert entries into an ordered implementation backlog and acceptance matrix.
