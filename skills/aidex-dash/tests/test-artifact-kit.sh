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
# ...and it is satisfied by the RULE, not by prose about the rule. The kit is
# injected into every page, so a comment that spells a check's tokens answers
# that check for pages that do not carry the rule at all. It happened twice
# during this file's own construction: once with the copy-button id, which made
# every read page fail as a consultation, and once here.
sed '/^:root\[data-theme="dark"\] \.consult-bar/d' "$KIT/components.css" | tr -d '\n' \
  | grep -qE 'data-theme="dark"[^{]*consult-bar' \
  && fail "components.css satisfies the dark-bar check from a COMMENT — delete the rule and the grep still passes"
for trigger in 'data-id=' 'data-title=' '<textarea' 'contenteditable=' 'class="consult-item'; do
  grep -qF "$trigger" "$KIT/tokens.css" "$KIT/components.css" "$KIT/composer.js" \
    && fail "an injected kit file spells the contract trigger '$trigger' — every page would match it"
done
# Every COLOUR token the kit ships exists in all four blocks — :root, the media
# query, and both explicit toggles — or a page carrying that token writes its own
# three theme blocks by hand, which is what every charted artifact on disk did.
#
# The list is DERIVED from tokens.css, never spelled here: a hand-written list of
# twelve is a check that cannot see the thirteenth token, which is this repo own
# systemic failure (a checker that lies by omission). The type stacks are the
# documented exception — a font does not change with the theme.
missing="$(python3 - "$KIT/tokens.css" <<'PYTOK'
import re, sys
css = open(sys.argv[1], encoding="utf-8").read()
css = re.sub(r"/\*.*?\*/", " ", css, flags=re.S)
counts = {}
for name in re.findall(r"--([\w-]+)\s*:", css):
    counts[name] = counts.get(name, 0) + 1
skip = {"serif", "sans", "mono"}          # type stacks: one theme, by design
print(" ".join(sorted(f"{k}={v}" for k, v in counts.items()
                      if k not in skip and v != 4)))
PYTOK
)"
[[ -z "$missing" ]] \
  || fail "tokens.css declares these in a number of blocks other than 4 (:root, the media query, [data-theme=dark], [data-theme=light]): $missing — a page would have to re-declare them per theme"
n_root="$(grep -cE -- '^[[:space:]]*--s[0-9]:' "$KIT/tokens.css")"
[[ "$n_root" -ge 4 ]] \
  || fail "the chart series slots are gone from tokens.css — a charted page would invent its own palette again"

# Typed answers persist across reloads (usage-retro run 6, R6-02). These two
# greps are structural, not functional — the functional proof is a live browser
# probe (type → reload → restored), recorded in the run's proofs. What they pin
# is the two halves a refactor could silently drop: the path-scoped storage key
# (local artifacts share the file:// origin, so a key without the path restores
# one page's answers onto another), and the recovered-answers banner the reader
# discards from.
grep -qF "'aidex-kit-answers:' + location.pathname" "$KIT/composer.js" \
  || fail "composer.js lost the path-scoped answer store — answers stop surviving reloads, or bleed between artifacts"
grep -qF 'consult-restored' "$KIT/composer.js" \
  || fail "composer.js lost the recovered-answers banner — restored state would be invisible and undiscardable"

# A textarea defaults to `resize: both`, and dragging one wider than its column
# overlaps the rail and the content beside it. Only the vertical axis has room.
grep -qE 'textarea[^}]*resize:[[:space:]]*vertical' "$KIT/components.css" \
  || fail "components.css does not pin the notes boxes to resize: vertical — the default lets the reader drag one over the content"

grep -q 'id="consult-copy"' "$KIT/skeleton.html" \
  || fail "skeleton.html has no id=\"consult-copy\" (the -end variant does not satisfy the contract)"
grep -q 'id="consult-status"' "$KIT/skeleton.html" \
  || fail "skeleton.html has no id=\"consult-status\""
n_area="$(grep -oiE '<textarea|contenteditable=' "$KIT/skeleton.html" | wc -l | tr -d ' ')"
# A block (`consult-group`) carries data-id/data-title for --prev but is not an item.
n_id="$(grep -viE 'consult-group' "$KIT/skeleton.html" | grep -oiE 'data-id=' | wc -l | tr -d ' ')"
n_title="$(grep -viE 'consult-group' "$KIT/skeleton.html" | grep -oiE 'data-title=' | wc -l | tr -d ' ')"
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

