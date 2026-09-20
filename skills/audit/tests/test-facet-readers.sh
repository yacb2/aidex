#!/usr/bin/env bash
# test-facet-readers.sh — pins the two residue readers of usage-retro's facets
# (usage-retro-facets, phase 4): facets/read_artifacts.py and facets/read_sweep.py.
#
# What is guarded: each reader walks the residue its facet declares (pages under
# `.context/` incl. `_archive/`; sweep reports under `worklists/_archive/`), refuses
# to run without a projects root, groups pages by kit version band, and ends with
# its object count — from NON-EMPTY input here, and `0` with exit 0 on an empty
# tree, so a run that saw nothing is distinguishable from one that was not run.
#
# Run with: bash skills/audit/tests/test-facet-readers.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
FACETS="$HERE/../scripts/usage-retro/facets"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
C="$W/demo_ws/.context"
mkdir -p "$C/reports/_archive" "$C/reports/.aidex-artifact-prev" "$C/worklists/_archive"

# A real wrapped page embeds the kit CSS and the composer script, and BOTH mention
# `data-decided` outside any item — that is what BL-386 was over-counting.
page() {  # path kit-version consult-round
  cat > "$1" <<EOF
<title>Page</title>
<meta name="artifact-kit" content="$2">
<meta name="consult-round" content="$3">
<style>.consult-item[data-decided] { border-style: dashed; }
.consult-item[data-decided] .opts label { cursor: default; }</style>
<main class="main"><section data-id="q1" data-title="one">a</section>
<section data-id="q2" data-title="two" data-decided>b</section></main>
<script>function isDecided(el) { return el.hasAttribute('data-decided'); }</script>
EOF
}
page "$C/reports/2026-01-05-live.html" 18 2
page "$C/reports/_archive/2026-01-02-old.html" 9 1
page "$C/reports/00-index.html" 18 0                     # a rendered board, not a page
page "$C/reports/.aidex-artifact-prev/2026-01-05-live.html" 17 1   # the wrap's prior copy
# BL-385 dates: 2026-07-24 is the day the envelope checks landed (the boundary — the
# rule existed that day), and `2026-13-45` passes mine_items.PAGE but is no date at all.
page "$C/reports/2026-07-24-boundary.html" 18 0
# Inside the kit's layout container, so it reaches `rail` — a check no since-map
# entry covers (it landed 2026-09-13, after the map the backlog item fixed).
cat > "$C/reports/2026-13-45-bad.html" <<'EOF'
<title>Page</title>
<meta name="artifact-kit" content="18">
<div class="page"><main class="main"><section data-id="q1" data-title="one">a</section>
<section data-id="q2" data-title="two" data-decided>b</section></main></div>
EOF

# A figure whose label is unreadable on the page ground: `svg-contrast`, the one
# check that FAILS a named file and only WARNS in the census. The same page active
# and archived, so the severity difference is the only variable between them.
fig() {  # path
  cat > "$1" <<'EOF'
<title>Fig</title>
<meta name="artifact-kit" content="18">
<main class="main"><figure><svg viewBox="0 0 100 40">
<text x="5" y="20" font-size="10" fill="#eef0ec">pale</text></svg></figure></main>
EOF
}
fig "$C/reports/2026-09-10-fig.html"
fig "$C/reports/_archive/2026-09-10-fig-old.html"
# A PROJECT (or any ancestor) literally named `_archive` does not archive the pages
# inside it: what archives a page is its place under its own `.context/`.
mkdir -p "$W/_archive/.context/reports"
fig "$W/_archive/.context/reports/2026-09-10-fig.html"

# `siblings`: a .css or .js file next to the page (the checker reads those two
# extensions only). Dated before the checker existed, so it must read predates-rule.
mkdir -p "$C/reports/sib"
page "$C/reports/sib/2026-07-01-with-assets.html" 18 0
: > "$C/reports/sib/style.css"

# A checker that fails WITHOUT printing a parseable `FAIL [check]` — a traceback on
# stderr, a usage error, a missing interpreter. The page is not ok; it is unjudged.
STUB="$W/stub-checker.sh"
printf '#!/usr/bin/env bash\necho boom >&2\nexit 1\n' > "$STUB"

