#!/usr/bin/env bash
# test-body-sidecar.sh — `wrap-report.sh --out` keeps the page's own CONTENT next to
# the baseline, so a revision round never has to load the wrapped file.
#
# A wrapped page is 100-200 KB of which the author's content is 12-33% (measured on
# four pages, 2026-09-20); the rest is kit styles and the composer. Revising a page
# used to mean reading the wrapped file, carving the content back out of it and
# re-wrapping — which is also the only way to double-wrap a page, a defect the
# contract check passes. The sidecar is the wrap's own input, written by the wrap,
# so it cannot drift from the page by hand.
#
# It lives INSIDE `.aidex-artifact-prev/` on purpose: validate.py, _lib.sh and the
# audit readers all skip that directory by name, and it is already gitignored in
# every workspace. It never ends in `.html`, so no sweep takes it for an artifact.
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
WRAP="$SKILL/scripts/wrap-report.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
ok()   { printf 'ok   — %s\n' "$*"; }

mkdir -p "$TMP/reports"
cat > "$TMP/body.html" <<'HTML'
<div class="page"><main class="main"><h1>Probe</h1>
<section id="sec-a"><h2>First</h2><p>One paragraph.</p></section>
</main></div>
HTML
PREV="$TMP/reports/.aidex-artifact-prev"

# 1. an html body is kept verbatim
bash "$WRAP" --title Probe --lang en --in "$TMP/body.html" --out "$TMP/reports/page.html" >/dev/null 2>"$TMP/err1" \
  || fail "the probe page does not pass the contract: $(tail -3 "$TMP/err1")"
if cmp -s "$TMP/body.html" "$PREV/page.html.body"; then ok "html body kept verbatim at .aidex-artifact-prev/page.html.body"
else fail "no verbatim body sidecar at $PREV/page.html.body"; fi

# 2. a markdown input keeps the MARKDOWN, under a name the wrap renders again
printf '# Probe md\n\n## First\n\nOne paragraph.\n' > "$TMP/report.md"
bash "$WRAP" --title Probe --lang en --in "$TMP/report.md" --out "$TMP/reports/md.html" >/dev/null 2>&1
if cmp -s "$TMP/report.md" "$PREV/md.html.body.md"; then ok "markdown input kept as md.html.body.md"
else fail "no markdown sidecar at $PREV/md.html.body.md"; fi

# 3. the revision round: wrapping FROM the sidecar passes and wraps exactly once
if bash "$WRAP" --title Probe --lang en --in "$PREV/page.html.body" --out "$TMP/reports/page.html" >/dev/null 2>&1; then
  n=$(grep -ci '<!doctype' "$TMP/reports/page.html")
  [[ "$n" == 1 ]] && ok "re-wrapping from the sidecar yields one document" || fail "re-wrap from the sidecar has $n doctypes"
else fail "re-wrapping from the sidecar fails the contract"; fi

# 4. the sidecar is not reported as an orphaned baseline while its page exists
bash "$WRAP" --title Probe --lang en --in "$TMP/body.html" --out "$TMP/reports/other.html" >/dev/null 2>"$TMP/err4"
if grep >/dev/null "orphaned baseline.*\.body" "$TMP/err4"; then fail "a live page's body is reported orphaned: $(grep 'orphaned' "$TMP/err4" | sed -n 1p)"
else ok "a live page's body is not an orphan"; fi

# 4b. BL-546: save-reply.sh's companions (<stem>.reply.md, <stem>.answered.html)
#     belong to <stem>.html; while it exists they are not orphans, once it is gone they are.
printf 'Q1: ok\n' | bash "$SKILL/scripts/save-reply.sh" "$TMP/reports/page.html" - >/dev/null 2>"$TMP/err4s"; rc=$?
[[ $rc -eq 0 && -f "$PREV/page.reply.md" && -f "$PREV/page.answered.html" ]] \
  && ok "save-reply wrote page.reply.md and page.answered.html" \
  || fail "save-reply did not write its companions (rc $rc): $(cat "$TMP/err4s")"
printf 'x\n' > "$PREV/gone.reply.md"; printf 'x\n' > "$PREV/gone.answered.html"
bash "$WRAP" --title Probe --lang en --in "$TMP/body.html" --out "$TMP/reports/other.html" >/dev/null 2>"$TMP/err4b"
if grep >/dev/null -E "orphaned baseline.*page\.(reply\.md|answered\.html)" "$TMP/err4b"; then
  fail "a live page's reply companions are reported orphaned: $(grep 'page\.\(reply\|answered\)' "$TMP/err4b" | sed -n 1p)"
