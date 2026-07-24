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
#   S3 anchor       — prompt names the SUBJECT of an existing backlog item and
#                    never its path: the artifact must NOT land in the reports/
#                    fallback (BL-074 step 0).
#   contract        — every produced file passes check-artifact.sh (doctype,
#                    charset, viewport, themes, self-contained, no siblings).
#                    Assertion logic is unit-tested API-free in
#                    skills/aidex-dash/tests/test-artifact-contract.sh.
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
# Keep the workdir (streams, err logs) when any assertion fails — deleting the
# evidence on failure made the first two runs undiagnosable.
cleanup() { if [ "${failures:-0}" -eq 0 ]; then rm -rf "$WORK"; else echo "evidence kept: $WORK"; fi; }
trap cleanup EXIT

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
# S3 anchor-discovery fixture: a backlog item the S3 prompt describes by SUBJECT
# only, never by path. The rule must go looking; landing in reports/ means it
# never did (the old S2 prompt said "no esta asociado a ningun documento",
# pre-answering the question the step is supposed to force).
cat > "$FIX/.context/backlog/2026-07-10-invoice-pdf-rendering-slow.md" <<'EOF'
---
title: "Invoice PDF rendering is slow on large accounts"
id: BL-001
status: open
created: 2026-07-10
updated: 2026-07-10
priority: P1
type: bug
---
# Invoice PDF rendering is slow on large accounts

## Context

Accounts over ~2k invoices take 40s+ to render a PDF batch. Suspected N+1 in
the line-item serializer plus synchronous font subsetting.
EOF

run_scenario() { # $1=name $2=prompt
  local name="$1" prompt="$2"
  : > "$WORK/open-calls.log"
  ( cd "$FIX" && PATH="$SHIM:$PATH" $TO claude -p "$prompt" \
      --output-format stream-json --verbose --dangerously-skip-permissions \
      > "$WORK/$name.stream.jsonl" 2> "$WORK/$name.err" )
  local rc=$?
  [ $rc -eq 0 ] || fail "$name: claude -p exited $rc (see $name.err)"
}

check_events() { # $1=name -> prints "<design_guidance_loaded> <artifact_tool_used> <dash_render>"
  # Design guidance = artifact-design OR its headless equivalents (theme-factory /
  # canvas-design / dataviz) — headless claude -p does not ship artifact-design.
  python3 - "$WORK/$1.stream.jsonl" <<'PY'
import json, sys
DESIGN = ("artifact-design", "theme-factory", "canvas-design", "dataviz")
dg = pub = dash = False
for line in open(sys.argv[1]):
    try: ev = json.loads(line)
    except Exception: continue
    for b in (ev.get("message") or {}).get("content") or []:
        if isinstance(b, dict) and b.get("type") == "tool_use":
            n = b.get("name", "")
            blob = json.dumps(b.get("input", {}))
            if n == "Skill" and any(d in blob for d in DESIGN): dg = True
            if n == "Artifact": pub = True
            if n == "Bash" and "render.sh" in blob: dash = True
print(int(dg), int(pub), int(dash))
PY
}

echo "== S1: anchored to a plan =="
run_scenario s1 "crea un artifact resumen del plan demo-feature (.context/plans/2026-07-01-demo-feature/) para revisarlo offline"
S1_HTML="$(ls "$FIX/.context/plans/2026-07-01-demo-feature/"*.html 2>/dev/null | head -1)"
[ -n "$S1_HTML" ] && pass "sibling HTML created inside the plan folder ($(basename "$S1_HTML"))" \
                  || fail "S1: no sibling HTML inside the plan folder"
grep -q "2026-07-01-demo-feature" "$WORK/open-calls.log" 2>/dev/null \
  && pass "opened locally via open(1) shim" || fail "S1: open(1) never called on the sibling"
read -r DG PUB DASH <<< "$(check_events s1)"
# A plan summary is legitimately route A (dash render.sh) OR route B (design skill).
{ [ "$DG" = "1" ] || [ "$DASH" = "1" ]; } && pass "design guidance loaded or dash renderer used (dg=$DG dash=$DASH)" \
  || fail "S1: neither a design-guidance skill nor render.sh was used"
[ "$PUB" = "0" ] && pass "Artifact (publish) tool NOT used" || fail "S1: published online without being asked"

echo "== S2: anchor-less -> .context/reports/ =="
run_scenario s2 "crea un artifact con un analisis comparativo de estrategias de caching (Redis vs in-memory vs CDN) para leerlo offline; no esta asociado a ningun documento del proyecto"
S2_HTML="$(ls "$FIX/.context/reports/"*.html 2>/dev/null | head -1)"
[ -n "$S2_HTML" ] && pass "anchor-less HTML landed in .context/reports/ ($(basename "$S2_HTML"))" \
                  || fail "S2: nothing in .context/reports/ (found: $(cd "$FIX" && find .context -name '*.html' | tr '\n' ' '))"
grep -q "reports/" "$WORK/open-calls.log" 2>/dev/null \
  && pass "opened locally via open(1) shim" || fail "S2: open(1) never called on the report"
read -r DG PUB DASH <<< "$(check_events s2)"
[ "$DG" = "1" ]  && pass "design-guidance skill fired" || fail "S2: no design-guidance skill fired"
[ "$PUB" = "0" ] && pass "Artifact (publish) tool NOT used" || fail "S2: published online without being asked"

echo "== S3: anchor discovery (prompt names the subject, never the path) =="
# Snapshot first: S1 and S2 already left .html files behind, so "newest file"
# would credit S3 with someone else's artifact.
BEFORE_S3="$(cd "$FIX" && find .context -name '*.html' | sort)"
run_scenario s3 "crea un artifact con un analisis de por que el renderizado de PDF de facturas esta lento y que opciones tenemos, para revisarlo offline"
S3_HTML="$(cd "$FIX" && comm -13 <(printf '%s\n' "$BEFORE_S3") <(find .context -name '*.html' | sort) | head -1)"
# Loose property on purpose: asserting WHICH anchor was picked is a fuzzy
# judgement that makes a flaky eval. What must hold is that a discoverable
# anchor stopped the fallback from being the default.
case "$S3_HTML" in
  .context/reports/*) fail "S3: fell back to reports/ although a matching backlog item exists (no anchor search)" ;;
  "")                 fail "S3: no artifact produced at all" ;;
  *)                  pass "anchored outside the reports/ fallback ($S3_HTML)" ;;
esac

echo "== artifact file contract (all produced files) =="
# Same checker the cheap unit test proves out (aidex-dash/tests/test-artifact-contract.sh);
# here it runs against whatever the real sessions actually wrote.
PRODUCED="$(cd "$FIX" && find .context -name '*.html' | sed "s|^|$FIX/|")"
if [ -n "$PRODUCED" ]; then
  # shellcheck disable=SC2086
  if CONTRACT_OUT="$(bash "$(dirname "$0")/../skills/aidex-dash/scripts/check-artifact.sh" $PRODUCED 2>&1)"; then
    pass "every produced artifact honours the file contract"
  else
    fail "artifact contract violations:\n$CONTRACT_OUT"
  fi
else
  fail "no artifacts produced by any scenario"
fi

echo
if [ "$failures" -eq 0 ]; then echo "RESULT: all behavioral assertions passed"; exit 0
else echo "RESULT: $failures failure(s)"; exit 1; fi
