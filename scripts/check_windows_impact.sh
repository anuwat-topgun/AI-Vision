#!/usr/bin/env bash
# README §18.2 / §19.2: PR must update the Windows ledger OR declare
# "Windows impact: NONE" with a reason. Usage: check_windows_impact.sh <base-ref> [pr-body-file]
set -euo pipefail
base="${1:-origin/main}"
body_file="${2:-}"
ledger="docs/windows-handoff/WINDOWS_PORTABILITY_LEDGER.md"
if git diff --name-only "$base"...HEAD | grep -qx "$ledger"; then
  echo "OK: Windows ledger updated."; exit 0
fi
if [[ -n "$body_file" && -f "$body_file" ]]; then
  reason=$(grep -iE 'windows impact:[[:space:]]*none' "$body_file" | sed -E 's/.*[Nn][Oo][Nn][Ee][[:space:]]*[—:-]*[[:space:]]*//' | head -1 || true)
  if [[ -n "$reason" && ! "$reason" =~ ^(N/?A|_+|explanation:?[[:space:]_]*)$ ]] && [[ ${#reason} -ge 15 ]]; then
    echo "OK: 'Windows impact: NONE' declared: $reason"; exit 0
  fi
fi
echo "FAIL: update $ledger or state 'Windows impact: NONE — <one-sentence reason>' in the PR body (N/A is not accepted)." >&2
exit 1
