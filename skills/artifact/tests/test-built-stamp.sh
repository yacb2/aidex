#!/usr/bin/env bash
# Every wrapped page says WHEN it was built, in the rail, without JavaScript.
#
# BL-439 (audit finding USAGE-29): the reader asked eight times across two retro
# windows whether the tab he had open was the page that had just been written
# ("¿está actualizado el artefacto?", "el artefacto me sigue mostrando lo mismo,
# no lo actualizaste"). Nothing on the page answered it, and the session's reply
# naming the absolute path answers "which file", never "which version".
#
# What is pinned here:
#   1. a wrapped page carries exactly ONE visible built line, with a parseable
#      local date-time, and a matching <meta name="artifact-built">;
#   2. the line is written by the WRAP, not by composer.js — a viewer that shows
#      a local page as a static snapshot with no JS still shows it;
#   3. a re-wrap of the same --out REPLACES the line, never appends a second one
#      (`double-wrap` must stay meaningful), and carries the new time;
#   4. a consultation names its round in that line; a plain report does not;
#   5. the wrap prints the same line on stdout, so the session can quote it and
#      the reader can compare the two;
#   6. the page still passes check-artifact.sh with the line on it.
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIT="$SKILL/assets/artifact-kit"
WRAP="$SKILL/scripts/wrap-report.sh"
CHECK="$SKILL/scripts/check-artifact.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# The rendered line, exactly as the reader sees it, or "" when the page has none.
built_line() {
  python3 - "$1" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.findall(r'<p class="railbuilt"[^>]*>(.*?)</p>', t, re.S)
print(m[0].strip() if len(m) == 1 else ("" if not m else "MULTIPLE:%d" % len(m)))
PY
}
built_count() { grep -o 'class="railbuilt"' "$1" | wc -l | tr -d ' '; }

# Is the built line inside the RAIL aside — the element, not the first string
# that looks like it? A page may quote the kit's own markup in a <code> and may
# carry an <aside class="note"> of its own; both are ordinary page content and
# neither is where the stamp belongs.
in_rail() {
  python3 - "$1" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r'<aside\b[^>]*class=["\'][^"\']*\brail\b[^"\']*["\']', t)
p = t.find('class="railbuilt"')
if not m or p < 0:
    sys.exit(1)
depth, end = 0, -1
for tok in re.finditer(r'</?aside\b', t[m.start():]):
    depth += 1 if tok.group(0) == '<aside' else -1
    if depth == 0:
        end = m.start() + tok.start()
        break
sys.exit(0 if m.start() < p < end else 1)
PY
}

PROJ="$TMP/proj"; mkdir -p "$PROJ/.context/reports"
printf '<div class="page"><main class="main"><section id="s1"><h2>Body</h2><p>A read.</p></section></main></div>\n' \
  > "$TMP/report-body.html"

# ---------- a plain report: one line, a real timestamp, no round -------------
PAGE="$PROJ/.context/reports/report.html"
# The minute the wrap runs in — either side of a rollover is the current time.
before="$(date +'%Y-%m-%d %H:%M')"
out="$(bash "$WRAP" --title "Report" --lang en --in "$TMP/report-body.html" --out "$PAGE" 2>/dev/null)"
after="$(date +'%Y-%m-%d %H:%M')"
if [[ ! -f "$PAGE" ]]; then
  fail "wrapping a plain report produced no page"
else
  n="$(built_count "$PAGE")"
  [[ "$n" == 1 ]] || fail "a wrapped page carries $n built line(s), expected exactly 1"
  line="$(built_line "$PAGE")"
  [[ "$line" =~ ^Built\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]] \
    || fail "the built line is not '<label> YYYY-MM-DD HH:MM' and nothing else: '$line'"
  stamp="${line#Built }"
  [[ "$stamp" == "$before" || "$stamp" == "$after" ]] \
    || fail "the built line does not carry the time of the wrap ('$stamp' vs '$before'/'$after')"
  grep -q "<meta name=\"artifact-built\" content=\"$stamp\">" "$PAGE" \
    || fail "the page has no <meta name=\"artifact-built\"> matching its visible line"
  # In the rail, where the reader looks for it — and the rail only.
  in_rail "$PAGE" || fail "the built line is not inside <aside class=\"rail\">"
  # Without JavaScript: the composer must not be what writes it.
  grep -q 'railbuilt' "$KIT/composer.js" \
    && fail "composer.js writes the built line — a static snapshot viewer with no JS would show no stamp"
  grep -q '· round' "$PAGE" \
    && fail "a plain report names a consultation round in its built line"
  [[ -n "$line" ]] && grep -qF "$line" <<<"$out" \
    || fail "the wrap did not print its own built line on stdout: $out"
  "$CHECK" "$PAGE" >/dev/null 2>&1 \
    || fail "a page carrying the built line no longer passes check-artifact.sh"
