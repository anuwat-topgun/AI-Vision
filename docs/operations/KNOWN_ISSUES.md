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
| KI-008 | Flutter texture + native GPU/AI contention unmeasured | High | OPEN | native performance spike | Client lead |
| KI-009 | Flutter shell not built or tested locally (no Flutter SDK); platform runners not generated | Medium | OPEN | install Flutter, `flutter create`, run `flutter test` | Client lead |
| KI-010 | Owners for all roles/decisions D-001..D-009 unassigned | High | OPEN | kickoff assignment (§22.2 step 1) | PM |
