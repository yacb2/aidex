#!/usr/bin/env bash
# test-escalation-gate.sh — USAGE-30: a batch escalation (several ids in one call, or a
# second escalation within 10 minutes) is refused without --page naming a consultation
# page (the artifact kit's <meta name="artifact-kit"> stamp AND a consult-group, citing
# every id as a whole token; it may live under .context/audits/); a single escalation is
# unchanged; a partial batch escalates nothing; the window slot is reserved under a lock.
# Layer: script-level, real sibling scripts. Run: bash skills/audit/tests/test-escalation-gate.sh

set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_STATE_HOME="$TMP/state"
PROJ="$TMP/proj"
mkdir -p "$PROJ/.context/audits/ux/2026-06-01-first-pass" "$PROJ/.context/backlog"
cd "$PROJ"
A=".context/audits"
cat > "$A/ux/00-inventory.md" <<'INV'
| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| F-1 | bug | auth | Token stored in URL | open | P1 | 2026-06-01 | — | — |
| F-2 | gap | a11y | Contrast below AA across app | open | P2 | 2026-06-01 | — | — |
| F-3 | gap | nav | Menu unreachable by keyboard | open | P2 | 2026-06-01 | — | — |
| F-4 | gap | nav | Focus ring missing | done | P2 | 2026-06-01 | backlog/x | — |
| F-5 | gap | nav | Race one | open | P2 | 2026-06-01 | — | — |
| F-6 | gap | nav | Race two | open | P2 | 2026-06-01 | — | — |
| F-7 | gap | nav | Window probe | open | P2 | 2026-06-01 | — | — |
INV
echo "# m" > "$A/ux/00-methodology.md"; echo "# c" > "$A/ux/00-changelog.md"
printf -- '---\ntitle: "UX first pass"\nstatus: done\ncreated: 2026-06-01\nupdated: 2026-06-01\nmethodology: ux\n---\n' > "$A/ux/2026-06-01-first-pass/index.md"
printf '# Findings\n\n- **F-1** a\n- **F-2** b\n- **F-3** c\n- **F-4** d\n- **F-5** e\n- **F-6** f\n- **F-7** g\n' > "$A/ux/2026-06-01-first-pass/findings.md"
WRAP="$(cd "$SCRIPTS/../../artifact/scripts" && pwd -P)/wrap-report.sh"
# Real kit output: a consult page built by wrap-report.sh, citing the given ids.
kit_page() { # <out.html> <id>...
  local out="$1"; shift
  { printf '<meta name="consult-visual" content="none: a fixture has no shape to draw">\n<div class="page"><main class="main">\n<header><h1>Probe</h1><p class="standfirst">Findings.</p></header>\n'
    printf '<section class="consult-group" id="G1" data-id="G1" data-title="Findings"><div class="sec-head"><h2>Findings</h2></div><p>Shared context.</p>\n'
    local i=0 id; for id in "$@"; do i=$((i+1))
      printf '<section class="consult-item" data-id="c%s" data-free data-title="Escalate %s"><h3>Escalate %s?</h3><p class="fieldlabel">Why</p><textarea></textarea></section>\n' "$i" "$id" "$id"; done
    printf '<div class="group-notes"><p class="fieldlabel">Block notes</p><textarea></textarea></div></section>\n<section class="consult-item consult-notes" data-id="notes" data-title="Notes"><h3>Notes</h3><p class="fieldlabel">Anything else</p><textarea></textarea></section>\n'
    printf '<div class="endbar"><button type="button" id="consult-copy-end">Copy</button><span class="consult-status" id="consult-status-end"></span></div>\n'
    printf '<aside class="rail"><div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div></aside>\n'
    printf '<section id="sec-ref"><div class="sec-head"><h2>Source</h2></div><p>Measured.</p></section>\n</main><aside class="rail"><p class="railhead">Contents</p><nav class="raillist" id="raillist"></nav></aside></div>\n'
  } > "$out.body"
  bash "$WRAP" --title "Probe" --lang en --in "$out.body" --out "$out" >/dev/null 2>"$out.err" \
    || { fail "fixture build failed: $(tail -3 "$out.err")"; return 1; }
}
kit_page page.html F-1 F-2
kit_page partial.html F-1
kit_page token.html F-10 F-2
kit_page dotted.html F-1.2 F-2
kit_page withdone.html F-1 F-2 F-4
kit_page "$A/ux/consult.html" F-1 F-2
kit_page f3.html F-3
printf '# spec\n' > f3.spec.md
printf '# spec\n' > only.spec.md
# A board render: GENERATED stamp, no kit meta, no consult-group (inventory 00-index.html shape).
printf '<!-- GENERATED 2026-10-04T00:00:00Z by /aidex:artifact audit — DO NOT EDIT, regenerate instead -->\n<html><body>F-1 F-2</body></html>\n' > board.html
cp board.html "$A/ux/00-index.html"
printf '<html>F-1 F-2 hand-written</html>\n' > nohdr.html
printf '<section class="consult-group">F-1 F-2</section>\n' > group-only.html
# (b) real kit output with a plain section and no consult-group
printf '<div class="page"><main class="main"><header><h1>Probe</h1></header><section id="s1"><div class="sec-head"><h2>Findings</h2></div><p>F-1 F-2</p></section></main></div>\n' > plain.body
bash "$WRAP" --title "Probe" --lang en --in plain.body --out plain.html >/dev/null 2>plain.err || fail "plain fixture build failed: $(tail -3 plain.err)"

