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
