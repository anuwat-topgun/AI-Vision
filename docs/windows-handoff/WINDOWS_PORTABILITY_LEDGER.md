# Windows Portability Ledger — MANDATORY

**Status:** Windows deferred (R5); portability actively tracked from first commit.  
**Owner:** Architecture Lead (assign at kickoff).  
**Rule:** Every PR with cross-platform ramifications appends a record or explicitly documents `Windows impact: NONE` with reviewable reason in PR description. Never replace historical records.

## Windows adapter backlog

| ID | Boundary | Planned Windows equivalent | Known risks | Validation |
|---|---|---|---|---|
| WIN-001 | File video decode/player | Media Foundation / reviewed cross-platform media engine | codec availability/MKV | MP4 1080p60 seek/audio tests |
| WIN-002 | Live UVC | Media Foundation device enumeration and capture | negotiated formats/USB quirks | same UVC test kit |
| WIN-003 | Video composition | Direct3D native texture path | swapchain integration with WinUI (ADR-0006) | no frame copies across FFI |
| WIN-004 | OCR | portable ONNX OCR backend | model binary and acceleration | EN/JA golden corpus |
| WIN-005 | Offline AI | Windows local runtime, possible ONNX DirectML/CPU/GPU | memory/driver model packaging | same Thai evaluation fixtures |
| WIN-006 | Secure secrets | Windows Credential Manager / DPAPI-backed store | key lifecycle | no plaintext artifact tests |
| WIN-007 | Local files | Windows picker + safe identity/permissions | filesystem assumptions | seek/reopen fixtures |
| WIN-008 | TV | Windows display management + audio routing | HDR/audio/display timing | processed video to secondary display |
| WIN-009 | Packaging | code-signed installer/updater | signing/version | install/uninstall/rollback |
| WIN-010 | UI | WinUI 3 / C# native UI over UniFFI C# bindings (ADR-0006) | third UI codebase; C# binding generator maturity | same §11 screen inventory, accessibility/fullscreen |

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

### WIN-CHANGE-20261110-002 — Native UI per platform (supersedes Flutter)
- Date / author / PR: 2026-11-10 / Claude Code for repo owner / branch feat/native-ui-adr-0006
- Requirement and AC IDs: FR-010, NFR-004, NFR-008, AC-004, AC-021
- Current decision and motivation: product owner chose native UI; ADR-0006.
- Changed modules / contracts / formats: removed `app/flutter_ui`; added `app/apple` (SwiftUI), `app/android` (Compose), `core/ffi` (UniFFI), cargo workspace `core/Cargo.toml`, build scripts `scripts/build_apple_core.sh`, `scripts/build_android_core.sh`. Core contracts/schemas unchanged.
- iPadOS/macOS behavior: one SwiftUI target, links `SubtitleFFI.xcframework` (static lib).
- Android behavior: Compose app, loads `libsubtitle_ffi.so` through JNA.
- Windows future equivalent and required adapter: WinUI 3 app in C#; generate C# bindings for `core/ffi` (third-party uniffi-bindgen-cs, evaluate at R5) or a thin C ABI. Replaces previous "Flutter Windows desktop" plan.
- Compatibility/ABI/API/schema implications: FFI surface `core_api_version()`, `CoreSession` (epoch bump / is_current). No schema change.
- Dependency and licensing impact: uniffi 0.28 (MPL-2.0), JNA 5.17 (Apache-2.0/LGPL). Both usable on Windows.
- Risks/unknowns and experiment needed: C# binding generator maturity; 3 UI codebases at R5.
- Windows tasks with priority, owner and due milestone: P2 spike "C# bindings for core/ffi" before R5 — Architecture Lead.
- Tests / fixtures / evidence: `cargo test --workspace` (incl. windows-latest CI), macOS XCTest via FFI, Android assembleDebug.
- ADR link: ADR-0006
- Status: IMPLEMENTED

