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
#   3. degrade, never drop. The second producer — plan-exec's human-verification.md —
#      is PROSE, not script output, and it is where the renderer lost content: a
#      numbered checklist joined into one paragraph, a `####` heading dropped without
#      trace, no `# ` title so no heading at all. Each is pinned by the shape it
#      produced, not only by the shape it should produce.
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
# The leak this guards does NOT produce a line starting with `---`: the four
# front-matter lines carry no blank line between them, so `_blocks` folds them
# into ONE paragraph and `^---$` can never match. Grep for the KEYS instead —
# they are what actually lands, as the standfirst directly under the h1.
# Found by the branch review of the sweep that shipped this file: reverting
# md_body.py's `FM.sub` left this file green at exit 0, seven ok lines.
grep -q '^---$' "$TMP/report.html" && fail "the YAML front matter leaked into the page"
grep -q 'status: done' "$TMP/report.html" && fail "the front-matter key 'status: done' leaked into the page"
grep -q 'created: 2026-09-08' "$TMP/report.html" && fail "the front-matter key 'created:' leaked into the page"
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

# ---------- the OTHER producer: prose, not a script -------------------------
# `human-verification.md` is written by the session, and it is the shape that found
# every gap the renderer had. This fixture is the real one on disk reduced to its
# constructs: no `# ` title, a numbered checklist whose items wrap onto an indented
# second line, a heading level the subset never named, a bullet that also wraps.
cat > "$TMP/checklist.md" <<'MD'
---
title: "web-craft: human verification"
status: done
---

human-verification: skipped — the owner was absent. What a person must still judge:

1. Open `/` at desktop width and scroll the hero once: do the clouds and
   the puppets separate visibly.
2. Reduced motion: the composition stays complete.
3. The foreground cloud plane is nearly invisible; decide whether Phase 5 replaces it.

#### A fourth-level heading that must not vanish

- estimate `S` · surface `ops`, and a bullet that also
  wraps onto a second line.

Mechanical evidence already recorded.
MD

bash "$WRAP" --title "Checklist page" --lang en --in "$TMP/checklist.md" \
     --out "$TMP/checklist.html" >/dev/null 2>&1 \
  || fail "the prose checklist did not wrap"

bash "$CHECK" "$TMP/checklist.html" >"$TMP/chk2.out" 2>&1 \
  && ok "a prose human-verification.md passes check-artifact.sh" \
  || fail "check-artifact.sh on the checklist page: $(cat "$TMP/chk2.out")"

# Non-vacuous first: every assertion below is about WHERE this sentence landed, so
# it has to be on the page at all before any of them mean anything.
grep -q 'puppets separate visibly' "$TMP/checklist.html" \
  || fail "the continuation line is not on the page at all — the assertions below would be vacuous"

grep -q '<ol>' "$TMP/checklist.html" || fail "the '1.' checklist did not become an <ol>"
# Exactly 4 — 3 numbered items and 1 bullet. A count, not a presence check: the
# continuation lines must be folded INTO those items, not become items of their own.
[[ "$(grep -o '<li>' "$TMP/checklist.html" | wc -l | tr -d ' ')" == "4" ]] \
  || fail "expected 4 <li> (3 numbered + 1 bullet), got $(grep -o '<li>' "$TMP/checklist.html" | wc -l | tr -d ' ')"
# The whole item, marker stripped and continuation folded in — the two halves of the
# defect in one assertion. A marker-only fix passes the <ol> check and fails this.
grep -q '<li>Open <code>/</code> at desktop width and scroll the hero once: do the clouds and the puppets separate visibly.</li>' \
  "$TMP/checklist.html" || fail "the numbered item lost its continuation line (or kept its marker)"
grep -q '<li>estimate <code>S</code> · surface <code>ops</code>, and a bullet that also wraps onto a second line.</li>' \
  "$TMP/checklist.html" || fail "the bullet's continuation line was not folded into its <li>"
