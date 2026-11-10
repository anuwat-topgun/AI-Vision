# Changelog

## [Unreleased] — v2.0 product planning (2026-11-10)
- Changed primary platform priority to iPadOS, macOS, Android tablets. Windows postponed to R5.
- Changed architecture to offline-first EN/JA→TH with opt-in Cloud BYOK.
- Promoted File Input Mode to permanent top-level feature.
- Added device-specific UVC/TV-out support qualification and performance gates.
- Introduced mandatory Windows Portability Ledger and per-PR documentation rule.
- Added FFI contracts, state machine, acceptance criteria, QA matrix and security/legal release gates.

## [Unreleased] — Live subtitle zone and steadier overlay (2026-11-10)
- Live Capture: "Subtitle zone" button — drag a box over the video; OCR and translation read only inside it. Saved between sessions; "Reset zone" restores the default bottom band.
- OCR keeps only the subtitle block (lines as tall as the main line and contiguous with it), so small game UI labels such as "Auto Play" / "Story Logs" are no longer joined into the sentence.
- Overlay no longer blinks: the tracker tolerates 2 missed samples, the Thai stays 0.8 s after the source vanishes, and the previous Thai stays until the next line's translation is ready.

## [Unreleased] — Live Capture on macOS (E07) (2026-11-10)
- Live Capture screen: pick a UVC capture device and format (Auto prefers 1080p60), optional capture-card audio, live preview with the Thai subtitle pipeline, capture fps/dropped frames in Debug. Unplug clears subtitles and waits; replugging the same device resumes. Ledger WIN-CHANGE-20261110-008.

## [Unreleased] — Translation prompt p2 (2026-11-10)
- Prompt p1 → p2 (Natural Thai Game Localization) per `docs/translation/PROMPT_P2_SPEC.md`; canonical prompts and translation contract moved into Rust core. Typed results: `???`/invalid/timeout never shown. Session history deduped and cleared on seek/new file. Cache keys versioned by prompt/model/history. KV prefix reuse (p2 P50 231 ms on M4 Max).
- Fixes: crash when prompt exceeded 512 tokens; "AIVision quit unexpectedly" on quit with a model loaded.
- ADR-0009, ledger WIN-CHANGE-20261110-007, evaluation in `docs/translation/PROMPT_EVALUATION.md`.

## [Unreleased] — Model auto-load (2026-11-10)
- App loads the last-used model at launch; if none, picks up a local `.gguf` from `~/Models` (macOS, disk only, no download). A banner over the video says when no model is loaded, with a "เลือกโมเดล…" button. Windows impact: NONE beyond UI convenience (WIN-010 UI will need the same prompt).

## [Unreleased] — MKV support via VLC on macOS (2026-11-10)
- Video File now opens MKV (and WebM/AVI/TS) on macOS through VLC; MP4/MOV stay on AVFoundation. Thai subtitle pipeline works the same on both. MKV fixtures added. ADR-0008, ledger WIN-CHANGE-20261110-006.

## [Unreleased] — OCR + offline Thai translation on macOS/iPadOS (2026-11-10)
- Video File mode reads EN/JA burned-in subtitles (Apple Vision), translates offline with a user-imported GGUF model via llama.cpp, and shows Thai above the original. Debug overlay (ROI, box, timings, model). Rust stability tracker + CER shared via FFI. ADR-0007, ledger WIN-CHANGE-20261110-005, BENCH-20261110-001.

## [Unreleased] — E02 File playback (2026-11-10)
- Video File screen on iPadOS/macOS (AVPlayer) and Android (Media3): system file picker, play/pause, exact seek, ±10 s, speed 0.5–2×, volume/mute, fullscreen; seek bumps core epoch; clear errors for unsupported/DRM/damaged files. Tests run against golden fixtures. Ledger WIN-CHANGE-20261110-004.

## [Unreleased] — Synthetic fixtures (2026-11-10)
- Added two synthetic 12 s 1080p60 H.264/AAC fixtures (EN bottom-outline, JA dialog-box), 3 invented subtitles each with exact PTS + bbox and onset audio beeps; generator + CI verifier. Manifest v2. Ledger WIN-CHANGE-20261110-003.

## [Unreleased] — Native UI (2026-11-10)
- Replaced Flutter shell with native SwiftUI (iPadOS + macOS) and Kotlin/Jetpack Compose (Android) apps calling the Rust core via UniFFI (`core/ffi`). Handoff README bumped to v2.1. ADR-0006 supersedes ADR-0004. Windows ledger: WIN-CHANGE-20261110-002.

## [Unreleased] — Day-1 skeleton (2026-11-10)
- Added repo layout, Rust `subtitle_core` (contracts, epoch, FSM, cache key) with 9 tests, Flutter Home shell, platform stubs, CI, `check_windows_impact.sh`, PR template. Windows ledger: WIN-CHANGE-20261110-001. ADR-0005. No hardware evidence; all QA rows remain NOT_TESTED.

## Change entry template
- Date/version, feature or defect, changed contracts, migrations, affected AC, Windows ledger ID, QA evidence, owner.
