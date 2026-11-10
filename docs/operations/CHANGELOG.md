# Changelog

## [Unreleased] — v2.0 product planning (2026-11-10)
- Changed primary platform priority to iPadOS, macOS, Android tablets. Windows postponed to R5.
- Changed architecture to offline-first EN/JA→TH with opt-in Cloud BYOK.
- Promoted File Input Mode to permanent top-level feature.
- Added device-specific UVC/TV-out support qualification and performance gates.
- Introduced mandatory Windows Portability Ledger and per-PR documentation rule.
- Added FFI contracts, state machine, acceptance criteria, QA matrix and security/legal release gates.

## [Unreleased] — Day-1 skeleton (2026-11-10)
- Added repo layout, Rust `subtitle_core` (contracts, epoch, FSM, cache key) with 9 tests, Flutter Home shell, platform stubs, CI, `check_windows_impact.sh`, PR template. Windows ledger: WIN-CHANGE-20261110-001. ADR-0005. No hardware evidence; all QA rows remain NOT_TESTED.

## Change entry template
- Date/version, feature or defect, changed contracts, migrations, affected AC, Windows ledger ID, QA evidence, owner.
