#!/usr/bin/env bash
# The kit builds a page that passes the artifact contract.
#
# Phase 3's acceptance is "a page built from the skeleton alone passes
# check-artifact.sh". `tests/run-all.sh` cannot see that on its own — it knows
# nothing about the kit — so without this test the phase is verified by a suite
# that never looked at it, which is the lie-by-omission the whole plan is about.
#
# It also pins the four places where the kit and check-artifact.sh are in
# lockstep. Each one looks like decoration and is not:
#   1. `blank` is the identifier the composer scan greps for (comments stripped).
#   2. `:root[data-theme="dark"] .consult-bar` must stay ONE selector — the check
#      is `grep -qE 'data-theme="dark"[^{]*consult-bar'`, so no `{` may fall
#      between the two tokens.
#   3. `id="consult-copy"` / `id="consult-status"` are literal greps including
#      the closing quote; the `-end` variants do not satisfy them.
#   4. reply boxes, `data-id` and `data-title` are counted against each other, so
#      the skeleton must not name `data-id` in a comment either — the grep cannot
#      tell markup from prose.
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIT="$SKILL/assets/artifact-kit"
WRAP="$SKILL/scripts/wrap-report.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

for f in tokens.css components.css composer.js skeleton.html VERSION; do
  [[ -s "$KIT/$f" ]] || fail "kit is missing $f (or it is empty)"
done
[[ "$failures" -eq 0 ]] || { echo "$failures failure(s)"; exit 1; }

# ---------- lockstep with check-artifact.sh --------------------------------
grep -q 'blank' "$KIT/composer.js" \
  || fail "composer.js never says 'blank' — the contract's composer scan reads the identifier, not the display text"
tr -d '\n' < "$KIT/components.css" | grep -qE 'data-theme="dark"[^{]*consult-bar' \
  || fail "components.css lost the :root[data-theme=\"dark\"] .consult-bar rule, or split it across selectors"
grep -q 'id="consult-copy"' "$KIT/skeleton.html" \
  || fail "skeleton.html has no id=\"consult-copy\" (the -end variant does not satisfy the contract)"
grep -q 'id="consult-status"' "$KIT/skeleton.html" \
  || fail "skeleton.html has no id=\"consult-status\""
n_area="$(grep -oiE '<textarea|contenteditable=' "$KIT/skeleton.html" | wc -l | tr -d ' ')"
n_id="$(grep -oiE 'data-id=' "$KIT/skeleton.html" | wc -l | tr -d ' ')"
n_title="$(grep -oiE 'data-title=' "$KIT/skeleton.html" | wc -l | tr -d ' ')"
[[ "$n_area" == "$n_id" && "$n_id" == "$n_title" ]] \
  || fail "skeleton counts disagree: $n_area reply box(es), $n_id data-id, $n_title data-title"

# ---------- a page built from the skeleton passes the contract -------------
# Assembled by INLINING. Copying the .css/.js next to the output would trip the
# contract's own `siblings` rule, which scans the report's directory at depth 1.
OUT="$TMP/reports/kit-smoke.html"
mkdir -p "$TMP/reports"
{
  printf '<style>\n'; cat "$KIT/tokens.css"; printf '</style>\n'
  printf '<style>\n'; cat "$KIT/components.css"; printf '</style>\n'
  cat "$KIT/skeleton.html"
  printf '\n<script>\n'; cat "$KIT/composer.js"; printf '</script>\n'
} > "$TMP/body.html"

out="$(bash "$WRAP" --title "Kit smoke" --in "$TMP/body.html" --out "$OUT" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "wrapping the skeleton failed (exit $rc): $out"
grep -q 'artifact contract OK' <<<"$out" \
  || fail "the wrapped skeleton does not pass the artifact contract: $out"

# The kit is injected, never linked: the page must stand alone offline.
[[ -f "$OUT" ]] && {
  grep -qiE '<link[^>]+stylesheet|<script[^>]+src=' "$OUT" \
    && fail "the built page links an external asset instead of inlining it"
  grep -q 'prefers-color-scheme' "$OUT" \
    || fail "the built page has no prefers-color-scheme — tokens.css did not make it in"
}

# ---------- the composer speaks the page's language, not one hard-coded ----
# The kit ships to every project; only the project carries a language. Spanish
# display strings baked into the suite would ship Spanish to all of them.
grep -q "document.documentElement.lang" "$KIT/composer.js" \
  || fail "composer.js does not read <html lang> — its display strings are hard-coded to one language"
for key in en es; do
  grep -qE "^\s*$key: \{" "$KIT/composer.js" \
    || fail "composer.js has no '$key' entry in its strings table"
done

[[ "$failures" -eq 0 ]] || { echo "$failures failure(s)"; exit 1; }
echo "OK — the kit builds a page that passes the artifact contract, and stays in lockstep with it"
