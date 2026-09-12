#!/usr/bin/env bash
# test-detect-resolved-and-quick-wins.sh — BL-214: the two backlog actions RETRO-09 asked
# for, and the two properties that make them safe to run.
#
#   quick-wins      must NEVER open a body. Each item carries a marker string in its body
#                   that must not appear in the output — an ordering that quietly read the
#                   bodies would still print a plausible order, so only the marker catches it.
#   detect-resolved must PROPOSE and never close. Every fixture item is asserted to still
#                   exist, with its status untouched, after the run.

set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/SKILL.md"
QW="$SCRIPTS/quick-wins.py"
DR="$SCRIPTS/detect-resolved.py"
FAILURES=0
fail() { printf 'FAIL: %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$*"; }

WS="$(mktemp -d)"; trap 'rm -rf "$WS"' EXIT
CTX="$WS/.context"; mkdir -p "$CTX/backlog/_archive"
mkdir -p "$WS/skills/aidex-demo/scripts"; : > "$WS/skills/aidex-demo/scripts/thing.sh"

item() {  # item <file> <id> <status> <priority> <estimate> <blocked_by> <body>
  cat > "$CTX/backlog/$1" <<EOF
---
title: "item $2"
id: $2
status: $3
created: 2026-01-01
updated: 2026-01-01
priority: $4
type: task
estimate: $5
blocked_by: "$6"
---

# item $2

BODYMARKER-$2 — this string lives only in the body.
$7
EOF
}

item 2026-01-01-bl-001-a.md BL-001 open P2 M  ""            "It lives in skills/aidex-demo/scripts/thing.sh"
item 2026-01-02-bl-002-b.md BL-002 open P0 L  ""            "no anchors here at all"
item 2026-01-03-bl-003-c.md BL-003 open P2 XS ""            "see .context/decisions/x.md and decision/y.md"
item 2026-01-04-bl-004-d.md BL-004 open P3 S  ""            "cites skills/aidex-demo/scripts/gone.sh"
item 2026-01-05-bl-005-e.md BL-005 open P1 S  "user hold"   "blocked one"
item 2026-01-06-bl-006-f.md BL-006 done P0 XS ""            "closed already"

# --- quick-wins: order, and no body ever read -------------------------------------
OUT="$(python3 "$QW" "$CTX" 2>&1)"; RC=$?
[[ $RC -eq 0 ]] || fail "quick-wins expected exit 0, got $RC"
grep -q 'BODYMARKER' <<<"$OUT" && fail "quick-wins printed body content — it must read front-matter only"
pass "quick-wins never surfaces a body: no BODYMARKER in the output"

# Only the id COLUMN — the fixture titles contain the id too, and a bare grep counted
# each item twice.
ORDER="$( { grep -oE '^ *[0-9]+\. +BL-[0-9]+' <<<"$OUT"; grep -oE '^ +BL-[0-9]+' <<<"$OUT"; } \
          | grep -oE 'BL-[0-9]+' | tr '\n' ' ')"
# P0 first; inside P2 the XS beats the M; the done item is gone; the blocked one is apart.
[[ "$ORDER" == "BL-002 BL-003 BL-001 BL-004 BL-005 " ]] \
  || fail "unexpected order: '$ORDER' (want P0, then P2 XS before P2 M, then P3, blocked last)"
grep -q 'BL-006' <<<"$OUT" && fail "a done item appeared in the proposed order"
grep -q 'Blocked (1)' <<<"$OUT" || fail "the blocked item was not listed apart"
pass "priority, then cheapest estimate, then blocked apart; closed items excluded"

grep -qi 'no body was read' <<<"$OUT" || fail "the output does not state its own constraint"
grep -qi 'proposal, not a decision' <<<"$OUT" || fail "the output does not say it is a proposal"
pass "quick-wins states that it is a proposal and that it read no bodies"

# --- detect-resolved: anchors, and it proposes only --------------------------------
OUT_D="$(python3 "$DR" "$CTX" 2>&1)"; RC_D=$?
[[ $RC_D -eq 0 ]] || fail "detect-resolved expected exit 0, got $RC_D"
grep -q 'skills/aidex-demo/scripts/thing.sh' <<<"$OUT_D" \
  || fail "an existing cited path was not offered as an anchor"
grep -q 'gone.sh' <<<"$OUT_D" || fail "a cited path that does NOT exist was not surfaced"
grep -q 'cited but ABSENT' <<<"$OUT_D" || fail "missing paths are not labelled as absent"
pass "cited paths are split into anchors that exist and ones that do not"

# A .context/ path and a bare D-03 marker are cross-references, not code to review.
grep -q '\.context/decisions/x\.md' <<<"$OUT_D" && fail "a .context/ path was offered as a CODE anchor"
grep -q 'decision/y\.md' <<<"$OUT_D" && fail "a D-03 cross-ref marker was offered as a CODE anchor"
pass ".context/ paths and D-03 markers are excluded from the code anchors"

grep -q 'BL-002' <<<"$OUT_D" || fail "an item with no anchors should still be listed"
grep -q 'no code anchor' <<<"$OUT_D" || fail "an anchorless item is not marked as not worth a subagent"
grep -q 'BL-006' <<<"$OUT_D" && fail "a done item appeared in the work-list"
pass "anchorless items are listed but marked not worth a reviewer; closed items excluded"

grep -qi 'Nothing here closes anything' <<<"$OUT_D" \
  || fail "detect-resolved does not state that it never closes"
for f in "$CTX"/backlog/*.md; do
  grep -q '^status: ' "$f" || fail "detect-resolved damaged $f"
done
[[ "$(grep -l '^status: open' "$CTX"/backlog/*.md | wc -l | tr -d ' ')" == "5" ]] \
  || fail "detect-resolved changed a status — it must propose, never close"
pass "detect-resolved proposes: all five open items are still open afterwards"

# --- --json for both ---------------------------------------------------------------
python3 "$QW" "$CTX" --json "$WS/qw.json" >/dev/null 2>&1
python3 "$DR" "$CTX" --json "$WS/dr.json" >/dev/null 2>&1
python3 - "$WS/qw.json" "$WS/dr.json" <<'PY' || fail "--json payloads are not usable"
import json, sys
qw = json.load(open(sys.argv[1])); dr = json.load(open(sys.argv[2]))
assert [r["id"] for r in qw["order"]] == ["BL-002", "BL-003", "BL-001", "BL-004"], qw["order"]
assert [r["id"] for r in qw["blocked"]] == ["BL-005"]
assert not any("BODYMARKER" in json.dumps(r) for r in qw["order"]), "body leaked into json"
ids = {r["id"] for r in dr["items"]}
assert ids == {"BL-001", "BL-002", "BL-003", "BL-004", "BL-005"}, ids
byid = {r["id"]: r for r in dr["items"]}
assert byid["BL-001"]["checkable"] and not byid["BL-002"]["checkable"]
PY
pass "--json carries the same order and the same anchor verdicts"

# --- the SKILL.md must distinguish these from the existing `triage` ----------------
grep -qi 'health, not' "$SKILL" \
  || fail "SKILL.md does not state how these differ from triage (health, not prioritization)"
for a in 'detect-resolved' 'quick-wins'; do
  grep -q "$a" "$SKILL" || fail "SKILL.md does not document the '$a' action"
done
pass "SKILL.md documents both actions and separates them from triage"

# --- a backlog-less context is an error, not an empty clean answer ------------------
python3 "$QW" "$WS/nothing" >/dev/null 2>&1; [[ $? -eq 2 ]] || fail "quick-wins: missing backlog must exit 2"
python3 "$DR" "$WS/nothing" >/dev/null 2>&1; [[ $? -eq 2 ]] || fail "detect-resolved: missing backlog must exit 2"
pass "both exit 2 on a context with no backlog/"

if [[ $FAILURES -gt 0 ]]; then
  printf '\n%d check(s) failed\n' "$FAILURES"
  exit 1
fi
printf '\nOK — quick-wins (no body read, ordering) + detect-resolved (anchors, proposes only)\n'