open_rows() { grep -cE '^\| F-[123] .*\| open \|' "$A/ux/00-inventory.md"; }
backlog_count() { ls .context/backlog/*.md 2>/dev/null | grep -vc 00-index; }
STATE="$XDG_STATE_HOME/aidex/escalation-log"

refused() { # <label> <expected-msg-fragment> args...
  local label="$1" frag="$2"; shift 2
  local out rc
  out="$(bash "$SCRIPTS/escalate-finding.sh" "$@" 2>&1)"; rc=$?
  [[ $rc -ne 0 ]] || fail "$label: should be refused"
  [[ "$out" == *"$frag"* ]] || fail "$label: message should contain '$frag', got: $out"
  [[ "$(open_rows)" == "3" ]] || fail "$label: rows must stay open"
  [[ "$(backlog_count)" == "0" ]] || fail "$label: no backlog file may be created"
}

refused "batch without page" "/aidex:artifact" F-1 F-2
refused "page missing an id" "does not cite" F-1 F-2 --page partial.html
refused "hand-written page" "consultation page" F-1 F-2 --page nohdr.html
refused "board render with GENERATED stamp" "consultation page" F-1 F-2 --page board.html
refused "board render under .context/audits" "consultation page" F-1 F-2 --page "$A/ux/00-index.html"
refused "consult-group without the kit meta" "consultation page" F-1 F-2 --page group-only.html
refused "kit page without a consult-group" "consultation page" F-1 F-2 --page plain.html
refused "dotted id is not the id" "does not cite" F-1 F-2 --page dotted.html
refused "spec.md without built html" "consultation page" F-1 F-2 --page only.spec.md
refused "substring id match" "does not cite" F-1 F-2 --page token.html
refused "batch with an already-done id" "already done" F-1 F-2 F-4 --page withdone.html

# --page as the last arg: exit 2, no hang
perl -e 'alarm 20; exec @ARGV' bash "$SCRIPTS/escalate-finding.sh" F-1 --page >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] || fail "--page without a value should exit 2, got $rc"

# concurrency: two singles at once with no page; the window slot is reserved atomically,
# so exactly one escalates and the other is refused naming /aidex:artifact
bash "$SCRIPTS/escalate-finding.sh" F-5 >"$TMP/r5.out" 2>&1 &
bash "$SCRIPTS/escalate-finding.sh" F-6 >"$TMP/r6.out" 2>&1 &
wait
done56="$(grep -cE '^\| F-[56] .*\| done \|' "$A/ux/00-inventory.md")"
[[ "$done56" == "1" ]] || fail "two concurrent singles: exactly one should escalate, got $done56"
[[ "$(cat "$TMP/r5.out" "$TMP/r6.out")" == *"/aidex:artifact"* ]] || fail "the loser should be refused naming /aidex:artifact"
LOGF="$(ls "$STATE"/* 2>/dev/null | grep -v '\.lock$' | sed -n 1p)"
[[ -n "$LOGF" ]] || fail "log should live under XDG state"
[[ -z "$(ls "$A"/.escalation-log 2>/dev/null)" ]] || fail "log must not live in the committed tree"
[[ ! -d "$LOGF.lock" ]] || fail "lock must be released"

# lock: a fresh planted lock refuses (row untouched); one aged past 60 s is taken over
mkdir "$LOGF.lock"
out="$(bash "$SCRIPTS/escalate-finding.sh" F-7 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"could not take the escalation lock"* ]] || fail "fresh planted lock should refuse (rc=$rc): $out"
grep -qE '^\| F-7 .*\| open \|' "$A/ux/00-inventory.md" || fail "refused-by-lock must leave F-7 open"
touch -t 202001010000 "$LOGF.lock"
seed_old() { date +%s | awk '{print $1-900 " seed"}' > "$LOGF"; }
seed_old
out="$(bash "$SCRIPTS/escalate-finding.sh" F-7 2>&1)"; rc=$?
[[ $rc -eq 0 && "$out" == *"stale escalation lock"* ]] || fail "stale lock should be taken over with a message (rc=$rc): $out"
grep -qE '^\| F-7 .*\| done \|' "$A/ux/00-inventory.md" || fail "F-7 should escalate after the takeover"
[[ ! -d "$LOGF.lock" ]] || fail "lock must be released after the takeover"
sed -i.bak 's/^\(| F-7 .*\)| done |/\1| open |/' "$A/ux/00-inventory.md"; rm -f "$A"/ux/*.bak

# duplicate ids are one finding: "F-1 F-1 F-2 --page" escalates both rows
bash "$SCRIPTS/escalate-finding.sh" F-1 F-1 F-2 --page page.html >/dev/null 2>&1 || fail "duplicate ids with a page should be accepted"
[[ "$(open_rows)" == "1" ]] || fail "duplicate-id batch should escalate F-1 and F-2 once"
sed -i.bak -E 's/^(\| F-[12] .*)\| done \|/\1| open |/' "$A/ux/00-inventory.md"; rm -f "$A"/ux/*.bak

# accepted: a real kit consult page, including one that lives under .context/audits/
bash "$SCRIPTS/escalate-finding.sh" F-1 F-2 --page "$A/ux/consult.html" >/dev/null 2>&1 || fail "batch with a kit consult page under .context/audits should be accepted"
[[ "$(open_rows)" == "1" ]] || fail "accepted batch should escalate both"

# window, with margins: 300 s old still counts (page needed), 900 s old does not
seed() { date +%s | awk -v a="$1" '{print $1-a " seed"}' > "$LOGF"; }
seed 300
out="$(bash "$SCRIPTS/escalate-finding.sh" F-3 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"/aidex:artifact"* ]] || fail "escalation 300 s after the last one needs a page (rc=$rc): $out"
[[ "$(open_rows)" == "1" ]] || fail "refused window escalation must leave F-3 open"
# a .spec.md page whose built .html sibling is a kit page is accepted inside the window
bash "$SCRIPTS/escalate-finding.sh" F-3 --page f3.spec.md >/dev/null 2>&1 || fail ".spec.md page with a kit .html sibling should be accepted"
[[ "$(open_rows)" == "0" ]] || fail "F-3 should be escalated via the .spec.md page"
seed 900
bash "$SCRIPTS/escalate-finding.sh" F-7 >/dev/null 2>&1 || fail "single escalation 900 s after the last one should pass"
grep -qE '^\| F-7 .*\| done \|' "$A/ux/00-inventory.md" || fail "F-7 should be escalated"

bash "$SCRIPTS/validate-audit.sh" "$A" >/dev/null 2>&1 || fail "tree should still validate"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — batch gate: kit stamp, board refused, tokens, done ids, missing value, concurrency, window, log location"
