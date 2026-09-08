#!/usr/bin/env bash
# test-markdown-wrap.sh — `wrap-report.sh --in <file>.md` renders the markdown a
# close-out already writes into a page that passes the artifact contract.
#
# BL-345: a run's close-out emits a durable `.md` (sweep-report.sh's companion,
# plan-exec's human-verification.md) and nothing wrapped it, so the reader asked
# for the page every time. wrap-report.sh consumed page CONTENT — styles and
# markup — and there was no markdown renderer anywhere in dash, so "wrap the
# report" had no mechanism. This pins the one that was added.
#
# Two properties, and the second is the one that would rot silently:
#   1. the page passes check-artifact.sh — kit layout container, tables inside a
#      scrolling wrapper, no consultation battery on a page that asks nothing.
#   2. the markdown is DATA, never markup. Backlog titles and proof cells are
#      author-written text that reaches this renderer verbatim; a title carrying
#      `<script>` must land as text. The mutation below is what keeps assertion 2
#      from passing vacuously: it injects the tag and requires the escaped form.
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
WRAP="$SKILL/scripts/wrap-report.sh"
CHECK="$SKILL/scripts/check-artifact.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
ok()   { printf 'ok   — %s\n' "$*"; }

[[ -x "$WRAP" && -x "$CHECK" ]] || { echo "FAIL: wrap-report.sh / check-artifact.sh not executable"; exit 1; }

# ---------- a report of the shape sweep-report.py emits ----------------------
cat > "$TMP/report.md" <<'MD'
---
title: "Sweep report — probe"
status: done
created: 2026-09-08
---

# Sweep report — probe

Generated from disk on 2026-09-08; anchored to `worklist/probe.md`.

## Metrics

| metric | value |
|---|---|
| items closed | 3 |
| commits | 7 |

## Closed items

### BL-001 — a title with **bold** and `code`

- estimate `S` · surface `ops` · commits: `abc1234`

| kind | what | proof |
|---|---|---|
| test | the suite | 141 passed |

## Awaiting owner

_none_
MD

out="$(bash "$WRAP" --title "Sweep report — probe" --lang en \
       --in "$TMP/report.md" --out "$TMP/report.html" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || fail "wrap of a .md exited $rc: $out"
[[ -s "$TMP/report.html" ]] || fail "no page written from the .md"

bash "$CHECK" "$TMP/report.html" >"$TMP/check.out" 2>&1; crc=$?
[[ $crc -eq 0 ]] && ok "a wrapped .md passes check-artifact.sh" \
  || fail "check-artifact.sh exited $crc on the wrapped .md: $(cat "$TMP/check.out")"

# The markdown actually became markup, rather than being wrapped verbatim.
grep -q '<table' "$TMP/report.html" || fail "the pipe table did not become a <table>"
grep -q '<h2' "$TMP/report.html" || fail "'## Metrics' did not become an <h2>"
grep -q '<h3' "$TMP/report.html" || fail "'### BL-001 …' did not become an <h3>"
grep -q '<li>' "$TMP/report.html" || fail "the '- ' bullet did not become a list item"
grep -q '<code>' "$TMP/report.html" || fail "backticked spans did not become <code>"
grep -q '<strong>' "$TMP/report.html" || fail "**bold** did not become <strong>"
grep -q 'class="tw"' "$TMP/report.html" || fail "the table is not inside the kit's .tw scroll wrapper"
grep -qE 'class="[^"]*\bmain\b' "$TMP/report.html" || fail "no .main — the page renders full-bleed"
grep -q '^| metric | value |' "$TMP/report.html" && fail "the markdown was emitted verbatim, not rendered"
grep -q '^---$' "$TMP/report.html" && fail "the YAML front matter leaked into the page"
[[ $failures -eq 0 ]] && ok "headings, tables, lists and inline spans render as markup"

# ---------- the mutation: markdown is data, never markup --------------------
# Without this the escaping assertion could pass on a report that simply never
# contained a tag. Inject one and require it to come back as text.
sed 's/a title with \*\*bold\*\*/a title with <script>alert(1)<\/script>/' \
  "$TMP/report.md" > "$TMP/evil.md"
grep -q '<script>alert(1)</script>' "$TMP/evil.md" \
  || fail "the mutation did not land in the fixture — the escaping assertion would be vacuous"

bash "$WRAP" --title "Evil" --lang en --in "$TMP/evil.md" --out "$TMP/evil.html" >/dev/null 2>&1
if grep -q 'alert(1)' "$TMP/evil.html" && ! grep -q '<script>alert(1)</script>' "$TMP/evil.html"; then
  ok "a tag in the markdown lands as text, not as markup"
else
  fail "a <script> in the report body reached the page as markup (or vanished entirely)"
fi

# ---------- --lang wins over the project profile (BL-279) --------------------
# The report body is `.context/` English (D-04) even in a project whose artifacts
# are Spanish, so the close-out passes --lang en explicitly. If the profile could
# win, the page would be stamped lang="es" over an English body and fail `lang`.
mkdir -p "$TMP/proj/.context"
: > "$TMP/proj/.context/.aidex-root"
printf -- '- language: es\n' > "$TMP/proj/.context/artifact-style.md"
cp "$TMP/report.md" "$TMP/proj/report.md"
bash "$WRAP" --title "Lang probe" --lang en --in "$TMP/proj/report.md" \
     --out "$TMP/proj/.context/report.html" >/dev/null 2>&1
grep -q '<html lang="en"' "$TMP/proj/.context/report.html" \
  && ok "--lang en overrides an artifact-style.md that says es" \
  || fail "--lang did not override the profile language: $(grep -o '<html lang="[a-z]*"' "$TMP/proj/.context/report.html" | head -1)"

[[ $failures -eq 0 ]] && echo "OK — markdown wraps into a contract-passing page ($(wc -c < "$TMP/report.html" | tr -d ' ') bytes)"
exit $(( failures > 0 ))