else ok "a live page's reply and answered snapshot are not orphans"; fi
[[ "$(grep -cE "gone\.(reply\.md|answered\.html)'" "$TMP/err4b")" == 2 ]] \
  && ok "the companions of a page that is gone are still reported" \
  || fail "the companions of a deleted page went unreported: $(cat "$TMP/err4b")"
rm -f "$PREV/gone.reply.md" "$PREV/gone.answered.html"

# 5. ...and IS reported once the page is gone, or every page is silently doubled again.
#    CHANGED 2026-09-20 (review): the wording is per KIND of entry now. A `.body` is
#    the only copy of that page's content, so the note says so instead of offering a
#    bare `rm` on the one file nobody can regenerate.
rm "$TMP/reports/md.html"
bash "$WRAP" --title Probe --lang en --in "$TMP/body.html" --out "$TMP/reports/other.html" >/dev/null 2>"$TMP/err5"
if grep -q "source of a deleted artifact.*md\.html\.body\.md" "$TMP/err5"; then ok "a body whose page is gone is reported as the deleted page's source"
else fail "the body of a deleted page is not reported: $(grep -c . "$TMP/err5") stderr line(s)"; fi

# 6. the sidecar is the source of the page AT --out. A failing attempt never touches
#    it; the attempt lives entirely under the `.failed` name.
#
# CHANGED 2026-09-20 twice. It first asserted "the sidecar matches the file ON DISK
# even when that file fails the contract" — true only while a failing wrap was left
# at <page>. It then asserted the sidecar was the last wrap ATTEMPT, which locked in
# the defect the review found: a failing wrap overwrote the source of the version the
# rollback had just restored, so the page on disk had no source left anywhere.
cp "$TMP/reports/page.html" "$TMP/page-before-fail.html"
printf '<div class="page"><main class="main"><h1>Bad</h1><h2>No section</h2></main></div>\n' > "$TMP/bad.html"
bash "$WRAP" --title Probe --lang en --in "$TMP/bad.html" --out "$TMP/reports/page.html" >/dev/null 2>&1 \
  && fail "the failing probe unexpectedly passes — assertion 6 is vacuous"
if cmp -s "$TMP/page-before-fail.html" "$TMP/reports/page.html"; then ok "the page itself is byte-identical to the last version that passed"
else fail "a contract-failing render was left at the reader's path"; fi
if cmp -s "$TMP/body.html" "$PREV/page.html.body"; then ok "the sidecar still holds the source of the page on disk"
else fail "the failing wrap overwrote the source of the page it rolled back to"; fi
[[ -f "$PREV/page.html.failed" ]] && ok "the failing render is kept at <page>.failed" \
                                  || fail "the failing render is nowhere on disk"
if cmp -s "$TMP/bad.html" "$PREV/page.html.failed.body"; then ok "the failing attempt's own source is kept at <page>.failed.body"
else fail "the failing attempt's source is not at $PREV/page.html.failed.body"; fi

# 7. neither the kept render nor its source is an orphan while the page exists.
bash "$WRAP" --title Probe --lang en --in "$TMP/body.html" --out "$TMP/reports/other.html" >/dev/null 2>"$TMP/err7"
if grep >/dev/null "page\.html\.failed" "$TMP/err7"; then fail "a live page's failing attempt is reported as dead state: $(grep 'page\.html\.failed' "$TMP/err7" | sed -n 1p)"
else ok "a live page's .failed and .failed.body are not orphans"; fi

# 8. the spelling flip (the defect the review reproduced): a page wrapped FROM
#    markdown, then a failing wrap from html at the same path. The markdown sidecar
#    is the source of the page that is still on disk and must survive untouched —
#    the old code deleted it as "the other spelling" and wrote the failing html in
#    its place, while stderr said the page was left exactly as it was.
printf '# Probe md\n\n## First\n\nOne paragraph.\n' > "$TMP/mdp.md"
bash "$WRAP" --title Probe --lang en --in "$TMP/mdp.md" --out "$TMP/reports/mdp.html" >/dev/null 2>&1 \
  || fail "the markdown probe does not pass the contract"
bash "$WRAP" --title Probe --lang en --in "$TMP/bad.html" --out "$TMP/reports/mdp.html" >/dev/null 2>&1 \
  && fail "the failing probe unexpectedly passes — assertion 8 is vacuous"
if cmp -s "$TMP/mdp.md" "$PREV/mdp.html.body.md"; then ok "a failing html wrap leaves the markdown source of the page untouched"
else fail "the failing wrap destroyed the markdown source of the page on disk"; fi
[[ ! -e "$PREV/mdp.html.body" ]] \
  && ok "the failing attempt did not take the page's own sidecar name" \
  || fail "the failing attempt was written as the page's source under the other spelling"
if cmp -s "$TMP/bad.html" "$PREV/mdp.html.failed.body"; then ok "the failing attempt is at mdp.html.failed.body"
else fail "the failing attempt's source is not at $PREV/mdp.html.failed.body"; fi

# 9. a later PASSING wrap clears the whole `.failed` set, both spellings of its source.
bash "$WRAP" --title Probe --lang en --in "$TMP/mdp.md" --out "$TMP/reports/mdp.html" >/dev/null 2>"$TMP/err9" \
  || fail "the fixed markdown page does not pass the contract"
# ...and says so: hygiene calls that source "work, not residue", so a pass that
# removes it without a word takes the author's choice silently.
grep -q "unfinished attempt kept at .*mdp\.html\.failed\.body was superseded" "$TMP/err9" \
  && ok "the pass that removes an unfinished attempt says it did" \
  || fail "a passing wrap removed the attempt's source without mentioning it"
[[ ! -e "$PREV/mdp.html.failed" && ! -e "$PREV/mdp.html.failed.body" \
   && ! -e "$PREV/mdp.html.failed.body.md" ]] \
  && ok "a passing wrap removes the failing render and its source" \
  || fail "part of the failing attempt outlived the fix"

# 10. hygiene with the page gone. CHANGED 2026-09-20 (review): assertions 8 and 9 of
#     the first version pinned an EXEMPTION — "no baseline entry means an unfinished
#     first build, report nothing". That exemption silenced a real orphan (a page
#     written before baselines existed, failed once, then deleted: 88 KB kept
#     forever) and was not idempotent, since removing the baseline entry the note
#     asked for turned every remaining entry into an exempt one. There is no
#     exemption now; the NOTE tells the truth per kind of entry instead.
rm "$TMP/reports/page.html"
bash "$WRAP" --title Probe --lang en --in "$TMP/body.html" --out "$TMP/reports/other.html" >/dev/null 2>"$TMP/err10"
grep -q "orphaned baseline.*page\.html\.failed'" "$TMP/err10" \
  && ok "a deleted page's failing render is reported as a derived copy to rm" \
  || fail "the .failed of a deleted page is never reported"
grep -q "source of a deleted artifact.*page\.html\.body'" "$TMP/err10" \
  && ok "a deleted page's source says it is the only copy" \
  || fail "the .body of a deleted page is reported without saying what it is"
grep -q "unfinished attempt.*page\.html\.failed\.body'" "$TMP/err10" \
  && ok "a deleted page's failing source is reported as work to resume" \
  || fail "the .failed.body of a deleted page is not reported as an unfinished attempt"

# 11. ...and the notes are idempotent: doing exactly what one of them says must not
#     silence the others. The reviewer's case: rm the baseline entry alone.
rm "$PREV/page.html"
bash "$WRAP" --title Probe --lang en --in "$TMP/body.html" --out "$TMP/reports/other.html" >/dev/null 2>"$TMP/err11"
grep -q "page\.html\.failed'" "$TMP/err11" && grep -q "page\.html\.body'" "$TMP/err11" \
  && grep -q "page\.html\.failed\.body'" "$TMP/err11" \
  && ok "removing the baseline entry does not silence the rest of the set" \
  || fail "the remaining entries went quiet once the baseline entry was removed"

# 12. a FIRST wrap that fails leaves no page and no baseline at all. It is still
#     reported — the reviewer's 88 KB case is exactly this shape a year later — but
#     as an attempt to resume with --in, never as a bare rm.
bash "$WRAP" --title Probe --lang en --in "$TMP/bad.html" --out "$TMP/reports/first.html" >/dev/null 2>&1
[[ ! -e "$TMP/reports/first.html" && -f "$PREV/first.html.failed" ]] \
  && ok "a failing first wrap leaves no page, only the kept attempt" \
  || fail "a failing first wrap did not roll back cleanly"
bash "$WRAP" --title Probe --lang en --in "$TMP/body.html" --out "$TMP/reports/other.html" >/dev/null 2>"$TMP/err12"
grep -q "first\.html\.failed'" "$TMP/err12" \
  && ok "a failing build with no baseline at all still reports its render" \
  || fail "a .failed with no baseline entry beside it is silently kept forever"
first_note="$(grep "first\.html\.failed\.body'" "$TMP/err12" | sed -n 1p)"
[[ "$first_note" == *"unfinished attempt"* && "$first_note" == *"--in"* ]] \
  && ok "an unfinished first build is reported as work to resume, not as dead state" \
  || fail "the unfinished first build's advice is wrong or missing: $first_note"

# 13. BL-624: a baseline folder beside a LIVE page under _archive/ is not dead — the
#     builder recreates it on every build there, so a note about it would reappear
#     forever. It is dead per entry, once the page it belongs to is gone.
ARC="$TMP/arc"
mkdir -p "$ARC/.context/worklists/_archive/.aidex-artifact-prev"
cp "$TMP/body.html" "$ARC/.context/worklists/_archive/x-report.html"
printf 'x\n' > "$ARC/.context/worklists/_archive/.aidex-artifact-prev/x-report.html"
printf 'x\n' > "$ARC/.context/worklists/_archive/.aidex-artifact-prev/x-report.reply.md"
hygiene() { PYTHONPATH="$SKILL/scripts/dash" python3 -c \
  'import sys, check_artifact as c; print("\n".join(c.baseline_hygiene(sys.argv[1])))' "$ARC/.context"; }
if out="$(hygiene 2>&1)" && [[ -z "$out" ]]; then ok "a baseline folder beside a live page under _archive/ is not reported"
else fail "a live archived page's baseline is reported: $out"; fi
rm "$ARC/.context/worklists/_archive/x-report.html"
notes="$(hygiene 2>&1)"
[[ "$(grep -c "orphaned baseline" <<<"$notes")" == 2 \
   && "$notes" == *"x-report.html'"* && "$notes" == *"x-report.reply.md'"* ]] \
  && ok "with the archived page gone, each orphaned entry gets its own note" \
  || fail "the orphaned entries of a gone archived page are not each reported: $notes"

# 14. the same through the wrap: building a report with --out under _archive/ twice
#     prints no 'dead baseline (archived artifact)' line (the builder recreates the folder).
AW="$TMP/aw/.context/worklists/_archive"
mkdir -p "$AW"
bash "$WRAP" --title Probe --lang en --in "$TMP/body.html" --out "$AW/x-report.html" >/dev/null 2>"$TMP/err14a"
bash "$WRAP" --title Probe --lang en --in "$TMP/body.html" --out "$AW/x-report.html" >/dev/null 2>"$TMP/err14"
if [[ -f "$AW/x-report.html" ]] && ! grep -q "dead baseline (archived artifact)" "$TMP/err14" "$TMP/err14a"; then
  ok "a report built under _archive/ gets no dead-baseline note"
else fail "wrap under _archive/ printed the dead-baseline note: $(grep 'dead baseline' "$TMP/err14" "$TMP/err14a" | sed -n 1p)"; fi

# 15. a FAILED first spec build leaves no .aidex-artifact-prev/ it created (the spec is the
#     source, the kept attempt is redundant), but a pre-existing folder is never touched.
SB="$SKILL/scripts/spec_build.py"
cat > "$TMP/fail.spec.md" <<'SPEC'
::: masthead {eyebrow="x" byline="a"}
# Probe

Hello there.
:::

::: item {#Q1 title="t"}
?

- yes
- no
:::
SPEC
mkdir -p "$TMP/sb1" "$TMP/sb2/.aidex-artifact-prev"
printf 'keep\n' > "$TMP/sb2/.aidex-artifact-prev/other.html"
python3 "$SB" "$TMP/fail.spec.md" -o "$TMP/sb1/p.html" --lang en >/dev/null 2>&1 \
  && fail "the failing spec unexpectedly builds — assertion 15 is vacuous"
python3 "$SB" "$TMP/fail.spec.md" -o "$TMP/sb2/p.html" --lang en >/dev/null 2>&1
[[ ! -e "$TMP/sb1/.aidex-artifact-prev" && ! -e "$TMP/sb1/p.html" ]] \
  && ok "a failed first spec build leaves no baseline folder it created" \
  || fail "a failed first spec build left $(ls -a "$TMP/sb1" | tr '\n' ' ')"
[[ -f "$TMP/sb2/.aidex-artifact-prev/other.html" ]] \
  && ok "a pre-existing baseline folder survives a failed spec build" \
  || fail "a failed spec build removed a pre-existing baseline folder"

[[ $failures -eq 0 ]] && echo "PASS: body sidecar" || { echo "FAILED: $failures"; exit 1; }