# The two wrong shapes, named. Before the fix the numbered run was one prose <p>;
# a marker-only fix drops each continuation out as an orphan <p> between the items.
grep -q '<p>1\.' "$TMP/checklist.html" && fail "the numbered checklist stayed a run-on paragraph"
grep -qE '<p>[^<]*puppets separate visibly' "$TMP/checklist.html" \
  && fail "the continuation line fell out of the list as an orphan <p>"

# Degrade, never drop: a heading level the subset does not name is still readable.
grep -q 'A fourth-level heading that must not vanish' "$TMP/checklist.html" \
  || fail "the '####' heading was dropped from the page with no trace"

# No `# ` in the markdown, so --title is the h1. Without it the reader opens a
# headless wall of paragraphs with an empty rail.
grep -q '<h1>Checklist page</h1>' "$TMP/checklist.html" \
  || fail "a report with no '# ' title rendered with no <h1>: $(grep -o '<h1[^<]*' "$TMP/checklist.html" | head -1)"
# …and a `# ` in the markdown still beats the flag.
grep -q '<h1>Sweep report — probe</h1>' "$TMP/report.html" \
  || fail "the markdown's own '# ' title did not win over --title"

# ---------- repeated section titles get distinct ids ------------------------
# `## Notes` under two items is ordinary in a report; one id for both makes the
# rail's second entry link back to the first section.
printf '# Dup\n\n## Notes\n\nfirst\n\n## Notes\n\nsecond\n' > "$TMP/dup.md"
bash "$WRAP" --title "Dup" --lang en --in "$TMP/dup.md" --out "$TMP/dup.html" >/dev/null 2>&1
[[ "$(grep -o 'id="sec-notes[^"]*"' "$TMP/dup.html" | sort -u | wc -l | tr -d ' ')" == "2" ]] \
  && ok "two '## Notes' sections get distinct ids" \
  || fail "repeated section titles share an id: $(grep -o 'id="sec-notes[^"]*"' "$TMP/dup.html" | tr '\n' ' ')"

# ---------- fenced code blocks (BL-352) --------------------------------------
# The subset had no fence branch, so a ```bash run fell into the paragraph arm: the
# fence LINES were joined with the code into one <p>, and CODE (the single-backtick
# regex) paired the first backtick of the opening fence with the last of the closing
# one, wrapping the whole run in a bogus <code> span. Content survived, unreadable.
# It goes live the first time a human-verification.md pastes a command, which the
# plan-exec canon invites.
cat > "$TMP/fence.md" <<'MD'
# Fenced

Run this:

```bash
./test-e2e.sh e2e/login.spec.ts
grep -c "**not bold**" out.txt
```

And `inline code` after it still works.
MD

bash "$WRAP" --title "Fenced" --lang en --in "$TMP/fence.md" --out "$TMP/fence.html" >/dev/null 2>&1   || fail "the fenced report did not wrap"
bash "$CHECK" "$TMP/fence.html" >"$TMP/chk3.out" 2>&1   && ok "a page with a fenced block passes check-artifact.sh"   || fail "check-artifact.sh on the fenced page: $(cat "$TMP/chk3.out")"

# Non-vacuous first: the command has to be on the page before anything else means
# anything.
grep -q 'test-e2e.sh' "$TMP/fence.html"   || fail "the fenced command is not on the page at all — the assertions below would be vacuous"

grep -q '<pre><code class="lang-bash">' "$TMP/fence.html"   || fail "no <pre><code class=\"lang-bash\"> block: $(grep -o '<pre[^>]*>[^<]*<[^>]*>' "$TMP/fence.html" | head -1)"
# Line breaks are preserved: two lines, so one newline inside the block.
python3 - "$TMP/fence.html" <<'PY' || fail "fence markers leaked into <main>, or the block is not a <pre> with its line breaks"
import re, sys
html = open(sys.argv[1]).read()
# The fence markers never reach the page. Scoped to <main>, because the wrapper injects
# the kit's CSS — whose own comments are full of backticks — around the body: a grep
# over the whole file, or even from `<div class="page">` down, counts 57 of them in a
# CORRECT page and can never fail. Inside <main> the fixture's only backticks are the
# fence and one inline span, and both must have become tags: 4 before the fix, 0 after.
# Checked FIRST so it produces its own RED instead of being shadowed by the assert below.
main = re.search(r"<main[^>]*>(.*?)</main>", html, re.S)
assert main, "no <main> in the page"
assert main.group(1).count("`") == 0, f"{main.group(1).count('`')} backtick(s) leaked into <main>"
m = re.search(r"<pre><code[^>]*>(.*?)</code></pre>", html, re.S)
assert m, "no pre/code block"
assert m.group(1).count("\n") == 1, f"expected one newline inside the block, got {m.group(1)!r}"
# The command appears ONCE, inside that block — never also in a paragraph. Before the
# fix it was in a <p> with a bogus <code> span, which a <p>[^<]* grep cannot see
# because the span puts a `<` in the way.
assert html.count("test-e2e.sh") == 1, "the command appears outside the code block too"
PY
# Inline spans are NOT processed inside the block: the `**not bold**` in the command
# must survive as literal text, not become a <strong>.
grep -q '\*\*not bold\*\*' "$TMP/fence.html"   || fail "inline markup was processed inside the code block"
# …while inline code OUTSIDE the block still works, so the fix did not disable _inline.
grep -q '<code>inline code</code>' "$TMP/fence.html"   || fail "inline code after the block stopped rendering"
# The block scrolls rather than widening the page — the kit's `pre` rule owns this.
grep -q "overflow-x: auto" "$SKILL/assets/artifact-kit/components.css"   || fail "the kit has no overflow rule for <pre>, so a long command widens the page"

# A fence closes on its OWN marker, not on either one. FENCE matches the two markers
# alike, so toggling on any match let a BARE tilde line inside a backtick-fenced block
# close it early. It has to be BARE and alone on its line: the regex already rejects a
# marker with prose after it or text before it, so the first two fixtures drafted for
# this cell both passed over the live defect. The observed damage with the right one:
# an EMPTY code block, the content leaking out as a paragraph, and the section after it
# gone entirely - the splitter's flag stuck on.
# No backticks in the fail strings below — they are double-quoted, and a backtick there
# is command substitution, which silently ate part of this cell's own message once.
# Found by the branch review, 2026-09-08.
cat > "$TMP/mixed.md" <<'MD'
# Mixed fences

```markdown
~~~
still inside the block
```

## A heading that must survive

after.
MD

bash "$WRAP" --title "Mixed" --lang en --in "$TMP/mixed.md" --out "$TMP/mixed.html" >/dev/null 2>&1 \
  || fail 'the mixed-fence report did not wrap'
python3 - "$TMP/mixed.html" <<'PY' || fail 'a bare tilde line inside a backtick-fenced block closed it, or the heading after was swallowed'
import re, sys
html = open(sys.argv[1]).read()
blocks = re.findall(r"<pre><code[^>]*>(.*?)</code></pre>", html, re.S)
assert len(blocks) == 1, f"expected ONE code block, got {len(blocks)}"
assert "still inside the block" in blocks[0], "the block was cut at the tilde line"
assert 'id="sec-a-heading-that-must-survive"' in html, "the heading after the block was swallowed"
PY
ok 'a bare tilde line inside a backtick-fenced block is data, and the heading after survives'

[[ $failures -eq 0 ]] && ok "a prose checklist renders as a list, keeps every heading, and gets an h1"

[[ $failures -eq 0 ]] && echo "OK — markdown wraps into a contract-passing page ($(wc -c < "$TMP/report.html" | tr -d ' ') bytes)"
exit $(( failures > 0 ))
