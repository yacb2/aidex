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

page() {  # path kit-version consult-round
  cat > "$1" <<EOF
<title>Page</title>
<meta name="artifact-kit" content="$2">
<meta name="consult-round" content="$3">
<main class="main"><section data-id="q1" data-title="one">a</section>
<section data-id="q2" data-title="two" data-decided>b</section></main>
EOF
}
page "$C/reports/2026-01-05-live.html" 18 2
page "$C/reports/_archive/2026-01-02-old.html" 9 1
page "$C/reports/00-index.html" 18 0                     # a rendered board, not a page
page "$C/reports/.aidex-artifact-prev/2026-01-05-live.html" 17 1   # the wrap's prior copy

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
[[ "$(tail -1 <<<"$out")" == "pages processed: 2" ]] \
  && ok "pages processed: 2 is the LAST line (board and prior copy skipped)" \
  || bad "count line: $(tail -1 <<<"$out")"
grep -Eq '^v9 +1 +1 +1 +2 +1' <<<"$out" && ok "v9 band: 1 page, archived, consult, 2 items, 1 decided" \
  || bad "v9 band row missing: $out"
grep -Eq '^v18 +1 +0 +1 +2 +1' <<<"$out" && ok "v18 band: 1 page, active" || bad "v18 band row missing: $out"
# Both pages lack the kit envelope, so the checker fails them; the finding names the band range.
grep -Eq '^fail \[[^]]+\]: 2 page\(s\), v9–v18$' <<<"$out" \
  && ok "a checker failure is reported with its version band range" \
  || bad "band-ranged failure line missing: $out"

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