# A sweep report with the headings sweep-report.py emits (its `section()` regex is
# the contract, so a renamed heading here would be the generator's own change).
cat > "$C/worklists/_archive/2026-01-06-demo-report.md" <<'EOF'
# Sweep report — demo

## Metrics

| metric | value |
|---|---|
| items queued at kickoff | 5 |
| items closed | 2 |
| commits (from `commits:`) | 3 |
| emergent items appended | 1 |

## Closed items

### BL-901 — Alpha

### BL-904 — Delta (emergent)

## Awaiting owner — proven, parked, not closed

- BL-903 — Gamma: needs a look

## Owner rows — what only the owner can judge

## Needs decision — unchanged and unattempted

## Deferrals and mid-flight skips

- BL-902: skipped mid-flight
- BL-905: deferred

## Boundary gate — verbatim

- run 1 (2026-01-06): verdict **PASS**
  - leg=unit exit=0 count=12 secs=3
EOF

# (1) read_artifacts: two pages, bands, the board and the prior copy skipped -------
out="$(python3 "$FACETS/read_artifacts.py" --projects-root "$W" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "read_artifacts exits 0" || bad "read_artifacts rc=$rc: $out"
[[ "$(tail -1 <<<"$out")" == "pages processed: 8" ]] \
  && ok "pages processed: 8 is the LAST line (board and prior copy skipped)" \
  || bad "count line: $(tail -1 <<<"$out")"
# Every column, checker-ok included: no page in this fixture passes the contract, and
# nothing read that last column until a fail-open bug lived in it.
grep -Eq '^v9 +1 +1 +1 +2 +1 +0$' <<<"$out" && ok "v9 band: 1 page, archived, consult, 2 items, 1 decided, 0 ok" \
  || bad "v9 band row missing: $out"
grep -Eq '^v18 +7 +1 +1 +8 +4 +0$' <<<"$out" \
  && ok "v18 band: 7 pages, 1 archived (the _archive-named project is not), 8 items, 4 decided, 0 ok" \
  || bad "v18 band row missing: $out"
# BL-386: `data-decided` in the kit CSS and the composer script is not an item's attribute.
over="$(awk '/^(v[0-9]+|pre-wrapper)[[:space:]]/ && $6 > $5' <<<"$out")"
[[ -z "$over" ]] && ok "decided never exceeds items on a band row" \
  || bad "decided > items (token counted outside an item): $over"
# The round of each page, not only how many pages carry one.
grep -Eq '^round 2: .*2026-01-05-live\.html' <<<"$out" \
  && ok "the consult round is reported per page" || bad "per-page round line missing: $out"
# Every page lacks the kit envelope, so the checker fails them; the finding names the band range.
grep -Eq '^fail \[doctype\]: 8 page\(s\), v9–v18$' <<<"$out" \
  && ok "a checker failure is reported with its version band range" \
  || bad "band-ranged failure line missing: $out"

# BL-385: every failure line carries the page's date and its verdict against the
# check's since date, so predates-rule vs defect is read off the run.
grep -Fq 'fail [doctype] 2026-01-02 predates-rule (since 2026-07-24): ' <<<"$out" \
  && ok "a page older than the check is labelled predates-rule, with its date" \
  || bad "predates-rule line missing: $out"
grep -Fq 'fail [svg-contrast] 2026-09-10 defect (since 2026-09-07): ' <<<"$out" \
  && ok "a page younger than the check is labelled defect, with its date" \
  || bad "defect line missing: $out"
# The boundary: the rule landed that day, so the page had it.
grep -Fq 'fail [doctype] 2026-07-24 defect (since 2026-07-24): ' <<<"$out" \
  && ok "a page dated exactly on the since date is a defect, not predates-rule" \
  || bad "boundary line missing: $out"
grep -Fq 'fail [doctype] undated defect (since 2026-07-24): ' <<<"$out" \
  && ok "a page whose basename digits are no date is undated and a defect" \
  || bad "undated line missing: $out"
