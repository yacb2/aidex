#!/usr/bin/env bash
# eval-local-first-behavior.sh — BEHAVIORAL eval of rules/artifacts-local-first.md.
#
# NOT a unit gate: each scenario is a real headless `claude -p` session (API cost,
# minutes of wall clock). Instrument: stream-json event detection (the LOOP-004
# two-instrument architecture) + filesystem assertions + an `open` PATH shim so
# nothing actually opens a browser.
#
# Scenarios:
#   S1 anchored    — "crea un artifact del plan X" -> sibling HTML inside the plan
#                    folder, artifact-design Skill fired, open-shim called on that
#                    file, NO Artifact (publish) tool_use.
#   S2 anchor-less — analysis tied to nothing -> .context/reports/*.html, same
#                    open/no-publish assertions.
#
# Run with: bash tests/eval-local-first-behavior.sh   (requires `claude` on PATH)

set -uo pipefail
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
pass() { printf '  PASS  %s\n' "$*"; }

command -v claude >/dev/null || { echo "SKIP: claude CLI not on PATH"; exit 0; }

# macOS has no GNU timeout by default — use whichever exists, else run bare.
if command -v timeout >/dev/null; then TO="timeout 600"
elif command -v gtimeout >/dev/null; then TO="gtimeout 600"
else TO=""; fi

WORK="$(mktemp -d /tmp/aidex-lf-eval.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# --- open(1) shim: log instead of launching a browser -------------------------
SHIM="$WORK/shim"; mkdir -p "$SHIM"
cat > "$SHIM/open" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "$WORK/open-calls.log"
EOF
chmod +x "$SHIM/open"

# --- fixture project ----------------------------------------------------------
FIX="$WORK/fixture-proj"
mkdir -p "$FIX/.context/plans/2026-07-01-demo-feature" "$FIX/.context/backlog"
cat > "$FIX/.context/plans/2026-07-01-demo-feature/00-index.md" <<'EOF'
---
title: "Demo feature"
status: doing
current-phase: 2
created: 2026-07-01
updated: 2026-07-20
---
# Demo Feature Implementation Plan
**Goal:** Add CSV export to the invoices module.
## Phases Overview
| Phase | Description | Status |
|---|---|---|
| 1 | Backend serializer + endpoint | done |
| 2 | Frontend download button | doing |
| 3 | E2E test | open |
EOF
echo "# Backlog" > "$FIX/.context/backlog/00-index.md"

run_scenario() { # $1=name $2=prompt
  local name="$1" prompt="$2"
  : > "$WORK/open-calls.log"
  ( cd "$FIX" && PATH="$SHIM:$PATH" $TO claude -p "$prompt" \
      --output-format stream-json --verbose --dangerously-skip-permissions \
      > "$WORK/$name.stream.jsonl" 2> "$WORK/$name.err" )
  local rc=$?
  [ $rc -eq 0 ] || fail "$name: claude -p exited $rc (see $name.err)"
}

check_events() { # $1=name -> prints "<artifact_design_fired> <artifact_tool_used>"
  python3 - "$WORK/$1.stream.jsonl" <<'PY'
import json, sys
ad = pub = False
for line in open(sys.argv[1]):
    try: ev = json.loads(line)
    except Exception: continue
    for b in (ev.get("message") or {}).get("content") or []:
        if isinstance(b, dict) and b.get("type") == "tool_use":
            n = b.get("name", "")
            if n == "Skill" and "artifact-design" in json.dumps(b.get("input", {})): ad = True
            if n == "Artifact": pub = True
print(int(ad), int(pub))
PY
}

echo "== S1: anchored to a plan =="
run_scenario s1 "crea un artifact resumen del plan demo-feature (.context/plans/2026-07-01-demo-feature/) para revisarlo offline"
S1_HTML="$(ls "$FIX/.context/plans/2026-07-01-demo-feature/"*.html 2>/dev/null | head -1)"
[ -n "$S1_HTML" ] && pass "sibling HTML created inside the plan folder ($(basename "$S1_HTML"))" \
                  || fail "S1: no sibling HTML inside the plan folder"
grep -q "2026-07-01-demo-feature" "$WORK/open-calls.log" 2>/dev/null \
  && pass "opened locally via open(1) shim" || fail "S1: open(1) never called on the sibling"
read -r AD PUB <<< "$(check_events s1)"
[ "$AD" = "1" ]  && pass "artifact-design skill fired" || fail "S1: artifact-design did not fire"
[ "$PUB" = "0" ] && pass "Artifact (publish) tool NOT used" || fail "S1: published online without being asked"

echo "== S2: anchor-less -> .context/reports/ =="
run_scenario s2 "crea un artifact con un analisis comparativo de estrategias de caching (Redis vs in-memory vs CDN) para leerlo offline; no esta asociado a ningun documento del proyecto"
S2_HTML="$(ls "$FIX/.context/reports/"*.html 2>/dev/null | head -1)"
[ -n "$S2_HTML" ] && pass "anchor-less HTML landed in .context/reports/ ($(basename "$S2_HTML"))" \
                  || fail "S2: nothing in .context/reports/ (found: $(cd "$FIX" && find .context -name '*.html' | tr '\n' ' '))"
grep -q "reports/" "$WORK/open-calls.log" 2>/dev/null \
  && pass "opened locally via open(1) shim" || fail "S2: open(1) never called on the report"
read -r AD PUB <<< "$(check_events s2)"
[ "$AD" = "1" ]  && pass "artifact-design skill fired" || fail "S2: artifact-design did not fire"
[ "$PUB" = "0" ] && pass "Artifact (publish) tool NOT used" || fail "S2: published online without being asked"

echo
if [ "$failures" -eq 0 ]; then echo "RESULT: all behavioral assertions passed"; exit 0
else echo "RESULT: $failures failure(s) — streams kept in $WORK? (removed on exit; re-run with trap disabled to inspect)"; exit 1; fi
