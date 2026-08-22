#!/usr/bin/env bash
# The composer's persistence actually persists — proven in a real engine.
#
# composer.js is the only stateful runtime code in the suite, and until this
# file its only functional proof was a one-time live browser probe recorded in
# an audit run's proofs. Structural greps pin that the storage key and the
# banner EXIST; nothing repeatable proved that typing, reloading and restoring
# WORK — and the restore path is exactly where a latent field bug lived (v4
# keyed free text by one global order, so inserting a control shifted every
# later answer into the wrong box).
#
# Headless Chrome, no new dependencies: the page carries a harness script that
# runs on `load` (after the composer), simulates the typing, and writes what it
# sees into <title>; `--dump-dom` hands the DOM back after scripts ran, and a
# shared --user-data-dir carries localStorage between invocations the same way
# a reader's browser carries it between visits.
#
# If no Chrome/Chromium binary exists the test SKIPS — loudly, so the omission
# is visible in the runner's output rather than indistinguishable from a pass.
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
WRAP="$SKILL/scripts/wrap-report.sh"
# /tmp explicitly rather than bare mktemp ($TMPDIR/var/folders on macOS):
# every observed clean run had the page under /tmp, and it costs nothing.
# The load-bearing defence against Chrome's flaky teardown is chrome_dump
# below, not the path.
TMP="$(mktemp -d /tmp/composer-fn-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

CHROME=""
for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
         "$(command -v google-chrome 2>/dev/null || true)" \
         "$(command -v chromium 2>/dev/null || true)"; do
  [[ -n "$c" && -x "$c" ]] && { CHROME="$c"; break; }
done
if [[ -z "$CHROME" ]]; then
  echo "SKIP: no Chrome/Chromium binary found — the composer functional test DID NOT RUN"
  exit 0
fi

# Dump a URL's post-script DOM into a file. The shape here is load-bearing,
# learned the expensive way:
#   - A FILE, never a pipe. Chrome's teardown after --dump-dom hangs
#     nondeterministically on this machine (the DOM is fully written, the
#     process never exits), and a pipeline reader then blocks forever — while
#     grep's own buffered match dies with it, which made the hang look like
#     "the page never loaded".
#   - Completion is detected by </html> appearing in the file, so a teardown
#     hang costs seconds, not the watchdog budget.
#   - TERM before KILL, with grace both sides: a clean-ish shutdown is what
#     flushes localStorage to the profile, and the restore phases depend on it.
#   - perl's setpgrp makes Chrome a process-group leader, so the kill takes
#     its helper children down too.
chrome_dump() {  # <outfile> <url> <seconds>
  : > "$1"
  perl -e 'setpgrp(0,0); exec @ARGV' \
    "$CHROME" --headless=new --disable-gpu --no-first-run --disable-extensions \
              --user-data-dir="$TMP/profile" --dump-dom "$2" > "$1" 2>/dev/null &
  local pid=$! i
  for ((i = 0; i < 2 * $3; i++)); do
    kill -0 "$pid" 2>/dev/null || { wait "$pid" 2>/dev/null; return 0; }
    grep -q '</html>' "$1" 2>/dev/null && break
    sleep 0.5
  done
  for ((i = 0; i < 10; i++)); do            # grace: it may still exit cleanly
    kill -0 "$pid" 2>/dev/null || { wait "$pid" 2>/dev/null; return 0; }
    sleep 0.5
  done
  kill -TERM -- "-$pid" 2>/dev/null         # graceful: lets the profile flush
  for ((i = 0; i < 10; i++)); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.5
  done
  kill -9 -- "-$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  return 0
}

# Preflight: the binary existing does not mean it can RUN here — a sandboxed
# shell lets Chrome spawn and then wedges it mid-launch (observed in this
# repo's own harness). A trivial dump-dom under the watchdog separates "Chrome
# works" from "Chrome cannot run in this environment", so the environment
# skips loudly instead of producing eight false failures.
printf '<!doctype html><title>pre</title>' > "$TMP/pre.html"
chrome_dump "$TMP/pre.dom" "file://$TMP/pre.html" 20
if ! grep -q '<title>pre</title>' "$TMP/pre.dom"; then
  echo "SKIP: Chrome exists but cannot run headless in this environment — the composer functional test DID NOT RUN"
  exit 0
fi
rm -rf "$TMP/profile"

# A Spanish consultation page, so the run also proves the localised chrome:
# the skeleton ships English button labels and the composer must swap them.
mkdir -p "$TMP/reports"
PAGE="$TMP/reports/consult.html"

