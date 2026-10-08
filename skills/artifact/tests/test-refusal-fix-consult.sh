#!/usr/bin/env bash
# test-refusal-fix-consult.sh — the spec builder repairs, or names precisely, the
# four refusals a first consultation spec meets (LOOP-009 Phase C): missing
# general-notes block, an item title that repeats its id, `section title=`,
# and a masthead with no visual=. check_artifact stays exactly as strict; the
# HTML route (a page with no notes) still FAILs.
#
# Layer: integration over the real spec_build.py and check-artifact.sh.
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$SKILL/scripts/check-artifact.sh"
BUILD="$SKILL/scripts/spec_build.py"
export TESTS_DIR="$SKILL/tests"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
ok()   { printf 'ok   — %s\n' "$*"; }

n=0
# $1 masthead attrs, $2 item title, $3 extra spec text, $4 include notes (1/0)
mkspec() {
  n=$((n + 1)); D="$TMP/c$n/.context/reports"; mkdir -p "$D"
  SPEC="$D/p.spec.md"; PAGE="$D/p.html"
  {
    printf '::: masthead {%s}\nUna pregunta.\n:::\n\n' "$1"
    printf '::: group {#G1 title="Grupo"}\n::: item {#Q1 title="%s"}\n¿Seguimos?\n\n- Sí {recommended}\n- No\n:::\n:::\n\n' "$2"
    [ "${4:-0}" = 1 ] && printf '::: notes {title="Notas generales"}\n:::\n\n'
    printf '%s\n' "$3"
  } > "$SPEC"
}
build() { python3 "$BUILD" "$SPEC" -o "$PAGE" >"$TMP/out" 2>&1; }
V='visual="none: una sola pregunta, nada que dibujar" title="T"'

# 1. notes added, announced, page passes; English page gets the English title
mkspec "$V" "¿Seguimos?" "" 0
if build && bash "$CHECK" "$PAGE" >"$TMP/o" 2>&1 \
   && grep -q "added the general-notes block" "$TMP/out" \
   && grep -q 'class="consult-item consult-notes"' "$PAGE" && grep -q 'Notas generales' "$PAGE"; then
  ok "1. a spec without notes builds with one, says so, and passes check-artifact"
else fail "1. $(cat "$TMP/out" "$TMP/o" 2>/dev/null)"; fi
mkspec "$V lang=en" "Shall we go on?" "" 0
build; grep -q 'General notes' "$PAGE" && ok "1b. English page: General notes" \
  || fail "1b. $(cat "$TMP/out")"

# 1c. the HTML route is as strict as before: a page with no notes item FAILs
python3 - "$PAGE" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
t = re.sub(r'<section class="consult-item consult-notes".*?</section>', "", t, flags=re.S)
open(p, "w", encoding="utf-8").write(t)
PY
bash "$CHECK" "$PAGE" >"$TMP/o1c" 2>&1
if grep -q "no general-notes item" "$TMP/o1c"; then
  ok "1c. the same page without the notes item still FAILs check-artifact"
else fail "1c. check-artifact no longer refuses a page with no notes"; fi

# 2. id prefix stripped (every separator), a bare `Q1 foo` still refused
for sep in ' · ' ': ' ' - ' ' — ' '. '; do
  mkspec "$V" "Q1${sep}¿Seguimos?" "" 1
  if build && grep -q 'data-title="¿Seguimos?"' "$PAGE" \
     && grep -q "line 6: dropped the id prefix" "$TMP/out"; then
    ok "2. title 'Q1${sep}…' loses its id prefix, the note names line 6"
  else fail "2. sep '$sep': $(cat "$TMP/out")"; fi
done
mkspec "$V" "Q1 seguimos" "" 1
if ! build && grep -q "repeats its id" "$TMP/out"; then
  ok "2b. 'Q1 seguimos' (no separator) is still refused"
else fail "2b. $(cat "$TMP/out")"; fi
mkspec "$V" "¿Seguimos con Q1?" "" 1
if build && grep -q 'data-title="¿Seguimos con Q1?"' "$PAGE" \
   && ! grep -q "dropped the id prefix" "$TMP/out"; then
  ok "2c. an id elsewhere in the title is left alone"
else fail "2c. $(cat "$TMP/out")"; fi