fi

# ---------- a re-wrap replaces the line, never appends -----------------------
before2="$(date +'%Y-%m-%d %H:%M')"
bash "$WRAP" --title "Report" --lang en --in "$TMP/report-body.html" --out "$PAGE" >/dev/null 2>&1 \
  || fail "re-wrapping the same --out failed"
after2="$(date +'%Y-%m-%d %H:%M')"
n="$(built_count "$PAGE")"
[[ "$n" == 1 ]] || fail "a re-wrap left $n built line(s) on the page, expected exactly 1"
stamp2="$(built_line "$PAGE")"; stamp2="${stamp2#Built }"
[[ "$stamp2" == "$before2" || "$stamp2" == "$after2" ]] \
  || fail "the re-wrap kept a stale time ('$stamp2' vs '$before2'/'$after2')"

# ...including when the body handed back already carries one (the sidecar is the
# documented source, but a caller re-wrapping the PAGE must not end up with two).
python3 - "$PAGE" "$TMP/recycled.html" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r'<div class="page">.*</div>', t, re.S)
open(sys.argv[2], "w", encoding="utf-8").write(m.group(0))
PY
RECY="$PROJ/.context/reports/recycled.html"
bash "$WRAP" --title "Recycled" --lang en --in "$TMP/recycled.html" --out "$RECY" >/dev/null 2>&1
[[ -f "$RECY" ]] && { [[ "$(built_count "$RECY")" == 1 ]] \
  || fail "a body that already carried a built line produced $(built_count "$RECY") of them"; }

# ---------- a consultation names its round -----------------------------------
CPAGE="$PROJ/.context/reports/consult.html"
bash "$WRAP" --title "Consultation" --lang en --in "$KIT/skeleton.html" --out "$CPAGE" >/dev/null 2>&1 \
  || fail "wrapping the skeleton as a consultation failed"
line="$(built_line "$CPAGE")"
[[ "$line" =~ ^Built\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}\ ·\ round\ 1$ ]] \
  || fail "round 1 of a consultation does not name its round in the built line: '$line'"
# BL-507: round 2 is the reader's second round, so the reply to round 1 is saved
# first (a bare re-wrap now stays round 1; the expected value is unchanged).
printf 'Q1: ok\n' | bash "$SKILL/scripts/save-reply.sh" "$CPAGE" - >/dev/null 2>&1
bash "$WRAP" --title "Consultation" --lang en --in "$KIT/skeleton.html" --out "$CPAGE" >/dev/null 2>&1
line="$(built_line "$CPAGE")"
[[ "$line" == *"· round 2" ]] \
  || fail "round 2 of a consultation still reads '$line'"
[[ "$(built_count "$CPAGE")" == 1 ]] \
  || fail "a consultation re-wrap left $(built_count "$CPAGE") built line(s)"
"$CHECK" "$CPAGE" >/dev/null 2>&1 \
  || fail "a consultation carrying the built line no longer passes check-artifact.sh"

# ---------- a --building build shows ONE round, the one it started at --------
# Every passing wrap advances the baseline, so a delegated build that wraps its
# page three times used to hand the reader `· round 3` for a page he had never
# seen — the number the line exists to make trustworthy, inflated by the
# mechanism that keeps him from seeing the intermediate states at all. The
# ROUND METAS keep counting (BL-421's decided-round stamping reads them); only
# what is DISPLAYED is held still, and only while the lock is there.
BPAGE="$PROJ/.context/reports/build.html"
for _ in 1 2 3; do
  bash "$WRAP" --building --title "Consultation" --lang en \
       --in "$KIT/skeleton.html" --out "$BPAGE" >/dev/null 2>&1 \
    || fail "a --building wrap of the skeleton failed"