# ---------- the project delta lands on top of the kit ----------------------
# This project's own delta is EMPTY by design — the kit is aidex's palette — so
# without a fixture "the delta injects" would be a claim no test makes, and the
# phase-7 regeneration cannot catch it either.
PROJ="$TMP/proj"
mkdir -p "$PROJ/.context/reports"
cat > "$PROJ/.context/artifact-style.md" <<'MD'
# Artifact style profile — fixture

## Identity

- Favicon emoji: `🧪`

## Palette

A fence OUTSIDE the Delta section is an example and must not be injected. This is
how a profile documents the feature without becoming it.

```css
:root { --accent: #00FF00; }
```

## Delta

```css
:root { --accent: #B4005A; }
```

## Language

- language: en
MD
printf '<div class="page"><main class="main"><h1>Delta</h1></main></div>\n' > "$TMP/delta-body.html"
bash "$WRAP" --title "Delta" --in "$TMP/delta-body.html" \
     --out "$PROJ/.context/reports/d.html" >/dev/null 2>&1 \
  || fail "wrapping into a project with a style delta failed"
if [[ -f "$PROJ/.context/reports/d.html" ]]; then
  page="$PROJ/.context/reports/d.html"
  grep -q '#B4005A' "$page" || fail "the project's CSS delta was not injected"
  # A fence outside the Delta section is documentation. Injecting it is how the
  # first real profile written against this feature turned a report's accents
  # magenta — the example it used to explain the rule became the rule.
  grep -q '#00FF00' "$page" \
    && fail "a css fence outside the ## Delta section was injected — an example is not the delta"
  # After the kit, or it does not override anything.
  [[ "$(grep -n '#B4005A' "$page" | head -1 | cut -d: -f1)" -gt \
     "$(grep -n 'artifact-kit — components' "$page" | head -1 | cut -d: -f1)" ]] \
    || fail "the project delta is injected BEFORE the kit, so it cannot override it"
  # The emoji is percent-encoded into an inline SVG data URI, so grep for the
  # encoding rather than the character.
  enc() { python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1"; }
  grep -q "$(enc '🧪')" "$page" || fail "the profile's favicon emoji was not used"
fi
# A delta that closes the <style> element is markup, not CSS. The profile is a
# file in the repo, so a cloned or edited project could otherwise inject script
# into EVERY artifact generated in it — the kit's whole value is that it runs
# across every project, which is also the blast radius.
mkdir -p "$TMP/evil/.context/reports"
cat > "$TMP/evil/.context/artifact-style.md" <<'MD'
# Artifact style profile — hostile fixture

## Delta

```css
:root { --accent: #123456; }
</style><script>window.__pwned = 1;</script><style>
```

## Language

- language: en
MD
bash "$WRAP" --title "Evil" --in "$TMP/delta-body.html" \
     --out "$TMP/evil/.context/reports/e.html" >/dev/null 2>&1
if [[ -f "$TMP/evil/.context/reports/e.html" ]]; then
  grep -q '__pwned' "$TMP/evil/.context/reports/e.html" \
    && fail "a style-closing sequence in the profile delta reached the page as markup"
  grep -q '#123456' "$TMP/evil/.context/reports/e.html" \
    && fail "the hostile delta was injected at all — it must be refused whole, not partly"
fi

# An explicit flag still wins, the same precedence `language:` already has.
bash "$WRAP" --title "Delta" --favicon "🔬" --in "$TMP/delta-body.html" \
     --out "$PROJ/.context/reports/e.html" >/dev/null 2>&1
[[ -f "$PROJ/.context/reports/e.html" ]] && {
  grep -q "$(enc '🔬')" "$PROJ/.context/reports/e.html" \
    || fail "--favicon did not win over the profile's favicon"
  grep -q "$(enc '🧪')" "$PROJ/.context/reports/e.html" \
    && fail "--favicon did not replace the profile's favicon, it added to it"
}

# ---------- the shipped template documents the delta without BECOMING it ---
# The delta is the only mechanism a project has to restyle anything, and the two
# files a new project actually starts from are this template and the reference.
# It was documented in neither: the only prose explaining it lived in aidex's own
# .context/, which is gitignored and never travels. A project seeded from the
# template filled in its palette table in good faith and nothing happened.
TPL="$SKILL/assets/templates/artifact-style.md.template"
grep -qE '^#{2,6}[ \t]*Delta\b' "$TPL" \
  || fail "artifact-style.md.template has no ## Delta section — the one section the wrapper reads as CSS is missing from the file every new project copies"

# ...and that section must not carry a worked example. Scoping the rule to a
# section stops an example placed ELSEWHERE from being injected; it does nothing
# about one placed here, which every seeded project would inherit as its palette.
python3 - "$TPL" <<'TPLCHK' || fail "the template's ## Delta section ships a CSS declaration — every project seeded from it would inject that as its own palette"
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
sec = re.search(r"^(#{2,6})[ \t]*Delta\b[^\n]*\n(.*?)(?=^\1[ \t]|\Z)", text, re.M | re.S | re.I)
if sec is None:
    sys.exit(0)                    # the grep above already reported the missing section
fence = re.search(r"^```css[ \t]*\n(.*?)^```", sec.group(2), re.M | re.S)
if fence is None:
    sys.exit(0)                    # no fence at all also injects nothing
body = re.sub(r"/\*.*?\*/", "", fence.group(1), flags=re.S)
sys.exit(1 if re.search(r"[\w-]+\s*:\s*\S", body) else 0)
TPLCHK

# End to end: a project seeded from the unedited template inherits the kit and
# adds nothing of its own.
mkdir -p "$TMP/tpl/.context/reports"
cp "$TPL" "$TMP/tpl/.context/artifact-style.md"
bash "$WRAP" --title "From the template" --in "$TMP/delta-body.html" \
     --out "$TMP/tpl/.context/reports/t.html" >/dev/null 2>&1 \
  || fail "wrapping in a project seeded from the unedited template failed"
if [[ -f "$TMP/tpl/.context/reports/t.html" ]]; then
  grep -q '#116B5F' "$TMP/tpl/.context/reports/t.html" \
    && fail "the template's worked EXAMPLE reached the page — an example is not the delta"
  grep -q 'artifact-kit — components' "$TMP/tpl/.context/reports/t.html" \
    || fail "a page built in a template-seeded project lost the kit"
fi

# ---------- the composer speaks the page's language, not one hard-coded ----
# The kit ships to every project; only the project carries a language. Spanish
# display strings baked into the suite would ship Spanish to all of them.
grep -q "document.documentElement.lang" "$KIT/composer.js" \
  || fail "composer.js does not read <html lang> — its display strings are hard-coded to one language"
for key in en es; do
  grep -qE "^\s*$key: \{" "$KIT/composer.js" \
    || fail "composer.js has no '$key' entry in its strings table"
done

# ...and the chrome too, not only the status messages. The composer replaces a
# button or rail-head label only when it is EXACTLY the skeleton's English
# default — so the two must stay in lockstep, or retitling the skeleton
# silently turns the localisation off and every non-English page ships English
# buttons again (field pages were translating them by hand).
en_copy="$(sed -nE "s/^[[:space:]]*copy: '([^']*)'.*/\1/p" "$KIT/composer.js" | head -1)"
en_contents="$(sed -nE "s/^[[:space:]]*contents: '([^']*)'.*/\1/p" "$KIT/composer.js" | head -1)"
[[ -n "$en_copy" && -n "$en_contents" ]] \
  || fail "composer.js lost its chrome labels (copy/contents) — the buttons stop being localised"
