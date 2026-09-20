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
if grep -q "orphaned baseline.*\.body" "$TMP/err4"; then fail "a live page's body is reported orphaned: $(grep 'orphaned' "$TMP/err4" | head -1)"
else ok "a live page's body is not an orphan"; fi

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
if grep -q "page\.html\.failed" "$TMP/err7"; then fail "a live page's failing attempt is reported as dead state: $(grep 'page\.html\.failed' "$TMP/err7" | head -1)"
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
first_note="$(grep "first\.html\.failed\.body'" "$TMP/err12" | head -1)"
[[ "$first_note" == *"unfinished attempt"* && "$first_note" == *"--in"* ]] \
  && ok "an unfinished first build is reported as work to resume, not as dead state" \
  || fail "the unfinished first build's advice is wrong or missing: $first_note"

[[ $failures -eq 0 ]] && echo "PASS: body sidecar" || { echo "FAILED: $failures"; exit 1; }