# The body is generated, not fixed, because BL-190 is about a page REGENERATED
# at the same path with a question rephrased. $1 is Q1's question sentence; the
# ids and data-titles are held identical across both versions, which is what the
# real case looks like -- check_prev enforces id stability AND fails when a kept
# id's data-title changes, so a session cannot signal "same claim, new question"
# through either.
write_body() {  # write_body <q1-question-sentence>
cat > "$TMP/body.html" <<HTML
<meta name="consult-visual" content="none: a persistence probe, nothing to draw">
<div class="page">
<main class="main">
<header><p class="eyebrow">PROBE</p><h1>Persistence probe</h1></header>
<section id="sec-ask">
  <div class="sec-head"><h2>Questions</h2></div>
  <section class="consult-item" data-id="Q1" data-title="The probed question">
    <h3><span class="consult-id">Q1</span>$1</h3>
    <div class="opts one">
      <label><input type="radio" name="Q1" data-label="Option A"><span>Option A</span></label>
      <label><input type="radio" name="Q1" data-label="Option B"><span>Option B</span></label>
    </div>
    <p class="fieldlabel">Notes on this one</p>
    <textarea></textarea>
  </section>
  <section class="consult-item" data-id="Q2" data-title="The untouched question">
    <h3><span class="consult-id">Q2</span>This question never changes</h3>
    <p class="fieldlabel">Write freely</p>
    <div contenteditable="true"></div>
  </section>
  <section class="consult-item consult-notes" data-id="notes" data-title="General notes">
    <h3><span class="consult-id">notes</span>General notes</h3>
    <textarea></textarea>
  </section>
  <div class="endbar">
    <button type="button" id="consult-copy-end">Copy my answers</button>
    <span class="consult-status" id="consult-status-end"></span>
  </div>
</section>
</main>
<aside class="rail">
  <p class="railhead">Contents</p>
  <nav class="raillist" id="raillist"></nav>
  <div class="consult-bar">
    <button type="button" id="consult-copy">Copy my answers</button>
    <span class="consult-status" id="consult-status"></span>
  </div>
</aside>
</div>
<script>
/* Test harness. Runs on load — AFTER the composer, which sits at the end of
 * <body> — and reports through <title>, the one element --dump-dom hands back
 * without needing interaction. */
window.addEventListener('load', function () {
  var q = location.search;
  var ta = document.querySelector('[data-id="Q1"] textarea');
  var radio = document.querySelector('[data-id="Q1"] input[data-label="Option A"]');
  var ce = document.querySelector('[data-id="Q2"] [contenteditable]');
  if (q.indexOf('phase=fill') !== -1) {
    ta.value = 'persisted-answer-123';
    ta.dispatchEvent(new Event('input', { bubbles: true }));
    radio.checked = true;
    radio.dispatchEvent(new Event('change', { bubbles: true }));
    /* The contenteditable is the trap BL-190 names: its text lands in the
     * item's textContent, so a fingerprint taken over the RAW textContent puts
     * the reader's own typing into it and a plain reload stops matching. */
    ce.textContent = 'typed-into-contenteditable-789';
    ce.dispatchEvent(new Event('input', { bubbles: true }));
    document.title = 'FILLED';
  } else if (q.indexOf('phase=seed-legacy') !== -1) {
    /* The v4 schema: marks plus ONE flat free-text list in fixed query order
     * (select, text, contenteditable, textarea). A reader's browser may still
     * hold it; the composer must keep restoring it. */
    localStorage.setItem('aidex-kit-answers:' + location.pathname,
      JSON.stringify({ Q1: { m: ['Option B'], f: ['legacy-answer-456'] } }));
    document.title = 'SEEDED';
  } else if (q.indexOf('phase=verify') !== -1) {
    var banner = document.getElementById('consult-restored');
    document.title = 'RESTORED=' + ta.value
      + '|MARK=' + (radio.checked ? 'A' : (document.querySelector('[data-id="Q1"] input[data-label="Option B"]').checked ? 'B' : '-'))
      + '|CE=' + ce.textContent
      + '|BANNER=' + (banner ? '1' : '0')
      + '|NOTE=' + (banner ? banner.textContent.replace(/[|<>]/g, ' ') : '')
      + '|STATUS=' + document.getElementById('consult-status').textContent.replace(/[|<>]/g, ' ')
      + '|BTN=' + document.getElementById('consult-copy').textContent
      + '|RAIL=' + document.querySelector('.railhead').textContent;
  }
});
</script>
HTML
}

wrap_page() {
  bash "$WRAP" --title "probe" --lang es --out "$PAGE" < "$TMP/body.html" >/dev/null 2>&1 \
    || { fail "the probe page failed to wrap"; echo "1 failure(s)"; exit 1; }
}

