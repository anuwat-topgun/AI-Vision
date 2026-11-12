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
| KI-020 | MKV not supported on iPadOS (needs MobileVLCKit, ~264 MB) | Medium | OPEN | decide after store/legal review | iOS lead |
| KI-021 | LGPL-2.1 (VLCKit) obligations: attribution + source offer in Help/Legal, relinking; App Store compatibility unreviewed | High | OPEN | legal review before release | Legal lead |
| KI-022 | VLC A/V sync with our display layer not measured | Medium | OPEN | sync fixture test | QA lead |
| KI-023 | p2 still adds ครับ on ありがとうございます and renders "Leave it to me!" literally (Qwen3-4B) | Medium | OPEN | few-shot examples or larger model; §10.2 human eval | ML lead |
| KI-024 | Spec §10.2 human evaluation (200 EN + 200 JA, blinded Thai reviewers) not done; only N=12 smoke | High | OPEN | build licensed bilingual fixture set | QA lead |
| KI-025 | Metal residency sets disabled to avoid ggml exit abort; measure any perf impact on iPad | Low | OPEN | iPad benchmark | iOS lead |
| KI-026 | Live Capture tested only with a USB webcam; no capture card / console yet, no optical latency measurement (§14) | High | OPEN | test with real capture card (QA-005) | Platform QA |
| KI-027 | Unplug/replug path implemented but not exercised on hardware | Medium | OPEN | manual unplug test | Platform QA |
| KI-033 | Typhoon Translate 1.5 license is inconsistent (card metadata Apache-2.0, text says Gemma License) and comes with OpenTyphoon terms; not cleared for bundling | High | OPEN | legal review before any distribution (D-001) | Legal |
| KI-034 | Typhoon models are documented EN↔TH only; Japanese output works in a small test but is unsupported | Medium | OPEN | keep Qwen for JA or route by language | Translation |
| KI-031 | p3 still makes small-model meaning errors (e.g. "Stay behind me" → "ข้างๆ"); profile quality depends on player-written voice notes | Medium | OPEN | human eval set; try Thai-tuned model (Typhoon) | Translation |
| KI-032 | Speaker zone needs manual setup per game; stylised name tags may OCR wrongly (unknown names fall back to name only) | Low | OPEN | per-profile default zones | Pipeline |
| KI-029 | Mask & Replace patch is a flat sampled colour: visible on gradients/animated backdrops; long Thai lines shrink to fit the source box (§9.1 known limitation) | Medium | OPEN | background-sampled gradient patch / allow box growth | Compositor |
| KI-030 | Multiple zones translate one line at a time through the single local model; extra zones can lag the dialogue zone | Low | OPEN | priority queue favouring zone 1 | Pipeline |
| KI-028 | No live-capture audio on iPadOS yet (no AVCaptureAudioPreviewOutput); A/V sync unmeasured | Medium | OPEN | E06 | iOS lead |
| KI-012 | Apple builds need a signing team for device install; CI builds unsigned | Low | OPEN | set DEVELOPMENT_TEAM in project.yml | iOS lead |
| KI-010 | Owners for all roles/decisions D-001..D-009 unassigned | High | OPEN | kickoff assignment (§22.2 step 1) | PM |
