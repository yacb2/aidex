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

# Default: judge unavailable (exit 1) so the pre-BL-044 tests exercise the
# deterministic regex-fallback path. The judge section overrides this per-test.
export AIDEX_JUDGE_CMD="false"

# Isolate telemetry. Without this every run appended synthetic forced-fallback rows to
# the production log — 94.5% of its 1,206 stop-hook rows turned out to be this harness
# (measured 2026-08-01), which invalidated every durability figure computed from it.
export AIDEX_DURABILITY_LOG="$TMP/events.jsonl"
PROD_LOG="$HOME/.aidex/durability/events.jsonl"
PROD_SUM_BEFORE="$( [ -f "$PROD_LOG" ] && shasum "$PROD_LOG" | cut -d' ' -f1 || echo none )"

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
pltp() { # payload carrying a transcript_path: $1=last_msg $2=transcript_path
  python3 -c 'import json,sys; print(json.dumps({"cwd":sys.argv[1],"stop_hook_active":False,"last_assistant_message":sys.argv[2],"transcript_path":sys.argv[3],"hook_event_name":"Stop"}))' "$TMP" "$1" "$2"
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

echo "== anchored marker lookup (session cwd in a subdir) =="
# The marker is written at the project anchor, so the hook must resolve the same
# anchor from the session cwd. Reading raw cwd made enforcement silently inert
# for any session started in backend/ or frontend/ (BL-075, consumer side).
SUB="$TMP/backend/src"
mkdir -p "$SUB"
active enforce
subpl() { python3 -c 'import json,sys; print(json.dumps({"cwd":sys.argv[1],"stop_hook_active":False,"last_assistant_message":sys.argv[2],"hook_event_name":"Stop"}))' "$SUB" "$1"; }
check "subdir cwd finds the anchored marker" block "$(subpl 'Phase 2 committed. Moving on.')"
clear_run
check "subdir cwd with no marker -> allow"   allow "$(subpl 'Phase 2 committed. Moving on.')"

echo "== model judge (mocked via AIDEX_JUDGE_CMD) =="
# judge verdict wins over the regex in both directions: it blocks a
# summary-no-question message the regex would allow, and allows an
# overstop-phrased message the regex would block.
active remind
export AIDEX_JUDGE_CMD="cat >/dev/null; printf '{\"block\": true, \"reason\": \"[durability-arbiter] mock: mid-plan summary, continue\"}'"
check "judge block, no-question summary -> block" block "$(pl 'Everything is in a clean state. Here is the summary of phase 2.' false)"
export AIDEX_JUDGE_CMD="cat >/dev/null; printf '{\"block\": false}'"
check "judge allow overrides overstop regex -> allow" allow "$(pl 'Done with phase 2. Should I proceed to phase 3?' false)"
# judge failure (unparseable output) -> regex fallback still catches overstop
export AIDEX_JUDGE_CMD="cat >/dev/null; echo judge exploded, no json here"
check "judge garbage -> regex fallback block" block "$(pl 'Done with phase 2. Should I proceed to phase 3?' false)"
# quoted-boolean sloppiness: {"block": "false"} must allow (bool("false") is True
# — the unfixed coercion would block a stop the judge meant to allow).
export AIDEX_JUDGE_CMD="cat >/dev/null; printf '{\"block\": \"false\", \"reason\": \"mock: legit stop\"}'"
check "judge quoted-string false -> allow" allow "$(pl 'Everything is in a clean state. Here is the summary of phase 2.' false)"
# {"block": "true"} must still block (string coerced, not bailed to regex fallback
# — the regex would allow this no-question summary).
export AIDEX_JUDGE_CMD="cat >/dev/null; printf '{\"block\": \"true\", \"reason\": \"[durability-arbiter] mock: continue\"}'"
check "judge quoted-string true -> block" block "$(pl 'Everything is in a clean state. Here is the summary of phase 2.' false)"
# marker absent -> the judge must never be invoked (zero cost in idle sessions)
export AIDEX_JUDGE_CMD="cat >/dev/null; touch '$TMP/judge-invoked'; printf '{\"block\": true}'"
check "no run file -> judge not invoked, allow" allow "$(clear_run; pl 'Everything is in a clean state. Here is the summary.' false)"
if [ -e "$TMP/judge-invoked" ]; then
  echo "  FAIL  no run file -> judge sentinel exists (judge was invoked)"; FAIL=$((FAIL+1))
else
  echo "  PASS  no run file -> judge sentinel absent"; PASS=$((PASS+1))
fi
# LEGIT keyword must NOT short-circuit the judge (review 2026-07-04): an
# over-stop that merely mentions "deploy" is judged, and a block verdict wins.
active remind
export AIDEX_JUDGE_CMD="cat >/dev/null; printf '{\"block\": true, \"reason\": \"[durability-arbiter] mock: deploy mention is not a publish ask\"}'"
check "judge block wins over LEGIT keyword -> block" block "$(pl 'Phase 2 done. The next phase touches the deploy config — should I proceed?' false)"
# ...and when the judge is unavailable, the same message falls back to the
# LEGIT regex and is allowed (pre-BL-044 behavior preserved on the fallback path).
export AIDEX_JUDGE_CMD="false"
check "judge down, LEGIT fallback -> allow" allow "$(pl 'Phase 2 done. The next phase touches the deploy config — should I proceed?' false)"

echo "== last_user_message extraction + retro-run4 policy (mock judge) =="
# The judge now receives last_user_message, extracted from the transcript. Build a
# fixture whose real last user turn is preceded by the noise shapes the extractor
# must skip: a tool_result-bearing turn, a <system-reminder>, a skill-body
# injection, and a slash command. The mock judge dumps its stdin so we can prove
# what the hook actually sent, and returns an ALLOW verdict (an answer-to-user).
active remind
cat > "$TMP/transcript.jsonl" <<'JSONL'
{"type":"user","message":{"content":"First question about the deploy pipeline"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Here is how it works."}]}}
{"type":"user","message":{"content":[{"type":"tool_result","content":"NOISEBEEF tool output"}]}}
{"type":"user","message":{"content":"<system-reminder>NOISEBEEF reminder</system-reminder>"}}
{"type":"user","message":{"content":"Base directory for this skill: NOISEBEEF"}}
{"type":"user","message":{"content":"<command-name>/SLASHNOISE-cmd</command-name>"}}
{"type":"user","message":{"content":"Please write the final summary report"}}
JSONL
export AIDEX_JUDGE_CMD="cat > '$TMP/judge-stdin'; printf '{\"block\": false}'"
out="$(pltp 'Here is the final summary report you requested.' "$TMP/transcript.jsonl" | bash "$HOOK" 2>/dev/null || true)"
# answer-to-user allowed (mock allow honored, no regex override)
if printf '%s' "$out" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then
  echo "  FAIL  answer-to-user allowed: got block  out=$out"; FAIL=$((FAIL+1))
else
  echo "  PASS  answer-to-user allowed (allow)"; PASS=$((PASS+1))
fi
# payload carries the real last user message (load-bearing: proves Task 1.1 plumbed)
if grep -q 'Please write the final summary report' "$TMP/judge-stdin"; then
  echo "  PASS  last_user_message extracted into judge payload"; PASS=$((PASS+1))
else
  echo "  FAIL  last_user_message missing from payload: $(cat "$TMP/judge-stdin" 2>/dev/null)"; FAIL=$((FAIL+1))
fi
# noise + slash entries excluded (proves the skip-filter, not just presence)
if grep -q 'NOISEBEEF' "$TMP/judge-stdin" || grep -q 'SLASHNOISE' "$TMP/judge-stdin"; then
  echo "  FAIL  noise leaked into last_user_message: $(cat "$TMP/judge-stdin" 2>/dev/null)"; FAIL=$((FAIL+1))
else
  echo "  PASS  tool_result / system-reminder / skill-body / slash noise excluded"; PASS=$((PASS+1))
fi
# gated-publish-only completed summary (ES) — a terminal state, allowed
export AIDEX_JUDGE_CMD="cat >/dev/null; printf '{\"block\": false}'"
check "ES gated-publish summary allowed" allow "$(pl 'Todo verificado y en verde. Solo queda pushear a producción, que requiere tu aprobación.' false)"
export AIDEX_JUDGE_CMD="false"

echo "== marker lifecycle (durability-run.sh) =="
RUN="$HERE/durability-run.sh"
# stop from a subdir must find and remove the ROOT marker (the 07-21/22 leak shape)
RT="$(mktemp -d)"
mkdir -p "$RT/.context/.durability" "$RT/backend/deep"
printf '{"type":"plan-exec","mode":"remind","expires":"2999-01-01T00:00:00+00:00"}' > "$RT/.context/.durability/active-run.json"
( cd "$RT/backend/deep" && bash "$RUN" stop ) >/dev/null 2>&1 || true
if [ -f "$RT/.context/.durability/active-run.json" ]; then
  echo "  FAIL  run.sh stop from subdir did not remove root marker"; FAIL=$((FAIL+1))
else
  echo "  PASS  run.sh stop from subdir removed root marker"; PASS=$((PASS+1))
fi
rm -rf "$RT"
# start from a subdir must plant the marker at the PROJECT ROOT, not at raw cwd
# (BL-075: 6 orphan markers across 5 projects, every one in a subdirectory —
# backend/, frontend/, even .context/backlog/. stop searches upward, so a marker
# written downward from the root is unreachable and leaks).
SR="$(mktemp -d)"
mkdir -p "$SR/.context/plans" "$SR/frontend/src"
( cd "$SR/frontend/src" && bash "$RUN" start plan-exec ) >/dev/null 2>&1 || true
if [ -f "$SR/.context/.durability/active-run.json" ]; then
  echo "  PASS  run.sh start from a subdir anchors the marker at the project root"; PASS=$((PASS+1))
else
  echo "  FAIL  run.sh start from a subdir did not write the root marker"; FAIL=$((FAIL+1))
fi
if [ -e "$SR/frontend/src/.context" ] || [ -e "$SR/frontend/.context" ]; then
  echo "  FAIL  run.sh start leaked a .context/ into the subdirectory"; FAIL=$((FAIL+1))
else
  echo "  PASS  run.sh start left no orphan .context/ in the subdirectory"; PASS=$((PASS+1))
fi
# ...and `stop` from the ROOT clears it — the mirror case that used to leak.
( cd "$SR" && bash "$RUN" stop ) >/dev/null 2>&1 || true
if [ -f "$SR/.context/.durability/active-run.json" ]; then
  echo "  FAIL  run.sh stop at the root did not clear a subdir-started run"; FAIL=$((FAIL+1))
else
  echo "  PASS  run.sh stop at the root clears a subdir-started run"; PASS=$((PASS+1))
fi
# status must read the same anchored marker from anywhere in the tree
( cd "$SR/frontend/src" && bash "$RUN" start loop ) >/dev/null 2>&1 || true
statout="$( ( cd "$SR/frontend" && bash "$RUN" status ) 2>&1 || true )"
if printf '%s' "$statout" | grep -q '"type": "loop"'; then
  echo "  PASS  run.sh status from another subdir sees the anchored marker"; PASS=$((PASS+1))
else
  echo "  FAIL  run.sh status did not see the anchored marker: $statout"; FAIL=$((FAIL+1))
fi
rm -rf "$SR"

# Workspace shape: root is NOT a repo, backend/ and frontend/ are sibling repos
# with their own .context/. One run spans them, so one marker at the workspace
# root — a nearest-ancestor anchor would give each subrepo its own and leak again.
WS="$(mktemp -d)"
mkdir -p "$WS/.context" "$WS/backend/.context" "$WS/frontend/.context/plans"
( cd "$WS/backend" && git init -q . ) 2>/dev/null || true
( cd "$WS/backend" && bash "$RUN" start audit ) >/dev/null 2>&1 || true
if [ -f "$WS/.context/.durability/active-run.json" ]; then
  echo "  PASS  run.sh start in a sibling repo anchors at the workspace root"; PASS=$((PASS+1))
else
  echo "  FAIL  run.sh start in a sibling repo did not anchor at the workspace root"; FAIL=$((FAIL+1))
fi
( cd "$WS/frontend/.context/plans" && bash "$RUN" stop ) >/dev/null 2>&1 || true
if [ -f "$WS/.context/.durability/active-run.json" ]; then
  echo "  FAIL  run.sh stop from the other sibling repo did not clear the run"; FAIL=$((FAIL+1))
else
  echo "  PASS  run.sh stop from the other sibling repo clears the run"; PASS=$((PASS+1))
fi
rm -rf "$WS"

# stop with no marker anywhere must warn loudly (a silent no-op is what leaked)
NM="$(mktemp -d)"
warnout="$( ( cd "$NM" && bash "$RUN" stop ) 2>&1 1>/dev/null || true )"
if printf '%s' "$warnout" | grep -qi 'warning'; then
  echo "  PASS  run.sh stop with no marker warns"; PASS=$((PASS+1))
else
  echo "  FAIL  run.sh stop with no marker did not warn: $warnout"; FAIL=$((FAIL+1))
fi
rm -rf "$NM"

echo "== shipped default judge command (claude shim on PATH) =="
# With AIDEX_JUDGE_CMD unset, the hook must invoke `claude -p --model claude-sonnet-5`.
# A PATH shim records the argv and returns a block verdict — no real binary is called.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<SHIM
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' "\$*" > "$TMP/claude-argv"
printf '{"block": true, "reason": "[durability-arbiter] shim"}'
SHIM
chmod +x "$TMP/bin/claude"
active remind
unset AIDEX_JUDGE_CMD
out="$(pl 'Everything is in a clean state. Here is the summary of phase 2.' false | PATH="$TMP/bin:$PATH" bash "$HOOK" 2>/dev/null || true)"
if printf '%s' "$out" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' \
   && grep -q -- '-p' "$TMP/claude-argv" 2>/dev/null \
   && grep -q -- '--model claude-sonnet-5' "$TMP/claude-argv" 2>/dev/null; then
  echo "  PASS  default judge cmd is 'claude -p --model claude-sonnet-5' and verdict honored"; PASS=$((PASS+1))
else
  echo "  FAIL  default judge cmd: out=$out argv=$(cat "$TMP/claude-argv" 2>/dev/null)"; FAIL=$((FAIL+1))
fi
export AIDEX_JUDGE_CMD="false"

# Telemetry isolation is itself an assertion: this suite must never touch the
# production log. Regression guard for the 2026-08-01 contamination.
PROD_SUM_AFTER="$( [ -f "$PROD_LOG" ] && shasum "$PROD_LOG" | cut -d' ' -f1 || echo none )"
if [ "$PROD_SUM_BEFORE" = "$PROD_SUM_AFTER" ]; then
  echo "  PASS  production telemetry untouched by this suite"; PASS=$((PASS+1))
else
  echo "  FAIL  production telemetry was written to: $PROD_LOG"; FAIL=$((FAIL+1))
fi

echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
