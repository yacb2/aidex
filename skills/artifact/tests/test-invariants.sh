#!/usr/bin/env bash
# test-invariants.sh — render-probe.sh --invariants against tests/invariants/catalog.md:
# every catalog id has a RED fixture that yields exactly that id (and no other), the
# GREEN fixtures yield nothing, and the line shape and exit codes hold. Fixtures are page
# BODIES wrapped here with the real wrap-report.sh (to stdout: the contract is not asked,
# the defect is the point), so each run probes today's kit.
#
# Needs Playwright (AIDEX_PLAYWRIGHT_DIR or a global install); without it prints SKIP and
# exits 2 (run-all.sh reports a skip, never a pass).
# Run with: bash skills/artifact/tests/test-invariants.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPTS="$(cd "$HERE/../scripts" && pwd -P)"
PROBE="$SCRIPTS/render-probe.sh"
FIX="$HERE/fixtures/invariants"
CATALOG="$HERE/invariants/catalog.md"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

have=0
[[ -n "${AIDEX_PLAYWRIGHT_DIR:-}" && -f "$AIDEX_PLAYWRIGHT_DIR/node_modules/playwright/package.json" ]] && have=1
g="$(npm root -g 2>/dev/null || true)"
[[ -n "$g" && -f "$g/playwright/package.json" ]] && have=1
if [[ $have -eq 0 ]]; then
  echo "SKIP: Playwright not found (set AIDEX_PLAYWRIGHT_DIR or npm i -g playwright)"
  exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ids="$(awk -F'|' '/^\| [A-Z]+-[0-9]+ \|/ { gsub(/ /, "", $2); print $2 }' "$CATALOG")"
[[ -n "$ids" ]] && ok "catalog lists $(wc -l <<<"$ids" | tr -d ' ') invariants" || bad "no catalog rows"

echo "== the probe's composer-chrome list is composer.js's questionHash list =="
want="$(grep -o "querySelectorAll('\.kit-tag, [^']*'" "$HERE/../assets/artifact-kit/composer.js" | head -1 | sed "s/querySelectorAll('//; s/'$//")"
grep -qF "const CHROME = '$want, details.opts-more > summary';" "$SCRIPTS/render-probe.mjs" \
  && ok "CHROME list matches composer.js" || bad "CHROME list drifted from composer.js questionHash: [$want]"

echo "== wrap every fixture with the kit =="
# A fixture whose first line is `<!-- wrap-lang: en -->` is wrapped in that language, else es.
for f in "$FIX"/*.html; do
  n="$(basename "$f" .html)"; lang=es
  head -1 "$f" | grep -q '^<!-- wrap-lang: en -->' && lang=en
  ( cd "$TMP" && bash "$SCRIPTS/wrap-report.sh" --title "$n" --lang "$lang" --in "$f" > "$TMP/$n.html" 2>/dev/null ) \
    || bad "wrap-report failed on $n"
done

echo "== each RED fixture yields its id and only its id =="
for id in $ids; do
  [[ -f "$TMP/$id.html" ]] || { bad "$id has no RED fixture"; continue; }
  out="$(bash "$PROBE" --invariants "$TMP/$id.html" 2>&1)"; rc=$?
  got="$(grep '^INV ' <<<"$out" | awk '{print $2}' | sort -u | tr '\n' ' ')"
  [[ $rc -eq 1 && "$got" == "$id " ]] && ok "$id: RED" || bad "$id: exit $rc, ids [$got]: $out"
  grep -q "^INV $id $id.html " <<<"$out" && grep -q '^INVARIANTS pages=1 violations=[1-9]' <<<"$out" \
    || bad "$id: line shape wrong: $out"
done

echo "== reviewer counterexamples (<ID>.<tag>.html) yield their id and only it =="
for f in "$FIX"/*.*.html; do
  n="$(basename "$f" .html)"; id="${n%%.*}"
  out="$(bash "$PROBE" --invariants "$TMP/$n.html" 2>&1)"; rc=$?
  got="$(grep '^INV ' <<<"$out" | awk '{print $2}' | sort -u | tr '\n' ' ')"
  [[ $rc -eq 1 && "$got" == "$id " ]] && ok "$n: $id" || bad "$n: exit $rc, ids [$got]: $out"
done

echo "== each GREEN fixture yields nothing =="
for f in "$FIX"/green-*.html; do
  n="$(basename "$f" .html)"
  out="$(bash "$PROBE" --invariants "$TMP/$n.html" 2>&1)"; rc=$?
  [[ $rc -eq 0 && "$out" == "INVARIANTS pages=1 violations=0" ]] && ok "$n: clean" || bad "$n: exit $rc: $out"
done

echo "== several pages: one summary line, exit 1 =="
out="$(bash "$PROBE" --invariants "$TMP/green-presentation.html" "$TMP/NAV-7.html" 2>&1)"; rc=$?
[[ $rc -eq 1 && "$(tail -1 <<<"$out")" == "INVARIANTS pages=2 violations=1" ]] && ok "pages=2 violations=1" || bad "multi-page: exit $rc: $out"

echo "== --invariants is its own mode =="
for flag in "--shots $TMP/nodir" "--contract text-style-drift"; do
  out="$(bash "$PROBE" --invariants $flag "$TMP/green-presentation.html" 2>&1)"; rc=$?
  [[ $rc -eq 2 ]] && ok "--invariants with ${flag%% *} exits 2" || bad "--invariants $flag: exit $rc: $out"
done
[[ ! -e "$TMP/nodir" ]] && ok "the refused --shots made no directory" || bad "--shots dir was created"

echo "== the default mode is unchanged =="
out="$(bash "$PROBE" "$TMP/green-presentation.html" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && grep -q '^render-probe: clean' <<<"$out" && ! grep -q INVARIANTS <<<"$out" \
  && ok "no --invariants: geometry run, no INV lines" || bad "default mode changed: exit $rc: $out"

echo "$PASS ok, $FAIL failed"
[[ $FAIL -eq 0 ]]