### WIN-CHANGE-20261110-003 — Synthetic EN/JA golden fixtures
- Date / author / PR: 2026-11-10 / Claude Code for repo owner / branch feat/synthetic-fixtures
- Requirement and AC IDs: §16.2, §22.2 step 4; AC-001..003, AC-005, AC-006, AC-010, E2E-01, E2E-03
- Current decision and motivation: first golden media for file playback, OCR and seek-race tests.
- Changed modules / contracts / formats: `fixtures/manifest.yaml` v2 (adds path, sha256, style, duration_ms, audio_markers, font); `fixtures/media/*.mp4`; `fixtures/tools/generate_fixtures.py`, `verify_fixtures.py`.
- iPadOS/macOS behavior: H.264 High/AAC MP4 — AVFoundation baseline format.
- Android behavior: same file, Media3 baseline format.
- Windows future equivalent and required adapter: same files must play via Media Foundation (WIN-001); generator is pure Python + ffmpeg and runs on Windows.
- Compatibility/ABI/API/schema implications: manifest schema version 1 → 2 (additive).
- Dependency and licensing impact: Noto Sans JP (SIL OFL 1.1) used only to render fixtures; font binary not committed (downloaded by hash), license text committed.
- Risks/unknowns and experiment needed: re-running the generator with a different ffmpeg/x264 version changes sha256; manifest records generator ffmpeg version.
- Windows tasks with priority, owner and due milestone: include these fixtures in the R5 WIN-001 file-playback parity test (P1, QA Lead).
- Tests / fixtures / evidence: `verify_fixtures.py` OK (2 fixtures); frames visually checked.
- ADR link: none (no architecture change)
- Status: IMPLEMENTED

### WIN-CHANGE-20261110-004 — E02 file playback (Apple + Android)
- Date / author / PR: 2026-11-10 / Claude Code for repo owner / branch feat/e02-file-playback
- Requirement and AC IDs: FR-001, FR-002, FR-010, NFR-009; AC-001, AC-002, AC-003, AC-010 (epoch on seek), AC-033 (media part)
- Current decision and motivation: permanent File mode playback with exact seek, 10 s skip, speed 0.5–2×, volume/mute, fullscreen; seek bumps the Rust session epoch.
- Changed modules / contracts / formats: `app/apple/Sources/PlayerModel.swift`, `PlayerView.swift`; `app/android/.../PlayerController.kt`, `FilePlayerScreen.kt`. No core/FFI/schema change.
- iPadOS/macOS behavior: AVPlayer + AVPlayerLayer; document picker with security-scoped URL, file not copied; waits for `readyToPlay` before seeking; DRM/undecodable files rejected with distinct messages.
- Android behavior: Media3 ExoPlayer 1.8 with `SeekParameters.EXACT` + PlayerView surface; SAF `OpenDocument` with persisted read grant (no raw paths); PlaybackException codes mapped to user messages.
- Windows future equivalent and required adapter: WIN-001 Media Foundation `IMFMediaEngine` (or MediaPlayer in WinUI) behind the same controller shape: open(opaque source) / seek(ms) bumps epoch / Ready|Failed(message) states; `FileOpenPicker` for WIN-007. Same fixtures and same seek-accuracy assertion (±1 frame) are the parity test.
- Compatibility/ABI/API/schema implications: source id is an opaque `file:<uuid>`, never a path (§19.1(6)).
- Dependency and licensing impact: androidx.media3 exoplayer/ui 1.8.0 (Apache-2.0); AndroidX test libs (Apache-2.0, test only).
- Risks/unknowns and experiment needed: Recent Files / bookmark restore not yet built; MKV/HEVC not yet tested; no real tablet/iPad run.
- Windows tasks with priority, owner and due milestone: port controller contract + seek test to Media Foundation at R5 (P1, Architecture Lead).
- Tests / fixtures / evidence: macOS XCTest 5/5 (M4 Max, macOS 26.7.1); Android instrumented 2/2 on DOT_tablet AVD (Android 16); iPadOS build only.
- ADR link: none (implements ADR-0003 within ADR-0006)
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
