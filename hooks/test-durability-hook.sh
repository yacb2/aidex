#!/usr/bin/env bash
# test-durability-hook.sh — isolated tests for durability-stop-hook.sh.
# Feeds synthetic Stop-hook stdin payloads and asserts block-vs-allow.
# No global activation, no settings.json — pure stdin/stdout.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/durability-stop-hook.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.context/.durability"
PASS=0; FAIL=0

# helper: run hook with a payload, assert decision is "block" or "allow"
check() {
  local name="$1" want="$2" payload="$3"
  local out got
  out="$(printf '%s' "$payload" | bash "$HOOK" 2>/dev/null || true)"
  if printf '%s' "$out" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then got=block; else got=allow; fi
  if [ "$got" = "$want" ]; then echo "  PASS  $name ($got)"; PASS=$((PASS+1));
  else echo "  FAIL  $name: want=$want got=$got  out=$out"; FAIL=$((FAIL+1)); fi
}

active() { printf '{"mode":"%s","expires":"2999-01-01T00:00:00+00:00","type":"plan-exec"}' "$1" > "$TMP/.context/.durability/active-run.json"; }
clear_run() { rm -f "$TMP/.context/.durability/active-run.json"; }
pl() { # build payload: $1=last_msg $2=stop_hook_active(true/false)
  python3 -c 'import json,sys; print(json.dumps({"cwd":sys.argv[1],"stop_hook_active":sys.argv[2]=="true","last_assistant_message":sys.argv[3],"hook_event_name":"Stop"}))' "$TMP" "$2" "$1"
}

echo "== remind mode =="
active remind
check "no run file -> allow"        allow "$(clear_run; pl '¿quieres que continúe?' false)"
active remind
check "over-stop ES -> block"       block "$(pl 'Listo. ¿Quieres que continúe con la fase 3?' false)"
check "over-stop EN -> block"       block "$(pl 'Done with phase 2. Should I proceed to phase 3?' false)"
check "neutral progress -> allow"   allow "$(pl 'Phase 2 committed. Moving on.' false)"
check "legit publish ask -> allow"  allow "$(pl 'Finished all safe work. Awaiting your approval on the deploy.' false)"
check "hard blocker -> allow"       allow "$(pl 'I cannot proceed: missing credentials for the API.' false)"
check "stop_hook_active -> allow"   allow "$(pl '¿Quieres que continúe?' true)"

echo "== enforce mode =="
active enforce
check "enforce neutral -> block"    block "$(pl 'Phase 2 committed. Moving on.' false)"
check "enforce publish -> allow"    allow "$(pl 'Awaiting your approval on the release.' false)"
check "enforce done -> allow"       allow "$(pl 'All phases complete. Final summary below.' false)"

echo "== expiry / inert =="
printf '{"mode":"enforce","expires":"2000-01-01T00:00:00+00:00","type":"plan-exec"}' > "$TMP/.context/.durability/active-run.json"
check "expired state -> allow"      allow "$(pl 'Phase 2 committed. Moving on.' false)"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