done
line="$(built_line "$BPAGE")"
[[ "$line" == *"· round 1" ]] \
  || fail "three --building wraps of a FIRST build read '$line' — the reader has seen no round yet"
bash "$WRAP" --done --out "$BPAGE" >/dev/null 2>&1 \
  || fail "--done on the built page failed"
[[ "$(built_line "$BPAGE")" == *"· round 1" ]] \
  || fail "--done changed the round the finished page shows: '$(built_line "$BPAGE")'"
"$CHECK" "$BPAGE" >/dev/null 2>&1 \
  || fail "a page built under --building no longer passes check-artifact.sh"
# ...and a build that starts from a page the reader HAS seen shows N+1, once.
NPAGE="$PROJ/.context/reports/build2.html"
bash "$WRAP" --title "Consultation" --lang en --in "$KIT/skeleton.html" --out "$NPAGE" >/dev/null 2>&1
[[ "$(built_line "$NPAGE")" == *"· round 1" ]] \
  || fail "the page the build starts from does not read round 1: '$(built_line "$NPAGE")'"
# BL-507: the reader answered round 1 (save-reply.sh), so the build is round 2.
printf 'Q1: ok\n' | bash "$SKILL/scripts/save-reply.sh" "$NPAGE" - >/dev/null 2>&1
for i in 1 2 3; do
  # save-reply while the build runs would snapshot the delegate's intermediate
  # page, not the one the reader saw, and skip a round: it must be refused.
  if [[ $i == 3 ]]; then
    rout="$(printf 'Q1: ok\n' | bash "$SKILL/scripts/save-reply.sh" "$NPAGE" - 2>&1)"; rrc=$?
    { [[ $rrc -ne 0 && "$rout" == *".building"* ]]; } \
      || fail "save-reply during a running build was accepted or did not name the lock (rc $rrc): $rout"
  fi
  bash "$WRAP" --building --title "Consultation" --lang en \
       --in "$KIT/skeleton.html" --out "$NPAGE" >/dev/null 2>&1
  [[ "$(built_line "$NPAGE")" == *"· round 2" ]] \
    || fail "a build over a page answered at round 1 reads '$(built_line "$NPAGE")' — it is one round, not three"
done
bash "$WRAP" --done --out "$NPAGE" >/dev/null 2>&1
# BL-507: the consult-round META is the reader's round too (was: counted wraps, so
# >= 4 after this build); three wraps of one build read 2, same as the display.
python3 - "$NPAGE" <<'PY' || fail "the consult-round meta of a one-round build is not the reader's round 2"
import re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r'<meta name="consult-round" content="(\d+)"', t)
sys.exit(0 if m and int(m.group(1)) == 2 else 1)
PY

# ---------- the label follows the page's language ----------------------------
ES="$PROJ/.context/reports/es.html"
bash "$WRAP" --title "Informe" --lang es --in "$TMP/report-body.html" --out "$ES" >/dev/null 2>&1
[[ -f "$ES" ]] && { [[ "$(built_line "$ES")" == Generado\ * ]] \
  || fail "a lang=\"es\" page shows an English built label: '$(built_line "$ES")'"; }
# The round word too. Not through a page: the skeleton's prose is English, so a
# Spanish consultation fixture would have to be translated here to clear the
# `lang` gate — the label is read straight out of the wrapper instead.
es_round="$(python3 - "$SKILL/scripts/dash" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import wrap_report
print(wrap_report.built_text("es", 3, when=__import__("datetime").datetime(2026, 9, 21, 8, 24)))
PY
)"
[[ "$es_round" == "Generado 2026-09-21 08:24 · ronda 3" ]] \
  || fail "the Spanish built line is not 'Generado <stamp> · ronda 3': '$es_round'"