# 3. section title= is read as heading=; both given is refused
mkspec "$V" "¿Seguimos?" '::: section {#S1 title="Referencia"}
Un texto.
:::' 0
if build && grep -q '<h2>Referencia</h2>' "$PAGE" && grep -q "section. title= as heading=" "$TMP/out" \
   && bash "$CHECK" "$PAGE" >"$TMP/o" 2>&1; then
  ok "3. section title= becomes heading=, with a note; the added notes sit before the reference section"
else fail "3. $(cat "$TMP/out")"; fi
mkspec "$V" "¿Seguimos?" '::: section {#S1 title="A" heading="B"}
Un texto.
:::' 1
if ! build && grep -q "takes no attr 'title'" "$TMP/out"; then
  ok "3b. title= with heading= both given is refused"
else fail "3b. $(cat "$TMP/out")"; fi

# 4. no visual= on a consultation masthead: refused with the masthead line
mkspec 'title="T"' "¿Seguimos?" "" 1
if ! build && grep -q "p.spec.md:1: a consultation masthead needs visual=" "$TMP/out" \
   && [ ! -e "$PAGE" ]; then
  ok "4. a consultation masthead with no visual= is refused at its line, no page written"
else fail "4. $(cat "$TMP/out")"; fi

# 4b. the refusal is the build's own, before anything is written beside the page
[ ! -e "$D/p-assets" ] && ok "4b. a refused spec leaves no p-assets/ folder" \
  || fail "4b. p-assets/ left behind"

# 4c. a markdown image is not a figure (md_body renders none): still refused
mkspec 'title="T"' "¿Seguimos?" "" 1
python3 - "$SPEC" <<'PY'
import sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(t.replace("Una pregunta.", "Una pregunta. ![d](a.png)", 1))
PY
if ! build && grep -q "p.spec.md:1: a consultation masthead needs visual=" "$TMP/out"; then
  ok "4c. masthead prose with ![d](a.png) and no visual= is refused at line 1"
else fail "4c. $(cat "$TMP/out")"; fi

# 4d. a visual= that is not `none:` and no figure block names nothing: refused
mkspec 'title="T" visual="un diagrama del flujo"' "¿Seguimos?" "" 1
if ! build && grep -q "p.spec.md:1: a consultation masthead needs visual=" "$TMP/out" \
   && grep -q "names a figure but the spec has no such block" "$TMP/out"; then
  ok "4d. visual=\"un diagrama…\" with no figure block is refused at the masthead line"
else fail "4d. $(cat "$TMP/out")"; fi

# 4e. a gallery puts <img> on the page: item + gallery + no visual= builds and passes
mkspec 'title="T"' "¿Seguimos?" "" 1
python3 - "$D" "$SPEC" <<'PY'
import json, os, subprocess, sys
d, spec = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(spec))
tests = os.environ["TESTS_DIR"]
rows = {"gallery": "audit", "variants": ["light-desktop"],
        "rows": [{"cell": "with-data", "variant": "light-desktop", "kind": "review",
                  "look": "The table header", "before": "shots/a.png", "after": "actual/a.png"}]}
json.dump(rows, open(os.path.join(d, "rows.json"), "w"))
for rel, grey in (("shots/a.png", ["96"]), ("actual/a.png", [])):
    os.makedirs(os.path.dirname(os.path.join(d, rel)), exist_ok=True)
    subprocess.run([sys.executable, os.path.join(tests, "png_fixture.py"),
                    os.path.join(d, rel), "16", "9"] + grey, check=True)
t = open(spec, encoding="utf-8").read()
t = t.replace("::: group", '::: gallery {#E title="Galeria" rows="rows.json" root="%s"}\n:::\n\n::: group' % d, 1)
open(spec, "w", encoding="utf-8").write(t)
PY
if build && bash "$CHECK" "$PAGE" >"$TMP/o" 2>&1; then
  ok "4e. item + gallery with no visual= builds and passes check-artifact"
else fail "4e. $(cat "$TMP/out" "$TMP/o")"; fi

[ "$failures" -eq 0 ] && { echo "OK — consult refusals: notes, id prefix, section title fixed; visual named"; exit 0; }
echo "$failures failure(s)"; exit 1
