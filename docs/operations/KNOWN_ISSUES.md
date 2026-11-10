# Known Issues / Unknowns (planning stage)

| ID | Description | Risk | Status | Next action | Owner |
|---|---|---|---|---|---|
| KI-001 | UVC support varies across Android tablet vendors and models | High | OPEN | R0 device matrix | Android lead |
| KI-002 | Simultaneous UVC input + external TV out + power on tablet may not work on all docks | High | OPEN | R0 dock qualification | Platform QA |
| KI-003 | EN/JA→TH local model quality/latency not measured | High | OPEN | benchmark on-device | ML lead |
| KI-004 | MKV/MOV codec and audio support varies by OS | Medium | OPEN | format matrix | Media lead |
| KI-005 | Cloud BYOK direct key placement may violate some provider security guidance/terms | High | OPEN | verify each provider | Security lead |
| KI-006 | App Store model packaging and paid licensing workflow unverified | High | OPEN | store/legal spike | Release lead |
| KI-007 | Commercial translation/copyright treatment requires jurisdiction-specific review | High | OPEN | legal counsel | Legal lead |
| KI-008 | Native video surface + GPU/AI contention unmeasured (Flutter bridge removed by ADR-0006) | High | OPEN | native performance spike | Client lead |
| KI-009 | ~~Flutter shell not built~~ — CLOSED by ADR-0006 (Flutter removed) | — | CLOSED | — | Client lead |
| KI-011 | Android app built but not yet launched on an emulator/tablet; no Compose UI test yet | Medium | OPEN | run on tablet, add instrumented test | Android lead |
| KI-013 | Android instrumented tests run only locally; CI has no emulator job yet | Medium | OPEN | add emulator CI job or device lab | Android lead |
| KI-014 | Recent Files (Apple bookmarks / Android persisted URIs) not built yet | Medium | OPEN | E02 follow-up | Client lead |
| KI-015 | macOS App Sandbox entitlement (user-selected read-only) not set; needed for App Store | Medium | OPEN | decide with D-005 | iOS lead |
| KI-016 | Thai overlay can linger up to ~0.5 s after the source subtitle disappears (4 Hz sampling + 1-miss tolerance) | Low | OPEN | tune sample rate / tolerance after R0 | Client lead |
| KI-017 | ROI fixed to bottom 36%: dialogue boxes higher on screen are missed; no ROI editor yet | Medium | OPEN | ROI editor (FR-016, E03) | Client lead |
| KI-018 | Android has no OCR/translation yet (only playback) | High | OPEN | ML Kit/ONNX OCR + llama.cpp Android | Android lead |
| KI-019 | Translation quality unreviewed; some awkward/drifting lines with Qwen3-4B | High | OPEN | SPK-02 bake-off + native Thai reviewers | ML lead |
| KI-012 | Apple builds need a signing team for device install; CI builds unsigned | Low | OPEN | set DEVELOPMENT_TEAM in project.yml | iOS lead |
| KI-010 | Owners for all roles/decisions D-001..D-009 unassigned | High | OPEN | kickoff assignment (§22.2 step 1) | PM |
