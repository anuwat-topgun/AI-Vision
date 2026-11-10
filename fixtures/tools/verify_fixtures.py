#!/usr/bin/env python3
"""CI check: every fixture in manifest.yaml exists, matches sha256, and has sane subtitle events."""
import hashlib, sys
from pathlib import Path
import yaml

root = Path(__file__).resolve().parents[1]
m = yaml.safe_load((root / "manifest.yaml").read_text(encoding="utf-8"))
errors = []
for fx in m["fixtures"]:
    p = root / fx["path"]
    if not p.exists():
        errors.append(f"{fx['id']}: missing {p}"); continue
    if hashlib.sha256(p.read_bytes()).hexdigest() != fx["sha256"]:
        errors.append(f"{fx['id']}: sha256 mismatch")
    prev_end = -1
    for s in fx["expected_subtitles"]:
        if not (0 <= s["start_ms"] < s["end_ms"] <= fx["duration_ms"]) or s["start_ms"] < prev_end:
            errors.append(f"{fx['id']}: bad timing {s}")
        l, t, w, h = s["normalized_bbox"]
        if min(l, t, w, h) < 0 or l + w > 1 or t + h > 1:
            errors.append(f"{fx['id']}: bad bbox {s}")
        prev_end = s["end_ms"]
print("\n".join(errors) or f"OK: {len(m['fixtures'])} fixtures verified")
sys.exit(1 if errors else 0)