# ---------- the anchor is the rail ELEMENT, not a string that looks like it ---
# A page that quotes the kit's own markup — `id="raillist"` inside a <code>,
# which nothing escapes — followed by an <aside> of its own in the main column
# put the stamp inside that margin note and left the rail without one. "Exactly
# one line" passed the whole way: the count is right and the place is wrong,
# which is the shape a count-based check cannot see.
cat > "$TMP/quoting-body.html" <<'HTML'
<div class="page">
  <main class="main">
    <section id="s1">
      <h2>How the rail is built</h2>
      <p>The kit's own index lives in <code>id="raillist"</code>, injected by the wrap.</p>
      <aside class="note">A margin note of the page's own, which is not the rail.</aside>
    </section>
  </main>
  <aside class="rail">
    <p class="railhead">Contents</p>
    <nav class="raillist" id="raillist"></nav>
  </aside>
</div>
HTML
QPAGE="$PROJ/.context/reports/quoting.html"
bash "$WRAP" --title "Quoting the kit" --lang en --in "$TMP/quoting-body.html" \
     --out "$QPAGE" >/dev/null 2>&1 || fail "wrapping a page that quotes id=\"raillist\" failed"
[[ -f "$QPAGE" ]] && {
  [[ "$(built_count "$QPAGE")" == 1 ]] \
    || fail "the quoting page carries $(built_count "$QPAGE") built line(s)"
  in_rail "$QPAGE" \
    || fail "the built line landed outside <aside class=\"rail\"> on a page that quotes id=\"raillist\""
}
# The fallback pattern is closed on the right, or `id="raillist-old"` answers for
# the rail on a page that has none.
python3 - "$SKILL/scripts/dash" <<'PY' || fail "RAILLIST_ID matches id=\"raillist-old\" — an unrelated id would anchor the stamp"
import sys
sys.path.insert(0, sys.argv[1])
import wrap_report
bad = [s for s in ('id="raillist-old"', "id='raillist2'", 'id=raillist-x')
       if wrap_report.RAILLIST_ID.search(s)]
good = [s for s in ('id="raillist"', "id='raillist'", 'id=raillist ')
        if not wrap_report.RAILLIST_ID.search(s)]
sys.exit(0 if not bad and not good else 1)
PY

# ---------- the kit can style it, and hides it where the rail is a bar --------
grep -q '^\.railbuilt' "$KIT/components.css" \
  || fail "components.css has no .railbuilt rule — the line renders as unstyled body text in the rail"
# Below 62rem the rail stops being a column and becomes a sticky BOTTOM BAR
# carrying the copy button; everything else in it is hidden there. A stamp left
# visible sits pinned over the content of every page at that width.
python3 - "$KIT/components.css" <<'PY' || fail ".railbuilt is not in the narrow-viewport hide list — the stamp is pinned over the content below 62rem"
import re, sys
css = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"@media \(max-width: 62rem\) \{(.*?)\n\}", css, re.S)
if not m:
    sys.exit(1)
hide = re.search(r"([^{}]*\.rail \.railbuilt[^{}]*)\{([^}]*)\}", m.group(1))
sys.exit(0 if hide and re.search(r"display:\s*none", hide.group(2)) else 1)
PY

# ---------- what the wrap prints last ----------------------------------------
# The session quotes the last line in the reply and the reader compares it with
# what his tab shows, so the order is part of the contract: the path (which
# FILE), then the stamp (which VERSION of it).
PPAGE="$PROJ/.context/reports/printed.html"
out="$(bash "$WRAP" --title "Printed" --lang en --in "$TMP/report-body.html" --out "$PPAGE" 2>/dev/null)"
abs="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$PPAGE")"
[[ "$(tail -n 2 <<<"$out" | head -n 1)" == "$abs" ]] \
  || fail "the absolute path is not the second-to-last line of stdout: $(tail -n 2 <<<"$out")"
[[ "$(tail -n 1 <<<"$out")" == "$(built_line "$PPAGE")" ]] \
  || fail "the last line of stdout is not the page's own built line: '$(tail -n 1 <<<"$out")'"

if [[ "$failures" -eq 0 ]]; then
  echo "test-built-stamp.sh: all checks passed"
else
  echo "$failures failure(s)"; exit 1
fi
