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
cat > "$TMP/body.html" <<'HTML'
<meta name="consult-visual" content="none: a persistence probe, nothing to draw">
<div class="page">
<main class="main">
<header><p class="eyebrow">PROBE</p><h1>Persistence probe</h1></header>
<section id="sec-ask">
  <div class="sec-head"><h2>Questions</h2></div>
  <section class="consult-item" data-id="Q1" data-title="The probed question">
    <h3><span class="consult-id">Q1</span>Pick and qualify</h3>
    <div class="opts one">
      <label><input type="radio" name="Q1" data-label="Option A"><span>Option A</span></label>
      <label><input type="radio" name="Q1" data-label="Option B"><span>Option B</span></label>
    </div>
    <p class="fieldlabel">Notes on this one</p>
    <textarea></textarea>
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
  if (q.indexOf('phase=fill') !== -1) {
    ta.value = 'persisted-answer-123';
    ta.dispatchEvent(new Event('input', { bubbles: true }));
    radio.checked = true;
    radio.dispatchEvent(new Event('change', { bubbles: true }));
    document.title = 'FILLED';
  } else if (q.indexOf('phase=seed-legacy') !== -1) {
    /* The v4 schema: marks plus ONE flat free-text list in fixed query order
     * (select, text, contenteditable, textarea). A reader's browser may still
     * hold it; the composer must keep restoring it. */
    localStorage.setItem('aidex-kit-answers:' + location.pathname,
      JSON.stringify({ Q1: { m: ['Option B'], f: ['legacy-answer-456'] } }));
    document.title = 'SEEDED';
  } else if (q.indexOf('phase=verify') !== -1) {
    document.title = 'RESTORED=' + ta.value
      + '|MARK=' + (radio.checked ? 'A' : (document.querySelector('[data-id="Q1"] input[data-label="Option B"]').checked ? 'B' : '-'))
      + '|BANNER=' + (document.getElementById('consult-restored') ? '1' : '0')
      + '|BTN=' + document.getElementById('consult-copy').textContent
      + '|RAIL=' + document.querySelector('.railhead').textContent;
  }
});
</script>
HTML
bash "$WRAP" --title "probe" --lang es --out "$PAGE" < "$TMP/body.html" >/dev/null 2>&1 \
  || { fail "the probe page failed to wrap"; echo "1 failure(s)"; exit 1; }

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

# ---- the chrome speaks the page's language ----------------------------------
[[ "$t" == *"BTN=Copiar mis respuestas"* ]] \
  || fail "the copy button stayed in English on a lang=es page: $t"
[[ "$t" == *"RAIL=Contenido"* ]] \
  || fail "the rail head stayed in English on a lang=es page: $t"

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