grep -qF ">$en_copy<" "$KIT/skeleton.html" \
  || fail "skeleton.html's copy-button label is not the composer's en.copy ('$en_copy') — the exact-match replacement no-ops and non-English pages keep English buttons"
grep -qF ">$en_contents<" "$KIT/skeleton.html" \
  || fail "skeleton.html's rail head is not the composer's en.contents ('$en_contents') — same silent no-op"

# The v4 storage schema (one flat free-text list) must keep restoring: a
# reader's browser may hold an answer set saved before the typed keying, and
# dropping the branch would lose it on the very reload that should recover it.
grep -q "Array.isArray(s.f)" "$KIT/composer.js" \
  || fail "composer.js lost the v4 flat-schema restore branch — pre-v5 saved answers stop restoring"

# ---------- the round marker counts from the BASELINE, not from disk -------
#
# The composer drops a SENT answer when the round advances, so what counts as a
# new round is load-bearing. A failing wrap is left on disk on purpose and does
# NOT advance the baseline, so counting from the file would increment across a
# round the reader never saw and blank answers on it.
RND="$TMP/rounds"
mkdir -p "$RND/.context/reports"
PG="$RND/.context/reports/r.html"
round_of() { sed -nE 's/.*<meta name="consult-round" content="([0-9]+)">.*/\1/p' "$1" | head -1; }

