# Changelog

## [Unreleased] — v2.0 product planning (2026-11-10)
- Changed primary platform priority to iPadOS, macOS, Android tablets. Windows postponed to R5.
- Changed architecture to offline-first EN/JA→TH with opt-in Cloud BYOK.
- Promoted File Input Mode to permanent top-level feature.
- Added device-specific UVC/TV-out support qualification and performance gates.
- Introduced mandatory Windows Portability Ledger and per-PR documentation rule.
- Added FFI contracts, state machine, acceptance criteria, QA matrix and security/legal release gates.

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