Q1_V1='Pick and qualify'
Q1_V2='Pick and qualify — and say which constraint decides it'

write_body "$Q1_V1"
wrap_page

run() {  # run <query> — load the page once, print the resulting <title>
  # A wedged Chrome must FAIL the assertion that reads its title, never hang
  # the whole suite waiting on it — chrome_dump carries the watchdog.
  chrome_dump "$TMP/dom.html" "file://$PAGE?$1" 45 || true
  grep -oE '<title>[^<]*</title>' "$TMP/dom.html" | head -1
}

# ---- type -> reload -> restored --------------------------------------------
t="$(run 'phase=fill')"
[[ "$t" == *FILLED* ]] || fail "the fill phase did not run: $t"

t="$(run 'phase=verify')"
[[ "$t" == *"RESTORED=persisted-answer-123"* ]] \
  || fail "typed free text did not survive the reload: $t"
[[ "$t" == *"MARK=A"* ]] \
  || fail "a checked mark did not survive the reload: $t"
[[ "$t" == *"BANNER=1"* ]] \
  || fail "restored answers arrived without the visible banner: $t"
# The trap: a fingerprint over the item's RAW textContent would include this
# text, so a plain reload with no regeneration would already fail to match.
[[ "$t" == *"CE=typed-into-contenteditable-789"* ]] \
  || fail "text typed into a contenteditable did not survive the reload: $t"

# ---- the chrome speaks the page's language ----------------------------------
[[ "$t" == *"BTN=Copiar mis respuestas"* ]] \
  || fail "the copy button stayed in English on a lang=es page: $t"
[[ "$t" == *"RAIL=Contenido"* ]] \
  || fail "the rail head stayed in English on a lang=es page: $t"

# ---- BL-190: a REPHRASED question must not restore its old answer -----------
#
# The reported case: the reader answered, asked for some questions to be
# explained better, and on reopening the regenerated page those items read as
# already answered with the previous text in them. The page is regenerated at
# the SAME path (that is what keeps the store), with the same id and the same
# data-title, and only the question body changed.
#
# Q2 is the control and it carries the whole weight of this section: it proves
# the discriminant is "did THIS question change", not "was the page
# regenerated". Clearing the store on regeneration would pass every assertion
# about Q1 below and destroy Q2 -- which is R6-02, the defect the persistence
# was built to fix.
write_body "$Q1_V2"
wrap_page
t="$(run 'phase=verify')"

[[ "$t" == *"RESTORED=persisted-answer-123"* ]] \
  && fail "BL-190: a rephrased question restored its stale answer: $t"
[[ "$t" == *"MARK=A"* ]] \
  && fail "BL-190: a rephrased question restored its stale mark: $t"
[[ "$t" == *"CE=typed-into-contenteditable-789"* ]] \
  || fail "BL-190: the UNCHANGED question lost its answer — the fingerprint is not per-item: $t"
# Blank in the status line too, not merely visually empty: `blank` is what the
# artifact contract judges a half-answered page by.
[[ "$t" == *"STATUS="*"Q1"* ]] \
  || fail "BL-190: the skipped item is not counted as blank in the status line: $t"
# The reader must be told why an answer they typed is not there.
[[ "$t" == *"BANNER=1"* ]] \
  || fail "BL-190: nothing told the reader an answer was dropped: $t"
# Matched on the reason, not on a bare digit: `*"1"*` would be satisfied by any
# stray 1 anywhere later in the title and could not fail for the right reason.
[[ "$t" == *"NOTE="*"1 se dejaron en blanco porque su pregunta cambió"* ]] \
  || fail "BL-190: the banner does not report how many were NOT restored, and why: $t"

# Restore the page to v1 so the phases below run against the body they expect.
write_body "$Q1_V1"
wrap_page

# ---- the v4 flat schema still restores (a reader's browser may hold one) ----
rm -rf "$TMP/profile"
t="$(run 'phase=seed-legacy')"
[[ "$t" == *SEEDED* ]] || fail "the legacy seed phase did not run: $t"
t="$(run 'phase=verify')"
[[ "$t" == *"RESTORED=legacy-answer-456"* ]] \
  || fail "a v4 flat-schema answer set no longer restores: $t"
[[ "$t" == *"MARK=B"* ]] \
  || fail "a v4 flat-schema mark no longer restores: $t"

[[ "$failures" -eq 0 ]] || { echo "$failures failure(s)"; exit 1; }
echo "OK — type, reload, restore proven in a real engine; v4 answer sets and the localised chrome included"