printf '<div class="page"><main class="main"><h1>Round probe</h1></main></div>\n' > "$TMP/rbody.html"
bash "$WRAP" --title "Round probe" --in "$TMP/rbody.html" --out "$PG" >/dev/null 2>&1 \
  || fail "the round probe failed to wrap"
[[ "$(round_of "$PG")" == "1" ]] \
  || fail "a first page is not round 1 (got '$(round_of "$PG")')"

bash "$WRAP" --title "Round probe" --in "$TMP/rbody.html" --out "$PG" >/dev/null 2>&1
[[ "$(round_of "$PG")" == "2" ]] \
  || fail "a regeneration did not advance the round (got '$(round_of "$PG")')"

# A wrap that FAILS the contract: an external script is the cheapest violation
# that leaves the file on disk.
printf '<div class="page"><main class="main"><h1>Bad</h1><script src="https://x/y.js"></script></main></div>\n' > "$TMP/rbad.html"
bash "$WRAP" --title "Round probe" --in "$TMP/rbad.html" --out "$PG" >/dev/null 2>&1
rc=$?
[[ "$rc" -ne 0 ]] || fail "the deliberately-violating page passed the contract — the round test proves nothing"
[[ "$(round_of "$PG")" == "3" ]] \
  || fail "the failing wrap did not stamp its own round (got '$(round_of "$PG")')"

bash "$WRAP" --title "Round probe" --in "$TMP/rbody.html" --out "$PG" >/dev/null 2>&1 \
  || fail "the fixed page failed to wrap"
[[ "$(round_of "$PG")" == "3" ]] \
  || fail "the round was counted from the file on disk, not from the baseline: a failed wrap and its fix advanced it twice (got '$(round_of "$PG")', expected 3)"

# The composer must actually read it, or the wrapper stamps a marker nothing uses.
grep -q 'consult-round' "$KIT/composer.js" \
  || fail "composer.js never reads the consult-round marker the wrapper stamps"

# ---------- the recommendation is ONE declaration, on both surfaces --------
# It travelled in `data-label` alone once, which is the composer's copy string:
# the marker reached the pasted reply and was invisible on the page.
grep -q 'data-recommended' "$KIT/composer.js" \
  || fail "composer.js does not read data-recommended — the badge and the copied suffix have no source"
grep -q 'data-recommended' "$KIT/components.css" \
  || fail "components.css has no data-recommended rule — the badge has no styles"
grep -q 'data-recommended' "$SKILL/assets/templates/consultation-block.html.template" \
  || fail "the consultation template does not show data-recommended — an author copying it has no affordance and will type the marker into data-label again"
# ...and the template names .opts as the wrapper, so the group is not re-invented.
grep -q 'class="opts one"' "$SKILL/assets/templates/consultation-block.html.template" \
  || fail "the consultation template no longer shows class=\"opts one\" for a radio group"

# ---------- per-item clear arrives by wrapping, not by authoring -----------
grep -q 'consult-clear' "$KIT/composer.js" \
  || fail "composer.js does not inject a per-item clear control"

# BL-268: the injected "other" choice, and it must stay OUT of the question
# fingerprint — it is text inside the item, so hashing it would mark every
# answer stored before the upgrade as "the question changed" and drop it.
grep -q 'kit-other' "$KIT/composer.js" \
  || fail "composer.js does not inject the 'other' choice into option groups"
grep -qE "querySelectorAll\('[^']*\.kit-other[^']*'\)\.forEach\(function \(c\) \{ c\.remove\(\); \}\)" "$KIT/composer.js" \
  || fail "composer.js hashes the injected 'other' choice into the question fingerprint — every stored answer is dropped on the upgrade"
grep -q 'consult-clear' "$KIT/components.css" \
  || fail "components.css has no .consult-clear rule — the injected control is unstyled"
grep -q 'consult-clear' "$SKILL/assets/templates/consultation-block.html.template" \
  && fail "the consultation template hand-writes a clear control — it is injected, so a copied block would end up with two"

[[ "$failures" -eq 0 ]] || { echo "$failures failure(s)"; exit 1; }
echo "OK — the kit builds a page that passes the artifact contract, and stays in lockstep with it"
