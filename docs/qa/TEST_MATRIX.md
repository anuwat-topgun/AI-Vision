# Hardware and QA Test Matrix

## Instructions
- Record every tested combination. `NOT_TESTED` is never equivalent to PASS.
- Include actual OS build, device model/chip/RAM, capture card USB VID/PID+firmware, console, cable, dock, power and video format.
- Optical and audio latency estimates require method, sample count, P50/P95 and evidence identifier.
- Declare compatibility only for tested combinations; qualification can cover one setup, not a whole vendor model family.

| ID | Target | Device / OS | Input | Capture card / dock | Video/audio | AI model | Output | State | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| QA-001 | iPadOS | TBD | MP4 H.264 sample | N/A | 1080p60+AAC | TBD | Internal | NOT_TESTED | TBD |
| QA-002 | macOS | TBD | MP4 H.264 sample | N/A | 1080p60+AAC | TBD | Internal | NOT_TESTED | TBD |
| QA-003 | Android tablet | TBD | MP4 H.264 sample | N/A | 1080p60+AAC | TBD | Internal | NOT_TESTED | TBD |
| QA-004 | iPadOS | TBD | Switch console UVC | TBD / powered hub | negotiate | TBD | Internal | NOT_TESTED | TBD |
| QA-005 | macOS | TBD | PS5 console UVC | TBD | negotiate | TBD | Internal/TV | NOT_TESTED | TBD |
| QA-006 | Android tablet | TBD | Xbox console UVC | TBD / powered hub | negotiate | TBD | Internal | NOT_TESTED | TBD |
| QA-007 | iPadOS | TBD | UVC + external TV simultaneously | TBD / dock | negotiate | TBD | Processed TV | NOT_TESTED | TBD |
| QA-008 | Android tablet | TBD | UVC + external TV simultaneously | TBD / dock | negotiate | TBD | Processed TV | NOT_TESTED | TBD |

## Automated software evidence (not device certification)
| Date | Platform / host | Tests | Result | Covers |
|---|---|---|---|---|
| 2026-11-10 | macOS 26.7.1, Apple M4 Max (dev machine) | XCTest FilePlaybackTests + CoreBridgeTests | 5/5 PASS | open fixtures, 1080p60 decode metadata, exact seek ±1 frame, epoch bump, corrupt file error |
| 2026-11-10 | Android 16 emulator DOT_tablet (arm64) | FilePlaybackTest (instrumented) | 2/2 PASS | same as above via Media3 |
| 2026-11-10 | iPadOS | generic build only | BUILD OK | not run on an iPad |

QA-001..003 stay NOT_TESTED until run manually on real devices with the full AC steps (audio, fullscreen, picker).

## Golden fixtures available
| Fixture | Lang | Style | Format | Use |
|---|---|---|---|---|
| synth_en_1080p60_001 | EN | bottom subtitle, black outline | 1080p60 H.264 High + AAC 48k, 12 s | QA-001..003, AC-005, E2E-01/03 |
| synth_ja_1080p60_001 | JA | dialog box | 1080p60 H.264 High + AAC 48k, 12 s | QA-001..003, AC-006, E2E-01/03 |

Not yet covered (add later): furigana, typewriter animation, gradient/animated text, katakana-heavy lines, VFR, MKV/MOV, corrupt file.

## Test case template

```markdown
### QA-XXX — Title
- Date / tester:
- Requirement / AC:
- Device / chip / RAM / OS build:
- Capture/console/cable/dock/power:
- Media container / codec / format / resolution / fps:
- Offline model / runtime / quantization:
- Initial thermal/power conditions:
- Steps:
- Expected:
- Actual:
- Metrics (N, P50, P95, P99, audio offset, drops):
- Logs, trace, video, fixture hash:
- Status: PASS | FAIL | CONDITIONAL | NOT_TESTED | BLOCKED
- Issue link / follow-up:
- Windows-portability impact:
```