# A check the map does not carry cannot be claimed to postdate any page.
grep -Fq 'fail [rail] undated defect (no since date): ' <<<"$out" \
  && ok "a check absent from the since-map is a defect, and says so" \
  || bad "unmapped-check line missing: $out"

# Census severity: `svg-contrast` fails the active page and is only advisory on the
# archived one — the page the census leaves alone.
grep -Eq '^advisory \[svg-contrast\] 2026-09-10 \(census severity, archived\): .*2026-09-10-fig-old\.html$' <<<"$out" \
  && ok "svg-contrast on an _archive/ page is graded at census severity" \
  || bad "advisory line missing: $out"
grep -Fq 'fail [svg-contrast] 2026-09-10 defect (since 2026-09-07): '"$C/reports/_archive/2026-09-10-fig-old.html" <<<"$out" \
  && bad "svg-contrast still fails an archived page at wrap severity: $out" \
  || ok "an archived page does not fail on a census-advisory check"
# An ANCESTOR named `_archive` is not an archive: the page is active, at wrap severity.
grep -Fq 'fail [svg-contrast] 2026-09-10 defect (since 2026-09-07): '"$W/_archive/.context/reports/2026-09-10-fig.html" <<<"$out" \
  && ok "a page under a project named _archive keeps wrap severity" \
  || bad "the _archive-named project was demoted to census severity: $out"

# `siblings` is a check of the same 2026-07-24 commit, so a page older than it predates it.
grep -Fq 'fail [siblings] 2026-07-01 predates-rule (since 2026-07-24): ' <<<"$out" \
  && ok "siblings carries its since date, and an older page predates it" \
  || bad "siblings since-date line missing: $out"

# A checker that fails without a parseable FAIL line leaves the page UNJUDGED, never ok.
stub_out="$(python3 "$FACETS/read_artifacts.py" --projects-root "$W" --checker "$STUB" 2>/dev/null)"
[[ "$(tail -1 <<<"$stub_out")" == "pages processed: 8" ]] \
  && ok "a checker with no sibling module still ends with the count line" \
  || bad "the reader died before its count line: $(tail -1 <<<"$stub_out")"
awk '/^(v[0-9]+|pre-wrapper)[[:space:]]/ && $7 != 0 { exit 1 }' <<<"$stub_out" \
  && ok "a checker that exits non-zero with no FAIL line counts 0 pages checker-ok" \
  || bad "fail-open: an unjudged page counted as checker-ok: $stub_out"

# (2) read_sweep: one report, counts from its sections ----------------------------
out="$(python3 "$FACETS/read_sweep.py" --projects-root "$W" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "read_sweep exits 0" || bad "read_sweep rc=$rc: $out"
[[ "$(tail -1 <<<"$out")" == "reports processed: 1" ]] \
  && ok "reports processed: 1 is the LAST line" || bad "count line: $(tail -1 <<<"$out")"
grep -Eq '^2026-01-06-demo-report.md +5 +2 +1 +1 +2 +1 +PASS$' <<<"$out" \
  && ok "row: queued 5, closed 2, emergent 1, awaiting 1, deferrals 2, 1 gate run PASS" \
  || bad "report row wrong: $out"

# (3) both refuse to run rootless -------------------------------------------------
for r in read_artifacts read_sweep; do
  out="$(env -u AIDEX_PROJECTS_ROOT python3 "$FACETS/$r.py" 2>&1)"; rc=$?
  [[ $rc -ne 0 && "$out" == *"no projects root"* ]] && ok "$r refuses without --projects-root" \
    || bad "$r ran rootless (rc=$rc): $out"
done

# (4) an empty tree prints 0 and exits 0 -----------------------------------------
E="$(mktemp -d)"; mkdir -p "$E/p/.context"
for r in read_artifacts:pages read_sweep:reports; do
  out="$(python3 "$FACETS/${r%%:*}.py" --projects-root "$E" 2>&1)"; rc=$?
  [[ $rc -eq 0 && "$(tail -1 <<<"$out")" == "${r##*:} processed: 0" ]] \
    && ok "${r%%:*} on an empty tree says 0 and exits 0" || bad "${r%%:*} empty tree rc=$rc: $out"
done
rm -rf "$E"

echo "facet readers: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
