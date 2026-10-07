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
# Chrome runs under setpgrp (below), so it leads its own process group and does
# not die with this script: the trap kills that group on any exit, and a run
# killed with SIGKILL (no trap runs) is swept by the next start instead, which
# kills every Chrome re-parented to launchd that still holds a composer-fn profile
# and removes its dir. A concurrent run's Chrome is never ppid 1 (BL-495).
CHROME_PID=""
trap '[[ -n "$CHROME_PID" ]] && kill -9 -- "-$CHROME_PID" 2>/dev/null; rm -rf "$TMP"' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
while read -r p dir; do
  kill -9 -- "-$p" "$p" 2>/dev/null
  rm -rf "$dir"
done < <(ps -axo pid=,ppid=,command= \
           | awk '$2 == 1 && match($0, /--user-data-dir=\/tmp\/composer-fn-[^\/ ]+/) {
                    print $1, substr($0, RSTART + 16, RLENGTH - 16) }')
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# $AIDEX_CHROME wins; then chrome-headless-shell, which is not an .app bundle, so
# its launches do not register with LaunchServices and flicker the Dock the way
# every Google Chrome.app launch does, even headless (BL-465); then Chrome.app.
CHROME=""
for c in "${AIDEX_CHROME:-}" \
         "$(command -v chrome-headless-shell 2>/dev/null || true)" \
         "$(ls -d "$HOME"/.cache/puppeteer/chrome-headless-shell/*/chrome-headless-shell-*/chrome-headless-shell 2>/dev/null | tail -1)" \
         "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
         "$(command -v google-chrome 2>/dev/null || true)" \
         "$(command -v chromium 2>/dev/null || true)"; do
  [[ -n "$c" && -x "$c" ]] && { CHROME="$c"; break; }
done
if [[ -z "$CHROME" ]]; then
  echo "SKIP: no Chrome/Chromium binary found — the composer functional test DID NOT RUN"
  exit 0
fi
# Chrome.app's new headless gives its default window a 756x469 viewport; the
# shell gives 800x600, and the cells were written against the former (at 600 px
# tall the BL-326 spy cell read BOTTOM=#Q2 until BL-488; the spy cell now pins 1100x600
# itself). Same default viewport on both.
[[ "$(basename "$CHROME")" == chrome-headless-shell ]] && CHROME_WINDOW="${CHROME_WINDOW:-756,469}"

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
# CHROME_WINDOW=<w>,<h> in the environment sets the window, for the cells that
# measure a layout at a given width (the headless default is 800x600).
chrome_dump() {  # <outfile> <url> <seconds>
  : > "$1"
  perl -e 'setpgrp(0,0); exec @ARGV' \
    "$CHROME" --headless=new --disable-gpu --no-first-run --disable-extensions \
              ${CHROME_WINDOW:+--window-size=$CHROME_WINDOW} \
              --user-data-dir="$TMP/profile" --dump-dom "$2" > "$1" 2>/dev/null &
  CHROME_PID=$!
  local pid=$CHROME_PID i
  for ((i = 0; i < 2 * $3; i++)); do
    kill -0 "$pid" 2>/dev/null || { wait "$pid" 2>/dev/null; CHROME_PID=""; return 0; }
    grep -q '</html>' "$1" 2>/dev/null && break
    sleep 0.5
  done
  for ((i = 0; i < 10; i++)); do            # grace: it may still exit cleanly
    kill -0 "$pid" 2>/dev/null || { wait "$pid" 2>/dev/null; CHROME_PID=""; return 0; }
    sleep 0.5
  done
  kill -TERM -- "-$pid" 2>/dev/null         # graceful: lets the profile flush
  for ((i = 0; i < 10; i++)); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.5
  done
  kill -9 -- "-$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  CHROME_PID=""
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
# These probes test the COMPOSER, and their hand-written pages predate the notes boxes check-artifact
# requires of every block and item (BL-701). Every wrap below goes through a shim that adds the missing
# ones, so no fixture has to repeat them; the BL-701 probe carries its own and the fixup leaves those alone.
REAL_WRAP="$WRAP"
WRAP="$TMP/wrap-with-boxes.sh"
printf '#!/usr/bin/env bash\npython3 "%s" | bash "%s" "$@"\n' "$SKILL/tests/consult_box_fixup.py" "$REAL_WRAP" > "$WRAP"
gopen='<section class="consult-group" id="G1" data-id="G1" data-title="The context"><div class="sec-head"><h2>The context</h2></div><p>What the decisions below share.</p>'
gclose='</section>'
PAGE="$TMP/reports/consult.html"

# The body is generated, not fixed, because BL-190 is about a page REGENERATED
# at the same path with a question rephrased. $1 is Q1's question sentence; the
# ids and data-titles are held identical across both versions, which is what the
# real case looks like -- check_prev enforces id stability AND fails when a kept
# id's data-title changes, so a session cannot signal "same claim, new question"
# through either.
write_body() {  # write_body <q1-question-sentence> [decided-attr]
# $2, when given, is `data-decided="<verdict>"`, stamped on Q1 AND Q2 — the page
# BL-331 taught the checker to accept and BL-341 found the composer had never
# been taught: every question settled, so collect()'s denominator is 0.
local dec="${2:-}"
cat > "$TMP/body.html" <<HTML
<meta name="consult-visual" content="none: a persistence probe, nothing to draw">
<div class="page">
<main class="main">
<header><p class="eyebrow">PROBE</p><h1>Persistence probe</h1></header>
<section id="sec-ask">
  <div class="sec-head"><h2>Questions</h2></div>
$gopen
  <section class="consult-item" data-id="Q0" data-title="La decision ya tomada" data-decided>
    <h3><span class="consult-id">Q0</span>Esta ya se decidi&oacute; en una ronda anterior</h3>
    <div class="opts one">
      <label><input type="radio" name="Q0" data-label="La opcion elegida" checked><span>La opci&oacute;n elegida</span></label>
      <label><input type="radio" name="Q0" data-label="La opcion descartada"><span>La opci&oacute;n descartada</span></label>
    </div>
    <p class="fieldlabel">Notes on this one</p>
    <textarea></textarea>
  </section>
  <section class="consult-item" data-id="Q1" data-title="The probed question" $dec>
    <h3><span class="consult-id">Q1</span>$1</h3>
    <div class="opts one">
      <label><input type="radio" name="Q1" data-label="Option A" data-recommended><span>Option A <span class="hint">why</span></span></label>
      <label><input type="radio" name="Q1" data-label="Option B"><span>Option B</span></label>
    </div>
    <p class="fieldlabel">Notes on this one</p>
    <textarea placeholder="Anything the options do not cover&hellip;"></textarea>
  </section>
  <section class="consult-item" data-id="Q2" data-title="The untouched question" data-free $dec>
    <h3><span class="consult-id">Q2</span>This question never changes</h3>
    <p class="fieldlabel">Write freely</p>
    <div contenteditable="true"></div>
  </section>
$gclose
  <!-- Headless defaults to 800x600 and the spy needs a page that actually
       scrolls. Inert, aria-hidden, and after the block, so no other phase's
       assertion can see it. -->
  <div aria-hidden="true" style="height:1600px"></div>
  <section class="consult-item consult-notes" data-id="notes" data-title="General notes">
    <h3><span class="consult-id">notes</span>General notes</h3>
    <textarea></textarea>
  </section>
  <div class="endbar">
    <button type="button" id="consult-copy-end">Copy my answers</button>
    <span class="consult-status" id="consult-status-end"></span>
  </div>
</section>
<section id="sec-ref"><div class="sec-head"><h2>Reference</h2></div><p>A short trailing section, after the general notes (BL-488).</p></section>
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
  } else if (q.indexOf('phase=spy') !== -1) {
    /* BL-326. Capping the rail to the viewport is only half the fix: a rail
     * that now scrolls internally hides the reader's position instead of
     * hiding its own bottom. This asserts the other half — the entry marked
     * aria-current follows the page, and is inside the list's visible box when
     * it does, which is what a scrollable index has to guarantee.
     *
     * No backticks anywhere in this branch: write_body's heredoc is unquoted,
     * so a backtick in a comment is a command substitution run by bash. */
    var rl = document.getElementById('raillist');
    var cur = function () {
      var c = rl.querySelector('[aria-current]');
      return c ? c.getAttribute('href') : 'none';
    };
    var vis = function () {
      var c = rl.querySelector('[aria-current]');
      if (!c) return '0';
      var lr = rl.getBoundingClientRect(), cr = c.getBoundingClientRect();
      return (cr.top >= lr.top - 1 && cr.bottom <= lr.bottom + 1) ? '1' : '0';
    };
    var atTop = cur();
    window.scrollTo(0, document.documentElement.scrollHeight);
    window.dispatchEvent(new Event('scroll'));
    var atBottom = cur(), visAtBottom = vis();
    window.scrollTo(0, 0);
    window.dispatchEvent(new Event('scroll'));
    document.title = 'SPY|RLDISP=' + getComputedStyle(rl).display + '|TOP=' + atTop + '|BOTTOM=' + atBottom
                   + '|VIS=' + visAtBottom + '|BACK=' + cur();
  } else if (q.indexOf('phase=seed-legacy') !== -1) {
    /* The v4 schema: marks plus ONE flat free-text list in fixed query order
     * (select, text, contenteditable, textarea). A reader's browser may still
     * hold it; the composer must keep restoring it. */
    localStorage.setItem('aidex-kit-answers:' + location.pathname,
      JSON.stringify({ Q1: { m: ['Option B'], f: ['legacy-answer-456'] } }));
    document.title = 'SEEDED';
  } else if (q.indexOf('phase=send') !== -1) {
    /* Pressing the copy button IS sending. The clipboard is stubbed rather than
     * read back: navigator.clipboard.writeText is what the composer calls, so
     * capturing it proves the composed markdown the reader actually pastes —
     * including the recommendation suffix, which is the half of BL-245 that a
     * DOM assertion cannot see. */
    var captured = '';
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: function (s) { captured = s; return Promise.resolve(); } }
    });
    document.getElementById('consult-copy').click();
    document.title = 'SENT|PASTE=' + captured.replace(/[|<>\n]/g, ' ');
  } else if (q.indexOf('phase=retype') !== -1) {
    /* Editing an item after sending it un-sends it: the sent flag is derived by
     * comparing the copied fingerprint against the CURRENT body on every save,
     * so this needs no event of its own to stay in step. */
    ce.textContent = 'retyped-after-sending-000';
    ce.dispatchEvent(new Event('input', { bubbles: true }));
    document.title = 'RETYPED';
  } else if (q.indexOf('phase=downgrade') !== -1) {
    /* A reader mid-thread when the kit is upgraded: their stored answers were
     * saved by v6, so they carry no round and no sent flag. Rebuilt by sending
     * and then stripping both keys, rather than hand-written, so the question
     * fingerprint is a real one this page will match. */
    var K = 'aidex-kit-answers:' + location.pathname;
    document.getElementById('consult-copy').click();
    var d = JSON.parse(localStorage.getItem(K) || '{}');
    Object.keys(d).forEach(function (k) { delete d[k].r; delete d[k].x; });
    localStorage.setItem(K, JSON.stringify(d));
    document.title = 'DOWNGRADED=' + JSON.stringify(d).replace(/[|<>]/g, ' ');
  } else if (q.indexOf('phase=stale') !== -1) {
    /* BL-635: another tab writing a NEWER built stamp for this path marks this tab
     * stale; an equal or older stamp, or this tab's own load, shows nothing. No
     * backticks in this branch (the heredoc is unquoted). */
    var bm = document.querySelector('meta[name="artifact-built"]');
    var mine = bm ? bm.getAttribute('content') : '';
    var SK = 'aidex-kit-built:' + location.pathname;
    var nb = function () { return document.getElementById('consult-stale') ? '1' : '0'; };
    var send = function (b, r, m, k) {
      window.dispatchEvent(new StorageEvent('storage', { key: k || SK,
        newValue: JSON.stringify({ b: b, r: r === undefined ? '1' : r, m: m || 0 }) }));
      return nb();
    };
    var R = parseInt(document.querySelector('meta[name="consult-round"]').getAttribute('content'), 10) || 0;
    var LM = Date.parse(document.lastModified) || 0;
    var own = nb(), eq = send(mine, String(R), LM), old = send('2000-01-01 00:00'),
        xkey = send('9999-01-01 00:00', '1', 0, 'aidex-kit-built:/elsewhere.html');
    /* Same minute: an equal stamp and round with an OLDER mtime shows nothing, a
     * later round shows the banner (tie-break on the round as a number), and
     * where the round ties a later mtime does (tie-break on the file). */
    var eqold = send(mine, String(R), LM - 1000);
    var sb0 = document.getElementById('consult-stale');
    var other = send(mine, String(R + 1), 0);
    if (sb0 = document.getElementById('consult-stale')) sb0.remove();
    var eqm = send(mine, String(R), LM + 1000);
    if (sb0 = document.getElementById('consult-stale')) sb0.remove();
    var big = send('9999-01-01 00:00');
    var sb = document.getElementById('consult-stale');
    document.title = 'STALE|OWN=' + own + '|EQ=' + eq + '|OLD=' + old + '|XKEY=' + xkey + '|EQOLD=' + eqold + '|NEWR=' + other + '|NEWM=' + eqm + '|NEW=' + big
      + '|N=' + document.querySelectorAll('#consult-stale').length
      + '|BTN=' + (sb && sb.querySelector('a,button') ? '1' : '0')
      + '|TXT=' + (sb ? sb.textContent : '').replace(/[|<>]/g, ' ')
      + '|SHOWN=' + (sb && sb.getBoundingClientRect().height > 0 ? '1' : '0')
      + '|STORED=' + (localStorage.getItem(SK) || '').replace(/[|<>]/g, ' ');
  } else if (q.indexOf('phase=clear') !== -1) {
    var btn = document.querySelector('[data-id="Q1"] .consult-clear');
    if (btn) btn.click();
    document.title = 'CLEARED=' + (btn ? '1' : '0')
      + '|TA=' + ta.value
      + '|MARK=' + (radio.checked ? 'A' : '-')
      + '|STORE=' + (localStorage.getItem('aidex-kit-answers:' + location.pathname) || '')
          .replace(/[|<>]/g, ' ')
      + '|LABEL=' + btn.textContent
      /* BL-248: the control lives in the label row, not under the resize
       * handle, and disappears once the item is blank again. */
      + '|CLEARROW=' + (btn && btn.parentElement.classList.contains('fieldrow') ? '1' : '0')
      + '|CLEARVIS=' + (btn ? getComputedStyle(btn).display : '');
  } else if (q.indexOf('phase=count') !== -1) {
    /* BL-268: the status counted BLOCK HEADINGS as answers. collect() pushed
     * "## G1 · title" into the same array whose length it reported, so two
     * answered items in one block read "3 de 3" — and a full page read "12 de 9"
     * in the field. Two items answered here, one blank: the truth is 2 of 3. */
    ta.value = 'count-probe';
    ta.dispatchEvent(new Event('input', { bubbles: true }));
    ce.textContent = 'count-probe-2';
    ce.dispatchEvent(new Event('input', { bubbles: true }));
    document.title = 'COUNTED|STATUS=' + document.getElementById('consult-status').textContent.replace(/[|<>]/g, ' ');
  } else if (q.indexOf('phase=toggle') !== -1) {
    /* BL-268: a radio, once picked, could not be un-picked except by Clear —
     * which also wipes the notes. Clicking the picked option again releases it.
     * The label is what a reader clicks; mousedown precedes the click the
     * browser then forwards to the input, which is the sequence the composer
     * keys on. */
    var lab = radio.closest('label');
    function press() {
      lab.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
      lab.click();
    }
    press();
    var after1 = radio.checked ? 'A' : '-';
    press();
    var after2 = radio.checked ? 'A' : '-';
    document.title = 'TOGGLED|AFTER1=' + after1 + '|AFTER2=' + after2
      + '|STATUS=' + document.getElementById('consult-status').textContent.replace(/[|<>]/g, ' ');
  } else if (q.indexOf('phase=other') !== -1) {
    /* BL-268: every option group ends with an "other" choice the composer
     * injects, so a reader whose answer is none of the options can say so with
     * a mark and put the answer in the notes — instead of leaving the group
     * unmarked and hoping the notes are read as the answer. */
    var other = document.querySelector('[data-id="Q1"] .opts .kit-other input');
    var lastLabel = document.querySelector('[data-id="Q1"] .opts label:last-child');
    if (other) {
      other.checked = true;
      other.dispatchEvent(new Event('change', { bubbles: true }));
    }
    document.title = 'OTHERED|OTHER=' + (other ? '1' : '0')
      + '|OTHERNAME=' + (other ? other.name : '')
      + '|OTHERTYPE=' + (other ? other.type : '')
      /* Since v18 the group ends with the "not now" radio (BL-381), so "other"
       * is the last ANSWER choice — the row immediately before it. */
      + '|OTHERLAST=' + (other && lastLabel && lastLabel.contains(other) ? '1' : '0')
      + '|OTHERBEFOREEX=' + (other && other.closest('label').nextElementSibling
          && other.closest('label').nextElementSibling.classList.contains('kit-notnow') ? '1' : '0')
      + '|OTHERTEXT=' + (other ? other.closest('label').textContent.replace(/[|<>]/g, ' ').trim() : '')
      + '|OTHERCOUNT=' + document.querySelectorAll('[data-id="Q1"] .opts .kit-other').length
      + '|A=' + (radio.checked ? 'A' : '-');
  } else if (q.indexOf('phase=notes') !== -1) {
    /* C: the general-notes box is not one of the questions. Two readings of the
     * same rule, both from the owner: a page whose every QUESTION is answered
     * must not report the notes box as an omission, and a page whose ONLY
     * filled box is the notes must still be sendable. */
    var qa = document.querySelector('[data-id="Q1"] input[data-label="Option A"]');
    if (qa) { qa.checked = true; qa.dispatchEvent(new Event('change', { bubbles: true })); }
    var ce = document.querySelector('[data-id="Q2"] [contenteditable]');
    if (ce) { ce.textContent = 'answered in free text'; ce.dispatchEvent(new Event('input', { bubbles: true })); }
    var full = document.getElementById('consult-status').textContent;

    /* Now the other direction: clear the questions, fill only the notes. */
    if (qa) { qa.checked = false; qa.dispatchEvent(new Event('change', { bubbles: true })); }
    if (ce) { ce.textContent = ''; ce.dispatchEvent(new Event('input', { bubbles: true })); }
    var nt = document.querySelector('.consult-notes textarea');
    if (nt) { nt.value = 'something that fits no question'; nt.dispatchEvent(new Event('input', { bubbles: true })); }
    var ncap = '';
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: function (str) { ncap = str; return Promise.resolve(); } }
    });
    document.getElementById('consult-copy').click();
    var dec = document.querySelector('[data-id="Q0"]');
    document.title = 'NOTED|DECIN=' + (dec ? dec.querySelectorAll('input:not(:disabled), textarea:not(:disabled)').length : -1)
      + '|DECCTL=' + (dec ? dec.querySelectorAll('.kit-explain, .kit-other, .consult-clear').length : -1)
      + '|DECDONE=' + (dec && dec.classList.contains('has-answer') ? '1' : '0')
      + '|FULL=' + full.replace(/[|<>]/g, ' ')
      + '|ONLYNOTES=' + ncap.replace(/[|<>\n]/g, ' ')
      + '|STATUS=' + document.getElementById('consult-status').textContent.replace(/[|<>]/g, ' ');
  } else if (q.indexOf('phase=alldecided') !== -1) {
    /* BL-341: every question on the page is decided, so collect() counts a
     * denominator of ZERO — and refresh() fell through to the same string a
     * blank page shows, telling a reader who had just settled the last question
     * that nothing was answered yet. What must be true: the status names the
     * closed state, and the copy bar STAYS — the general-notes box is not one
     * of the questions, so it is still fillable and still sendable here.
     *
     * DECIDED is the non-empty-input guard: if the decided attribute stopped
     * being stamped, this phase would be probing an ordinary page and every
     * assertion below it would pass for the wrong reason. */
    var stEl = document.getElementById('consult-status');
    var st0 = stEl.textContent;
    var bar = document.querySelector('.consult-bar');
    var eb = document.querySelector('.endbar');
    var barH = bar ? bar.getBoundingClientRect().height : 0;
    var ebH = eb ? eb.getBoundingClientRect().height : 0;
    var nt3 = document.querySelector('.consult-notes textarea');
    var acap = '';
    /* BL-587: copy with the notes box still empty. The message must not contradict
     * the status line (which says everything is decided). */
    document.getElementById('consult-copy').click();
    var emptyCopy = stEl.textContent;
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: function (s) { acap = s; return Promise.resolve(); } }
    });
    if (nt3) {
      nt3.value = 'the notes box still takes an answer';
      nt3.dispatchEvent(new Event('input', { bubbles: true }));
    }
    var st1 = stEl.textContent;
    document.getElementById('consult-copy').click();
    document.title = 'ALLDECIDED|STATUS=' + st0.replace(/[|<>]/g, ' ')
      + '|EMPTYCOPY=' + emptyCopy.replace(/[|<>]/g, ' ') + '|'
      + '|AFTERNOTES=' + st1.replace(/[|<>]/g, ' ')
      + '|DECIDED=' + document.querySelectorAll('.consult-item[data-decided]').length
      + '|OPEN=' + document.querySelectorAll('.consult-item:not([data-decided])').length
      + '|BARH=' + (barH > 0 ? '1' : '0')
      + '|BARDISP=' + (bar ? getComputedStyle(bar).display : 'none')
      + '|RAILPOS=' + getComputedStyle(document.querySelector('.rail')).position
      + '|ENDH=' + (ebH > 0 ? '1' : '0')
      + '|NOTESDIS=' + (nt3 ? (nt3.disabled ? '1' : '0') : 'x')
      + '|NOTESEND=' + acap.replace(/[|<>\n]/g, ' ')
      /* BL-373: the settled block is COLLAPSED out of the flow, not deleted and
       * not left in place. Every field here separates one of those three from
       * the other two, which a single "is it visible" check cannot. */
      + '|DECSEC=' + (document.getElementById('sec-decided') ? '1' : '0')
      + '|UNITS=' + document.querySelectorAll('#sec-decided .decided-unit').length
      + '|MOVED=' + (document.querySelector('#sec-decided [data-id="Q1"]') ? '1' : '0')
      + '|INFLOW=' + document.querySelectorAll('#sec-ask > .consult-group').length
      /* Anchored on the section EXISTING: without it the open-details query is
       * null and FOLDED would read 1 on a page that collapsed nothing. */
      + '|FOLDED=' + (document.getElementById('sec-decided')
          && !document.querySelector('#sec-decided details[open]') ? '1' : '0')
      + '|DECHEAD=' + ((document.querySelector('#sec-decided h2') || {}).textContent || '')
      + '|RAILDEC=' + document.querySelectorAll('#raillist a[href="#sec-decided"]').length
      + '|RAILQ=' + document.querySelectorAll('#raillist a[href="#Q0"], #raillist a[href="#Q1"], #raillist a[href="#Q2"], #raillist a[href="#G1"]').length
      + '|RAILN=' + document.querySelectorAll('#raillist a[href="#notes"]').length;
  } else if (q.indexOf('phase=partial') !== -1) {
    /* BL-380: a block that is only PARTLY decided. v17 left such a block
     * entirely alone — every decided item stayed fully drawn and kept its rail
     * entry — so a page eleven blocks deep in its iteration looked exactly like
     * round one. The fixture's G1 is that shape: Q0 decided, Q1 and Q2 open.
     * What must be true: Q0 folds IN PLACE (inside G1, behind a summary that
     * carries its id, title and the option that won), the block's context and
     * open items stay drawn, no composer section is built, and the rail lists
     * the block plus its OPEN items only. */
    var g1 = document.getElementById('G1');
    var unit = g1 ? g1.querySelector('details.decided-unit') : null;
    var q0 = document.querySelector('[data-id="Q0"]');
    document.title = 'PARTIAL|DECSEC=' + (document.getElementById('sec-decided') ? '1' : '0')
      + '|INPLACE=' + (unit && unit.contains(q0) ? '1' : '0')
      + '|UNITS=' + (g1 ? g1.querySelectorAll('details.decided-unit').length : -1)
      + '|FOLDED=' + (unit && !unit.open ? '1' : '0')
      + '|SUMMARY=' + (unit ? unit.querySelector('summary').textContent.replace(/[|<>]/g, ' ').replace(/\s+/g, ' ').trim() : '')
      + '|CONTEXT=' + (g1 && g1.querySelector(':scope > p') ? '1' : '0')
      + '|OPENINFLOW=' + (g1 ? g1.querySelectorAll(':scope > .consult-item:not([data-decided])').length : -1)
      + '|SEALED=' + (q0 ? q0.querySelectorAll('input:not(:disabled), textarea:not(:disabled)').length : -1)
      + '|RAILG=' + document.querySelectorAll('#raillist a[href="#G1"]').length
      + '|RAILDEC=' + document.querySelectorAll('#raillist a[href="#Q0"]').length
      + '|RAILOPEN=' + document.querySelectorAll('#raillist a[href="#Q1"], #raillist a[href="#Q2"]').length
      + '|STATUS=' + document.getElementById('consult-status').textContent.replace(/[|<>]/g, ' ');
  } else if (q.indexOf('phase=explain') !== -1) {
    /* BL-325 / BL-381: the reader who cannot answer because the QUESTION is
     * unreadable — or who can answer and still needs something explained.
     * v15/v16 made the escapes radios in the answer group, exclusive with the
     * answer and with each other; 348 mined owner messages showed the asks
     * arriving combined ("explícamelo mejor y vuelve a darme las opciones")
     * and alongside answers ("Sí, pero…"). Since v18 the asks are a CHECKBOX
     * ROW on the item, separate from the answer radio, with a tagged
     * vocabulary; the answer group gains a "not now" radio.
     *
     * The paste is captured the same way phase=send does it, because the
     * markers travelling back is the whole point. */
    var row = document.querySelector('[data-id="Q1"] .kit-ask');
    var ask = function (m) { return row ? row.querySelector('input[data-label="' + m + '"]') : null; };
    var exState = ask('[explain-state]'), exOpts = ask('[explain-options]'),
        exWhy = ask('[explain-why]'), exSimpler = ask('[explain-simpler]'),
        exQuestion = ask('[question]'), exReframe = ask('[reframe]'), exShow = ask('[show-me]'),
        exMore = ask('[more-examples]');
    var pre = document.querySelector('[data-id="Q1"] input[data-label="Option A"]');
    if (pre) { pre.checked = true; pre.dispatchEvent(new Event('change', { bubbles: true })); }
    /* An option AND asks: the item is PROVISIONAL, and the page has to say so
     * the moment both are set (census 2026-09-20: 19 of 333 answers are this
     * shape and the rule for them was unwritten). */
    var provBefore = document.querySelectorAll('[data-id="Q1"] .kit-provisional').length;
    [exState, exWhy, exQuestion].forEach(function (c) {
      if (c) { c.checked = true; c.dispatchEvent(new Event('change', { bubbles: true })); }
    });
    /* Ticking 'tengo una pregunta' puts the cursor in the notes box: the
     * question itself travels in the notes, so the box is where the reader
     * must land without hunting for it. */
    var focused = document.activeElement === document.querySelector('[data-id="Q1"] textarea');
    var provOn = document.querySelectorAll('[data-id="Q1"] .kit-provisional').length;
    var provText = provOn ? document.querySelector('[data-id="Q1"] .kit-provisional')
        .textContent.replace(/[|<>]/g, ' ').replace(/\s+/g, ' ').trim() : '';
    var xcap = '';
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: function (s) { xcap = s; return Promise.resolve(); } }
    });
    document.getElementById('consult-copy').click();
    var st1 = document.getElementById('consult-status').textContent;
    var answerKept = pre && pre.checked;
    /* Releasing the option releases the provisional line with it. */
    if (pre) { pre.checked = false; pre.dispatchEvent(new Event('change', { bubbles: true })); }
    var provOff = document.querySelectorAll('[data-id="Q1"] .kit-provisional').length;
    if (pre) { pre.checked = true; pre.dispatchEvent(new Event('change', { bubbles: true })); }
    /* BL-505: [more-examples] combines like any other ask — ticked alone
     * beside the chosen answer it makes the item provisional too. Isolated
     * from exState/exWhy/exQuestion so the provisional count reflects ONLY
     * more-examples, not a mix already proven above. */
    [exState, exWhy, exQuestion].forEach(function (c) {
      if (c) { c.checked = false; c.dispatchEvent(new Event('change', { bubbles: true })); }
    });
    var provNoAsks = document.querySelectorAll('[data-id="Q1"] .kit-provisional').length;
    if (exMore) { exMore.checked = true; exMore.dispatchEvent(new Event('change', { bubbles: true })); }
    var provWithMore = document.querySelectorAll('[data-id="Q1"] .kit-provisional').length;
    var mcap = '';
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: function (s) { mcap = s; return Promise.resolve(); } }
    });
    document.getElementById('consult-copy').click();
    if (exMore) { exMore.checked = false; exMore.dispatchEvent(new Event('change', { bubbles: true })); }
    /* The page-defect report (LOOP-008 Q10) is a button that opens its OWN
     * box, apart from the notes. It must not make the answer provisional, it
     * must travel as a labelled sub-block at the END of the item's block, and
     * alone (no answer) it still travels. Blur first so a stale focus on the
     * notes box cannot pass the focus check for free. */
    document.activeElement.blur();
    var dBtn = document.querySelector('[data-id="Q1"] .kit-defect-btn');
    var dBox = document.querySelector('[data-id="Q1"] textarea.kit-defect-text');
    var notesBox = document.querySelector('[data-id="Q1"] textarea:not(.kit-defect-text)');
    var dHiddenBefore = dBox ? dBox.closest('.kit-defect-box').hidden : null;
    if (dBtn) dBtn.click();
    var focusedDefect = dBox && document.activeElement === dBox;
    var dOpen = dBox ? !dBox.closest('.kit-defect-box').hidden : false;
    notesBox.value = 'una nota'; notesBox.dispatchEvent(new Event('input', { bubbles: true }));
    dBox.value = 'el boton | se ve roto'; dBox.dispatchEvent(new Event('input', { bubbles: true }));
    if (dBtn) dBtn.click();   /* filled: stays open */
    var dStaysOpen = dBox ? !dBox.closest('.kit-defect-box').hidden : false;
    var provWithDefect = document.querySelectorAll('[data-id="Q1"] .kit-provisional').length;
    var dcap = '';
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: function (s) { dcap = s; return Promise.resolve(); } }
    });
    document.getElementById('consult-copy').click();
    /* a defect alone: release the answer and the note */
    if (pre) { pre.checked = false; pre.dispatchEvent(new Event('change', { bubbles: true })); }
    notesBox.value = ''; notesBox.dispatchEvent(new Event('input', { bubbles: true }));
    var dAnswered = document.querySelector('[data-id="Q1"]').classList.contains('has-answer');
    var donly = '';
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: function (s) { donly = s; return Promise.resolve(); } }
    });
    document.getElementById('consult-copy').click();
    /* saved and restored by the store, like the other free fields */
    var stored = (localStorage.getItem(Object.keys(localStorage).filter(function (k) { return k.indexOf('aidex-kit-answers:') === 0; })[0]) || '');
    var dStored = stored.indexOf('el boton') !== -1;
    /* with the defect alone, Clear is shown (and empties the box) though nothing is answered */
    var clearBtn = document.querySelector('[data-id="Q1"] .consult-clear');
    var clearShown = clearBtn ? getComputedStyle(clearBtn).display !== 'none' : false;
    if (clearBtn) clearBtn.click();
    var clearEmptied = dBox.value === '';
    if (dBtn) dBtn.click();   /* Clear closed the emptied box: open it again... */
    if (dBtn) dBtn.click();   /* ...and an empty box closes on the next click */
    var dClosed = dBox ? dBox.closest('.kit-defect-box').hidden : false;
    if (pre) { pre.checked = true; pre.dispatchEvent(new Event('change', { bubbles: true })); }
    /* Restore the state the rest of the scenario (the notNow paste checks
     * below) expects. */
    [exState, exWhy, exQuestion].forEach(function (c) {
      if (c) { c.checked = true; c.dispatchEvent(new Event('change', { bubbles: true })); }
    });
    /* Now the answer side: "not now" is a radio in the group, so it releases
     * the answer, counts as a response and pastes its own marker. */
    var notNow = document.querySelector('[data-id="Q1"] .opts input[data-label="[not-now]"]');
    if (notNow) { notNow.checked = true; notNow.dispatchEvent(new Event('change', { bubbles: true })); }
    var ncap = '';
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: function (s) { ncap = s; return Promise.resolve(); } }
    });
    document.getElementById('consult-copy').click();
    var rowEl = row;
    document.title = 'EXPLAINED|ROW=' + (row ? '1' : '0')
      + '|CHIPS=' + [exState, exOpts, exWhy, exSimpler, exQuestion, exReframe, exShow, exMore].filter(Boolean).length
      + '|TERMCHIP=' + (row && row.querySelector('input[data-label="[explain-term]"]') ? '1' : '0')
      + '|TERMBOX=' + document.querySelectorAll('[data-id="Q1"] .kit-term').length
      + '|PROVBEFORE=' + provBefore + '|PROVON=' + provOn + '|PROVOFF=' + provOff
      + '|PROVTEXT=' + provText
      + '|PROVNOASKS=' + provNoAsks + '|PROVWITHMORE=' + provWithMore + '|PROVWITHDEFECT=' + provWithDefect
      + '|FOCUSDEFECT=' + (focusedDefect ? '1' : '0')
      + '|MCAP=' + mcap.replace(/[|<>\n]/g, ' ')
      + '|DCAP=' + dcap.replace(/[|<>]/g, ' ').replace(/\n/g, '~')
      + '|DONLY=' + donly.replace(/[|<>]/g, ' ').replace(/\n/g, '~')
      + '|DSTATE=' + [dHiddenBefore ? 1 : 0, dOpen ? 1 : 0, dStaysOpen ? 1 : 0, dClosed ? 1 : 0, dAnswered ? 1 : 0, dStored ? 1 : 0, clearShown ? 1 : 0, clearEmptied ? 1 : 0].join('')
      + '|DCHIP=' + (row && row.querySelector('input[data-label="[page-defect]"]') ? 1 : 0)
      + '|FOCUSNOTES=' + (focused ? '1' : '0')
      + '|CHIPTYPE=' + (exState ? exState.type : '')
      + '|CHIPINGROUP=' + (exState && exState.closest('.opts') ? '1' : '0')
      + '|ANSWERKEPT=' + (answerKept ? '1' : '0')
      + '|BOTHKEPT=' + (exState && exState.checked && exWhy && exWhy.checked ? '1' : '0')
      + '|ROWAFTEROPTS=' + (rowEl && rowEl.previousElementSibling && rowEl.previousElementSibling.classList.contains('opts') ? '1' : '0')
      + '|EXNOGROUP=' + document.querySelectorAll('[data-id="Q2"] .kit-ask').length
      + '|EXNOTES=' + document.querySelectorAll('.consult-notes .kit-ask').length
      + '|EXDECIDED=' + document.querySelectorAll('[data-id="Q0"] .kit-ask, [data-id="Q0"] input[data-label="[not-now]"]').length
      + '|EXCOUNT=' + document.querySelectorAll('.consult-item .kit-ask').length
      + '|ROWTEXT=' + (row ? row.textContent.replace(/[|<>]/g, ' ').replace(/\s+/g, ' ').trim() : '')
      + '|NOTNOW=' + (notNow ? notNow.type + ':' + notNow.name : '')
      + '|NOTNOWRELEASED=' + (pre && !pre.checked ? '1' : '0')
      + '|NOTNOWTEXT=' + (notNow ? notNow.closest('label').textContent.replace(/[|<>]/g, ' ').trim() : '')
      + '|PROVNOTNOW=' + document.querySelectorAll('[data-id="Q1"] .kit-provisional').length
      + '|PASTE=' + xcap.replace(/[|<>\n]/g, ' ')
      + '|PASTE2=' + ncap.replace(/[|<>\n]/g, ' ')
      + '|STATUS=' + st1.replace(/[|<>]/g, ' ')
      + '|STATUS2=' + document.getElementById('consult-status').textContent.replace(/[|<>]/g, ' ');
  } else if (q.indexOf('phase=theme') !== -1) {
    /* BL-327. tokens.css has defined the palette three times since it was
     * written and nothing ever set data-theme, so a third of it had never
     * applied. What has to be true: no stored choice means NO attribute (the
     * default path is prefers-color-scheme and must not change), a click sets
     * it and the page actually repaints, and a second click comes back. The
     * background is read from the computed style, not from the attribute — an
     * attribute that no rule matches would pass an attribute-only assertion. */
    var tb = document.getElementById('kit-theme');
    var bg = function () { return getComputedStyle(document.body).backgroundColor; };
    var before = document.documentElement.getAttribute('data-theme');
    var bg0 = bg();
    if (tb) tb.click();
    var t1 = document.documentElement.getAttribute('data-theme'), bg1 = bg(), lab1 = tb ? tb.textContent : '';
    if (tb) tb.click();
    var t2 = document.documentElement.getAttribute('data-theme'), bg2 = bg();
    if (tb) tb.click();
    document.title = 'THEMED|BTN=' + (tb ? '1' : '0')
      + '|BEFORE=' + (before === null ? 'null' : before)
      + '|T1=' + t1 + '|T2=' + t2
      + '|REPAINT1=' + (bg1 !== bg0 ? '1' : '0')
      + '|REPAINT2=' + (bg2 !== bg1 ? '1' : '0')
      + '|LABEL1=' + lab1
      + '|TAB=' + (tb ? (tb.tabIndex >= 0 ? '1' : '0') : '0');
  } else if (q.indexOf('phase=recall') !== -1) {
    var tk = document.getElementById('kit-theme');
    document.title = 'THEMEKEPT=' + document.documentElement.getAttribute('data-theme')
      + '|LABEL=' + (tk ? tk.textContent : '');
  } else if (q.indexOf('phase=verify') !== -1) {
    var banner = document.getElementById('consult-restored');
    document.title = 'RESTORED=' + ta.value
      + '|MARK=' + (radio.checked ? 'A' : (document.querySelector('[data-id="Q1"] input[data-label="Option B"]').checked ? 'B'
                   : ((document.querySelector('[data-id="Q1"] .kit-other input') || {}).checked ? 'O' : '-')))
      + '|CE=' + ce.textContent
      + '|BANNER=' + (banner ? '1' : '0')
      + '|NOTE=' + (banner ? banner.textContent.replace(/[|<>]/g, ' ') : '')
      + '|STATUS=' + document.getElementById('consult-status').textContent.replace(/[|<>]/g, ' ')
      + '|BTN=' + document.getElementById('consult-copy').textContent
      + '|RAIL=' + document.querySelector('.railhead').textContent
      + '|FL=' + document.querySelector('[data-id="Q1"] .fieldlabel').textContent
      + '|PH=' + document.querySelector('[data-id="Q1"] textarea').getAttribute('placeholder')
      + '|FLKEPT=' + document.querySelector('[data-id="Q2"] .fieldlabel').textContent
      + '|ROUND=' + ((document.querySelector('meta[name="consult-round"]') || {}).content || '')
      /* BL-325: the explain request is a mark like any other, so it inherits
       * the round rule for free — restored on a reload, gone once sent. */
      + '|EXKEPT=' + ((document.querySelector('[data-id="Q1"] .kit-ask input[type="checkbox"]') || {}).checked ? '1' : '0')
      + '|QKEPT=' + ((document.querySelector('[data-id="Q1"] .kit-ask input[data-label="[question]"]') || {}).checked ? '1' : '0')
      + '|REC=' + (document.querySelector('[data-id="Q1"] .kit-tag') || {}).textContent
      + '|RECPOS=' + (document.querySelector('[data-id="Q1"] .kit-tag + .hint') ? 'before-hint' : 'elsewhere')
      /* BL-247: the rail nests a block's items under the block — one entry
       * for the context, its decisions indented below, the loose general
       * notes after the separator. Read as the ORDER of rail entries. */
      + '|RAIL_ORDER=' + [].map.call(document.querySelectorAll('#raillist .railitem'), function (a) {
          return (a.classList.contains('grp') ? 'G:' : a.classList.contains('sub') ? 'sub:' : a.classList.contains('sec') ? 'sec:' : 'item:') + a.getAttribute('href');
        }).join(',');
  }
});
</script>
HTML
}

wrap_page() {  # wrap_page [lang] — the page's language, es unless a caller says otherwise
  bash "$WRAP" --title "probe" --lang "${1:-es}" --out "$PAGE" < "$TMP/body.html" > "$TMP/wrap.log" 2>&1 \
    || { fail "the probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/wrap.log" | sed -n 1,4p)"; echo "1 failure(s)"; exit 1; }
}

# BL-507: `consult-round` is the READER's round. A re-wrap stays in the same round
# until save-reply.sh has recorded the answer to it, so a fixture that means "a new
# round arrives" saves a reply first. Before BL-507 every wrap was a new round; the
# cells below that mean a new round call this, and their expectations are unchanged.
wrap_next_round() {
  printf 'Q1: ok\nQ2: ok\n' | bash "$SKILL/scripts/save-reply.sh" "$PAGE" - >/dev/null 2>&1 \
    || fail "save-reply.sh failed on the probe page"
  wrap_page "$@"
}

Q1_V1='Pick and qualify'
Q1_V2='Pick and qualify — and say which constraint decides it'

write_body "$Q1_V1"
wrap_page

run() {  # run <query> — load the page once, print the resulting <title>
  # A wedged Chrome must FAIL the assertion that reads its title, never hang
  # the whole suite waiting on it — chrome_dump carries the watchdog.
  chrome_dump "$TMP/dom.html" "file://$PAGE?$1" 45 || true
  grep -oE '<title>[^<]*</title>' "$TMP/dom.html" | sed -n 1p
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
# Q0 is a DECIDED item: it leaves the question set but stays in the rail, which
# is the index of the page and not a list of what is still owed. Q0 is decided,
# so since v18 (BL-380) it has no entry of its own: the block is the way in.
# The notes sit inside sec-ask, before sec-ref, and the rail lists them there
# (kit 41, rail-order-loose-items): until then they were appended after sec-ref.
[[ "$t" == *"RAIL_ORDER=sec:#sec-ask,G:#G1,sub:#Q1,sub:#Q2,item:#notes,sec:#sec-ref"* ]] \
  || fail "BL-247: the rail does not nest the block's items under the block (context once, decisions indented, loose notes in body order): $t"
# The trap: a fingerprint over the item's RAW textContent would include this
# text, so a plain reload with no regeneration would already fail to match.
[[ "$t" == *"CE=typed-into-contenteditable-789"* ]] \
  || fail "text typed into a contenteditable did not survive the reload: $t"

# ---- BL-326: the rail says where the reader is, and keeps it in view --------
# Its own variable, not $t: the assertions below this block read the title of
# the `phase=verify` run above, so reusing $t here silently retargets five
# localisation checks at this page instead.
# BL-488: a short trailing section never passes the reading line, so the cell scrolls to
# the bottom at 1100x600 (rail visible, below 62rem the list is display:none) and expects
# the LAST section in the page, not the last rail entry.
ts="$(CHROME_WINDOW=1100,600 run 'phase=spy')"
[[ "$ts" == *"RLDISP="* && "$ts" != *"RLDISP=none"* ]] \
  || fail "BL-488: the rail list is not displayed at the spy window, so the cell would prove nothing: $ts"
[[ "$ts" == *SPY* ]] || fail "the spy phase did not run: $ts"
[[ "$ts" == *"TOP=#sec-ask"* ]] \
  || fail "BL-326: nothing was marked current at the top of the page: $ts"
[[ "$ts" == *"BOTTOM=#sec-ref"* ]] \
  || fail "BL-326: the current entry did not follow the page to its last section: $ts"
# The half that makes the cap survivable: a marked entry the reader cannot see
# inside a now-scrollable rail is the original complaint moved indoors.
[[ "$ts" == *"VIS=1"* ]] \
  || fail "BL-326: the current entry was outside the rail's visible box: $ts"
[[ "$ts" == *"BACK=#sec-ask"* ]] \
  || fail "BL-326: scrolling back up did not move the current entry back: $ts"

# ---- BL-599: an overflowing rail shows the entry AFTER the current one -------
# 21 entries at 1280x900 overflow the list. With Q3 current the general notes
# entry is the next one; the tracker used to scroll the list only far enough for
# Q3, so notes stayed below the list's edge until the page bottom, and the
# separator above it shrank to 0 px as an empty flex child.
PAGE_SAVED="$PAGE"; PAGE="$TMP/reports/rail599.html"
{
  echo '<meta name="consult-visual" content="none: a rail probe, nothing to draw">'
  echo '<div class="page"><main class="main"><header><p class="eyebrow">PROBE</p><h1>Rail probe</h1></header>'
  echo '<section class="consult-group" id="G1" data-id="G1" data-title="Estados"><div class="sec-head"><h2>Estados de la página</h2></div><p>Contexto.</p>'
  for i in $(seq 1 14); do
    echo "<section class=\"consult-item\" data-id=\"R$i\" data-title=\"Cambiar persona: el servidor lo rechaza $i\"><h3><span class=\"consult-id\">R$i</span>¿Cambiar persona en el caso $i?</h3><div class=\"opts one\"><label><input type=\"radio\" name=\"R$i\" data-label=\"Si\"><span>Sí</span></label><label><input type=\"radio\" name=\"R$i\" data-label=\"No\"><span>No</span></label></div><textarea></textarea></section>"
  done
  echo '</section><section class="consult-group" id="G2" data-id="G2" data-title="Detalles"><div class="sec-head"><h2>Tres detalles de la página</h2></div><p>Contexto.</p>'
  for i in 1 2 3; do
    echo "<section class=\"consult-item\" data-id=\"Q$i\" data-title=\"¿Un solo botón Dar acceso cuando la persona no tiene accesos $i?\"><h3><span class=\"consult-id\">Q$i</span>¿Un solo botón Dar acceso $i?</h3><div class=\"opts one\"><label><input type=\"radio\" name=\"Q$i\" data-label=\"Si\"><span>Sí</span></label><label><input type=\"radio\" name=\"Q$i\" data-label=\"No\"><span>No</span></label></div><textarea></textarea></section>"
  done
  echo '</section><section class="consult-item consult-notes" data-id="notes" data-title="Notas generales"><h3><span class="consult-id">notas</span>Notas generales</h3><textarea></textarea></section>'
  echo '<div class="endbar"><button type="button" id="consult-copy-end">Copiar</button><span class="consult-status" id="consult-status-end"></span></div>'
  echo '</main><aside class="rail"><p class="railhead">Contenido</p><nav class="raillist" id="raillist"></nav><div class="consult-bar"><button type="button" id="consult-copy">Copiar</button><span class="consult-status" id="consult-status"></span></div></aside></div>'
  cat <<'HTML'
<script>window.addEventListener('load', function () {
  var rl = document.getElementById('raillist');
  scrollTo(0, document.getElementById('Q3').getBoundingClientRect().top + scrollY - 100);
  dispatchEvent(new Event('scroll'));
  var cur = rl.querySelector('[aria-current]'), lr = rl.getBoundingClientRect();
  var nr = rl.querySelector('a[href="#notes"]').getBoundingClientRect();
  var cr = cur ? cur.getBoundingClientRect() : nr;
  document.title = 'R599|OVER=' + (rl.scrollHeight > rl.clientHeight ? 1 : 0)
    + '|CUR=' + (cur ? cur.getAttribute('href') : 'none')
    + '|CURVIS=' + (cr.top >= lr.top - 1 && cr.bottom <= lr.bottom + 1 ? 1 : 0)
    + '|NOTESVIS=' + (nr.top >= lr.top - 1 && nr.bottom <= lr.bottom + 1 ? 1 : 0)
    + '|SEPH=' + rl.querySelector('.railsep').getBoundingClientRect().height
    + '|CURTOP=' + (cr.top >= lr.top - 1 ? 1 : 0)
    + '|PAIR=' + (function () {
        var n = cur && cur.nextElementSibling;
        while (n && !n.classList.contains('railitem')) n = n.nextElementSibling;
        return n && n.getBoundingClientRect().bottom - cr.top > rl.clientHeight ? 1 : 0;
      })() + '|';
});</script>
HTML
} > "$TMP/body.html"
wrap_page es
tr="$(CHROME_WINDOW=1280,900 run 'phase=rail599')"
[[ "$tr" == *"|OVER=1|"* && "$tr" == *"|CUR=#Q3|"* && "$tr" == *"|CURVIS=1|"* ]] \
  || fail "BL-599: the probe did not reach an overflowing rail with Q3 current and in view, so the cell proves nothing: $tr"
[[ "$tr" == *"|NOTESVIS=1|"* ]] \
  || fail "BL-599: with Q3 current the next rail entry (general notes) is below the list's visible edge: $tr"
[[ "$tr" =~ \|SEPH=([0-9.]+)\| ]] && python3 -c "import sys; sys.exit(abs(float('${BASH_REMATCH[1]}') - 1) > 0.5)" \
  || fail "BL-599: the rail separator is not its declared 1 px in an overflowing list: $tr"
# A short window: the current entry and the one after it no longer fit together, so the current
# entry wins and its top stays inside the list.
tr="$(CHROME_WINDOW=1280,300 run 'phase=rail599')"
[[ "$tr" == *"|OVER=1|"* && "$tr" != *"|CUR=none|"* && "$tr" == *"|PAIR=1|"* ]] \
  || fail "BL-599: the short-window probe did not reach a current+next pair taller than the list, so the cap cell proves nothing: $tr"
[[ "$tr" == *"|CURTOP=1|"* ]] \
  || fail "BL-599: keeping the next entry in view scrolled the current entry's top out of the list: $tr"
PAGE="$PAGE_SAVED"

# ---- rail-order-loose-items / kit-hidden-section-visible ---------------------
# The general notes sit in the body BEFORE a later section. The rail listed every
# section first and appended loose items after a separator, so it disagreed with
# the body on 28 of 84 real pages. And `.main > section { display:flex }` beat the
# UA's [hidden] rule, so a section marked hidden stayed drawn. A hidden section
# gets no rail entry either: drawn as nothing, its rect top is 0 and the scroll
# spy marked it current while the reader was still in the section before it.
ORD="$TMP/reports/railorder.html"
cat > "$TMP/ordbody.html" <<'HTML'
<meta name="consult-visual" content="none: a rail order probe, nothing to draw">
<div class="page"><main class="main"><header><p class="eyebrow">PROBE</p><h1>Rail order probe</h1></header>
<section class="consult-group" id="G1" data-id="G1" data-title="Uno"><div class="sec-head"><h2>Uno</h2></div><p>Contexto.</p>
<section class="consult-item" data-id="Q1" data-title="Primera"><h3><span class="consult-id">Q1</span>¿Primera?</h3><div class="opts one"><label><input type="radio" name="Q1" data-label="Si"><span>Sí</span></label><label><input type="radio" name="Q1" data-label="No"><span>No</span></label></div><textarea></textarea></section>
<section class="consult-item" data-id="Q2" data-title="Segunda"><h3><span class="consult-id">Q2</span>¿Segunda?</h3><div class="opts one"><label><input type="radio" name="Q2" data-label="Si"><span>Sí</span></label><label><input type="radio" name="Q2" data-label="No"><span>No</span></label></div><textarea></textarea></section>
</section>
<section class="consult-item consult-notes" data-id="notes" data-title="Notas generales"><h3><span class="consult-id">notas</span>Notas generales</h3><textarea></textarea></section>
<section id="sec-after"><div class="sec-head"><h2>Después de las notas</h2></div><p>Una sección que el cuerpo pone tras las notas.</p><div aria-hidden="true" style="height:1400px"></div></section>
<section id="sec-hid" hidden><div class="sec-head"><h2>Oculta</h2></div><p>Marcada hidden por el autor.</p></section>
<section id="sec-end"><div class="sec-head"><h2>Al final</h2></div><p>Visible, tras la oculta.</p><div aria-hidden="true" style="height:1400px"></div></section>
<div class="endbar"><button type="button" id="consult-copy-end">Copiar</button><span class="consult-status" id="consult-status-end"></span></div>
</main><aside class="rail"><p class="railhead">Contenido</p><nav class="raillist" id="raillist"></nav><div class="consult-bar"><button type="button" id="consult-copy">Copiar</button><span class="consult-status" id="consult-status"></span></div></aside></div>
<script>window.addEventListener('load', function () {
  scrollTo(0, document.getElementById('sec-after').getBoundingClientRect().top + scrollY + 300);
  dispatchEvent(new Event('scroll'));
  var cur = document.querySelector('#raillist [aria-current]');
  document.title = 'ORD|ORDER=' + [].map.call(document.querySelectorAll('#raillist a'), function (a) {
      return a.getAttribute('href'); }).join(',')
    + '|HID=' + getComputedStyle(document.getElementById('sec-hid')).display
    + '|CUR=' + (cur ? cur.getAttribute('href') : 'none') + '|';
});</script>
HTML
bash "$WRAP" --title "probe" --lang es --out "$ORD" < "$TMP/ordbody.html" > "$TMP/ord.log" 2>&1 \
  || fail "rail-order-loose-items: the probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/ord.log" | sed -n 1,4p)"
CHROME_WINDOW=1280,900 chrome_dump "$TMP/ord.dom" "file://$ORD" 45 || true
to="$(grep -oE '<title>[^<]*</title>' "$TMP/ord.dom" | sed -n 1p)"
[[ "$to" == *"ORD|"* ]] || fail "rail-order-loose-items: the order probe did not run: $to"
[[ "$to" == *"|ORDER=#G1,#Q1,#Q2,#notes,#sec-after,#sec-end|"* ]] \
  || fail "rail-order-loose-items: the rail does not follow the body's order, hidden section left out (want #G1,#Q1,#Q2,#notes,#sec-after,#sec-end): $to"
[[ "$to" == *"|CUR=#sec-after|"* ]] \
  || fail "kit-hidden-section-visible: scrolled into the section before a hidden one, the rail marks another entry current (want #sec-after): $to"
[[ "$to" == *"|HID=none|"* ]] \
  || fail "kit-hidden-section-visible: a section marked hidden is still drawn (want display none): $to"

# ---- BL-532 / BL-535 / BL-536: dropped items, one copy bar, the table's first column
# One small page: a decided item, a DROPPED one (never answered), an open one, a
# table whose second column is long prose, and both copy bars. Read at 390 px
# (the phone layout, where the rail is a bottom bar and the end bar used to repeat it).
NPAGE="$TMP/reports/narrow.html"
cat > "$TMP/nbody.html" <<HTML
<meta name="consult-visual" content="none: a layout probe, nothing to draw">
<div class="page">
<main class="main">
<header><p class="eyebrow">PROBE</p><h1>Narrow probe</h1></header>
<section id="sec-ask">
  <div class="sec-head"><h2>Questions</h2></div>
<section class="consult-group" id="G1" data-id="G1" data-title="Uno"><div class="sec-head"><h2>Uno</h2></div><p>El contexto de la pregunta, en espa&ntilde;ol.</p>
  <section class="consult-item" data-id="D1" data-title="Settled" data-decided="**Option A**, con notas">
    <h3><span class="consult-id">D1</span>Pregunta ya resuelta de esta sonda</h3>
    <div class="opts one"><label><input type="radio" name="D1" data-label="Option A" checked><span>Option A</span></label></div>
    <p class="fieldlabel">Notas sobre esta</p><textarea></textarea>
  </section>

</section>
<section class="consult-group" id="G2" data-id="G2" data-title="Dos"><div class="sec-head"><h2>Dos</h2></div><p>El contexto de la pregunta, en espa&ntilde;ol.</p>
  <section class="consult-item" data-id="X1" data-title="Left the set" data-decided="Descartada: ya no aplica" data-dropped="ya no aplica">
    <h3><span class="consult-id">X1</span>Pregunta descartada de esta sonda</h3>
    <p class="fieldlabel">Notas sobre esta</p><textarea></textarea>
  </section>

</section>
<section class="consult-group" id="G4" data-id="G4" data-title="Cuatro"><div class="sec-head"><h2>Cuatro</h2></div><p>Un bloque con una decidida y una descartada.</p>
  <section class="consult-item" data-id="D2" data-title="Settled two" data-decided="Option A">
    <h3><span class="consult-id">D2</span>Segunda pregunta ya resuelta</h3>
    <div class="opts one"><label><input type="radio" name="D2" data-label="Option A" checked><span>Option A</span></label></div>
    <p class="fieldlabel">Notas sobre esta</p><textarea></textarea>
  </section>
  <section class="consult-item" data-id="X2" data-title="Left two" data-decided="Descartada: ya no aplica" data-dropped="ya no aplica">
    <h3><span class="consult-id">X2</span>Segunda pregunta descartada</h3>
    <p class="fieldlabel">Notas sobre esta</p><textarea></textarea>
  </section>
</section>
<section class="consult-group" id="G3" data-id="G3" data-title="Tres"><div class="sec-head"><h2>Tres</h2></div><p>El contexto de la pregunta, en espa&ntilde;ol.</p>
  <section class="consult-item" data-id="Q1" data-title="Open" data-free>
    <h3><span class="consult-id">Q1</span>Pregunta abierta de esta sonda</h3>
    <p class="fieldlabel">Escribe con libertad</p><div contenteditable="true"></div>
  </section>

</section>
  <section class="consult-item consult-notes" data-id="notes" data-title="Notas generales">
    <h3><span class="consult-id">notes</span>Notas generales</h3>
    <textarea></textarea>
  </section>
  <div class="tw"><table id="t-label">
    <thead><tr><th>Rol</th><th>Por qu&eacute;</th></tr></thead>
    <tbody><tr><td>Responsable de la entrega</td><td>El reporte de barridos toma la ventana por d&iacute;a natural, as&iacute; que dos barridos del mismo d&iacute;a se reclaman las corridas de prueba del otro; al terminar, cada corrida queda ligada a su lista de trabajo</td></tr></tbody>
  </table></div>
  <div class="tw"><table id="t-id">
    <thead><tr><th>Fuente</th><th>Tarea</th></tr></thead>
    <tbody><tr><td>BL-489</td><td>El reporte de barridos toma la ventana por d&iacute;a natural, as&iacute; que dos barridos del mismo d&iacute;a se reclaman las corridas de prueba del otro; al terminar, cada corrida queda ligada a su lista de trabajo</td></tr></tbody>
  </table></div>
  <div class="tw"><table id="t-two">
    <thead><tr><th>Categor&iacute;a</th><th>Conteo</th></tr></thead>
    <tbody><tr><td>Herramienta equivocada o llamada repetida en la misma sesi&oacute;n</td><td>41</td></tr><tr><td>Contexto perdido</td><td>12</td></tr></tbody>
  </table></div>
  <div class="tw"><table id="t-three">
    <thead><tr><th>Cat</th><th>Nombre de columna muy largo sin cortes</th><th>Otra</th></tr></thead>
    <tbody><tr><td>a</td><td>El reporte de barridos toma la ventana por d&iacute;a natural</td><td>c</td></tr></tbody>
  </table></div>
  <div class="tw"><table id="t-short2">
    <thead><tr><th>Archivo</th><th>Estado</th></tr></thead>
    <tbody><tr><td>components.css l&iacute;nea 520</td><td>pendiente de la revisi&oacute;n</td></tr></tbody>
  </table></div>
  <div class="tw"><table id="t-short3">
    <thead><tr><th>Fecha</th><th>Ruta</th><th>Estado</th></tr></thead>
    <tbody><tr><td>2026-08-21 10:00 UTC</td><td>skills/artifact/scripts</td><td>pendiente de revisar</td></tr></tbody>
  </table></div>
  <div class="tw"><table id="t-path">
    <thead><tr><th>Ruta</th><th>Estado</th></tr></thead>
    <tbody><tr><td id="pathcell">skills/artifact/assets/artifact_kit/scripts/composer_functional.js</td><td id="datecell">revisado el 01/10/2026 por el equipo</td></tr></tbody>
  </table></div>
  <ul><li><div class="tw"><table id="t-li"><tbody><tr><td id="liprose">entrada/salida y/o errores</td></tr></tbody></table></div></li></ul>
  <div class="tw"><table id="t-pdate">
    <thead><tr><th>Ruta</th><th>Estado</th></tr></thead>
    <tbody><tr><td id="pathcell3">skills/artifact/assets/artifact_kit/2026/10/01/composer_functional.js</td><td>pendiente de revisar</td></tr></tbody>
  </table></div>
  <div class="tw"><table id="t-pnest">
    <thead><tr><th>Paso</th><th>Detalle</th><th>Estado</th></tr></thead>
    <tbody><tr><td>Medir</td><td><table><thead><tr><th>Ruta</th></tr></thead><tbody><tr><td id="pathcell2">skills/artifact/assets/artifact_kit/scripts/composer_functional.js</td></tr></tbody></table></td><td>ok</td></tr></tbody>
  </table></div>
  <div class="tw"><table id="t-pnestw">
    <thead><tr><th>Paso</th><th>Detalle</th><th>Estado</th></tr></thead>
    <tbody><tr><td>Medir</td><td><div class="tw"><table><thead><tr><th>Ruta</th></tr></thead><tbody><tr><td id="pathcell4">skills/artifact/assets/artifact_kit/scripts/composer_functional.js</td></tr></tbody></table></div></td><td>ok</td></tr></tbody>
  </table></div>
  <div class="tw"><table id="t-nest">
    <thead><tr><th>Paso</th><th>Detalle</th></tr></thead>
    <tbody><tr><td>Medir</td><td><table><thead><tr><th>A</th><th>B</th><th>C</th><th>D</th></tr></thead><tbody><tr><td>a</td><td>b</td><td>c</td><td>d</td></tr></tbody></table></td></tr></tbody>
  </table></div>
  <div class="tw"><table id="t-four">
    <thead><tr><th>Rol</th><th>Por qu&eacute;</th><th>Cu&aacute;ndo</th><th>Qui&eacute;n</th></tr></thead>
    <tbody><tr><td>Responsable de la entrega</td><td>El reporte de barridos toma la ventana por d&iacute;a natural, as&iacute; que dos barridos del mismo d&iacute;a se reclaman las corridas de prueba del otro; al terminar, cada corrida queda ligada a su lista de trabajo</td><td>Hoy</td><td>Ana</td></tr></tbody>
  </table></div>
  <div class="endbar">
    <button type="button" id="consult-copy-end">Copiar mis respuestas</button>
    <span class="consult-status" id="consult-status-end"></span>
  </div>
</section>
</main>
<aside class="rail">
  <p class="railhead">Contenido</p>
  <nav class="raillist" id="raillist"></nav>
  <div class="consult-bar">
    <button type="button" id="consult-copy">Copiar mis respuestas</button>
    <span class="consult-status" id="consult-status"></span>
  </div>
</aside>
</div>
<script>
window.addEventListener('load', function () {
  var shown = function (el) {
    return !!el && getComputedStyle(el).display !== 'none' && el.getClientRects().length > 0;
  };
  var txt = function (sel) { var e = document.querySelector(sel); return e ? e.textContent.replace(/[|]/g, '/').replace(/\n/g, '; ') : 'none'; };
  var w = function (sel) { var e = document.querySelector(sel); return e ? Math.round(e.getBoundingClientRect().width) : -1; };
  /* BL-567: 1 when the table needs no sideways scroll AND its last cell ends inside the
   * viewport; the 4-column table is the one that may keep scrolling. */
  var fits = function (sel) {
    var t = document.querySelector(sel), box = t && t.closest('.tw');
    if (!box) return -1;
    var row = t.rows[t.rows.length - 1], last = row.cells[row.cells.length - 1].getBoundingClientRect().right;
    return box.scrollWidth <= box.clientWidth + 1 && last <= window.innerWidth ? 1 : 0;
  };
  /* BL-585: 1 when the path cell is cut (more than one line, the last-resort class on) and
   * every line starts right after a "/", with the text unchanged; else why not. Lines are
   * read per character from Range rects, so a mid-word cut is seen where it happens. */
  var PATH = 'skills/artifact/assets/artifact_kit/scripts/composer_functional.js';
  var pathBreaks = function (id, want) {
    var td = document.getElementById(id || 'pathcell');
    if (!td || td.textContent !== (want || PATH)) return 'text';
    if (!td.classList.contains('brk')) return 'nobrk' + td.className + '_' + td.getBoundingClientRect().width + '_' + td.closest('.tw').scrollWidth + '_' + td.closest('.tw').clientWidth;
    var tw = document.createTreeWalker(td, NodeFilter.SHOW_TEXT), n, text = '', tops = [];
    while ((n = tw.nextNode())) {
      for (var i = 0; i < n.nodeValue.length; i++) {
        var r = document.createRange();
        r.setStart(n, i); r.setEnd(n, i + 1);
        tops.push(Math.round(r.getBoundingClientRect().top)); text += n.nodeValue.charAt(i);
      }
    }
    var lines = 1;
    for (var k = 1; k < tops.length; k++) {
      if (tops[k] > tops[k - 1] + 2) { lines++; if (text.charAt(k - 1) !== '/') return 'mid@' + k; }
    }
    return lines > 1 ? 1 : 'oneline';
  };
  /* BL-585: a date (digit "/" digit) stays on one line even when the table is cut. */
  var dateJoined = function () {
    var td = document.getElementById('datecell'), D = '01/10/2026';
    var at = td.textContent.indexOf(D), tops = [], tw = document.createTreeWalker(td, NodeFilter.SHOW_TEXT), n, pos = 0;
    if (!td.classList.contains('brk')) return 'nobrk';
    while ((n = tw.nextNode())) {
      for (var i = 0; i < n.nodeValue.length; i++, pos++) {
        if (pos < at || pos >= at + D.length) continue;
        var r = document.createRange(); r.setStart(n, i); r.setEnd(n, i + 1);
        var tp = Math.round(r.getBoundingClientRect().top);
        if (tops.indexOf(tp) === -1) tops.push(tp);
      }
    }
    return tops.length === 1 ? 1 : 'split' + tops.length;
  };
  var slashWbr = function () { return document.querySelectorAll('#t-path wbr.kit-slash').length; };
  var PATH3 = 'skills/artifact/assets/artifact_kit/2026/10/01/composer_functional.js';
  var dateJ = dateJoined(), path3 = pathBreaks('pathcell3', PATH3);
  /* BL-585: widening the box drops .brk and the hints; narrowing brings them back. */
  var tw1 = document.getElementById('t-path').closest('.tw'), wb0 = slashWbr();
  tw1.style.width = '3000px'; tw1.style.maxWidth = 'none'; window.dispatchEvent(new Event('resize'));
  var wbWide = slashWbr(), brkWide = document.getElementById('pathcell').classList.contains('brk') ? 1 : 0;
  /* BL-604: a table that fits, inside an <li> (which inherits overflow-wrap: anywhere), is not cut. */
  var liWbr = document.querySelectorAll('#t-li wbr.kit-slash').length + '/' + (document.getElementById('liprose').classList.contains('brk') ? 1 : 0);
  tw1.style.width = ''; tw1.style.maxWidth = ''; window.dispatchEvent(new Event('resize'));
  var wbBack = slashWbr();
  /* BL-585: the same answer after every resize (the cut is re-measured each time). */
  var first = pathBreaks(), first2 = pathBreaks('pathcell2'), first2w = pathBreaks('pathcell4'), rs = [];
  for (var q = 0; q < 2; q++) {
    window.dispatchEvent(new Event('resize'));
    rs.push(pathBreaks() + '/' + fits('#t-path'));
  }
  document.title = 'NARROW|W=' + window.innerWidth
    + '|PATHBRK=' + first + '|DATEJ=' + dateJ + '|PATHDATE=' + path3 + '|WBR=' + (wb0 > 0 ? 1 : 0) + '/' + wbWide + '/' + brkWide + '/' + (wbBack === wb0 ? 1 : 0) + '|PATHBRK2=' + first2 + '|PATHBRK2W=' + first2w + '|LIWBR=' + liWbr + '|PATHRS=' + rs.join(',')
    + '|BARS=' + ['consult-copy', 'consult-copy-end'].filter(function (i) { return shown(document.getElementById(i)); }).length
    + '|L1=' + w('#t-label td:first-child') + '|L2=' + w('#t-label td:last-child') + '|I1=' + w('#t-id td:first-child')
    + '|FIT2=' + fits('#t-two') + '|FIT3=' + fits('#t-three') + '|FITS2=' + fits('#t-short2') + '|FITS3=' + fits('#t-short3') + '|FITN=' + fits('#t-nest')
    + '|FIT4=' + fits('#t-four') + '|F4C2=' + w('#t-four td:nth-child(2)')
    + '|RAILPOS=' + getComputedStyle(document.querySelector('.rail')).position
    + '|DEC=' + txt('#sec-decided .eyebrow')
    + '|DECH=' + txt('#sec-decided h2')
    + '|DEC_HAS_X1=' + (document.querySelector('#sec-decided [data-id="X1"]') ? 1 : 0)
    + '|DRP=' + txt('#sec-dropped .eyebrow')
    + '|DRPH=' + txt('#sec-dropped h2')
    + '|DRPN=' + document.querySelectorAll('#sec-dropped .consult-item').length
    + '|DRPHINT=' + txt('#sec-dropped .decided-hint')
    + '|MIX=' + [].map.call(document.querySelectorAll('#sec-decided summary'), function (d) { return d.textContent.replace(/[|]/g, '/').replace(/\n/g, '; '); }).join(';')
    + '|DRP_HAS_X1=' + (document.querySelector('#sec-dropped [data-id="X1"]') ? 1 : 0)
    + '|RAIL=' + [].map.call(document.querySelectorAll('#raillist .railitem.sec'), function (a) { return a.textContent.trim(); }).join(',')
    /* Last, because it mutates: answer the one open question WITHOUT deciding it. Nothing
     * is left blank, but the question is still open, so the bar must stay pinned. */
    + (function () {
      var ce = document.querySelector('[data-id="Q1"] [contenteditable]');
      ce.textContent = 'answered in the browser';
      ce.dispatchEvent(new Event('input', { bubbles: true }));
      return '|RAILANS=' + getComputedStyle(document.querySelector('.rail')).position;
    })();
});
</script>
HTML
bash "$WRAP" --title "narrow" --lang es --out "$NPAGE" < "$TMP/nbody.html" > "$TMP/nwrap.log" 2>&1 \
  || fail "the narrow probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/nwrap.log" | sed -n 1,4p)"
CHROME_WINDOW=390,900 chrome_dump "$TMP/ndom.html" "file://$NPAGE" 45 || true
tn="$(grep -oE '<title>[^<]*</title>' "$TMP/ndom.html" | sed -n 1p)"
[[ "$tn" == *"NARROW|W=390|"* ]] || fail "the narrow phase did not run at 390 px: $tn"
# BL-532: a dropped item is counted and headed apart from the decided ones.
[[ "$tn" == *"|DEC=2 preguntas ya resueltas|DECH=Decidido|DEC_HAS_X1=0|"* ]] \
  || fail "BL-532: a dropped item was counted or filed as decided: $tn"
[[ "$tn" == *"|DRP=1 pregunta descartada, sin responder|DRPH=Descartadas|DRPN=1|"* && "$tn" == *"|DRP_HAS_X1=1|"* ]] \
  || fail "BL-532: a dropped item was not shown as dropped, or the count is not what the section holds: $tn"
[[ "$tn" == *"|DRPHINT=Estas preguntas salieron del conjunto"* ]] \
  || fail "BL-532: the dropped section reuses the decided hint instead of saying the questions left the set: $tn"
[[ "$tn" == *"Left two: Descartada: ya no aplica"* && "$tn" != *"Settled two: Descartada"* ]] \
  || fail "BL-532/BL-608: in a mixed block the dropped item X2 must carry its dropped verdict and the decided D2 must not: $tn"
# BL-545: D1's verdict is written `**Option A**, con notas`, which is NOT its checked
# label: the fold shows the written verdict, plain (the checked label alone would be
# decidedLine winning over data-decided).
mix="${tn#*|MIX=}"; mix="${mix%%|*}"
[[ "$mix" == *"Settled: Option A, con notas"* && "$mix" != *"**"* ]] \
  || fail "BL-545: the decided summary does not show D1's written verdict plain (want 'Settled: Option A, con notas', no '**'): MIX=$mix"
[[ "$tn" == *"RAIL="*"Descartadas"* ]] \
  || fail "BL-532: the rail has no entry for the dropped section: $tn"
[[ "$tn" == *"|BARS=1|"* ]] \
  || fail "BL-535: at 390 px the copy bar is not shown exactly once: $tn"
l1="$(sed -nE 's/.*\|L1=([0-9]+)\|.*/\1/p' <<<"$tn")"
l2="$(sed -nE 's/.*\|L2=([0-9]+)\|.*/\1/p' <<<"$tn")"
i1="$(sed -nE 's/.*\|I1=([0-9]+)\|.*/\1/p' <<<"$tn")"
# BL-567: a table of one to three columns FITS the screen (every column visible, no
# sideways scroll); only a table of four or more keeps the BL-536 floor and scrolls
# inside .tw. The 2-column t-label used to be the floor's example (L2 = 358 with it):
# it now wraps to the screen, and what must hold is that its label column is not
# squeezed to a single word per line (L1 >= 100) while the prose beside it still fits
# (the floor itself is pinned by F4C2 below, not by these two).
# BL-585: the last-resort cut of a path falls after a "/", never inside a segment.
[[ "$tn" == *"|PATHBRK=1|"* ]] \
  || fail "BL-585: at 390 px a still-overflowing table cuts a path mid-segment, or never cut it (want every line break after '/'): $tn"
[[ "$tn" == *"|PATHBRK2=1|"* ]] \
  || fail "BL-585: a path in a table nested in a cell of a 3-column table is cut mid-segment or never cut on first load: $tn"
# BL-604: the same nested table with its OWN .tw wrapper. The inner .tw is measured after the
# outer one and its box fits (the outer cell's overflow-wrap reaches the path), so it used to
# drop the slash hints and the path was cut mid-segment.
[[ "$tn" == *"|PATHBRK2W=1|"* ]] \
  || fail "BL-604: a path in a nested table with its own .tw wrapper is cut mid-segment or never cut (want breaks after '/' only): $tn"
[[ "$tn" == *"|LIWBR=0/0|"* ]] \
  || fail "BL-604: a fitting table inside an <li> got .brk or slash <wbr> from the li's inherited overflow-wrap (want 0/0): $tn"
[[ "$tn" == *"|PATHRS=1/1,1/1|"* ]] \
  || fail "BL-585: after a resize the path cut changes (want 1/1 twice: broken after slashes, table fits): $tn"
[[ "$tn" == *"|DATEJ=1|"* ]] \
  || fail "BL-585: a d/m/y date in a prose cell is split across lines when the table is cut (want one line): $tn"
[[ "$tn" == *"|PATHDATE=1|"* ]] \
  || fail "BL-585: a path with a dated segment is cut mid-segment or never cut (want breaks after '/' only): $tn"
[[ "$tn" == *"|WBR=1/0/0/1|"* ]] \
  || fail "BL-585: widening must drop .brk and every kit-slash wbr, narrowing must bring them back (want 1/0/0/1): $tn"
fit2="$(sed -nE 's/.*\|FIT2=(-?[0-9]+)\|.*/\1/p' <<<"$tn")"
fit3="$(sed -nE 's/.*\|FIT3=(-?[0-9]+)\|.*/\1/p' <<<"$tn")"
fit4="$(sed -nE 's/.*\|FIT4=(-?[0-9]+)\|.*/\1/p' <<<"$tn")"
[[ "$fit2" == 1 ]] \
  || fail "BL-567: at 390 px a 2-column table scrolls sideways or ends off screen (FIT2=${fit2:-?}): its answer column is out of sight: $tn"
[[ "$fit3" == 1 ]] \
  || fail "BL-567: at 390 px a 3-column table with a long header scrolls sideways or ends off screen (FIT3=${fit3:-?}): $tn"
[[ "$fit4" == 0 ]] \
  || fail "BL-536: at 390 px a 4-column table fits the screen (FIT4=${fit4:-?}) so it lost its floor and its columns are squeezed to a word: $tn"
fits2="$(sed -nE 's/.*\|FITS2=(-?[0-9]+)\|.*/\1/p' <<<"$tn")"
fits3="$(sed -nE 's/.*\|FITS3=(-?[0-9]+)\|.*/\1/p' <<<"$tn")"
fitn="$(sed -nE 's/.*\|FITN=(-?[0-9]+)\|.*/\1/p' <<<"$tn")"
# BL-248 keeps a short cell on one line, but not at the price of the answer column: when
# the no-wrap cells make a small table wider than the screen, the table wraps instead.
[[ "$fits2" == 1 ]] \
  || fail "BL-567: at 390 px a 2-column table of short cells scrolls sideways (FITS2=${fits2:-?}): the no-wrap cells of BL-248 pushed its answer column out of sight: $tn"
[[ "$fits3" == 1 ]] \
  || fail "BL-567: at 390 px a 3-column table of short cells scrolls sideways (FITS3=${fits3:-?}): $tn"
# A 4-column table inside a cell is not the outer table's column count.
[[ "$fitn" == 1 ]] \
  || fail "BL-567: at 390 px a 2-column table holding a 4-column table in a cell was given the 4-column floor and scrolls (FITN=${fitn:-?}): $tn"
# What only the 30rem floor produces: the prose column of the 4-column table stays wide
# (226 px with the floor, 81 without it, measured at 390 px; the table itself 480 vs 324).
f4c2="$(sed -nE 's/.*\|F4C2=(-?[0-9]+)\|.*/\1/p' <<<"$tn")"
[[ -n "$f4c2" && "$f4c2" -ge 150 ]] \
  || fail "BL-536: at 390 px the prose column of a 4-column table is ${f4c2:-?}px: the table lost its 30rem floor and was squeezed onto the screen instead of scrolling inside .tw (want >= 150): $tn"
[[ -n "$l1" && "$l1" -ge 100 && -n "$l2" && "$l2" -ge 150 ]] \
  || fail "BL-536/BL-567: at 390 px a short label column (${l1:-?}px) or the prose beside it (${l2:-?}px) is squeezed to a sliver (want >= 100 and >= 150): $tn"
[[ -n "$i1" && "$i1" -le 80 ]] \
  || fail "BL-536: at 390 px an id column is ${i1:-?}px wide, it should stay narrow (want <= 80: the id plus cell padding): $tn"
# BL-575: this page has an open item, so its bottom bar stays pinned.
[[ "$tn" == *"|RAILPOS=sticky|"* ]] \
  || fail "BL-575: at 390 px with an open question the copy bar is not pinned to the viewport bottom: $tn"
# ... and it stays pinned after that question is ANSWERED (nothing blank, but not decided):
# the bar is released only when no question is left to answer, not when none is blank.
[[ "$tn" == *"|RAILANS=sticky"* ]] \
  || fail "BL-575: answering the last open question released the copy bar although the question is not decided: $tn"

# ---- BL-608: the Decidido fold names each row and counts what it shows ----
# A block of six gallery rows, every one decided: two approved, four "to redo" (a verdict the
# owner gave, written decided="Se rehace ...", never dropped=). The summary must carry each
# row's title with the verdict written on it (no bare "(descartada)", no slug) and the eyebrow
# must equal the rows listed, in rows. Three pages: es rows, es rows mixed with a plain
# question ("elementos"), en rows.
rows_body() {  # rows_body <lang: es|en> <extra decided plain question: 0|1>
  local lang="$1" plain="$2" n attr ok redo head=Contenido
  [[ "$lang" == en ]] && head=Contents
  if [[ "$lang" == es ]]; then ok="Aprobada: se ve bien"; redo="Se rehace seg&uacute;n Q1"; else ok="Approved: looks right"; redo="Redo per Q1"; fi
  printf '%s\n' '<meta name="consult-visual" content="none: a layout probe, nothing to draw">' \
    '<div class="page"><main class="main"><header><p class="eyebrow">PROBE</p><h1>Decided rows</h1></header>' \
    '<section id="sec-ask"><div class="sec-head"><h2>Questions</h2></div>' \
    '<section class="consult-group" id="E" data-id="E" data-title="La matriz" data-tiles="after"><div class="sec-head"><h2>La matriz</h2></div><p>Seis filas.</p>'
  for n in 1 2 3 4 5 6; do
    if (( n <= 2 )); then attr="data-decided=\"$ok $n\""; else attr="data-decided=\"$redo\""; fi
    printf '<section class="consult-item consult-gallery" data-id="audit-row%s-after" data-title="audit &middot; row%s &middot; after" data-heading="Fila %s" %s><h3>Fila %s</h3><p class="gal-na">no aplica</p><textarea></textarea></section>\n' "$n" "$n" "$n" "$attr" "$n"
  done
  printf '%s\n' '</section>'
  if (( plain )); then
    printf '%s\n' '<section class="consult-group" id="P" data-id="P" data-title="Plain"><div class="sec-head"><h2>Plain</h2></div><p>One plain question.</p><section class="consult-item" data-id="P1" data-title="Plain" data-decided="Option A"><h3><span class="consult-id">P1</span>Una pregunta normal</h3><div class="opts one"><label><input type="radio" name="P1" data-label="Option A" checked><span>Option A</span></label></div><textarea></textarea></section></section>'
  fi
  printf '%s\n' '<div class="endbar"><button type="button" id="consult-copy-end">Copy</button><span class="consult-status" id="consult-status-end"></span></div>' \
    '<section class="consult-item consult-notes" data-id="notes" data-title="Notas generales"><h3>Notas generales</h3><textarea></textarea></section>' \
    '</section></main><aside class="rail"><p class="railhead">'"$head"'</p><nav class="raillist" id="raillist"></nav>' \
    '<div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div></aside></div>' \
    '<script>window.addEventListener("load", function () {' \
    ' var t = function (q) { return ((document.querySelector(q) || {}).textContent || "").replace(/[|]/g, "/").replace(/\n/g, "; "); };' \
    ' document.title = "ROWS|EYEBROW=" + t("#sec-decided .eyebrow") + "|SUM=" + t("#sec-decided summary") + "|ENTRIES=" + document.querySelectorAll("#sec-decided .consult-item").length;' \
    '});</script>'
}
rows_title() {  # rows_title <lang> <plain> -> the probe's <title>
  rows_body "$1" "$2" > "$TMP/rbody.html"
  bash "$WRAP" --title "rows" --lang "$1" --out "$TMP/reports/rows-$1-$2.html" < "$TMP/rbody.html" > "$TMP/rwrap.log" 2>&1 \
    || fail "BL-608: the decided-rows probe ($1/$2) failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/rwrap.log" | sed -n 1,4p)"
  CHROME_WINDOW=1280,900 chrome_dump "$TMP/rdom.html" "file://$TMP/reports/rows-$1-$2.html" 45 || true
  grep -oE '<title>[^<]*</title>' "$TMP/rdom.html" | sed -n 1p
}
tr="$(rows_title es 0)"
[[ "$tr" == *"ROWS|EYEBROW=6 filas ya resueltas|"* && "$tr" == *"|ENTRIES=6"* ]] \
  || fail "BL-608: the Decidido eyebrow does not equal the six rows it holds, or does not say filas: $tr"
[[ "$tr" == *"Fila 1: Aprobada: se ve bien 1; Fila 2: Aprobada: se ve bien 2; Fila 3: Se rehace según Q1; "* && "$tr" == *"Fila 6: Se rehace según Q1"* ]] \
  || fail "BL-608: the Decidido summary does not give each row its title and the verdict written on it: $tr"
[[ "$tr" != *"(descartada)"* && "$tr" != *"audit-row"* ]] \
  || fail "BL-608: the Decidido summary shows the bare '(descartada)' mark or a raw slug: $tr"
tr="$(rows_title es 1)"
[[ "$tr" == *"EYEBROW=7 elementos ya resueltos|"* ]] \
  || fail "BL-608: a Decidido holding gallery rows and a plain question must count 'elementos', not rows or questions: $tr"
tr="$(rows_title en 0)"
[[ "$tr" == *"EYEBROW=6 rows already settled|"* ]] \
  || fail "BL-608: on an English page the Decidido eyebrow must read '6 rows already settled': $tr"

# ---- BL-629: a decided row carries the answer to the owner's note, visible while folded ----
# The owner approved a row and attached a worry; the next round's decided row folds, so the
# reply was hidden. `answer` on a decided row must show inside the folded summary, the row
# keeps its verdict-less shape (no radios) and the id a plain review row of that cell has,
# so consult-ids passes against the previous round. Layer: browser, because visibility
# (the text with the fold closed) and the restore of round 1's answer are what the composer decides.
mkdir -p "$TMP/g629/shots/light-desktop" "$TMP/g629/actual/light-desktop"
for c629 in empty loaded; do
  python3 "$SKILL/tests/png_fixture.py" "$TMP/g629/shots/light-desktop/audit-$c629.png" 160 90 96   # a before that differs from the after: the builder refuses identical pairs
  python3 "$SKILL/tests/png_fixture.py" "$TMP/g629/actual/light-desktop/audit-$c629.png" 160 90
done
row629() {  # row629 <cell> <extra row keys, json fragment starting with a comma, or empty>
  printf '{"cell": "%s", "variant": "light-desktop", "kind": "review", "look": "El estado", "before": "shots/light-desktop/audit-%s.png", "after": "actual/light-desktop/audit-%s.png"%s}' "$1" "$1" "$1" "$2"
}
ANS629=', "decided": "Aprobada en la ronda 2", "answer": "Respuesta zzzanswer a tu nota"'
gen629() {  # gen629 <out html> <row json>...
  local out="$1"; shift
  local IFS=,; printf '{"gallery": "audit", "variants": ["light-desktop"], "shots_dir": "shots", "actual_dir": "actual", "rows": [%s]}\n' "$*" > "$TMP/g629/rows.json"
  bash "$SKILL/scripts/gallery-items.sh" "$TMP/g629/rows.json" --root "$TMP/g629" --page "$TMP/reports/g629.html" \
    --group-id E --group-title "La matriz" > "$out" 2> "$TMP/g629/gen.err" \
    || fail "BL-629: gallery-items.sh failed: $(cat "$TMP/g629/gen.err")"
}
PROBE629='<script>window.addEventListener("load", function () {
  var row = document.querySelector("[data-id=audit-empty-light-desktop]"), vis = 0;
  if (location.search.indexOf("phase=fill") > -1) {
    var r = row.querySelector("input[type=radio]"); r.checked = true; r.dispatchEvent(new Event("change", { bubbles: true }));
    document.title = "FILLED"; return;
  }
  [].forEach.call(document.querySelectorAll("*"), function (n) { if (!n.children.length && (n.textContent || "").indexOf("zzzanswer") > -1 && n.offsetParent !== null && n.checkVisibility()) vis++; });
  var fold = row && row.closest("details.decided-unit");
  var rest = document.getElementById("consult-restored");
  document.title = "ANS|FOLDED=" + (fold && !fold.open && !row.checkVisibility() ? 1 : 0) + "|INPLACE=" + (fold && fold.classList.contains("inplace") ? 1 : 0) + "|VIS=" + vis + "|RADIOS=" + (row ? row.querySelectorAll("input[type=radio]").length : -1) + "|ID=" + (row ? row.dataset.id : "") + "|REST=" + (rest ? rest.textContent.replace(/[|]/g, "/").slice(0, 80) : "none") + "|";
});</script>'
page629() {  # page629 <rows html> <out page>: wraps a probe page around a generated block
  { printf '%s\n' '<meta name="consult-visual" content="none: a layout probe, nothing to draw">' \
      '<div class="page"><main class="main"><header><p class="eyebrow">PROBE</p><h1>Answered row</h1></header>' \
      '<section id="sec-ask"><div class="sec-head"><h2>Questions</h2></div>'
    cat "$1"
    printf '%s\n' '<div class="endbar"><button type="button" id="consult-copy-end">Copy</button><span class="consult-status" id="consult-status-end"></span></div>' \
      '<section class="consult-item consult-notes" data-id="notes" data-title="Notas generales"><h3>Notas generales</h3><textarea></textarea></section>' \
      '</section></main><aside class="rail"><p class="railhead">Contenido</p><nav class="raillist" id="raillist"></nav>' \
      '<div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div></aside></div>' \
      "$PROBE629"
  } > "$TMP/g629/body.html"
  bash "$WRAP" --title "ans" --lang es --out "$2" < "$TMP/g629/body.html" > "$TMP/g629/wrap.log" 2>&1 \
    || fail "BL-629: the answered-row probe failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/g629/wrap.log" | sed -n 1,4p)"
}
title629() {  # title629 <page> [query]
  CHROME_WINDOW=1280,900 chrome_dump "$TMP/g629/dom.html" "file://$1${2:+?$2}" 45 || true
  grep -oE '<title>[^<]*</title>' "$TMP/g629/dom.html" | sed -n 1p
}
id629() { grep -oE 'data-id="audit-[a-z0-9-]+"' "$1" | sed -n 1p; }
gen629 "$TMP/g629/plain.html" "$(row629 empty '')"
gen629 "$TMP/g629/ans.html" "$(row629 empty "$ANS629")"
id_plain="$(id629 "$TMP/g629/plain.html")"; id_ans="$(id629 "$TMP/g629/ans.html")"
slug629="${id_plain#data-id=\"}"; slug629="${slug629%\"}"

# Whole block decided: the block folds as one unit.
page629 "$TMP/g629/ans.html" "$TMP/reports/ans629.html"
ta="$(title629 "$TMP/reports/ans629.html")"
[[ "$ta" == *"|FOLDED=1|"* ]] \
  || fail "BL-629: a decided row with an answer is not folded (FOLDED=1 wanted): $ta"
[[ "$ta" == *"|VIS=1|"* ]] \
  || fail "BL-629: the answer text is not visible with the fold closed (a closed fold hides the row; the summary must carry the text): $ta"
[[ "$ta" == *"|RADIOS=0|"* ]] \
  || fail "BL-629: a decided row with an answer carries verdict radios: $ta"
[[ -n "$slug629" && "$id_plain" == "$id_ans" && "$ta" == *"|ID=$slug629|"* ]] \
  || fail "BL-629: the answered row's id (${id_ans:-none}) differs from a plain review row's (${id_plain:-none}), so consult-ids would fail: $ta"

# Block with an open sibling: the answered row folds in place, and its summary says so with a separator.
gen629 "$TMP/g629/mix.html" "$(row629 empty "$ANS629")" "$(row629 loaded '')"
page629 "$TMP/g629/mix.html" "$TMP/reports/mix629.html"
tm="$(title629 "$TMP/reports/mix629.html")"
[[ "$tm" == *"|FOLDED=1|INPLACE=1|VIS=1|RADIOS=0|ID=$slug629|"* ]] \
  || fail "BL-629: in a block with an open sibling the answered row must fold in place (details.decided-unit.inplace) with the answer visible once: $tm"
grep -qE 'decided-answer">— [^<]*zzzanswer' "$TMP/g629/dom.html" \
  || fail "BL-629: the in-place answer span does not start with the em dash separator the group path uses: $(grep -oE 'decided-verdict decided-answer">[^<]{0,60}' "$TMP/g629/dom.html" | sed -n 1p)"

# Round 2: round 1's approval of this row (open, radio ticked, saved under the page's path) must not be
# reported as 'left blank because the question changed' once the row is decided and answered.
gen629 "$TMP/g629/open.html" "$(row629 empty '')"
page629 "$TMP/g629/open.html" "$TMP/reports/r629.html"
[[ "$(title629 "$TMP/reports/r629.html" "phase=fill")" == *FILLED* ]] || fail "BL-629: round 1 fill phase did not run"
printf 'audit-empty-light-desktop: Aprobada\n' | bash "$SKILL/scripts/save-reply.sh" "$TMP/reports/r629.html" - >/dev/null 2>&1 \
  || fail "BL-629: save-reply.sh failed on the round-1 page"
page629 "$TMP/g629/ans.html" "$TMP/reports/r629.html"
tr2="$(title629 "$TMP/reports/r629.html")"
[[ "$tr2" == *"|FOLDED=1|"* && "$tr2" == *"|REST=none|"* ]] \
  || fail "BL-629: round 2 reports the owner's round-1 approval of a now decided+answer row as restored or stale ('se dejaron en blanco'): $tr2"

# ---- the chrome speaks the page's language ----------------------------------
[[ "$t" == *"BTN=Copiar mis respuestas"* ]] \
  || fail "the copy button stayed in English on a lang=es page: $t"
[[ "$t" == *"RAIL=Contenido"* ]] \
  || fail "the rail head stayed in English on a lang=es page: $t"
# BL-280: the labels the author copies out of skeleton.html are kit chrome too.
# Before this, a lang=es page carried Spanish buttons over English field labels
# and English placeholders, and only a hand translation fixed it.
[[ "$t" == *"FL=Notas sobre esta"* ]] \
  || fail "the notes field label stayed in English on a lang=es page: $t"
[[ "$t" == *"PH=Cualquier cosa que las opciones no cubran"* ]] \
  || fail "the notes placeholder stayed in English on a lang=es page: $t"
# A label the author wrote deliberately is not a skeleton default and is left
# alone — the same guard the copy button has always had.
[[ "$t" == *"FLKEPT=Write freely"* ]] \
  || fail "an author's own field label was overwritten by the kit: $t"

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

# ---- BL-245: the recommendation is visible AND in the paste -----------------
#
# It had neither. Left with no affordance, a session typed "(recomendada)" into
# `data-label` — the string the composer copies — so the marker reached the
# pasted reply and never reached the page, on all ten items of one round.
rm -rf "$TMP/profile"
write_body "$Q1_V1"
wrap_page
t="$(run 'phase=verify')"
[[ "$t" == *"REC=Recomendada"* ]] \
  || fail "BL-245: data-recommended rendered no visible badge, in the page's language: $t"
[[ "$t" == *"RECPOS=before-hint"* ]] \
  || fail "BL-245: the badge is not next to the option title, before its hint: $t"

t="$(run 'phase=fill')"
[[ "$t" == *FILLED* ]] || fail "the fill phase did not run before the send probe: $t"
t="$(run 'phase=send')"
[[ "$t" == *SENT* ]] || fail "the send phase did not run: $t"
[[ "$t" == *"Option A (recomendada)"* ]] \
  || fail "BL-245: the copied label lost the recommendation — the reply no longer records which option was backed: $t"
# BL-247: the pasted reply keeps the block — "## G1 · title" precedes the first
# answered item of the block, once, and never precedes the loose general notes.
# (newlines read as spaces inside <title>, hence the double space)
[[ "$t" == *"## G1 · The context  ### Q1"* ]] \
  || fail "BL-247: the copied reply does not open the block before its first item: $t"
[[ "$(printf '%s' "$t" | grep -o '## G1' | wc -l | tr -d ' ')" == 1 ]] \
  || fail "BL-247: the block heading was repeated (or missing) in the copied reply: $t"

# ---- BL-241: a SENT answer does not cross into a new round; an unsent one does
#
# The reported case: an item whose question did not change handed back a note the
# session had already read and acted on, every regeneration. Q1 is sent and must
# be gone; Q2 is sent and then EDITED, which un-sends it, and must survive — that
# pair is the whole rule, and a page-wide clear would pass the first and fail the
# second (R6-02, again).
t="$(run 'phase=retype')"
[[ "$t" == *RETYPED* ]] || fail "the retype phase did not run: $t"

t="$(run 'phase=verify')"
[[ "$t" == *"RESTORED=persisted-answer-123"* ]] \
  || fail "BL-241: a sent answer did not survive a RELOAD in its own round — the discriminant is the round, not the send: $t"

wrap_next_round                             # same content, new round
t="$(run 'phase=verify')"
[[ "$t" == *"RESTORED=persisted-answer-123"* ]] \
  && fail "BL-241: an answer already sent came back in the next round: $t"
[[ "$t" == *"MARK=A"* ]] \
  && fail "BL-241: a mark already sent came back in the next round: $t"
[[ "$t" == *"CE=retyped-after-sending-000"* ]] \
  || fail "BL-241: an answer edited AFTER sending was dropped — editing must un-send it: $t"
[[ "$t" == *"NOTE="*"ya las enviaste en una ronda anterior"* ]] \
  || fail "BL-241: nothing told the reader why a sent answer is not in its box: $t"
# The marker itself, so a wrapper that stops stamping it fails here rather than
# silently reverting the whole rule to the v6 behaviour.
[[ "$t" == *"ROUND="[0-9]* ]] \
  || fail "BL-241: the page carries no consult-round marker: $t"

# ---- the v6 -> v7 upgrade never blanks a reader who is mid-thread -----------
#
# Every cell above starts from a fresh profile, so none of them sees the case
# that applies to every page already on disk: answers saved before rounds
# existed. They carry no `r` and no `x`, and both guards require both sides to
# be known — so the answer comes back. Getting this wrong would blank the whole
# field on the upgrade, silently, once.
rm -rf "$TMP/profile"
write_body "$Q1_V1"
wrap_page
t="$(run 'phase=fill')"
[[ "$t" == *FILLED* ]] || fail "the fill phase did not run before the upgrade probe: $t"
t="$(run 'phase=downgrade')"
[[ "$t" == *DOWNGRADED* ]] || fail "the downgrade phase did not run: $t"
[[ "$t" == *'"r"'* || "$t" == *'"x"'* ]] \
  && fail "the downgraded entry still carries a round or sent key — it is not a v6 entry: $t"
wrap_next_round                             # a new round arrives with the upgrade
t="$(run 'phase=verify')"
[[ "$t" == *"RESTORED=persisted-answer-123"* ]] \
  || fail "a pre-round answer set was blanked by the upgrade: $t"
[[ "$t" == *"MARK=A"* ]] \
  || fail "a pre-round mark was blanked by the upgrade: $t"

# ---- BL-242: per-item clear -------------------------------------------------
rm -rf "$TMP/profile"
t="$(run 'phase=fill')"
[[ "$t" == *FILLED* ]] || fail "the fill phase did not run before the clear probe: $t"
t="$(run 'phase=clear')"
[[ "$t" == *"CLEARROW=1"* ]] \
  || fail "BL-248: the clear control is not in the label row next to the box it clears: $t"
[[ "$t" == *"CLEARVIS=none"* ]] \
  || fail "BL-248: the clear control stays visible on a blank item: $t"
[[ "$t" == *"CLEARED=1"* ]] || fail "BL-242: no per-item clear control was injected: $t"
[[ "$t" == *"LABEL=Limpiar"* ]] \
  || fail "BL-242: the clear control stayed in English on a lang=es page: $t"
[[ "$t" == *"|TA=|"* ]] || fail "BL-242: clearing left the textarea filled: $t"
[[ "$t" == *"MARK=-"* ]] \
  || fail "BL-242: clearing did not un-check the radio — the one thing a reader cannot undo by hand: $t"
[[ "$t" == *"persisted-answer-123"* ]] \
  && fail "BL-242: the cleared item is still in localStorage, so it returns on the next reload: $t"

# ---- BL-268: the count is of ITEMS, never of block headings -----------------
rm -rf "$TMP/profile"
write_body "$Q1_V1"
wrap_page
t="$(run 'phase=count')"
[[ "$t" == *COUNTED* ]] || fail "the count phase did not run: $t"
# "2 de 2", not "2 de 3": the numerator is what BL-268 is about (a block heading
# was being counted as an answer), and the denominator dropped the general-notes
# box in v15 — it is not one of the questions.
[[ "$t" == *"STATUS=2 de 2 respondidas"* ]] \
  || fail "BL-268: two answered items in one block are not reported as 2 of 3 — the block heading is being counted as an answer: $t"

# ---- BL-268: a picked radio can be released by picking it again -------------
rm -rf "$TMP/profile"
t="$(run 'phase=toggle')"
[[ "$t" == *TOGGLED* ]] || fail "the toggle phase did not run: $t"
[[ "$t" == *"AFTER1=A"* ]] || fail "BL-268: the first click on an option did not select it: $t"
[[ "$t" == *"AFTER2=-"* ]] \
  || fail "BL-268: clicking the selected option again did not release it — the reader is stuck with a mark they cannot undo: $t"
[[ "$t" == *"STATUS=Sin responder"* ]] \
  || fail "BL-268: releasing the only mark did not return the item to blank in the status line: $t"

# ---- BL-268: every option group carries an injected "other" choice ---------
rm -rf "$TMP/profile"
t="$(run 'phase=other')"
[[ "$t" == *OTHERED* ]] || fail "the other phase did not run: $t"
[[ "$t" == *"OTHER=1"* ]] || fail "BL-268: no 'other' option was injected into the option group: $t"
[[ "$t" == *"OTHERCOUNT=1"* ]] || fail "BL-268: the 'other' option was injected more than once: $t"
[[ "$t" == *"OTHERNAME=Q1"* ]] || fail "BL-268: the 'other' option is not in the group's radio set (name): $t"
[[ "$t" == *"OTHERTYPE=radio"* ]] || fail "BL-268: the 'other' option does not match the group's input type: $t"
[[ "$t" == *"OTHERBEFOREEX=1"* ]] \
  || fail "BL-268: the 'other' option is not the last ANSWER choice of its group — since v18 the not-now choice follows it, and nothing else may: $t"
[[ "$t" == *"OTHERTEXT=Otra"* ]] \
  || fail "BL-268: the 'other' option is not labelled in the page's language: $t"
[[ "$t" == *"|A=-"* ]] || fail "BL-268: picking 'other' left the recommended option checked too: $t"
# It persists like any other mark, and the paste names it.
t="$(run 'phase=verify')"
[[ "$t" == *"MARK=O"* ]] || fail "BL-268: the 'other' mark did not survive a reload: $t"
t="$(run 'phase=send')"
[[ "$t" == *"- Otra"* ]] || fail "BL-268: the copied reply does not name the 'other' choice: $t"

# ---- BL-325 / BL-381 (v18): the explain asks are a CHECKBOX ROW on the item -
#
# v15 put the escape in the option group as a radio, v16 split it in two by
# kind of gap, both exclusive with the answer and with each other. 348 owner
# messages mined from every transcript (BL-381) show the asks arriving
# COMBINED and ALONGSIDE an answer, plus three kinds the two markers never
# named (why, what is X, show me) and one answer-side state (not now). Since
# v18: the answer group stays a radio and gains "not now"; a separate checkbox
# row on the item carries five tagged asks. Marks still travel as fixed ASCII
# markers, never translated, because the session greps them.
rm -rf "$TMP/profile"
write_body "$Q1_V1"
wrap_page
t="$(run 'phase=explain')"
[[ "$t" == *EXPLAINED* ]] || fail "the explain phase did not run: $t"
[[ "$t" == *"ROW=1"* ]] \
  || fail "BL-381: no ask row was injected on the option item: $t"
[[ "$t" == *"CHIPS=8"* ]] \
  || fail "BL-381 + census 2026-09-20 + BL-505: the ask row does not carry the eight tagged asks (state, options, why, simpler, question, reframe, show-me, more-examples): $t"
[[ "$t" == *"TERMCHIP=0"* && "$t" == *"TERMBOX=0"* ]] \
  || fail "census 2026-09-20: the 'what is X' chip (or its term box) is still injected — 0 uses in 333 answered items, replaced by [question]: $t"
[[ "$t" == *"FOCUSNOTES=1"* ]] \
  || fail "census 2026-09-20: ticking 'tengo una pregunta' did not focus the notes box — the question text travels in the notes: $t"
[[ "$t" == *"CHIPTYPE=checkbox"* && "$t" == *"CHIPINGROUP=0"* ]] \
  || fail "BL-381: an ask is still a radio in the answer group — it must be a checkbox outside it, or it cannot combine with an answer: $t"
[[ "$t" == *"ANSWERKEPT=1"* ]] \
  || fail "BL-381: ticking an ask released the answer — 'Sí, pero explícame por qué' is the reported shape: $t"
[[ "$t" == *"BOTHKEPT=1"* ]] \
  || fail "BL-381: two asks in one round did not both stay ticked — 'explícamelo mejor y vuelve a darme las opciones' is the reported shape: $t"
[[ "$t" == *"ROWAFTEROPTS=1"* ]] \
  || fail "BL-381: the ask row is not immediately after the option group — it must read as a separate surface, below the answer: $t"
# An option WITH an ask is PROVISIONAL, and the page says so while both are set.
[[ "$t" == *"PROVBEFORE=0"* ]] \
  || fail "provisional: the item was marked provisional with an option and no ask — an option alone is an answer: $t"
[[ "$t" == *"PROVON=1"* ]] \
  || fail "provisional: an option plus an ask did not put the provisional line on the item — the reader has no signal that the option is not a decision: $t"
[[ "$t" == *"PROVOFF=0"* ]] \
  || fail "provisional: releasing the option left the provisional line behind — asks with no answer beside them leave the item plainly open: $t"
[[ "$t" == *"PROVTEXT=Provisional"* ]] \
  || fail "provisional: the line on the item is not in the page's language, or does not name the state: $t"
# BL-505: [more-examples] combines like any other ask — provisional on its own.
[[ "$t" == *"PROVNOASKS=0"* ]] \
  || fail "BL-505: the isolation setup left an ask ticked — the baseline for the more-examples/page-defect checks is not clean: $t"
[[ "$t" == *"PROVWITHMORE=1"* ]] \
  || fail "BL-505: [more-examples] ticked beside a chosen answer did not mark the item provisional — it must combine like every other ask: $t"
[[ "$t" == *"MCAP="*"[more-examples]"* ]] \
  || fail "BL-505: the copied reply does not carry the [more-examples] marker under the item: $t"
# LOOP-008 Q10: the page-defect report is a button + its own box, not a chip.
[[ "$t" == *"DCHIP=0"* ]] \
  || fail "LOOP-008 Q10: the [page-defect] checkbox chip is still in the ask row: $t"
[[ "$t" == *"PROVWITHDEFECT=0"* ]] \
  || fail "BL-505: a page-defect report beside a chosen answer marked it provisional — a page defect does not put the answer in question: $t"
[[ "$t" == *"FOCUSDEFECT=1"* ]] \
  || fail "LOOP-008 Q10: the report button did not focus its own box: $t"
# DSTATE digits: hidden-before, open-after-click, stays-open-while-filled, closed-when-empty, defect-only-answered(must be 0), stored
[[ "$t" == *"DSTATE=11110111"* ]] \
  || fail "LOOP-008 Q10: the report box did not hide/open/stay/close/store as specified (want DSTATE=11110111 = hidden, opens, stays open while filled, closes when empty, defect alone is NOT an answer, stored, Clear shown for a defect alone, Clear empties the box): $t"
dcapfield="$(printf '%s' "$t" | sed -nE 's/.*\|DCAP=([^|]*)\|.*/\1/p')"
[[ "$dcapfield" == *"### Q1 · The probed question~~- Option A (recomendada)~~una nota~~#### Fallo de la página~~el boton   se ve roto" ]] \
  || fail "LOOP-008 Q10: the copied reply is not answer + note + a '#### Fallo de la página' sub-block at the END of the item block: [$dcapfield]"
[[ "$dcapfield" == *"[provisional]"* || "$dcapfield" == *"[page-defect]"* ]] \
  && fail "LOOP-008 Q10: the copied reply carries [provisional] or the retired [page-defect] marker: $dcapfield"
donlyfield="$(printf '%s' "$t" | sed -nE 's/.*\|DONLY=([^|]*)\|.*/\1/p')"
[[ "$donlyfield" == *"### Q1 · The probed question~~#### Fallo de la página~~el boton   se ve roto" && "$donlyfield" != *"- "* ]] \
  || fail "LOOP-008 Q10: a defect with no answer did not emit just its ### block with the sub-block: [$donlyfield]"
[[ "$t" == *"EXNOGROUP=1"* ]] \
  || fail "BL-381: an item with no option group got no ask row — the row lives on the ITEM now, so the v15 cost is gone: $t"
[[ "$t" == *"EXNOTES=0"* ]] \
  || fail "BL-325 v15: the general-notes item got an ask row — it asks no question to explain: $t"
[[ "$t" == *"EXDECIDED=0"* ]] \
  || fail "BL-381: a decided item got an ask row or a not-now choice — it is not being asked: $t"
excount="$(printf '%s' "$t" | sed -nE 's/.*EXCOUNT=([0-9]+).*/\1/p')"
[[ "$excount" == "2" ]] \
  || fail "BL-381: the two open items do not carry exactly one ask row each ($excount): $t"
[[ "$t" == *"ROWTEXT=Antes de responder necesito"* ]] \
  || fail "BL-381: the ask row stayed in English on a lang=es page: $t"
[[ "$t" == *"NOTNOW=radio:Q1"* ]] \
  || fail "BL-381: 'not now' is not a radio in the group's own name — it is an answer-side state and must be exclusive with answering: $t"
[[ "$t" == *"NOTNOWRELEASED=1"* ]] \
  || fail "BL-381: picking 'not now' left the answer selected: $t"
[[ "$t" == *"NOTNOWTEXT=Todavía no"* ]] \
  || fail "BL-381: the not-now choice stayed in English on a lang=es page: $t"
# The paste: the answer AND every ask, each under the item's id, markers verbatim.
[[ "$t" == *"### Q1 · The probed question  - Option A (recomendada) [provisional] - [explain-state] - [explain-why] - [question]"* ]] \
  || fail "BL-381 + provisional: the paste does not carry the qualified answer plus the three asks in order: $t"
[[ "$t" == *"PASTE="*"[explain-options]"* ]] \
  && fail "BL-381: the paste carries a marker that was NOT ticked: $t"
[[ "$t" == *"### Q1 · The probed question  - [not-now] - [explain-state]"* ]] \
  || fail "BL-381: the not-now choice did not paste its marker in the answer's place, with the asks still following: $t"
[[ "$t" == *"PASTE2="*"Option A"* ]] \
  && fail "BL-381: 'not now' pasted alongside the answer it was meant to release: $t"
[[ "$t" == *"PROVNOTNOW=0"* ]] \
  || fail "provisional: 'not now' plus an ask was marked provisional — a deferral is not an option to qualify: $t"
[[ "$t" == *"PASTE2="*"[provisional]"* ]] \
  && fail "provisional: the marker travelled with no option beside it: $t"
# An ask IS a response; so is deferring. Neither leaves the item in the blank list.
[[ "$t" == *"STATUS=1 de 2 respondidas"* && "$t" == *"STATUS2=1 de 2 respondidas"* ]] \
  || fail "BL-381: an item carrying only asks, or only 'not now', is still counted blank: $t"

t="$(run 'phase=verify')"
[[ "$t" == *"EXKEPT=1"* && "$t" == *"QKEPT=1"* ]] \
  || fail "BL-381: the asks did not survive a reload in their own round: $t"
wrap_next_round                             # same content, new round
t="$(run 'phase=verify')"
[[ "$t" == *"EXKEPT=1"* ]] \
  && fail "BL-325: an explain request already sent came back in the next round — the reader would re-send a request the session has already answered: $t"

# ---- C: the general-notes box is not one of the questions -------------------
#
# Reported by the owner on the page that carried these very decisions: "las
# notas no cuentan por si solas como respuesta... las notas generales no deben
# contar como vacias si no las utilizo". Before this, a reader who answered
# every question still read "3 de 4 · en blanco: notes", and the box that exists
# for what fits nowhere was reported as an omission.
rm -rf "$TMP/profile"
write_body "$Q1_V1"
wrap_page
t="$(run 'phase=notes')"
[[ "$t" == *NOTED* ]] || fail "the notes phase did not run: $t"
[[ "$t" == *"FULL=2 de 2 respondidas"* ]] \
  || fail "C: with every question answered and the notes box empty, the page does not read 'all answered' — the notes box is still in the count: $t"
[[ "$t" == *"en blanco: notes"* ]] \
  && fail "C: the general-notes box was listed as a blank answer: $t"
# The other direction: notes-only is still something to send.
[[ "$t" == *"ONLYNOTES=### notes · General notes  something that fits no question"* ]] \
  || fail "C: a page whose only filled box is the general notes had nothing to copy: $t"

# ---- A settled decision is SHOWN, never re-asked ---------------------------
#
# Reported from use on the page that carried these very decisions: "me volviste
# a enviar las primeras respuestas seleccionadas". The canon said to record a
# verdict by marking the chosen option `checked` in the markup — and `restore()`
# can only mark an answer spent when it RESTORED it, so an option the page ships
# pre-checked is invisible to the round mechanism and re-composes forever.
[[ "$t" == *"DECIN=0"* ]] \
  || fail "decided: a settled item still has live inputs — a reader can change an answer that will never be sent: $t"
[[ "$t" == *"DECCTL=0"* ]] \
  || fail "decided: a settled item got injected controls (explain / other / clear) — it is not being asked: $t"
[[ "$t" == *"DECDONE=1"* ]] \
  || fail "decided: a settled item does not read as answered: $t"
[[ "$t" == *"### Q0"* ]] \
  && fail "decided: the settled decision re-composed into the paste — this is the reported defect: $t"

# ---- BL-327: the explicit theme, which nothing had ever set ----------------
#
# The palette is declared three times in tokens.css and the third block —
# :root[data-theme="dark"|"light"] — had never applied to any artifact the kit
# produced: measured on a real page, data-theme was null and skeleton.html never
# mentioned it. So the reader was pinned to the OS setting, and a figure whose
# colours come out wrong in the mode nobody looks at stayed invisible.
rm -rf "$TMP/profile"
write_body "$Q1_V1"
wrap_page
tt="$(run 'phase=theme')"
[[ "$tt" == *THEMED* ]] || fail "the theme phase did not run: $tt"
[[ "$tt" == *"BTN=1"* ]] || fail "BL-327: no theme control was injected into a wrapped page: $tt"
# The default path is the one that must NOT change.
[[ "$tt" == *"BEFORE=null"* ]] \
  || fail "BL-327: a page with no stored choice already carries data-theme — it no longer follows prefers-color-scheme: $tt"
[[ "$tt" == *"T1=dark"* || "$tt" == *"T1=light"* ]] \
  || fail "BL-327: the control did not set data-theme: $tt"
[[ "$tt" == *"T1=dark|T2=light"* || "$tt" == *"T1=light|T2=dark"* ]] \
  || fail "BL-327: the control does not go back the other way: $tt"
# Read off the computed background, so an attribute no rule matches cannot pass.
[[ "$tt" == *"REPAINT1=1"* && "$tt" == *"REPAINT2=1"* ]] \
  || fail "BL-327: data-theme changed but the page did not repaint in both directions: $tt"
[[ "$tt" == *"LABEL1=Claro"* || "$tt" == *"LABEL1=Oscuro"* ]] \
  || fail "BL-327: the control stayed in English on a lang=es page: $tt"
[[ "$tt" == *"TAB=1"* ]] || fail "BL-327: the control is not reachable by keyboard: $tt"
# It survives the reload, per artifact, and the label comes back with it.
tt="$(run 'phase=recall')"
[[ "$tt" == *"THEMEKEPT=dark"* || "$tt" == *"THEMEKEPT=light"* ]] \
  || fail "BL-327: the chosen theme did not survive a reload: $tt"
[[ "$tt" == *"LABEL=Claro"* || "$tt" == *"LABEL=Oscuro"* ]] \
  || fail "BL-327: the restored theme left the control mislabelled: $tt"

# ---- BL-280: localising the labels must not drop a stored answer -----------
#
# questionHash() hashes the item's whole textContent, and `.fieldlabel` is
# inside the item — so swapping "Notes on this one" for "Notas sobre esta" moves
# the fingerprint, and every answer a reader stored before the kit gained the
# swap reads as "the question changed" and is dropped on the upgrade. That is
# the failure the badge and the Clear button are already stripped to avoid, one
# release later.
#
# The upgrade, exactly: answer the page while its chrome is still English (what
# a v10 reader saw), then re-wrap THE SAME PATH — the store is keyed by path,
# so this is the reader reopening their page — with the localisation on.
rm -rf "$TMP/profile"
write_body "$Q1_V1"
wrap_page en
t="$(run 'phase=fill')"
[[ "$t" == *FILLED* ]] || fail "BL-280 upgrade: the fill phase did not run on the English page: $t"
wrap_page es
t="$(run 'phase=verify')"
[[ "$t" == *"RESTORED=persisted-answer-123"* ]] \
  || fail "BL-280 upgrade: localising the field label dropped a stored free-text answer: $t"
[[ "$t" == *"MARK=A"* ]] \
  || fail "BL-280 upgrade: localising the field label dropped a stored mark: $t"
[[ "$t" == *"FL=Notas sobre esta"* ]] \
  || fail "BL-280 upgrade: the label was not localised on the reopened page: $t"

# ---- BL-650b: relabelling the notes badge must not drop the reader's notes ----
# spec_build now prints the default notes badge as "notas" on an es page. The badge
# is inside the item, so a questionHash over the raw textContent moves with it and a
# live page regenerated with the new kit would read the typed "Notas generales" text
# as "the question changed". The hash must treat the badge as the item's data-id.
# The rail chip must show the badge the reader sees, not the raw data-id.
rm -rf "$TMP/profile"
PAGE_SAVED="$PAGE"; PAGE="$TMP/reports/n650.html"
n650() {  # n650 <badge text> <phase>: wrap a notes-only es page, load it with ?phase=
  cat > "$TMP/body.html" <<HTML
<meta name="consult-visual" content="none: a persistence probe, nothing to draw">
<div class="page"><main class="main"><header><p class="eyebrow">PROBE</p><h1>Notes probe</h1></header>
<section id="sec-ask"><div class="sec-head"><h2>Preguntas</h2></div>
  <section class="consult-item consult-notes" data-id="notes" data-title="Notas generales">
    <h3><span class="consult-id">$1</span>Notas generales</h3>
    <p class="fieldlabel">Lo que no encaja arriba</p>
    <textarea></textarea>
  </section>
  <div class="endbar"><button type="button" id="consult-copy-end">Copiar</button><span class="consult-status" id="consult-status-end"></span></div>
</section></main>
<aside class="rail"><p class="railhead">Contenido</p><nav class="raillist" id="raillist"></nav>
<div class="consult-bar"><button type="button" id="consult-copy">Copiar</button><span class="consult-status" id="consult-status"></span></div></aside></div>
<script>window.addEventListener('load', function () {
  var ta = document.querySelector('[data-id="notes"] textarea');
  if (location.search.indexOf('phase=fill') !== -1) {
    ta.value = 'unsent-notes-650';
    ta.dispatchEvent(new Event('input', { bubbles: true }));
    document.title = 'FILLED';
  } else {
    var st = document.getElementById('consult-restored');
    document.title = 'N650|TA=' + ta.value + '|STALE=' + (/pregunta cambi/.test(st ? st.textContent : '') ? 1 : 0) + '|RS=' + (st ? st.textContent.slice(0,70).replace(/[|]/g, '/') : 'none')
      + '|RAIL=' + document.getElementById('raillist').textContent.replace(/[|\s]+/g, ' ').trim() + '|';
  }
});</script>
HTML
  bash "$WRAP" --title "n650" --lang es --out "$PAGE" < "$TMP/body.html" > "$TMP/wrap.log" 2>&1 \
    || fail "BL-650b: the notes probe failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/wrap.log" | sed -n 1,4p)"
  run "$2"
}
t="$(n650 notes phase=fill)"
[[ "$t" == *FILLED* ]] || fail "BL-650b: the fill phase did not run: $t"
t="$(n650 notas phase=verify)"
[[ "$t" == *"|TA=unsent-notes-650|"* && "$t" == *"|STALE=0|"* ]] \
  || fail "BL-650b: relabelling the default notes badge notes->notas dropped the reader's unsent notes or marked them stale: $t"
[[ "$t" == *"RAIL="*notas* && "$t" != *"RAIL="*notes* ]] \
  || fail "BL-650b: the rail chip for the notes item shows the raw data-id instead of the visible badge: $t"
PAGE="$PAGE_SAVED"

# ---- LOOP-008 F3: a builder kicker must not change the question's hash --------
# spec_build now prints the item's title above a question h3 as `p.consult-kicker`.
# It is text inside the item, so a questionHash that keeps it reads every stored
# unsent answer of a live page as "the question changed" the first time it is rebuilt.
rm -rf "$TMP/profile"
PAGE_SAVED="$PAGE"; PAGE="$TMP/reports/kicker.html"
kick() {  # kick <kicker html or empty> <phase>: wrap a one-item es page, load it with ?phase=
  cat > "$TMP/body.html" <<HTML
<meta name="consult-visual" content="none: a persistence probe, nothing to draw">
<div class="page"><main class="main"><header><p class="eyebrow">PROBE</p><h1>Kicker probe</h1></header>
<section id="sec-ask"><div class="sec-head"><h2>Preguntas</h2></div>
  $gopen
  <section class="consult-item" data-id="Q1" data-title="Nombre corto" data-free>
    $1
    <h3><span class="consult-id">Q1</span>&iquest;Una pregunta larga?</h3>
    <p class="fieldlabel">Escribe libremente</p>
    <textarea></textarea>
  </section>
  $gclose
  <section class="consult-item consult-notes" data-id="notes" data-title="Notas generales">
    <h3><span class="consult-id">notas</span>Notas generales</h3>
    <textarea></textarea>
  </section>
  <div class="endbar"><button type="button" id="consult-copy-end">Copiar</button><span class="consult-status" id="consult-status-end"></span></div>
</section></main>
<aside class="rail"><p class="railhead">Contenido</p><nav class="raillist" id="raillist"></nav>
<div class="consult-bar"><button type="button" id="consult-copy">Copiar</button><span class="consult-status" id="consult-status"></span></div></aside></div>
<script>window.addEventListener('load', function () {
  var ta = document.querySelector('[data-id="Q1"] textarea');
  if (location.search.indexOf('phase=fill') !== -1) {
    ta.value = 'unsent-kicker-answer';
    ta.dispatchEvent(new Event('input', { bubbles: true }));
    document.title = 'FILLED';
  } else {
    var st = document.getElementById('consult-restored');
    document.title = 'KICK|TA=' + ta.value + '|STALE=' + (/pregunta cambi/.test(st ? st.textContent : '') ? 1 : 0) + '|';
  }
});</script>
HTML
  bash "$WRAP" --title "kicker" --lang es --out "$PAGE" < "$TMP/body.html" > "$TMP/wrap.log" 2>&1 \
    || fail "LOOP-008 F3: the kicker probe failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/wrap.log" | sed -n 1,4p)"
  run "$2"
}
t="$(kick '' phase=fill)"
[[ "$t" == *FILLED* ]] || fail "LOOP-008 F3: the fill phase did not run: $t"
t="$(kick '<p class="eyebrow consult-kicker">Nombre corto</p>' phase=verify)"
[[ "$t" == *"|TA=unsent-kicker-answer|"* && "$t" == *"|STALE=0|"* ]] \
  || fail "LOOP-008 F3: a rebuilt page that gained a kicker dropped the reader's unsent answer or marked it stale: $t"
PAGE="$PAGE_SAVED"

# ---- BL-341: a page whose every question is DECIDED --------------------------
#
# BL-331 taught the checker to accept such a page; the composer was never taught
# the same state. collect() drops decided items from both the numerator and the
# denominator, so an all-decided page reaches refresh() with total === 0 — and
# the old `r.answered ? progress : none` had exactly one reachable branch there.
# The reader who had just settled the last question was told "Sin responder
# todavía." over an empty question set.
#
# It is NOT a change to the copy bar. The general-notes box is not one of the
# questions (C, above): it is still fillable and still sendable on such a page,
# so a fix that hid the bar would trade one wrong page for another. Both halves
# are asserted, in both of the kit's languages.
rm -rf "$TMP/profile"
# A settled item carries its verdict (decided-item-without-verdict, LOOP-006).
write_body "$Q1_V1" 'data-decided="Resuelta en la ronda anterior"'
wrap_page es
td="$(run 'phase=alldecided')"
[[ "$td" == *ALLDECIDED* ]] || fail "the all-decided phase did not run: $td"
# The probe is worthless unless the page really is the shape it claims: three
# settled items, and the general-notes box as the only one left open.
[[ "$td" == *"DECIDED=3"* && "$td" == *"OPEN=1"* ]] \
  || fail "BL-341: the probe page is not all-decided, so every assertion below it would pass for the wrong reason: $td"
[[ "$td" == *"STATUS=Todas las preguntas están decididas"* ]] \
  || fail "BL-341: a page with every question decided does not name that state in its status line (es): $td"
[[ "$td" == *"STATUS=Sin responder"* ]] \
  && fail "BL-341: a page with every question decided still reads 'nothing answered yet' (es): $td"
# BL-587: copying with empty notes must not say "nothing answered yet" over a status
# that says everything is decided.
[[ "$td" == *"EMPTYCOPY=Todo está decidido; escribe una nota general si quieres enviar algo.|"* ]] \
  || fail "BL-587: copy on an all-decided page with empty notes contradicts the status line (es): $td"
# The bar stays. Measured as a real box, not as an attribute: at the harness
# width the rail collapses to a bottom bar, and a display-only assertion would
# pass on a bar of zero height.
[[ "$td" == *"BARH=1"* ]] \
  || fail "BL-341: the copy bar was hidden on an all-decided page — the notes box is no longer sendable: $td"
# BL-575: nothing is left to answer, so the bar must not stay pinned over every
# viewport; it is still in the page (BARH=1 above), after the content.
[[ "$td" == *"RAILPOS=static"* ]] \
  || fail "BL-575: below 62rem an all-decided page still pins the copy bar to the viewport bottom: $td"
[[ "$td" == *"ENDH=0"* ]] \
  || fail "BL-341/BL-535: below 62rem the rail bar is the sticky bottom bar, so the end bar must not repeat it (exactly one copy bar): $td"

# BL-373 — a settled question is HIDDEN, never removed, and stops being navigated.
#
# The v16 shape left it drawn where it was written, on the argument that the page
# should record the reasoning. One live use rejected the consequence: by round
# three the reader was scrolling past seven answered questions to reach the open
# ones — "es demasiado distractor iterar sobre un artefacto manteniendo las mismas
# respuestas previas".
#
# Three states have to be told apart, and each assertion below separates exactly
# one pair: MOVED distinguishes hidden from DELETED (the failure that would lose
# the reasoning), INFLOW distinguishes it from LEFT IN PLACE (the reported
# defect), and FOLDED from merely restyled. The fixture's G1 has all three of its
# items decided, so it must collapse as ONE unit rather than three.
[[ "$td" == *"DECSEC=1"* ]] \
  || fail "BL-373: no composer-built section on a page with settled questions — the author would have to hand-roll one, which is the gate-1 violation this replaces: $td"
[[ "$td" == *"UNITS=1"* ]] \
  || fail "BL-373: a block whose every item is decided did not collapse as ONE unit — the reader navigates the block, not the items in it: $td"
[[ "$td" == *"MOVED=1"* ]] \
  || fail "BL-373: a settled item is not inside the section — it was DELETED rather than hidden, and the reasoning is gone: $td"
[[ "$td" == *"INFLOW=0"* ]] \
  || fail "BL-373: the settled block is still in the run of the page — this is the reported defect, not a fix for it: $td"
[[ "$td" == *"FOLDED=1"* ]] \
  || fail "BL-373: the settled units are expanded on load — folded is the point; open is one click: $td"
# The heading is kit chrome, so it speaks the page's language like every other
# string. Asserted on the es page because en would pass on an untranslated table.
[[ "$td" == *"DECHEAD=Decidido"* ]] \
  || fail "BL-373: the section heading is not localised — it is kit chrome and belongs in STRINGS, not in the page: $td"
# The rail is the other half of "navegar sobre cosas ya respondidas": one entry
# for the section, and none for what it holds. RAILN is the non-empty-input
# guard — if the rail were empty altogether, RAILQ=0 would pass for free.
[[ "$td" == *"RAILDEC=1"* ]] \
  || fail "BL-373: the rail has no entry for the settled section, so there is no way into it from the index: $td"
[[ "$td" == *"RAILQ=0"* ]] \
  || fail "BL-373: the rail still lists settled questions — the index is where the reader navigates past them: $td"
[[ "$td" == *"RAILN=1"* ]] \
  || fail "BL-373: the rail lists nothing at all, so the RAILQ assertion above proves nothing: $td"
[[ "$td" == *"NOTESDIS=0"* ]] \
  || fail "BL-341: the general-notes box was sealed along with the decided questions: $td"
[[ "$td" == *"NOTESEND=### notes · General notes  the notes box still takes an answer"* ]] \
  || fail "BL-341: the notes typed on an all-decided page did not reach the paste: $td"

# The other language, because the string is chrome and the kit ships to projects
# that carry either one — the es run above cannot see an English regression.
rm -rf "$TMP/profile"
wrap_page en
td="$(run 'phase=alldecided')"
[[ "$td" == *ALLDECIDED* ]] || fail "the all-decided phase did not run on the English page: $td"
[[ "$td" == *"STATUS=Every question here is decided"* ]] \
  || fail "BL-341: a page with every question decided does not name that state in its status line (en): $td"
[[ "$td" == *"STATUS=Nothing answered yet"* ]] \
  && fail "BL-341: a page with every question decided still reads 'nothing answered yet' (en): $td"
[[ "$td" == *"BARH=1"* ]] \
  || fail "BL-341: the copy bar was hidden on an all-decided English page: $td"
[[ "$td" == *"EMPTYCOPY=Everything is decided; write a general note if you want to send something.|"* ]] \
  || fail "BL-587: copy on an all-decided page with empty notes contradicts the status line (en): $td"

# ---- BL-380: a decided item inside a HALF-answered block folds in place ----
#
# v17 collapsed a block only once every item in it was decided, and left a
# partly decided block untouched: every settled item fully drawn, every one of
# them still in the rail. Reported on a page with 11 blocks partly decided and
# 26 items: "solo se ocultaban los grupos completamente cerrados y no las
# opciones parciales ni la navegación parcial". The context the open questions
# need is the block's paragraph, not its decided siblings' evidence and options.
rm -rf "$TMP/profile"
write_body "$Q1_V1"
wrap_page
tp="$(run 'phase=partial')"
[[ "$tp" == *PARTIAL* ]] || fail "the partial phase did not run: $tp"
[[ "$tp" == *"DECSEC=0"* ]] \
  || fail "BL-380: a page with no fully decided block still built the Decided section — the half-answered block must keep its item: $tp"
[[ "$tp" == *"INPLACE=1"* ]] \
  || fail "BL-380: the decided item of a half-answered block is not folded inside its own block — this is the reported defect: $tp"
[[ "$tp" == *"UNITS=1"* ]] \
  || fail "BL-380: the half-answered block does not carry exactly one folded unit for its one decided item: $tp"
[[ "$tp" == *"FOLDED=1"* ]] \
  || fail "BL-380: the in-place unit is expanded on load — folded is the point; open is one click: $tp"
[[ "$tp" == *"SUMMARY=Q0"*"La decision ya tomada"*"La opcion elegida"* ]] \
  || fail "BL-380: the summary line does not carry the id, the title and the option that won: $tp"
[[ "$tp" == *"CONTEXT=1"* && "$tp" == *"OPENINFLOW=2"* ]] \
  || fail "BL-380: the block's context paragraph or its open items left the block — only the decided sibling folds: $tp"
[[ "$tp" == *"SEALED=0"* ]] \
  || fail "BL-380: the folded item has live inputs again: $tp"
[[ "$tp" == *"RAILG=1"* && "$tp" == *"RAILOPEN=2"* ]] \
  || fail "BL-380: the rail lost the block entry or its open items — the RAILDEC assertion below would pass on an empty rail: $tp"
[[ "$tp" == *"RAILDEC=0"* ]] \
  || fail "BL-380: the rail still lists the decided item of a half-answered block — the index is where the reader navigates past it: $tp"
[[ "$tp" == *"STATUS=Sin responder"* ]] \
  || fail "BL-380: folding in place changed the count — the decided item must stay out of numerator and denominator: $tp"

# ---- provisional across EVERY reply surface, not only the option group -----
#
# The kit documents four reply surfaces (radio/checkbox, select, short text,
# free prose) and the ask row is injected on an item whatever its surface is.
# A provisional rule that only knew about `.opts` would leave a chosen SELECT
# value with an ask beside it reading as a decision, on the page and in the
# paste — the exact ambiguity the rule exists to remove, on the surfaces the
# option group does not cover. The prose box is the deliberate exception: free
# prose is not a chosen answer, so an ask beside it leaves the item open, and
# that cell is also what would fail if isProvisional were hard-coded true.
SPAGE="$TMP/reports/surfaces.html"
write_surfaces_body() {
cat > "$TMP/sbody.html" <<'HTML'
<meta name="consult-visual" content="none: a surfaces probe, nothing to draw">
<div class="page">
<main class="main">
<header><p class="eyebrow">PROBE</p><h1>Surfaces probe</h1></header>
<section id="sec-ask">
  <div class="sec-head"><h2>Questions</h2></div>
  <section class="consult-group" id="G1" data-id="G1" data-title="The context">
    <div class="sec-head"><h2>The context</h2></div><p>What the decisions below share.</p>
  <section class="consult-item" data-id="S1" data-title="The select surface">
    <h3><span class="consult-id">S1</span>Which one, from the list</h3>
    <p class="fieldlabel">La eleccion</p>
    <select><option value="">&mdash;</option><option value="a">Alpha</option><option value="b">Beta</option></select>
    <p class="fieldlabel">Notas sobre esta</p>
    <textarea></textarea>
  </section>
  <section class="consult-item" data-id="S2" data-title="The value surface" data-free>
    <h3><span class="consult-id">S2</span>What value</h3>
    <p class="fieldlabel">El valor</p>
    <input type="text">
    <p class="fieldlabel">Notas sobre esta</p>
    <textarea></textarea>
  </section>
  <section class="consult-item" data-id="S3" data-title="The prose surface" data-free>
    <h3><span class="consult-id">S3</span>Write what you think</h3>
    <p class="fieldlabel">Write freely</p>
    <div contenteditable="true"></div>
  </section>
  <section class="consult-item" data-id="S4" data-title="The bare surface">
    <h3><span class="consult-id">S4</span>Which one, once more</h3>
    <p class="fieldlabel">La eleccion</p>
    <select><option value="">&mdash;</option><option value="a">Alpha</option></select>
    <p class="fieldlabel">Notas sobre esta</p>
    <textarea></textarea>
  </section>
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
    <button type="button" id="consult-copy"></button>
    <span class="consult-status" id="consult-status"></span>
  </div>
</aside>
</div>
<script>
window.addEventListener('load', function () {
  var q = location.search;
  var prov = function (id) { return document.querySelectorAll('[data-id="' + id + '"] .kit-provisional').length; };
  var ask = function (id, m) {
    return document.querySelector('[data-id="' + id + '"] .kit-ask input[data-label="' + m + '"]');
  };
  var tick = function (id, m) {
    var c = ask(id, m);
    if (c) { c.checked = true; c.dispatchEvent(new Event('change', { bubbles: true })); }
    return !!c;
  };
  if (q.indexOf('phase=sfill') === -1 && q.indexOf('phase=sverify') === -1) return;
  if (q.indexOf('phase=sfill') !== -1) {
    var sel = document.querySelector('[data-id="S1"] select');
    sel.value = 'a'; sel.dispatchEvent(new Event('change', { bubbles: true }));
    var txt = document.querySelector('[data-id="S2"] input[type="text"]');
    txt.value = 'Un valor'; txt.dispatchEvent(new Event('input', { bubbles: true }));
    var ce = document.querySelector('[data-id="S3"] [contenteditable]');
    ce.textContent = 'solo prosa'; ce.dispatchEvent(new Event('input', { bubbles: true }));
    var before = prov('S1') + prov('S2') + prov('S3');
    tick('S1', '[show-me]'); tick('S2', '[show-me]'); tick('S3', '[show-me]');
    /* [question] has no surface of its own. On an item whose only free box is
     * a contenteditable the cursor belongs there; on an item with no free box
     * at all it belongs in the page's general-notes box. */
    tick('S3', '[question]');
    var focusCe = document.activeElement === ce;
    /* The last fallback. The contract requires a notes box on a closed-choice
     * item, so a page that HAS no free box anywhere on the item only reaches
     * the composer when it was written by hand or predates that rule — the
     * composer still must not focus nothing. S4 is stripped of its box here to
     * stand in for that page; it is a separate item so the stale fingerprint
     * this creates cannot touch S1's stored answer. */
    var bare = document.querySelector('[data-id="S4"] textarea');
    if (bare) bare.remove();
    tick('S4', '[question]');
    var focusNotes = document.activeElement === document.querySelector('.consult-notes textarea');
    var cap = '';
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: function (x) { cap = x; return Promise.resolve(); } }
    });
    document.getElementById('consult-copy').click();
    document.title = 'SURFACES|BEFORE=' + before
      + '|S1PROV=' + prov('S1') + '|S2PROV=' + prov('S2') + '|S3PROV=' + prov('S3')
      + '|FOCUSCE=' + (focusCe ? '1' : '0') + '|FOCUSNOTES=' + (focusNotes ? '1' : '0')
      + '|PASTE=' + cap.replace(/[|<>\n]/g, ' ');
  } else {
    document.title = 'SVERIFY|S1PROV=' + prov('S1') + '|S2PROV=' + prov('S2')
      + '|SEL=' + (document.querySelector('[data-id="S1"] select') || {}).value
      + '|ASK=' + ((ask('S1', '[show-me]') || {}).checked ? '1' : '0');
  }
});
</script>
HTML
}

write_surfaces_body
bash "$WRAP" --title "surfaces" --lang es --out "$SPAGE" < "$TMP/sbody.html" > "$TMP/swrap.log" 2>&1 \
  || fail "the surfaces probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/swrap.log" | sed -n 1,4p)"
srun() {  # srun <query>
  chrome_dump "$TMP/sdom.html" "file://$SPAGE?$1" 45 || true
  grep -oE '<title>[^<]*</title>' "$TMP/sdom.html" | sed -n 1p
}
rm -rf "$TMP/profile"
ts="$(srun 'phase=sfill')"
[[ "$ts" == *SURFACES* ]] || fail "the surfaces phase did not run: $ts"
[[ "$ts" == *"BEFORE=0"* ]] \
  || fail "provisional: an answered surface with NO ask was marked provisional: $ts"
[[ "$ts" == *"S1PROV=1"* ]] \
  || fail "provisional: a chosen SELECT value with an ask beside it is not marked provisional — the surface is an answer like any option: $ts"
[[ "$ts" == *"S2PROV=1"* ]] \
  || fail "provisional: a short-text answer with an ask beside it is not marked provisional: $ts"
[[ "$ts" == *"S3PROV=0"* ]] \
  || fail "provisional: free prose with an ask beside it was marked provisional — prose is not a chosen answer, and this cell is what fails if the predicate is hard-coded: $ts"
[[ "$ts" == *"Alpha [provisional]"* ]] \
  || fail "provisional: the copied reply does not qualify the chosen select value: $ts"
[[ "$ts" == *"Un valor [provisional]"* ]] \
  || fail "provisional: the copied reply does not qualify the short-text answer: $ts"
[[ "$ts" == *"solo prosa [provisional]"* ]] \
  && fail "provisional: the copied reply qualified free prose, which is not an answer to qualify: $ts"
[[ "$ts" == *"FOCUSCE=1"* ]] \
  || fail "the question chip focused nothing on an item whose only free box is a contenteditable: $ts"
[[ "$ts" == *"FOCUSNOTES=1"* ]] \
  || fail "the question chip focused nothing on an item with no free box — the page's general-notes box is where the question goes: $ts"

# The state survives a reload: the pair is restored, so the line comes back.
ts="$(srun 'phase=sverify')"
[[ "$ts" == *"SEL=a"* && "$ts" == *"ASK=1"* ]] \
  || fail "provisional: the select answer or its ask did not survive the reload, so the line below proves nothing: $ts"
[[ "$ts" == *"S1PROV=1"* ]] \
  || fail "provisional: a restored answer-plus-ask pair came back without its provisional line: $ts"

# ---- the GALLERY row: zoom, keyboard and filters (plan 2026-09-22, Phase 2) --
#
# A gallery row is judged by LOOKING at the capture, so the kit gives every tile
# a dialog at native size. Three things have to hold together and none of them
# is visible to the structural checks:
#
#   the dialog OPENS in the page (no navigation, no new tab) and closes back
#   onto the tile that opened it — a zoom that navigated away would lose every
#   answer already typed on the page;
#
#   the arrows walk the matrix — the row's tiles in the block's declared order,
#   the same tile down the rows — and refuse to wrap, so an end is an end;
#
#   a filter hides tiles and changes NOTHING about the paste. That last cell is
#   the RED control of this section: the filter is a <button> writing an
#   attribute on the BLOCK, and if it were ever built as an input inside the
#   item (the obvious cheap way) the paste would gain a "- Light" line and this
#   assertion is what would say so.
GPAGE="$TMP/reports/gallery.html"
# A 1x1 PNG, inline: the tiles must be real images the dialog can show, and a
# path would make this test depend on a screenshot tree only one worktree has.
PX='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
# A 2x1 PNG on ONE sibling (audit-empty dark-mobile): the compare probe needs a
# pair whose intrinsic sizes differ, and swipe/onion over two sizes is a lie.
PX2='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGNgYGD4D8IABgMB/8+HxnAAAAAASUVORK5CYII='
write_gallery_body() {
cat > "$TMP/gbody.html" <<HTML
<meta name="consult-visual" content="none: a gallery probe, nothing to draw">
<div class="page">
<main class="main">
<header><p class="eyebrow">PROBE</p><h1>Gallery probe</h1></header>
<section id="sec-ask">
  <div class="sec-head"><h2>Questions</h2></div>
  <section class="consult-group" id="E" data-id="E" data-title="The matrix" data-tiles="light-desktop dark-desktop light-mobile dark-mobile">
    <div class="sec-head"><h2>The matrix</h2></div><p>One row per screen state.</p>
  <section class="consult-item consult-gallery" data-id="audit-with-data" data-title="audit &middot; with-data">
    <h3><span class="consult-id">audit-with-data</span>audit &middot; with-data</h3>
    <div class="gal">
      <figure data-tile="light-desktop"><img src="$PX" alt="with-data light-desktop"><figcaption>light &middot; desktop</figcaption></figure>
      <figure data-tile="dark-desktop"><img src="$PX" alt="with-data dark-desktop"><figcaption>dark &middot; desktop</figcaption></figure>
      <figure data-tile="light-mobile"><img src="$PX" alt="with-data light-mobile"><figcaption>light &middot; mobile</figcaption></figure>
      <!-- A trailing space in data-tile: the checker strips it, so the kit must too
           or the arrows freeze and the filter never hides this tile. -->
      <figure data-tile="dark-mobile "><img src="$PX" alt="with-data dark-mobile"><figcaption>dark &middot; mobile</figcaption></figure>
    </div>
    <div class="opts one">
      <label><input type="radio" name="audit-with-data" data-label="Approved"><span>Approved</span></label>
      <label><input type="radio" name="audit-with-data" data-label="Needs changes"><span>Needs changes</span></label>
    </div>
    <p class="fieldlabel">Notas sobre esta</p>
    <textarea></textarea>
  </section>
  <section class="consult-item consult-gallery" data-id="audit-empty" data-title="audit &middot; empty">
    <h3><span class="consult-id">audit-empty</span>audit &middot; empty</h3>
    <div class="gal">
      <figure data-tile="light-desktop"><img src="$PX" alt="empty light-desktop"><figcaption>light &middot; desktop</figcaption></figure>
      <figure data-tile="dark-desktop"><img src="$PX" alt="empty dark-desktop"><figcaption>dark &middot; desktop</figcaption></figure>
      <figure data-tile="light-mobile"><img src="$PX" alt="empty light-mobile"><figcaption>light &middot; mobile</figcaption></figure>
      <figure data-tile="dark-mobile"><img src="$PX2" alt="empty dark-mobile"><figcaption>dark &middot; mobile</figcaption></figure>
    </div>
    <div class="opts one">
      <label><input type="radio" name="audit-empty" data-label="Approved"><span>Approved</span></label>
      <label><input type="radio" name="audit-empty" data-label="Needs changes"><span>Needs changes</span></label>
    </div>
    <p class="fieldlabel">Notas sobre esta</p>
    <textarea></textarea>
  </section>
  <!-- The not-applicable row: no tiles at all, so the arrows must step OVER it
       rather than stop on it. -->
  <section class="consult-item consult-gallery" data-id="audit-no-permission" data-title="audit &middot; no-permission">
    <h3><span class="consult-id">audit-no-permission</span>audit &middot; no-permission</h3>
    <p class="gal-na">Unreachable in the demo.</p>
    <div class="opts one">
      <label><input type="radio" name="audit-no-permission" data-label="Approved"><span>Approved</span></label>
      <label><input type="radio" name="audit-no-permission" data-label="Needs changes"><span>Needs changes</span></label>
    </div>
    <p class="fieldlabel">Notas sobre esta</p>
    <textarea></textarea>
  </section>
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
    <button type="button" id="consult-copy"></button>
    <span class="consult-status" id="consult-status"></span>
  </div>
</aside>
</div>
<script>
window.addEventListener('load', function () {
  var q = location.search;
  if (q.indexOf('phase=g') === -1) return;
  var dlg = document.querySelector('dialog.kit-zoom');
  var fig = function (row, tile) {
    return document.querySelector('[data-id="' + row + '"] figure[data-tile="' + tile + '"]');
  };
  var htile = function () { return dlg ? dlg.querySelector('.kit-zoom-tile').textContent : ''; };
  var hcell = function () { return dlg ? dlg.querySelector('.kit-zoom-cell').textContent : ''; };
  var key = function (k) {
    dlg.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true }));
  };
  var bar = function (group, value) {
    var b = document.querySelector('#' + group + ' .kit-galbar button[data-value="' + value + '"]');
    if (b) b.click();
    return !!b;
  };
  var paste = function () {
    var cap = '';
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: function (s) { cap = s; return Promise.resolve(); } }
    });
    document.getElementById('consult-copy').click();
    return cap;
  };
  if (q.indexOf('phase=gzoom') !== -1) {
    var first = fig('audit-with-data', 'light-desktop');
    var href0 = location.href;
    var tabs = 0;
    var openWin = window.open;
    window.open = function () { tabs++; return null; };
    first.click();
    var openState = dlg && dlg.open ? '1' : '0';
    /* The :modal match is what says showModal() was used rather than show():
       the focus trap, the backdrop and Esc all come from that, and none of
       them can be asserted from a synthetic key event (the UA only honours a
       trusted Esc). */
    var modal = dlg && dlg.matches(':modal') ? '1' : '0';
    var hrow = dlg ? dlg.querySelector('.kit-zoom-row').textContent : '';
    var h0tile = htile(), h0cell = hcell();
    var fit = dlg.classList.contains('native') ? '1' : '0';
    dlg.querySelector('.kit-zoom-size').click();
    var nativeOn = dlg.classList.contains('native') ? '1' : '0';
    dlg.querySelector('.kit-zoom-size').click();
    var nativeOff = dlg.classList.contains('native') ? '1' : '0';
    /* The matrix, walked. Right from the first tile, then Left twice: the
       second Left has nowhere to go and must leave the dialog where it is. */
    key('ArrowRight'); var right1 = htile();
    key('ArrowLeft');  var left1 = htile();
    key('ArrowLeft');  var left2 = htile();
    key('ArrowDown');  var down1 = hcell() + '/' + htile();
    /* The third row carries no tiles (not applicable), so Down must step over
       it and stop — never land on a row with nothing to show. */
    key('ArrowDown');  var down2 = hcell() + '/' + htile();
    key('ArrowUp');    var up1 = hcell();
    key('ArrowUp');    var up2 = hcell();
    /* Rows exist here, so Down is the walk and the dialog must not scroll
       under it (Up puts the walk back where it was). */
    var downPass = dlg.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true, cancelable: true })) ? '1' : '0';
    key('ArrowUp');
    /* Walk to the row's far end and close THERE: focus must go back to the
       tile that opened the dialog, not to the last one shown (the walk above
       ends on the opener, so without this the FOCUS cell passes by chance). */
    key('ArrowRight'); key('ArrowRight'); key('ArrowRight');
    var right3 = htile();
    dlg.querySelector('.kit-zoom-close').click();
    /* Esc and the close button both return the focus through the dialog's
       own close event, which the engine queues rather than firing inline (no
       backticks anywhere in this heredoc: it is unquoted, so a backtick in a
       comment is a command run by bash) — and a real Esc needs a trusted key
       this harness cannot send. Dispatching the
       same event synchronously is what makes the return readable here. */
    dlg.dispatchEvent(new Event('close'));
    window.open = openWin;
    document.title = 'GZOOM|OPEN=' + openState + '|MODAL=' + modal
      + '|HROW=' + hrow.replace(/[|<>]/g, ' ') + '|HTILE=' + h0tile + '|HCELL=' + h0cell
      + '|SRC=' + (dlg.querySelector('img').getAttribute('src').slice(0, 14))
      + '|FIT=' + fit + '|NATIVE=' + nativeOn + '|NATIVEOFF=' + nativeOff
      + '|RIGHT=' + right1 + '|LEFT=' + left1 + '|LEFTEND=' + left2
      + '|DOWN=' + down1 + '|DOWNEND=' + down2 + '|UP=' + up1 + '|UPEND=' + up2 + '|DOWNPASS=' + downPass + '|RIGHT3=' + right3.trim() + '/' + (right3 === right3.trim() ? 'clean' : 'raw')
      + '|CLOSED=' + (dlg.open ? '0' : '1')
      + '|FOCUS=' + (document.activeElement === first ? '1' : '0')
      + '|ROLE=' + first.getAttribute('role') + '|TABINDEX=' + first.getAttribute('tabindex')
      /* The markup itself is untouched: a reader with scripts off sees the same
         grid and the same captions. */
      + '|FIGS=' + document.querySelectorAll('[data-id="audit-with-data"] figure[data-tile]').length
      + '|CAPS=' + document.querySelectorAll('[data-id="audit-with-data"] figcaption').length
      + '|HREF=' + (location.href === href0 ? 'same' : 'changed')
      + '|TABS=' + tabs;
  } else if (q.indexOf('phase=gkey') !== -1) {
    /* Enter on a focused tile opens it too: the tile is a button, and a
       reviewer on the keyboard never reaches a mouse-only affordance. */
    var f2 = fig('audit-empty', 'dark-mobile');
    f2.focus();
    f2.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
    document.title = 'GKEY|OPEN=' + (dlg && dlg.open ? '1' : '0')
      + '|CELL=' + hcell() + '|TILE=' + htile();
  } else if (q.indexOf('phase=gfilter') !== -1) {
    /* Two columns before any filter, or the lone-tile cell below would pass
       on a grid that was one column anyway. */
    var twoCol = fig('audit-empty', 'light-desktop').offsetTop === fig('audit-empty', 'dark-desktop').offsetTop ? '1' : '0';
    var r = document.querySelector('[data-id="audit-with-data"] input[data-label="Approved"]');
    r.checked = true; r.dispatchEvent(new Event('change', { bubbles: true }));
    var ta = document.querySelector('[data-id="audit-with-data"] textarea');
    ta.value = 'la fila se ve bien'; ta.dispatchEvent(new Event('input', { bubbles: true }));
    var before = paste();
    /* A stored value of the wrong shape (a string where a block's object
       belongs) must not stop the filter from being saved from then on. */
    var gk = 'aidex-kit-gallery:' + location.pathname;
    localStorage.setItem(gk, '{"E":"light"}');
    var hit = bar('E', 'light');
    var storedMode = '';
    try { storedMode = JSON.parse(localStorage.getItem(gk)).E.mode || ''; } catch (e) {}
    var g = document.getElementById('E');
    var darkFig = fig('audit-with-data', 'dark-desktop');
    var lightFig = fig('audit-with-data', 'light-desktop');
    var after = paste();
    /* Read while only the MODE filter is on: applying the viewport filter next
       would hide the light-desktop tile as well and the assertion below would
       pass for the other rule's reason. */
    var darkHid = getComputedStyle(darkFig).display;
    var lightVis = getComputedStyle(lightFig).display !== 'none' ? '1' : '0';
    bar('E', 'mobile');
    var deskFig = fig('audit-empty', 'light-desktop');
    var mobFig = fig('audit-empty', 'light-mobile');
    var deskHid = getComputedStyle(deskFig).display;
    var mobVis = getComputedStyle(mobFig).display !== 'none' ? '1' : '0';
    /* Light and mobile together leave ONE tile per row: it takes the row, not
       the left half of a grid whose right half is empty. */
    var gridE = mobFig.parentNode;
    var lone = mobFig.getBoundingClientRect().width >= gridE.clientWidth - 1 ? 'full' : 'half:' + Math.round(mobFig.getBoundingClientRect().width) + '/' + gridE.clientWidth;
    /* Filters are a viewing aid, never a change of what is being judged: the
       arrows still reach a hidden tile. */
    lightFig.click();
    key('ArrowRight');
    var reached = htile();
    dlg.querySelector('.kit-zoom-close').click();
    /* The viewport rule matches on the END of the tile name ($=), which is
       where a stray space sits; the mode rule (^=) would hide it regardless. */
    bar('E', 'both'); bar('E', 'desktop');
    var spaced = document.querySelector('[data-id="audit-with-data"] figure img[alt="with-data dark-mobile"]').parentNode;
    var spacedHid = getComputedStyle(spaced).display;
    bar('E', 'light'); bar('E', 'mobile');
    document.title = 'GFILTER|BAR=' + (hit ? '1' : '0')
      + '|MODE=' + g.getAttribute('data-mode') + '|VIEW=' + g.getAttribute('data-viewport')
      + '|DARKHID=' + darkHid + '|LIGHTVIS=' + lightVis
      + '|DESKHID=' + deskHid + '|MOBVIS=' + mobVis + '|SPACEDHID=' + spacedHid
      + '|TWOCOL=' + twoCol + '|LONE=' + lone + '|IW=' + window.innerWidth
      + '|STORED=' + storedMode
      + '|PRESSED=' + document.querySelectorAll('#E .kit-galbar button[aria-pressed="true"]').length
      + '|BARS=' + document.querySelectorAll('.kit-galbar').length
      + '|INPUTS=' + document.querySelectorAll('.kit-galbar input, .kit-galbar select, .kit-galbar textarea').length
      + '|SAME=' + (before === after ? '1' : '0')
      + '|REACHED=' + reached
      + '|PASTE=' + after.replace(/[|<>\n]/g, ' ');
  } else if (q.indexOf('phase=gonecol') !== -1) {
    /* BL-466: at a phone width a capture is only readable one per row, at the
       row's full width. Every tile below the one before, none narrower. */
    var gw = document.querySelector('[data-id="audit-with-data"] .gal').clientWidth;
    var tops = [], narrow = 0;
    [].forEach.call(document.querySelectorAll('[data-id="audit-with-data"] .gal figure'), function (f) {
      tops.push(f.offsetTop);
      if (f.offsetWidth < gw - 1) narrow++;
    });
    var stacked = tops.every(function (t, i) { return i === 0 || t > tops[i - 1]; });
    document.title = 'GONECOL|W=' + window.innerWidth + '|N=' + tops.length
      + '|STACKED=' + (stacked ? '1' : '0') + '|NARROW=' + narrow;
  } else if (q.indexOf('phase=gdecided') !== -1) {
    fig('audit-with-data', 'light-desktop').click();
    key('ArrowDown');
    var dd = hcell();
    dlg.querySelector('.kit-zoom-close').click();
    document.title = 'GDECIDED|DOWN=' + dd
      + '|FOLDED=' + (document.querySelector('[data-id="audit-empty"]').closest('details:not([open])') ? '1' : '0');
  } else if (q.indexOf('phase=gcompare') !== -1) {
    /* The compare control, walked mode by mode. Everything is read
       synchronously: the dialog shows images the page has already loaded, so
       their sizes are known the moment the src is set. */
    var r3 = document.querySelector('[data-id="audit-with-data"] input[data-label="Approved"]');
    r3.checked = true; r3.dispatchEvent(new Event('change', { bubbles: true }));
    var ta3 = document.querySelector('[data-id="audit-with-data"] textarea');
    ta3.value = 'la fila se ve bien'; ta3.dispatchEvent(new Event('input', { bubbles: true }));
    var plain = paste();
    fig('audit-with-data', 'light-desktop').click();
    /* Phase 2's contract: a fresh open puts the focus on the size button,
       not on the first header control (the compare group sits before it). */
    var focus0 = document.activeElement ? document.activeElement.className : '';
    var cmpB = function (v) { return dlg.querySelector('.kit-zoom-cmp[data-value="' + v + '"]'); };
    var state = function () { return dlg.getAttribute('data-compare'); };
    var rng = dlg.querySelector('input.kit-zoom-range');
    var other = dlg.querySelector('img.kit-zoom-other');
    var slide = function (v) {
      rng.value = v; rng.dispatchEvent(new Event('input', { bubbles: true }));
    };
    var ctrl = dlg.querySelectorAll('.kit-zoom-cmp').length;
    var enabled = [].every.call(dlg.querySelectorAll('.kit-zoom-cmp'), function (b) { return !b.disabled; });
    var st0 = state();
    cmpB('2up').click();
    var st2 = state() + '/' + (other ? other.getAttribute('alt') : '');
    cmpB('swipe').click();
    var stS = state();
    var sw = [25, 50, 75].map(function (v) {
      slide(v);
      return dlg.style.getPropertyValue('--kit-swipe').trim() + ':' + getComputedStyle(other).clipPath;
    }).join(',');
    cmpB('onion').click();
    var stO = state();
    var on = [25, 50, 75].map(function (v) {
      slide(v);
      return getComputedStyle(other).opacity;
    }).join(',');
    /* The arrows walk while compare is on, and compare stays on: the next
       tile's sibling is the other mode of the NEW tile. */
    key('ArrowRight');
    var walked = htile() + '/' + state() + '/' + other.getAttribute('alt') + '/' + rng.value;
    /* A focused slider keeps the arrows for itself, like any native range:
       the key reaches the dialog's handler and must not walk the tile. */
    rng.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true, cancelable: true }));
    var owned = htile();
    var moved = paste();
    var inItem = rng.closest('.consult-item') ? '1' : '0';
    dlg.querySelector('.kit-zoom-close').click();
    /* A fresh open: compare off, the slider back to its middle. */
    fig('audit-with-data', 'light-mobile').click();
    var fresh = state() + '/' + rng.value;
    /* The mobile pair differs in size (1x1 against 2x1): swipe falls back to
       2-up and says so; walking to a same-size pair restores swipe. */
    dlg.querySelector('.kit-zoom-close').click();
    fig('audit-empty', 'light-mobile').click();
    cmpB('swipe').click();
    var note = dlg.querySelector('.kit-zoom-note');
    var mism = state() + '/' + (note && !note.hidden ? note.textContent : 'nonote');
    key('ArrowLeft');
    var back = htile() + '/' + state() + '/' + (note && note.hidden ? 'hidden' : 'shown');
    dlg.querySelector('.kit-zoom-close').click();
    /* A filter hides the sibling tile; it is still the sibling. */
    bar('E', 'light');
    fig('audit-with-data', 'light-desktop').click();
    cmpB('2up').click();
    var filtered = state();
    dlg.querySelector('.kit-zoom-close').click();
    bar('E', 'both');
    /* No sibling at all: the control is disabled and says why. */
    fig('audit-empty', 'dark-desktop').remove();
    fig('audit-empty', 'light-desktop').click();
    var dis = [].every.call(dlg.querySelectorAll('.kit-zoom-cmp'), function (b) { return b.disabled; });
    var why = (cmpB('2up') && cmpB('2up').title) || '';
    cmpB('2up').click();
    var noSib = state();
    dlg.querySelector('.kit-zoom-close').click();
    /* The walk must survive a step onto a tile with no sibling while a compare
       button has the focus: that step disables the focused button, and a
       disabled control drops the focus to the body, out of the dialog, where
       the next arrow never reaches the dialog's key handler. Chrome runs that
       drop as a posted task, after this synchronous probe has reported, so
       what is asserted is its cause: after the step the focus must sit, in
       the dialog, on something that is NOT disabled. The keys go to whatever
       holds the focus, as a real key does. */
    var akey = function (k) {
      (document.activeElement || document.body).dispatchEvent(
        new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true }));
    };
    fig('audit-with-data', 'light-desktop').click();
    cmpB('swipe').click();
    cmpB('swipe').focus();
    akey('ArrowDown');                /* audit-empty light-desktop: no sibling now */
    var landed = hcell() + '/' + htile() + '/' + state();
    var ae = document.activeElement;
    var held = (dlg.contains(ae) ? 'in' : 'out:' + ae.tagName) + (ae.disabled ? ':disabled' : '');
    akey('ArrowRight');
    var kept = held + '/' + hcell() + '/' + htile();
    dlg.querySelector('.kit-zoom-close').click();
    /* The slider is not an answer: moving it must not reach the composer's
       document listeners, whose refresh() would overwrite the copy
       confirmation on the status line. The fallback path confirms
       synchronously, so the line is readable here. */
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: undefined });
    document.getElementById('consult-copy').click();
    var fb = document.querySelector('body > textarea:last-of-type');
    if (fb) fb.remove();
    var stEl = document.getElementById('consult-status');
    var st1 = stEl.textContent;
    fig('audit-with-data', 'light-desktop').click();
    cmpB('swipe').click();
    slide(30);
    rng.dispatchEvent(new Event('change', { bubbles: true }));
    var stKept = stEl.textContent === st1 ? '1' : '0:' + stEl.textContent.replace(/[|<>]/g, ' ');
    dlg.querySelector('.kit-zoom-close').click();
    document.title = 'GCOMPARE|CTRL=' + ctrl + '|ENABLED=' + (enabled ? '1' : '0')
      + '|ST0=' + st0 + '|ST2=' + st2 + '|STS=' + stS + '|SW=' + sw + '|STO=' + stO + '|ON=' + on
      + '|WALKED=' + walked + '|OWNED=' + owned + '|INITEM=' + inItem
      + '|SAME=' + (plain === moved ? '1' : '0')
      + '|FRESH=' + fresh + '|MISM=' + mism + '|BACK=' + back
      + '|FILTERED=' + filtered + '|DIS=' + (dis ? '1' : '0') + '|WHY=' + (why ? '1' : '0')
      + '|NOSIB=' + noSib + '|FOCUS0=' + focus0 + '|LANDED=' + landed + '|KEPT=' + kept
      + '|STKEPT=' + stKept
      + '|PASTE=' + moved.replace(/[|<>\n]/g, ' ');
  } else if (q.indexOf('phase=gm') !== -1) {
    /* REGION MARKS (Phase 4). Drawn by pointer on the layer over the dialog
       image, stored in the row's hidden kit-marks textarea, pasted by readItem
       like any textarea. The probe page gives audit-with-data a 400x200 image,
       so a pixel is 0.25 of a percent across and 0.5 down. */
    var mta = function (row) {
      return document.querySelector('[data-id="' + row + '"] textarea.kit-marks');
    };
    var layer = function () { return dlg.querySelector('.kit-marks-layer'); };
    var ndlg = function () { return document.querySelector('dialog.kit-mark-note'); };
    var drag = function (x0, y0, x1, y1) {
      var ly = layer();
      if (!ly) return;
      var r = ly.getBoundingClientRect();
      var ev = function (type, x, y, at) {
        at.dispatchEvent(new PointerEvent(type, { clientX: r.left + x, clientY: r.top + y,
          bubbles: true, cancelable: true, pointerId: 1, isPrimary: true, button: 0 }));
      };
      /* The press lands on whatever is under the pointer, as a real one does:
         inside a mark that is the mark, and the layer must still hear it. The
         move and the release go to the layer, which captures the pointer. */
      var under = document.elementFromPoint(r.left + x0, r.top + y0);
      ev('pointerdown', x0, y0, under && ly.contains(under) ? under : ly);
      ev('pointermove', x1, y1, ly); ev('pointerup', x1, y1, ly);
    };
    var note = function (text, act) {
      var n = ndlg();
      if (!n || !n.open) return '0';
      if (text !== null) n.querySelector('input').value = text;
      n.querySelector('button[data-act="' + act + '"]').click();
      return '1';
    };
    var tileMarks = function (row, tile) {
      return document.querySelectorAll('[data-id="' + row + '"] figure[data-tile="' + tile + '"] .kit-mark').length;
    };
    var enc = function (s) { return btoa(unescape(encodeURIComponent(s))); };
    var akey2 = function (k) {
      (document.activeElement || document.body).dispatchEvent(
        new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true }));
    };
    var pev = function (el) { return el ? getComputedStyle(el).pointerEvents : 'nomark'; };
    if (q.indexOf('phase=gmrecall') !== -1) {
      fig('audit-with-data', 'light-desktop').click();
      var inDlg = dlg.querySelectorAll('.kit-marks-layer .kit-mark').length;
      dlg.querySelector('.kit-zoom-close').click();
      document.title = 'GMRECALL|TILE=' + tileMarks('audit-with-data', 'light-desktop')
        + '|DLG=' + inDlg
        + '|PASTE=' + paste().replace(/[|<>\n]/g, ' ');
    } else if (q.indexOf('phase=gmedge') !== -1) {
      var chanE = mta('audit-with-data');
      fig('audit-with-data', 'light-desktop').click();
      /* A drag that clamps to no width (all of it left of the image) or has
         no height creates nothing: such a mark could never be hit, so never
         opened or deleted. */
      drag(0, 50, -40, 51);
      var deg1 = chanE.value + '/' + (ndlg().open ? 'note' : 'nonote');
      if (ndlg().open) note(null, 'cancel');
      drag(100, 100, 110, 100);
      var deg2 = chanE.value + '/' + (ndlg().open ? 'note' : 'nonote');
      if (ndlg().open) note(null, 'cancel');
      /* Right-to-left and bottom-to-top: the rectangle of the forward drag
         (50,68 to 210,89 is 12.5,34.0 40.0x10.5). */
      drag(210, 89, 50, 68);
      note('reversed', 'save');
      var rev = chanE.value;
      /* Past the right and the bottom edge: clamped to 100. */
      drag(300, 150, 450, 260);
      note('edge', 'save');
      var clamp = chanE.value.split('\n')[1] || '';
      var dmark = dlg.querySelector('.kit-marks-layer .kit-mark[title="edge"]');
      var peDlg = pev(dmark);
      /* A press inside a mark reaches the layer: the click opens its note. */
      drag(340, 180, 341, 180);
      var hitE = ndlg().open ? ndlg().querySelector('input').value : 'closed';
      /* Esc on the note dialog (the UA closes the TOP modal only; a trusted
         Esc cannot be sent, so its effects are replayed): the key reaches no
         handler of the zoom dialog, the note closes, the zoom stays open and
         holds the focus, and nothing is written. */
      var vEsc = chanE.value;
      ndlg().querySelector('input').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
      ndlg().close();
      ndlg().dispatchEvent(new Event('close'));
      var aeE = document.activeElement;
      var esc = (ndlg().open ? 'noteopen' : 'noteclosed') + '/' + (dlg.open ? 'zoomopen' : 'zoomclosed')
        + '/' + (dlg.contains(aeE) ? 'in' : 'out:' + (aeE ? aeE.tagName : 'none'))
        + '/' + (chanE.value === vEsc ? 'same' : 'changed');
      /* Two fingers (BL-649): a second finger down, moved, lifted, and a third
         one cancelled while the first draws neither starts a box of its own
         nor reshapes or ends the first one's. isPrimary as the browser sets it:
         only the first finger down is primary. The saved line is the first
         finger's rectangle (50,68 to 210,89), and no drawing box is left. */
      var mly = layer(), mr = mly.getBoundingClientRect();
      var mev = function (type, id, x, y) {
        mly.dispatchEvent(new PointerEvent(type, { pointerType: 'touch', pointerId: id, isPrimary: id === 21,
          button: 0, clientX: mr.left + x, clientY: mr.top + y, bubbles: true, cancelable: true }));
      };
      mev('pointerdown', 21, 50, 68); mev('pointerdown', 22, 300, 150);
      mev('pointermove', 21, 210, 89); mev('pointermove', 22, 350, 180);
      /* The box on screen is still the first finger's (left, width). */
      var mbox = [].map.call(dlg.querySelectorAll('.kit-marks-layer .kit-mark.drawing'), function (d) {
        return d.style.left + ',' + d.style.width;
      }).join(';');
      mev('pointerup', 22, 350, 180);
      mev('pointerdown', 23, 100, 100); mev('pointercancel', 23, 100, 100);
      mev('pointerup', 21, 210, 89);
      note('multi', 'save');
      var multi = chanE.value.split('\n')[2] || '';
      var stray = dlg.querySelectorAll('.kit-marks-layer .kit-mark.drawing').length;
      /* A primary press while a drag is still open (here a mouse while a
         finger draws; also a drag whose up never came) replaces it: one box. */
      var drawn = function () { return dlg.querySelectorAll('.kit-marks-layer .kit-mark.drawing').length; };
      var mouse = function (type, x, y) {
        mly.dispatchEvent(new PointerEvent(type, { pointerType: 'mouse', pointerId: 1, isPrimary: true,
          button: 0, clientX: mr.left + x, clientY: mr.top + y, bubbles: true, cancelable: true }));
      };
      mev('pointerdown', 21, 60, 20); mev('pointermove', 21, 100, 40);
      mouse('pointerdown', 200, 100);
      var replaced = drawn();
      mouse('pointerup', 240, 140);
      if (ndlg().open) note(null, 'cancel');
      mev('pointerup', 21, 100, 40);
      replaced += '/' + drawn();
      dlg.querySelector('.kit-zoom-close').click();
      /* The grid tile: the note shows on hover, and a click on a mark is still
         a click on the tile, which opens the zoom. */
      var tmark = document.querySelector('[data-id="audit-with-data"] figure[data-tile="light-desktop"] .kit-mark[title="edge"]');
      var peTile = pev(tmark);
      if (tmark) tmark.click();
      var tileZoom = dlg.open ? htile() : 'closed';
      if (dlg.open) dlg.querySelector('.kit-zoom-close').click();
      document.title = 'GMEDGE|DEG1=' + deg1 + '|DEG2=' + deg2
        + '|REV=' + rev.replace(/[|<>\n]/g, ' ') + '|CLAMP=' + clamp.replace(/[|<>\n]/g, ' ')
        + '|PEDLG=' + peDlg + '|HIT=' + hitE + '|ESC=' + esc
        + '|PETILE=' + peTile + '|TILEZOOM=' + tileZoom
        + '|MULTI=' + multi.replace(/[|<>\n]/g, ' ') + '|STRAY=' + stray
        + '|MBOX=' + mbox + '|REPLACED=' + replaced;
    } else if (q.indexOf('phase=gmask') !== -1) {
      /* The row's notes box is a contenteditable; the hidden kit-marks
         textarea is the only textarea in it. The chip must reach the box the
         reader can type in. */
      var chip = document.querySelector('[data-id="audit-with-data"] .kit-ask input[data-label="[question]"]');
      chip.checked = true;
      chip.dispatchEvent(new Event('change', { bubbles: true }));
      var ce = document.querySelector('[data-id="audit-with-data"] [contenteditable]');
      var aeA = document.activeElement;
      document.title = 'GMASK|FOCUSCE=' + (aeA === ce ? '1' : '0:' + (aeA ? aeA.tagName + '.' + aeA.className : 'none'));
    } else if (q.indexOf('phase=gmoldset') !== -1) {
      /* Entries as Phase 3 stored them: a gallery row's notes box was its
         only textarea, and the general-notes item carries the hash the kit
         computed for it before gallery rows hashed their tiles. */
      localStorage.setItem('aidex-kit-answers:' + location.pathname, JSON.stringify({
        'audit-with-data': { m: ['Approved'], a: ['notes from phase 3'] },
        /* Re-pinned (BL-701): the wrap shim now gives this probe's label-less notes item the label
           check-artifact requires, which moves its fingerprint. The rule under test (a gallery-row
           hash rule must not move a non-gallery item's hash) is unchanged, but this pin no longer
           proves a Phase-3 entry for a LABEL-LESS notes item still restores: it does not, and no
           kit change can make it (see the report's left-alone list). */
        'notes': { a: ['general from phase 3'], h: 'fd6c937e' }
      }));
      document.title = 'GMOLDSET|DONE';
    } else if (q.indexOf('phase=gmold') !== -1) {
      var vis = document.querySelector('[data-id="audit-with-data"] textarea:not(.kit-marks)');
      var genl = document.querySelector('[data-id="notes"] textarea');
      document.title = 'GMOLD|VIS=' + vis.value + '|MARKS=' + (mta('audit-with-data') ? '[' + mta('audit-with-data').value + ']' : 'none')
        + '|NOTES=' + genl.value;
    } else if (q.indexOf('phase=gmdecided') !== -1) {
      /* A decided row: its answer is sealed, so nothing is drawn on it; the
         marks it was decided with (written into the page) are still shown. */
      var before = mta('audit-with-data') ? mta('audit-with-data').value : 'none';
      fig('audit-with-data', 'light-desktop').click();
      drag(50, 68, 210, 89);
      var nOpen = ndlg() && ndlg().open ? '1' : '0';
      var after = mta('audit-with-data') ? mta('audit-with-data').value : 'none';
      dlg.querySelector('.kit-zoom-close').click();
      fig('audit-with-data', 'light-desktop').click();
      var mbD = dlg.querySelector('.kit-zoom-mark');
      var mbDs = mbD ? (mbD.disabled ? 'disabled' : 'enabled') : 'none';
      if (mbD) mbD.click();
      var dDraft = dlg.querySelectorAll('.kit-marks-layer .kit-mark.drawing').length;
      dlg.querySelector('.kit-zoom-close').click();
      document.title = 'GMDECIDED|SAME=' + (before === after ? '1' : '0') + '|MBD=' + mbDs + '|DDRAFT=' + dDraft
        + '|NOTE=' + nOpen + '|TILE=' + tileMarks('audit-with-data', 'light-desktop')
        + '|VAL=' + after.replace(/[|<>\n]/g, ' ');
    } else if (q.indexOf('phase=gmkey') !== -1) {
      /* KEYBOARD MARKS. The Mark button drafts a region in the middle of the
         image; arrows move it, Shift+arrows resize it, Enter asks for its note,
         Esc drops the draft and leaves the dialog open. Keys go to whatever
         holds the focus, as a real key does. */
      var chanK = mta('audit-with-data');
      var skey = function (k, shift) {
        (document.activeElement || document.body).dispatchEvent(
          new KeyboardEvent('keydown', { key: k, shiftKey: !!shift, bubbles: true, cancelable: true }));
      };
      var times = function (n, k, shift) { for (var i = 0; i < n; i++) skey(k, shift); };
      var drafting = function () { return dlg.querySelectorAll('.kit-marks-layer .kit-mark.drawing').length; };
      fig('audit-with-data', 'light-desktop').click();
      var mb = dlg.querySelector('.kit-zoom-mark');
      var mbState = mb ? (mb.disabled ? 'disabled' : 'enabled') : 'none';
      if (mb) mb.click();
      var drafts = drafting();
      times(5, 'ArrowRight'); times(3, 'ArrowDown', true);
      var stillTile = htile();
      skey('Enter');
      var kOpen = ndlg().open ? '1' : '0';
      note('kbd', 'save');
      var kOne = chanK.value;
      var aeK = document.activeElement;
      var kFocus = dlg.contains(aeK) ? 'in' : 'out:' + (aeK ? aeK.tagName : 'none');
      skey('ArrowRight'); var kWalk = htile(); skey('ArrowLeft');
      /* Clamped: grown past the right edge, then pushed against it. */
      if (mb) mb.click();
      times(100, 'ArrowRight', true); times(10, 'ArrowRight');
      skey('Enter'); note('edge', 'save');
      var kEdge = chanK.value.split('\n')[1] || '';
      /* Esc during a draft, and Enter on a focused dialog button, are the
         browser's default actions: a synthetic key never starts them, so
         test-gallery-keys.sh owns both with trusted key presses. */
      /* The SWIPE HANDLE: a visible line where the two captures meet, on the
         image (not the dialog), and only in swipe mode. */
      dlg.querySelector('.kit-zoom-cmp[data-value="swipe"]').click();
      var mbCmp = mb ? (getComputedStyle(mb).display === 'none' || mb.disabled ? 'off' : 'on') : 'none';
      var rngK = dlg.querySelector('input.kit-zoom-range');
      var hd = dlg.querySelector('.kit-swipe-handle');
      var imK = dlg.querySelector('.kit-compare img:not(.kit-zoom-other)');
      var handleAt = function () {
        /* No layout box: the handle or its layer is display:none. */
        if (!hd || !hd.getClientRects().length) return 'hidden';
        var hr = hd.getBoundingClientRect(), ir = imK.getBoundingClientRect();
        var want = ir.left + ir.width * rngK.value / 100;
        var mid = hr.left + hr.width / 2;
        return Math.abs(mid - want) <= 1.5 && hr.height >= ir.height - 1 && hr.width >= 2
          ? 'line' : 'off:' + Math.round(mid) + '/' + Math.round(want) + '/' + Math.round(hr.height) + 'x' + Math.round(hr.width);
      };
      rngK.value = '25'; rngK.dispatchEvent(new Event('input', { bubbles: true }));
      var h25 = handleAt();
      rngK.value = '75'; rngK.dispatchEvent(new Event('input', { bubbles: true }));
      var h75 = handleAt();
      dlg.querySelector('.kit-zoom-cmp[data-value="onion"]').click();
      var hOn = handleAt();
      dlg.querySelector('.kit-zoom-cmp[data-value="off"]').click();
      var hOff = handleAt();
      dlg.querySelector('.kit-zoom-close').click();
      document.title = 'GMKEY|MB=' + mbState + '|DRAFT=' + drafts + '|STILL=' + stillTile
        + '|KOPEN=' + kOpen + '|ONE=' + kOne.replace(/[|<>\n]/g, ' ') + '|KFOCUS=' + kFocus
        + '|KWALK=' + kWalk + '|EDGE=' + kEdge.replace(/[|<>\n]/g, ' ') 
        + '|MBCMP=' + mbCmp + '|H25=' + h25 + '|H75=' + h75 + '|HON=' + hOn + '|HOFF=' + hOff;
    } else if (q.indexOf('phase=gmnarrow') !== -1) {
      /* The zoom header at 500 px: two lines at most, compare on or off, and
         nothing wider than the dialog. Two lines is measured, not guessed:
         twice a button's height plus the header's own gap, padding and rule. */
      fig('audit-with-data', 'light-desktop').click();
      var hdN = dlg.querySelector('.kit-zoom-head');
      var fits = function () {
        var cs = getComputedStyle(hdN);
        var bh = dlg.querySelector('.kit-zoom-close').offsetHeight;
        var limit = 2 * bh + (parseFloat(cs.rowGap) || 0) + parseFloat(cs.paddingTop)
          + parseFloat(cs.paddingBottom) + parseFloat(cs.borderBottomWidth) + 1;
        var wide = hdN.scrollWidth > hdN.clientWidth || dlg.scrollWidth > dlg.clientWidth;
        return (hdN.offsetHeight <= limit && !wide ? 'fits' : 'over') + ':' + hdN.offsetHeight + '/' + Math.round(limit) + (wide ? '/wide' : '');
      };
      var nOff = fits();
      dlg.querySelector('.kit-zoom-cmp[data-value="swipe"]').click();
      var nSwipe = fits();
      dlg.querySelector('.kit-zoom-close').click();
      document.title = 'GMNARROW|W=' + window.innerWidth + '|OFF=' + nOff + '|SWIPE=' + nSwipe;
    } else {
      /* Identity first: a row with no marks pastes exactly what Phase 3 did,
         with the hidden textarea already in place. */
      var r4 = document.querySelector('[data-id="audit-with-data"] input[data-label="Approved"]');
      r4.checked = true; r4.dispatchEvent(new Event('change', { bubbles: true }));
      var ta4 = document.querySelector('[data-id="audit-with-data"] textarea:not(.kit-marks)');
      ta4.value = 'la fila se ve bien'; ta4.dispatchEvent(new Event('input', { bubbles: true }));
      var plain = paste();
      var chan = mta('audit-with-data');
      var chanState = chan ? (chan.hidden ? 'hidden' : 'shown') : 'none';
      fig('audit-with-data', 'light-desktop').click();
      /* A drag under 4 px is a click on empty image: nothing is created. */
      drag(100, 100, 103, 102);
      var sub = (chan ? chan.value : 'none') + '/' + (ndlg() && ndlg().open ? 'note' : 'nonote');
      drag(50, 68, 210, 89);
      var noteOpen = ndlg() && ndlg().open ? '1' : '0';
      var saved1 = note('the breadcrumb wraps under the title', 'save');
      var one = chan ? chan.value : '';
      /* Out of the image on the top-left: clamped to 0. */
      drag(-20, -10, 100, 50);
      note('the logo is cut', 'save');
      /* A third mark, then deleted by clicking inside it. */
      drag(300, 150, 380, 190);
      note('temporary', 'save');
      var three = chan ? chan.value.split('\n').length : 0;
      drag(340, 170, 341, 171);
      var editOpen = ndlg() && ndlg().open ? ndlg().querySelector('input').value : 'closed';
      note(null, 'delete');
      var afterDel = chan ? chan.value.split('\n').length : 0;
      /* Cancel on a NEW mark writes nothing. */
      drag(200, 20, 260, 60);
      note('never saved', 'cancel');
      var afterCancel = chan ? chan.value.split('\n').length : 0;
      var inDlg2 = dlg.querySelectorAll('.kit-marks-layer .kit-mark').length;
      /* The note dialog closed back into the zoom dialog: the arrows still walk. */
      var ae = document.activeElement;
      var focusIn = dlg.contains(ae) ? 'in' : 'out:' + (ae ? ae.tagName : 'none');
      akey2('ArrowRight');
      var walked = htile();
      akey2('ArrowLeft');
      /* Compare on: the layer is hidden and draws nothing. */
      dlg.querySelector('.kit-zoom-cmp[data-value="swipe"]').click();
      var lyDisp = layer() ? getComputedStyle(layer()).display : 'nolayer';
      var v0 = chan ? chan.value : '';
      drag(10, 10, 100, 100);
      var cmpDraw = (chan && chan.value === v0 ? 'none' : 'drawn') + '/' + (ndlg() && ndlg().open ? 'note' : 'nonote');
      if (ndlg() && ndlg().open) note(null, 'cancel');
      dlg.querySelector('.kit-zoom-cmp[data-value="off"]').click();
      dlg.querySelector('.kit-zoom-close').click();
      var tileN = tileMarks('audit-with-data', 'light-desktop');
      var r5 = document.querySelector('[data-id="audit-with-data"] input[data-label="Needs changes"]');
      r5.checked = true; r5.dispatchEvent(new Event('change', { bubbles: true }));
      var withMarks = paste();
      document.body.setAttribute('data-paste', enc(withMarks));
      document.title = 'GMARKS|CHAN=' + chanState
        + '|PLAIN=' + plain.replace(/[|<>\n]/g, ' ')
        + '|SUB=' + sub + '|NOTEOPEN=' + noteOpen + '|SAVED=' + saved1
        + '|ONE=' + one.replace(/[|<>\n]/g, ' ')
        + '|THREE=' + three + '|EDIT=' + editOpen + '|DEL=' + afterDel + '|CANCEL=' + afterCancel
        + '|DLG=' + inDlg2 + '|FOCUSIN=' + focusIn + '|WALKED=' + walked
        + '|LYCMP=' + lyDisp + '|CMPDRAW=' + cmpDraw + '|TILE=' + tileN
        + '|PASTE=' + withMarks.replace(/[|<>\n]/g, ' ');
    }
  } else if (q.indexOf('phase=gun') !== -1) {
    /* Two blocks with no id: each keeps its own filter. */
    var gs = document.querySelectorAll('.consult-group');
    if (q.indexOf('phase=gunset') !== -1) {
      var b0 = gs[0].querySelector('.kit-galbar button[data-value="light"]');
      if (b0) b0.click();
      document.title = 'GUNSET|N=' + gs.length + '|M0=' + gs[0].getAttribute('data-mode') + '|M1=' + gs[1].getAttribute('data-mode');
    } else {
      document.title = 'GUNGET|M0=' + gs[0].getAttribute('data-mode') + '|M1=' + gs[1].getAttribute('data-mode');
    }
  } else if (q.indexOf('phase=grecall') !== -1) {
    var g2 = document.getElementById('E');
    var pressed = [].map.call(document.querySelectorAll('#E .kit-galbar button[aria-pressed="true"]'),
      function (b) { return b.dataset.value; }).join(',');
    document.title = 'GRECALL|MODE=' + g2.getAttribute('data-mode')
      + '|VIEW=' + g2.getAttribute('data-viewport')
      + '|PRESSED=' + pressed
      + '|PASTE=' + paste().replace(/[|<>\n]/g, ' ');
  }
});
</script>
HTML
}

write_gallery_body
bash "$WRAP" --title "gallery" --lang es --out "$GPAGE" < "$TMP/gbody.html" > "$TMP/gwrap.log" 2>&1 \
  || fail "the gallery probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap.log" | sed -n 1,4p)"
grun() {  # grun <query>
  chrome_dump "$TMP/gdom.html" "file://$GPAGE?$1" 45 || true
  grep -oE '<title>[^<]*</title>' "$TMP/gdom.html" | sed -n 1p
}
# Before any filter phase stores a mode or a viewport: a hidden tile would read
# as a narrow one.
rm -rf "$TMP/profile"
tg="$(CHROME_WINDOW=390,900 grun 'phase=gonecol')"
[[ "$tg" == *"GONECOL|W=390|N=4"* ]] || fail "the one-per-row phase did not run at 390 px on four tiles: $tg"
[[ "$tg" == *"STACKED=1"* && "$tg" == *"NARROW=0"* ]] \
  || fail "at 390 px the gallery tiles share a row or do not fill it — one per row at full width is the only readable layout (BL-466): $tg"

rm -rf "$TMP/profile"
tg="$(grun 'phase=gzoom')"
[[ "$tg" == *GZOOM* ]] || fail "the gallery zoom phase did not run: $tg"
[[ "$tg" == *"OPEN=1"* ]] \
  || fail "clicking a tile did not open the zoom dialog: $tg"
[[ "$tg" == *"MODAL=1"* ]] \
  || fail "the dialog was opened with show() rather than showModal() — no focus trap, no backdrop, and Esc does not close it: $tg"
[[ "$tg" == *"HROW=audit · with-data"* && "$tg" == *"HTILE=light-desktop"* \
   && "$tg" == *"HCELL=audit-with-data"* ]] \
  || fail "the dialog header does not carry the row, the tile and the cell id: $tg"
[[ "$tg" == *"SRC=data:image/png"* ]] \
  || fail "the dialog showed no image for the tile that opened it: $tg"
[[ "$tg" == *"FIT=0"* ]] \
  || fail "the dialog opened at native size — fit to the window is the default: $tg"
[[ "$tg" == *"NATIVE=1"* && "$tg" == *"NATIVEOFF=0"* ]] \
  || fail "the size toggle does not switch the dialog between fit and native: $tg"
[[ "$tg" == *"RIGHT=dark-desktop"* ]] \
  || fail "Right did not move to the next tile of the block's declared order: $tg"
[[ "$tg" == *"LEFT=light-desktop"* ]] \
  || fail "Left did not move back to the previous tile: $tg"
[[ "$tg" == *"LEFTEND=light-desktop"* ]] \
  || fail "Left wrapped around from the first tile — the ends are the ends: $tg"
[[ "$tg" == *"DOWN=audit-empty/light-desktop"* ]] \
  || fail "Down did not move to the same tile on the next row: $tg"
[[ "$tg" == *"DOWNEND=audit-empty/light-desktop"* ]] \
  || fail "Down landed on the not-applicable row (or wrapped): a row with no tiles has nothing to show: $tg"
[[ "$tg" == *"UP=audit-with-data"* ]] \
  || fail "Up did not move back to the previous row: $tg"
[[ "$tg" == *"UPEND=audit-with-data"* ]] \
  || fail "Up wrapped around from the first row: $tg"
[[ "$tg" == *"DOWNPASS=0"* ]] \
  || fail "Down walked the rows but the dialog was left to scroll under it (only the item-images mode lets Up/Down through): $tg"
[[ "$tg" == *"CLOSED=1"* ]] \
  || fail "the close button did not close the dialog: $tg"
[[ "$tg" == *"FOCUS=1"* ]] \
  || fail "closing the dialog did not return focus to the tile that opened it (the walk ended on another tile): $tg"
[[ "$tg" == *"RIGHT3=dark-mobile/clean"* ]] \
  || fail "Right did not reach a tile whose data-tile carries a stray space the checker accepts (or the header shows the raw value): $tg"
[[ "$tg" == *"ROLE=button"* && "$tg" == *"TABINDEX=0"* ]] \
  || fail "the tile was not made a button (role and tabindex), so it is unreachable from the keyboard: $tg"
[[ "$tg" == *"FIGS=4"* && "$tg" == *"CAPS=4"* ]] \
  || fail "the composer rewrote the row's markup — with scripts off the grid and its captions must be unchanged: $tg"
[[ "$tg" == *"HREF=same"* ]] \
  || fail "opening a tile changed the page URL — the answers already typed would be lost: $tg"
[[ "$tg" == *"TABS=0"* ]] \
  || fail "opening a tile opened a new tab: $tg"

tg="$(grun 'phase=gkey')"
[[ "$tg" == *"GKEY|OPEN=1"* ]] \
  || fail "Enter on a focused tile did not open it: $tg"
[[ "$tg" == *"CELL=audit-empty"* && "$tg" == *"TILE=dark-mobile"* ]] \
  || fail "Enter opened the wrong tile: $tg"

rm -rf "$TMP/profile"
tg="$(CHROME_WINDOW=1280,900 grun 'phase=gfilter')"
[[ "$tg" == *GFILTER* ]] || fail "the gallery filter phase did not run: $tg"
[[ "$tg" == *"BAR=1"* && "$tg" == *"BARS=1"* ]] \
  || fail "no filter toolbar was injected on the block that declares a matrix: $tg"
[[ "$tg" == *"MODE=light"* ]] \
  || fail "the mode filter did not set data-mode on the block: $tg"
[[ "$tg" == *"VIEW=mobile"* ]] \
  || fail "the viewport filter did not set data-viewport on the block: $tg"
[[ "$tg" == *"DARKHID=none"* && "$tg" == *"LIGHTVIS=1"* ]] \
  || fail "filtering to light did not hide the dark tiles (or hid everything): $tg"
[[ "$tg" == *"DESKHID=none"* && "$tg" == *"MOBVIS=1"* ]] \
  || fail "filtering to mobile did not hide the desktop tiles (or hid everything): $tg"
[[ "$tg" == *"SPACEDHID=none"* ]] \
  || fail "the desktop filter did not hide a mobile tile whose data-tile carries a stray space: $tg"
[[ "$tg" == *"STORED=light"* ]] \
  || fail "a stored filter of the wrong shape stopped the filter from being saved: $tg"
[[ "$tg" == *"PRESSED=2"* ]] \
  || fail "the toolbar does not show which filter is on (one pressed button per control): $tg"
# THE RED CONTROL. The filter writes an attribute on the block and nothing else;
# built the cheap way — a radio group inside the item — the paste would gain a
# "- Light" line here and SAME would read 0.
[[ "$tg" == *"INPUTS=0"* ]] \
  || fail "the filter toolbar carries a form control — the composer pastes those, so how the reader was LOOKING at the page would travel as part of their answer: $tg"
[[ "$tg" == *"SAME=1"* ]] \
  || fail "a filtered page pastes different text from an unfiltered one: $tg"
[[ "$tg" == *"PASTE=## E · The matrix  ### audit-with-data · audit · with-data  - Approved  la fila se ve bien"* ]] \
  || fail "the row's verdict and notes did not reach the paste, so the identity assertion above proves nothing: $tg"
[[ "$tg" == *"REACHED=dark-desktop"* ]] \
  || fail "the arrows skipped a filtered-out tile — a filter is a viewing aid, not a change to what is being judged: $tg"
[[ "$tg" == *"TWOCOL=1"* ]] \
  || fail "the grid was not two columns at 1280 px before filtering, so the lone-tile cell proves nothing: $tg"
[[ "$tg" == *"LONE=full"* ]] \
  || fail "a filter that leaves one tile per row left it in half a two-column grid, the other half empty: $tg"

# A decided row is folded out of view by the composer; the arrows must not open
# it from the row above (the kit's collapse contract: open questions stay in view).
sed 's/data-id="audit-empty" data-title/data-id="audit-empty" data-decided="Approved" data-title/' \
  "$TMP/gbody.html" > "$TMP/gbody-decided.html"
GPAGE_D="$TMP/reports/gallery-decided.html"
bash "$WRAP" --title "gallery" --lang es --out "$GPAGE_D" < "$TMP/gbody-decided.html" > "$TMP/gwrap-d.log" 2>&1 \
  || fail "the decided gallery probe failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-d.log" | sed -n 1,4p)"
chrome_dump "$TMP/gdom-d.html" "file://$GPAGE_D?phase=gdecided" 45 || true
tg="$(grep -oE '<title>[^<]*</title>' "$TMP/gdom-d.html" | sed -n 1p)"
[[ "$tg" == *"GDECIDED"* && "$tg" == *"FOLDED=1"* ]] \
  || fail "the decided gallery probe did not run, or the decided row was not folded: $tg"
[[ "$tg" == *"DOWN=audit-with-data"* ]] \
  || fail "Down opened a decided row that the page has folded away: $tg"

# The filter is where the reader left it on the next visit (same profile, same
# path), and it is still not part of the paste.
tg="$(grun 'phase=grecall')"
[[ "$tg" == *"GRECALL|MODE=light"* && "$tg" == *"VIEW=mobile"* ]] \
  || fail "the filter did not survive the reload — it is stored per block under the kit's path-keyed scheme: $tg"
[[ "$tg" == *"PRESSED=light,mobile"* ]] \
  || fail "the restored filter is not reflected in the toolbar, so the reader cannot see what is hidden: $tg"
[[ "$tg" == *"PASTE=## E · The matrix  ### audit-with-data · audit · with-data  - Approved  la fila se ve bien"* ]] \
  || fail "a restored filter changed what the page pastes: $tg"

# Blocks with no id share no filter: before, both were stored under the empty
# key, so filtering the first block hid the tiles of the second on the next visit.
perl -0pe 's{<section class="consult-group" id="E" data-id="E" data-title="The matrix"}{<section class="consult-group" data-title="The matrix"}; s{  <!-- The not-applicable row}{  </section>\n  <section class="consult-group" data-title="Second matrix" data-tiles="light-desktop dark-desktop light-mobile dark-mobile">\n    <div class="sec-head"><h2>Second matrix</h2></div><p>The rows the second block reviews.</p>\n  <!-- The not-applicable row}' \
  "$TMP/gbody.html" > "$TMP/gbody-unnamed.html"
GPAGE_U="$TMP/reports/gallery-unnamed.html"
bash "$WRAP" --title "gallery" --lang es --out "$GPAGE_U" < "$TMP/gbody-unnamed.html" > "$TMP/gwrap-u.log" 2>&1 \
  || fail "the unnamed-blocks probe failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-u.log" | sed -n 1,4p)"
rm -rf "$TMP/profile"
chrome_dump "$TMP/gdom-u.html" "file://$GPAGE_U?phase=gunset" 45 || true
tg="$(grep -oE '<title>[^<]*</title>' "$TMP/gdom-u.html" | sed -n 1p)"
[[ "$tg" == *"GUNSET|N=2|M0=light|M1=both"* ]] \
  || fail "the unnamed-blocks probe did not filter the first block alone: $tg"
chrome_dump "$TMP/gdom-u.html" "file://$GPAGE_U?phase=gunget" 45 || true
tg="$(grep -oE '<title>[^<]*</title>' "$TMP/gdom-u.html" | sed -n 1p)"
[[ "$tg" == *"GUNGET"* && "$tg" == *"M1=both"* ]] \
  || fail "a filter set on one block with no id came back on another block with no id (one shared empty key): $tg"

# ---- the COMPARE control (plan 2026-09-22, Phase 3) ----
# The other mode of the same viewport, in 2-up, swipe or onion skin. The slider
# is the one form control the dialog carries, and the dialog lives outside every
# item: the paste taken with compare on and the slider moved must be the very
# bytes of the paste taken before the dialog was opened.
rm -rf "$TMP/profile"
tg="$(grun 'phase=gcompare')"
[[ "$tg" == *GCOMPARE* ]] || fail "the gallery compare phase did not run: $tg"
[[ "$tg" == *"CTRL=4"* && "$tg" == *"ENABLED=1"* ]] \
  || fail "the dialog carries no compare control (off, 2-up, swipe, onion) on a tiled row: $tg"
[[ "$tg" == *"ST0=off"* ]] \
  || fail "the dialog did not open with compare off: $tg"
[[ "$tg" == *"ST2=2up/with-data dark-desktop"* ]] \
  || fail "2-up did not show the other mode of the same viewport: $tg"
[[ "$tg" == *"STS=swipe"* && "$tg" == *"STO=onion"* ]] \
  || fail "swipe and onion skin did not set their state on the dialog: $tg"
[[ "$tg" == *"SW=25%:inset(0px 0px 0px 25%),50%:inset(0px 0px 0px 50%),75%:inset(0px 0px 0px 75%)"* ]] \
  || fail "the slider does not drive --kit-swipe and the top image's clip-path in swipe mode: $tg"
[[ "$tg" == *"ON=0.75,0.5,0.25"* ]] \
  || fail "the slider does not drive the top image's opacity in onion mode (the slider is the current tile's share in both modes): $tg"
[[ "$tg" == *"WALKED=dark-desktop/onion/with-data light-desktop/75"* ]] \
  || fail "the arrows did not walk with compare on, or dropped the mode, the sibling or the slider: $tg"
[[ "$tg" == *"OWNED=dark-desktop"* ]] \
  || fail "an arrow on the focused slider walked the tile instead of moving the slider: $tg"
[[ "$tg" == *"INITEM=0"* ]] \
  || fail "the compare slider sits inside a consult-item, where the composer would read it: $tg"
[[ "$tg" == *"SAME=1"* ]] \
  || fail "a paste taken with compare on and the slider moved differs from one taken without them: $tg"
[[ "$tg" == *"PASTE=## E · The matrix  ### audit-with-data · audit · with-data  - Approved  la fila se ve bien"* ]] \
  || fail "the row's verdict and notes did not reach the compare paste, so its identity proves nothing: $tg"
[[ "$tg" == *"FRESH=off/50"* ]] \
  || fail "a fresh open did not reset compare to off and the slider to the middle: $tg"
[[ "$tg" == *"MISM=2up/"*"1x1"*"2x1"* ]] \
  || fail "swipe over two captures of different sizes did not fall back to 2-up with a note naming both sizes: $tg"
[[ "$tg" == *"BACK=dark-desktop/swipe/hidden"* ]] \
  || fail "walking from a mismatched pair to a same-size pair did not restore swipe and hide the note: $tg"
[[ "$tg" == *"FILTERED=2up"* ]] \
  || fail "a sibling tile hidden by a filter stopped counting as the sibling: $tg"
[[ "$tg" == *"DIS=1"* && "$tg" == *"WHY=1"* && "$tg" == *"NOSIB=off"* ]] \
  || fail "a tile with no sibling left the compare control enabled, or without its reason in the title: $tg"
[[ "$tg" == *"FOCUS0=kit-zoom-size|"* ]] \
  || fail "a fresh open did not put the focus on the size button: $tg"
[[ "$tg" == *"LANDED=audit-empty/light-desktop/off"* ]] \
  || fail "the focus probe did not step onto the tile with no sibling: $tg"
[[ "$tg" == *"KEPT=in/audit-empty/light-mobile"* ]] \
  || fail "a step that disabled the focused compare button left the focus on it (Chrome then drops it to the body and the walk dies): $tg"
[[ "$tg" == *"STKEPT=1"* ]] \
  || fail "moving the compare slider overwrote the copy confirmation on the status line: $tg"

# ---- REGION MARKS (plan 2026-09-22, Phase 4, Task 4.1) ----
# A rectangle dragged on the dialog image, stored as percentages of the image in
# the row's hidden <textarea class="kit-marks">, one contract line per mark:
#   [mark <tile> x,y wxh] note
# That textarea is the ONLY channel: readItem pastes it, the answer store keeps
# it, the question-hash rule governs it. The probe page gives audit-with-data a
# 400x200 PNG on every tile so a drag in pixels is an exact percentage.
BIG='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAZAAAADICAAAAADjfug+AAABJ0lEQVR42u3RMQEAAAzCMPxrQxQmduxIJTSpXhULgAgIEAEBIiBABASIgAgIEAEBIiBABASIgAgIEAEBIiBABASIgAgIEAEBIiBABASIgAgIEAEBIiBABASIgAgIEAEBIiBABASIgAgIEAEBIiBABASIgAgIEAEBIiBABASIgAgIEAEBIiBABASIgAgIEAEBIiBABASIgAAREAEBIiBABASIgAAREAEBIiBABASIgAAREAEBIiBABASIgAAREAEBIiBABASIgAAREAEBIiBABASIgAAREAEBIiBABASIgAAREAEBIiBABASIgAAREAEBIiBABASIgAAREAEBIiBABASIgAAREAEBIiBABASIgAARECACIiBABASIgAARECACIiBABASIgAARECACIiBABASILhsrGRSYySDjUQAAAABJRU5ErkJggg=='
sed "/alt=\"with-data/s|$PX|$BIG|" "$TMP/gbody.html" > "$TMP/gbody-marks.html"
GPAGE_M="$TMP/reports/gallery-marks.html"
bash "$WRAP" --title "gallery" --lang es --out "$GPAGE_M" < "$TMP/gbody-marks.html" > "$TMP/gwrap-m.log" 2>&1 \
  || fail "the marks probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-m.log" | sed -n 1,4p)"
mrun() {  # mrun <page> <query>
  chrome_dump "$TMP/gdom-m.html" "file://$1?$2" 45 || true
  grep -oE '<title>[^<]*</title>' "$TMP/gdom-m.html" | sed -n 1p
}
rm -rf "$TMP/profile"
tg="$(mrun "$GPAGE_M" 'phase=gmarks')"
[[ "$tg" == *GMARKS* ]] || fail "the marks phase did not run: $tg"
[[ "$tg" == *"CHAN=hidden"* ]] \
  || fail "the composer did not give the tiled row one hidden kit-marks textarea: $tg"
[[ "$tg" == *"PLAIN=## E · The matrix  ### audit-with-data · audit · with-data  - Approved  la fila se ve bien|"* ]] \
  || fail "a row with no marks no longer pastes what Phase 3 pasted (identity): $tg"
[[ "$tg" == *"SUB=/nonote"* ]] \
  || fail "a drag under 4 px created a mark or opened the note dialog: $tg"
[[ "$tg" == *"NOTEOPEN=1"* && "$tg" == *"SAVED=1"* ]] \
  || fail "a real drag did not open the note dialog: $tg"
[[ "$tg" == *"ONE=[mark light-desktop 12.5,34.0 40.0x10.5] the breadcrumb wraps under the title|"* ]] \
  || fail "the drag was not stored as the contract line with its percentages and its note: $tg"
[[ "$tg" == *"THREE=3"* && "$tg" == *"EDIT=temporary"* && "$tg" == *"DEL=2"* ]] \
  || fail "clicking inside a mark did not open its note, or delete did not remove it: $tg"
[[ "$tg" == *"CANCEL=2"* ]] \
  || fail "cancelling the note of a new mark still stored the mark: $tg"
[[ "$tg" == *"DLG=2"* ]] \
  || fail "the dialog image does not carry one overlay per mark of the tile: $tg"
[[ "$tg" == *"FOCUSIN=in"* && "$tg" == *"WALKED=dark-desktop"* ]] \
  || fail "after the note dialog closed the focus left the zoom dialog, or the arrows stopped walking: $tg"
[[ "$tg" == *"LYCMP=none"* && "$tg" == *"CMPDRAW=none/nonote"* ]] \
  || fail "with compare on the mark layer is still shown or still draws: $tg"
[[ "$tg" == *"TILE=2"* ]] \
  || fail "the grid tile does not carry an overlay per mark: $tg"
b64="$(grep -oE 'data-paste="[^"]*"' "$TMP/gdom-m.html" | sed -n 1p | sed -E 's/^data-paste="(.*)"$/\1/')"
printf '%s' "$b64" | base64 -d > "$TMP/gmarks-paste.txt" 2>/dev/null
printf '%s\n' '## E · The matrix' '' '### audit-with-data · audit · with-data' '' '- Needs changes' '' \
  'la fila se ve bien' '' \
  '[mark light-desktop 12.5,34.0 40.0x10.5] the breadcrumb wraps under the title' \
  '[mark light-desktop 0.0,0.0 25.0x25.0] the logo is cut' > "$TMP/gmarks-want.txt"
# The paste has no trailing newline; the expectation file does.
printf '\n' >> "$TMP/gmarks-paste.txt"
cmp -s "$TMP/gmarks-paste.txt" "$TMP/gmarks-want.txt" \
  || fail "the paste with two marks is not the verdict, the notes and one contract line per mark under the row heading: $(diff "$TMP/gmarks-want.txt" "$TMP/gmarks-paste.txt" | sed -n 1,12p)"

# Same profile, a reload: the marks come back through the answer store.
tg="$(mrun "$GPAGE_M" 'phase=gmrecall')"
[[ "$tg" == *"GMRECALL|TILE=2"* && "$tg" == *"DLG=2"* ]] \
  || fail "the marks did not survive a reload (grid overlay and dialog overlay): $tg"
[[ "$tg" == *"PASTE=## E · The matrix  ### audit-with-data · audit · with-data  - Needs changes  la fila se ve bien  [mark light-desktop 12.5,34.0 40.0x10.5] the breadcrumb wraps under the title [mark light-desktop 0.0,0.0 25.0x25.0] the logo is cut"* ]] \
  || fail "the restored marks do not paste: $tg"

# The edges of drawing: degenerate drags, reversed drags, clamping on the far
# edges, the note on hover (a title needs pointer events), Esc on the note.
rm -rf "$TMP/profile"
tg="$(mrun "$GPAGE_M" 'phase=gmedge')"
[[ "$tg" == *GMEDGE* ]] || fail "the marks edge phase did not run: $tg"
[[ "$tg" == *"DEG1=/nonote"* && "$tg" == *"DEG2=/nonote"* ]] \
  || fail "a drag that clamps to no width, or has no height, created a mark nobody can open or delete (or opened the note dialog): $tg"
[[ "$tg" == *"REV=[mark light-desktop 12.5,34.0 40.0x10.5] reversed|"* ]] \
  || fail "a right-to-left, bottom-to-top drag is not the rectangle of the same forward drag: $tg"
[[ "$tg" == *"CLAMP=[mark light-desktop 75.0,75.0 25.0x25.0] edge|"* ]] \
  || fail "a drag past the right and bottom edges was not clamped to 100: $tg"
[[ "$tg" == *"PEDLG="* && "$tg" != *"PEDLG=none"* && "$tg" != *"PEDLG=nomark"* ]] \
  || fail "a mark in the dialog takes no pointer events, so its note (title) never shows on hover: $tg"
[[ "$tg" == *"PETILE="* && "$tg" != *"PETILE=none"* && "$tg" != *"PETILE=nomark"* ]] \
  || fail "a mark on the grid tile takes no pointer events, so its note (title) never shows on hover: $tg"
[[ "$tg" == *"HIT=edge"* ]] \
  || fail "a click inside a mark no longer reaches the layer and opens its note: $tg"
[[ "$tg" == *"ESC=noteclosed/zoomopen/in/same"* ]] \
  || fail "Esc on the note dialog closed the zoom dialog too, left the focus outside it, or wrote something: $tg"
[[ "$tg" == *"TILEZOOM=light-desktop"* ]] \
  || fail "a click on a mark of the grid tile no longer opens the tile in the zoom dialog: $tg"
[[ "$tg" == *"MULTI=[mark light-desktop 12.5,34.0 40.0x10.5] multi|"* ]] \
  || fail "a second finger reshaped or ended the first finger's mark (or a third finger's cancel dropped it): $tg"
[[ "$tg" == *"STRAY=0|"* ]] \
  || fail "a second finger down during a mark drag left a stray drawing box behind: $tg"
[[ "$tg" == *"MBOX=12.5%,40%|"* ]] \
  || fail "a second finger's move reshaped the first finger's drawing box: $tg"
[[ "$tg" == *"REPLACED=1/0"* ]] \
  || fail "a primary press during an open mark drag left the old drawing box behind: $tg"

# A round that RE-CAPTURES a tile is a new question for the row (marks are
# answers, and the question-hash covers the tiles' image src): the unsent
# marks of the old capture must not come back onto a different screenshot.
# Same profile as gmedge, which left three marks on light-desktop.
PX="$PX" perl -0pe 's{(<figure data-tile="light-desktop"><img src=")[^"]*(" alt="with-data light-desktop")}{$1$ENV{PX}$2}' \
  "$TMP/gbody-marks.html" > "$TMP/gbody-marks-recap.html"
bash "$WRAP" --title "gallery" --lang es --out "$GPAGE_M" < "$TMP/gbody-marks-recap.html" > "$TMP/gwrap-mr.log" 2>&1 \
  || fail "the re-captured marks probe failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-mr.log" | sed -n 1,4p)"
tg="$(mrun "$GPAGE_M" 'phase=gmrecall')"
[[ "$tg" == *"GMRECALL|TILE=0"* && "$tg" == *"DLG=0"* && "$tg" != *"[mark"* ]] \
  || fail "marks drawn on the old capture came back onto a re-captured tile: $tg"
bash "$WRAP" --title "gallery" --lang es --out "$GPAGE_M" < "$TMP/gbody-marks.html" > "$TMP/gwrap-m.log" 2>&1 \
  || fail "the marks probe page failed to re-wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-m.log" | sed -n 1,4p)"

# Entries a Phase-3 page stored: the gallery row's notes answer (no hash, the
# kit's upgrade path) lands in the visible notes box and not in the kit-marks
# channel appended after it; the general-notes item's stored hash, computed by
# the kit before gallery rows hashed their tiles, still matches — the rule
# changed for gallery rows only.
rm -rf "$TMP/profile"
mrun "$GPAGE_M" 'phase=gmoldset' > /dev/null
tg="$(mrun "$GPAGE_M" 'phase=gmold')"
[[ "$tg" == *"GMOLD|VIS=notes from phase 3|MARKS=[]"* ]] \
  || fail "a Phase-3 notes answer on a gallery row did not restore into the visible notes box (or leaked into the marks channel): $tg"
[[ "$tg" == *"NOTES=general from phase 3"* ]] \
  || fail "a non-gallery item's question hash moved with the gallery-row rule, so its stored answer read as stale: $tg"

# The [question] chip on a gallery row whose notes box is a contenteditable:
# the row's only textarea is the hidden kit-marks channel, which must not take
# the focus.
perl -0pe 's{(data-id="audit-with-data".*?)<textarea></textarea>}{$1<div contenteditable="true"></div>}s' \
  "$TMP/gbody-marks.html" > "$TMP/gbody-marks-ce.html"
GPAGE_MC="$TMP/reports/gallery-marks-ce.html"
bash "$WRAP" --title "gallery" --lang es --out "$GPAGE_MC" < "$TMP/gbody-marks-ce.html" > "$TMP/gwrap-mc.log" 2>&1 \
  || fail "the contenteditable marks probe failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-mc.log" | sed -n 1,4p)"
rm -rf "$TMP/profile"
tg="$(mrun "$GPAGE_MC" 'phase=gmask')"
[[ "$tg" == *"GMASK|FOCUSCE=1"* ]] \
  || fail "the question chip focused the hidden kit-marks textarea instead of the row's contenteditable notes box: $tg"

# A decided row: the page carries the marks it was decided with; they are shown
# and nothing new is drawn (the answer is sealed).
perl -0pe 's/data-id="audit-with-data" data-title/data-id="audit-with-data" data-decided="Needs changes" data-title/; s{(data-id="audit-with-data".*?<textarea></textarea>)}{$1\n    <textarea class="kit-marks" hidden>[mark light-desktop 10.0,10.0 20.0x20.0] recorded</textarea>}s' \
  "$TMP/gbody-marks.html" > "$TMP/gbody-marks-d.html"
GPAGE_MD="$TMP/reports/gallery-marks-decided.html"
bash "$WRAP" --title "gallery" --lang es --out "$GPAGE_MD" < "$TMP/gbody-marks-d.html" > "$TMP/gwrap-md.log" 2>&1 \
  || fail "the decided marks probe failed to wrap (a hidden kit-marks textarea beside the notes box must pass): $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-md.log" | sed -n 1,4p)"
rm -rf "$TMP/profile"
tg="$(mrun "$GPAGE_MD" 'phase=gmdecided')"
[[ "$tg" == *"GMDECIDED|SAME=1"* && "$tg" == *"NOTE=0"* ]] \
  || fail "a mark was drawn on a decided row: $tg"
[[ "$tg" == *"TILE=1"* && "$tg" == *"VAL=[mark light-desktop 10.0,10.0 20.0x20.0] recorded"* ]] \
  || fail "the marks a decided row carries in the page are not shown on its tile: $tg"
[[ "$tg" == *"MBD=disabled"* && "$tg" == *"DDRAFT=0"* ]] \
  || fail "the keyboard Mark button drafts a region on a decided row: $tg"

# ---- KEYBOARD MARKS and the SWIPE HANDLE (plan 2026-09-26 ui-contract, Phase 4) ----
rm -rf "$TMP/profile"
tg="$(mrun "$GPAGE_M" 'phase=gmkey')"
[[ "$tg" == *GMKEY* ]] || fail "the keyboard marks phase did not run: $tg"
[[ "$tg" == *"MB=enabled"* && "$tg" == *"DRAFT=1"* ]] \
  || fail "the dialog has no enabled Mark button, or it drafts no region — marks are pointer-only: $tg"
[[ "$tg" == *"STILL=light-desktop"* ]] \
  || fail "the arrows walked the tiles while a region was being drafted, instead of moving it: $tg"
[[ "$tg" == *"KOPEN=1"* && "$tg" == *"ONE=[mark light-desktop 45.0,40.0 20.0x23.0] kbd|"* ]] \
  || fail "arrows and Shift+arrows did not move and resize the draft, or Enter did not ask for its note and store the contract line: $tg"
[[ "$tg" == *"KFOCUS=in"* && "$tg" == *"KWALK=dark-desktop"* ]] \
  || fail "after a keyboard mark the focus left the dialog or the arrows stopped walking the tiles: $tg"
[[ "$tg" == *"EDGE=[mark light-desktop 40.0,40.0 60.0x20.0] edge"* ]] \
  || fail "a keyboard draft grew or moved past the image's right edge: $tg"
[[ "$tg" == *"MBCMP=off"* ]] \
  || fail "the Mark button is offered with compare on, where no mark can be drawn: $tg"
[[ "$tg" == *"H25=line"* && "$tg" == *"H75=line"* ]] \
  || fail "swipe mode shows no handle on the image where the two captures meet: $tg"
[[ "$tg" == *"HON=hidden"* && "$tg" == *"HOFF=hidden"* ]] \
  || fail "the swipe handle shows outside swipe mode: $tg"

# ---- the zoom header at 500 px wide -----------------------------------------
rm -rf "$TMP/profile"
tg="$(CHROME_WINDOW=500,900 mrun "$GPAGE_M" 'phase=gmnarrow')"
[[ "$tg" == *"GMNARROW|W=500"* ]] || fail "the narrow header phase did not run at 500 px: $tg"
[[ "$tg" == *"OFF=fits"* && "$tg" == *"SWIPE=fits"* ]] \
  || fail "the zoom header takes more than two lines at 500 px (or is wider than the dialog): $tg"

# ---- the BEFORE/AFTER review row (rows contract, 2026-09-27) ----
# A review block declares `before after`: the compare pairs the two halves of
# the row (the owner's main comparison is antes/propuesto, not light/dark), and
# the mode/viewport toolbar, meaningless on that block, is not injected at all.
cat > "$TMP/gbody-pair.html" <<HTML
<meta name="consult-visual" content="none: a gallery probe, nothing to draw">
<div class="page"><main class="main">
<header><p class="eyebrow">PROBE</p><h1>Pair probe</h1></header>
<section class="consult-group" id="R" data-id="R" data-title="Review" data-tiles="before after">
  <div class="sec-head"><h2>Review</h2></div>
  <section class="consult-item consult-gallery" data-id="audit-empty-light-desktop" data-title="audit &middot; empty &middot; light-desktop" data-variant="light-desktop">
    <h3><span class="consult-id">audit-empty-light-desktop</span>audit &middot; empty &middot; light-desktop</h3>
    <p>Before and proposed.</p>
    <div class="gal">
      <figure data-tile="before"><img src="$PX" alt="empty before"><figcaption>antes</figcaption></figure>
      <figure data-tile="after"><img src="$PX" alt="empty after"><figcaption>propuesto</figcaption></figure>
    </div>
    <div class="opts one"><label><input type="radio" name="audit-empty-light-desktop" data-label="Aprobada"><span>Aprobada</span></label><label><input type="radio" name="audit-empty-light-desktop" data-label="Necesita cambios"><span>Necesita cambios</span></label></div>
    <p class="fieldlabel">Notas</p><textarea></textarea>
  </section>
  <section class="consult-item consult-gallery" data-id="audit-new-light-desktop" data-title="audit &middot; new &middot; light-desktop" data-variant="light-desktop" data-tiles="after">
    <h3><span class="consult-id">audit-new-light-desktop</span>audit &middot; new &middot; light-desktop</h3>
    <p>New screen.</p>
    <div class="gal"><figure data-tile="after"><img src="$PX" alt="new after"><figcaption>pantalla nueva</figcaption></figure></div>
    <div class="opts one"><label><input type="radio" name="audit-new-light-desktop" data-label="Aprobada"><span>Aprobada</span></label><label><input type="radio" name="audit-new-light-desktop" data-label="Necesita cambios"><span>Necesita cambios</span></label></div>
    <p class="fieldlabel">Notas</p><textarea></textarea>
  </section>
</section>
<section class="consult-item consult-notes" data-id="notes" data-title="Notas"><h3>Notas</h3><textarea></textarea></section>
<div class="endbar"><button type="button" id="consult-copy-end">Copiar</button><span class="consult-status" id="consult-status-end"></span></div>
</main><aside class="rail"><nav class="raillist" id="raillist"></nav>
<div class="consult-bar"><button type="button" id="consult-copy">Copiar</button><span class="consult-status" id="consult-status"></span></div></aside></div>
<script>
window.addEventListener('load', function () {
  var dlg = document.querySelector('dialog.kit-zoom');
  var fig = function (row, t) { return document.querySelector('[data-id="' + row + '"] figure[data-tile="' + t + '"]'); };
  var cmp = function (v) { return dlg.querySelector('.kit-zoom-cmp[data-value="' + v + '"]'); };
  fig('audit-empty-light-desktop', 'before').click();
  cmp('2up').click();
  var pair = dlg.getAttribute('data-compare') + '/' + dlg.querySelector('img.kit-zoom-other').getAttribute('alt');
  dlg.close();
  fig('audit-new-light-desktop', 'after').click();
  var lone = cmp('2up').disabled ? 'disabled' : 'enabled';
  document.title = 'GPAIR|BARS=' + document.querySelectorAll('.kit-galbar').length
    + '|PAIR=' + pair + '|LONE=' + lone;
});
</script>
HTML
GPAGE_P="$TMP/reports/gallery-pair.html"
bash "$WRAP" --title "pair" --lang es --out "$GPAGE_P" < "$TMP/gbody-pair.html" > "$TMP/gwrap-p.log" 2>&1 \
  || fail "the pair probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-p.log" | sed -n 1,4p)"
rm -rf "$TMP/profile"
chrome_dump "$TMP/gdom-p.html" "file://$GPAGE_P" 45 || true
tg="$(grep -oE '<title>[^<]*</title>' "$TMP/gdom-p.html" | sed -n 1p)"
[[ "$tg" == *GPAIR* ]] || fail "the pair probe did not run: $tg"
[[ "$tg" == *"PAIR=2up/empty after"* ]] \
  || fail "compare on a before tile did not pair it with the row's after: $tg"
[[ "$tg" == *"LONE=disabled"* ]] \
  || fail "a new-screen row's lone capture offers a compare it has nothing for: $tg"
[[ "$tg" == *"BARS=0"* ]] \
  || fail "a before/after review block got the light/dark filter toolbar: $tg"

# ---- BL-493: an item's own screenshots are a thumbnail grid with an in-place viewer ----
# Built through the real route (spec -> .gal.shots -> wrap, which runs the
# contract). The viewer is the gallery's dialog in a reduced mode: it walks ONLY
# this item's images, offers no compare/marks/rows, and the item stays a normal
# question (not a gallery row). Layer: the browser, because the viewer is behaviour.
mkdir -p "$TMP/shots"
for n in 1 2 3 4 5 6; do python3 "$SKILL/tests/png_fixture.py" "$TMP/shots/s$n.png" 80 60; done
cat > "$TMP/shots/page.spec.md" <<'SPEC'
::: masthead {visual="none: a viewer probe, nothing to draw"}
# Shots probe

A page with one item that carries four captures.
:::

::: group {#G title="Grupo"}
::: item {#Q1 title="Capturas"}
¿Cuál captura es la correcta?

::: diagram {shape=row}
a: uno
b: dos
:::

::: figure {src="s1.png" alt="uno" title="Uno"}
:::

::: figure {src="s2.png" alt="dos"}
:::

::: figure {src="s3.png" alt="tres"}
:::

::: figure {src="s4.png" alt="cuatro"}
:::

- Primera — la primera
- Segunda — la segunda
:::

::: item {#Q2 title="Otras capturas"}
¿Y entre estas dos?

::: figure {src="s5.png" alt="cinco"}
:::

::: figure {src="s6.png" alt="seis"}
:::

- Quinta — la quinta
- Sexta — la sexta
:::
:::

::: notes {title="Notas generales"}
:::
SPEC
python3 "$SKILL/scripts/spec_build.py" "$TMP/shots/page.spec.md" > "$TMP/gbody-shots.html" 2> "$TMP/gshots-build.log" \
  || fail "the shots probe spec failed to build: $(head -3 "$TMP/gshots-build.log")"
# The item carries a kit-marks channel of its own (the page may write one; the
# checker accepts it); shots mode still draws no marks on it (BL-655).
perl -0pi -e 's{(<section class="consult-item" data-id="Q1".*?)(</section>)}{$1  <textarea class="kit-marks" hidden></textarea>\n$2}s' "$TMP/gbody-shots.html"
cat >> "$TMP/gbody-shots.html" <<'HTML'
<script>
window.addEventListener('load', function () {
  var dlg = document.querySelector('dialog.kit-zoom');
  var item = document.querySelector('[data-id="Q1"]');
  var grid = item.querySelector('.gal.shots');
  var figs = grid ? [].slice.call(grid.querySelectorAll('figure')) : [];
  var tile = function () { return dlg ? dlg.querySelector('.kit-zoom-tile').textContent : ''; };
  var key = function (k) { dlg.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true })); };
  /* 1 when the dialog let the key through (dispatchEvent is false only when
   * a listener called preventDefault). */
  var passes = function (k) { return dlg.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true })) ? 1 : 0; };
  var r = {};
  r.figs = figs.length;
  r.cols = grid ? getComputedStyle(grid).gridTemplateColumns.split(' ').length : 0;
  r.svgIn = grid ? grid.querySelectorAll('svg').length : -1;
  r.svgOut = item.querySelectorAll('figure svg').length;
  r.galRow = item.querySelector('details.opts-more .kit-other, details.kit-ask-more') ? 1 : 0;
  r.role = figs.length && figs[0].getAttribute('role');
  if (figs.length) {
    figs[0].click();
    r.open = dlg.open ? 1 : 0;
    r.t1 = tile();
    key('ArrowLeft'); r.first = tile();
    r.cmpHidden = getComputedStyle(dlg.querySelector('.kit-zoom-cmpgroup')).display;
    key('ArrowRight'); r.t2 = tile();
    key('ArrowDown'); r.down = tile();
    r.downPass = passes('ArrowDown'); r.upPass = passes('ArrowUp');
    key('ArrowRight'); key('ArrowRight'); key('ArrowRight'); r.end = tile();
    key('ArrowLeft'); r.left = tile();
    var body = dlg.querySelector('.kit-zoom-body');
    /* isPrimary as the browser sets it: true only for the first finger down
     * while no other synthetic touch is held (the constructor defaults false). */
    var held = {};
    var touch = function (type, x, y, id) {
      id = id || 0;
      if (type === 'pointerdown') held[id] = !Object.keys(held).length;
      var primary = !!held[id];
      if (type === 'pointerup' || type === 'pointercancel') delete held[id];
      body.dispatchEvent(new PointerEvent(type, { pointerType: 'touch', pointerId: id, isPrimary: primary, clientX: x, clientY: y || 0, bubbles: true }));
    };
    touch('pointerdown', 100); touch('pointerup', 200); r.swR = tile();   // drag right: previous
    touch('pointerdown', 200); touch('pointerup', 100); r.swL = tile();   // drag left: next
    touch('pointerdown', 100); touch('pointerup', 120); r.swS = tile();   // under 40 px: stays
    touch('pointerdown', 100, 100); touch('pointerup', 150, 300); r.swV = tile();   // mostly vertical: stays
    /* Each recorded as before~after, and in opposite directions, so a step in
     * one cannot be undone by the other into a matching value (BL-554). */
    var b = tile();
    touch('pointerdown', 200, 0, 5); touch('pointermove', 100, 0, 5);
    touch('pointercancel', 100, 0, 5); touch('pointerup', 100, 0, 5);
    r.swC = b + '~' + tile();   // cancelled mid-drag, then an up 100 px left: stays
    b = tile();
    touch('pointerdown', 300, 0, 6); touch('pointerdown', 100, 0, 7);
    touch('pointermove', 200, 0, 7); touch('pointerup', 200, 0, 7);
    touch('pointerup', 380, 0, 6);
    r.swP = b + '~' + tile();   // a pinch: neither finger's lift walks, whichever moved 40+ px across
    b = tile();
    touch('pointerdown', 300, 0, 8); touch('pointerdown', 100, 0, 9); touch('pointerup', 100, 0, 9);
    touch('pointerdown', 300, 0, 10); touch('pointerup', 200, 0, 10);
    touch('pointerup', 300, 0, 8);
    r.swT = b + '~' + tile();   // a finger put down while another is still held never starts a swipe
    b = tile();
    touch('pointerdown', 100, 0, 11);
    body.dispatchEvent(new PointerEvent('pointerup', { pointerType: 'mouse', pointerId: 1, isPrimary: true, clientX: 200, clientY: 0, bubbles: true }));
    touch('pointerup', 100, 0, 11);
    r.swX = b + '~' + tile();   // a mouse released 100 px across while a touch is down is not that touch's lift
    touch('pointerdown', 200, 100); touch('pointerup', 100, 160); r.swD = tile();   // diagonal, mostly across: next
    touch('pointerdown', 100, 100); touch('pointerup', 150, 150); r.swE = tile();   // as far down as across: stays
    var mlayer = dlg.querySelector('.kit-marks-layer');
    var mr = mlayer.getBoundingClientRect();
    var mnote = document.querySelector('dialog.kit-mark-note');
    /* Shots mode draws no marks (BL-493), even on an item that carries a
     * kit-marks channel: a mouse drag on the image opens no note and, saved
     * if one did open, writes no line (its tile would be null, so it could
     * never be redrawn, opened or deleted: BL-655). */
    var mmouse = function (type, x, y) {
      mlayer.dispatchEvent(new PointerEvent(type, { pointerType: 'mouse', pointerId: 1, isPrimary: true, button: 0,
        clientX: mr.left + x, clientY: mr.top + y, bubbles: true, cancelable: true }));
    };
    mmouse('pointerdown', 5, 5); mmouse('pointermove', 65, 45); mmouse('pointerup', 65, 45);
    var mopened = mnote && mnote.open;
    if (mopened) mnote.querySelector('button[data-act="save"]').click();
    r.mkS = (mopened ? 'note' : 'nonote') + '~'
      + (item.querySelector('textarea.kit-marks').value.indexOf('[mark') !== -1 ? 'mark' : 'nomark') + '~'
      + (mlayer.classList.contains('readonly') ? 'ro' : 'rw');
    /* So the layer is read-only there, and a touch 60 px across on it is a
     * swipe like on any read-only layer: it walks back one image (BL-655). */
    var mtouch = function (type, x, y) {
      mlayer.dispatchEvent(new PointerEvent(type, { pointerType: 'touch', pointerId: 12, isPrimary: true, button: 0,
        clientX: mr.left + x, clientY: mr.top + y, bubbles: true, cancelable: true }));
    };
    b = tile();
    mtouch('pointerdown', 5, 5); mtouch('pointermove', 65, 15); mtouch('pointerup', 65, 15);
    r.swK = b + '~' + tile() + '~' + (mnote && mnote.open ? 'note' : 'nonote');
    if (mnote && mnote.open) mnote.querySelector('button[data-act="cancel"]').click();
    key('ArrowRight');   // back to 4 / 4 for the cells below
    r.taFit = getComputedStyle(mlayer).touchAction;
    dlg.querySelector('.kit-zoom-size').click(); r.native = dlg.classList.contains('native') ? 1 : 0;
    r.taNat = getComputedStyle(mlayer).touchAction;
    touch('pointerdown', 100); touch('pointerup', 200); r.swN = tile();   // 1:1 is panned, not walked
    dlg.close();
    dlg.dispatchEvent(new Event('close'));   // the engine queues the real one; see GZOOM
    r.focus = item.contains(document.activeElement) ? 1 : 0;
    /* Q2 has no kit-marks channel, so its marks layer is read-only, and a
     * real finger's swipe starts on that layer (it covers the image), not on
     * the body: it still walks (BL-649). */
    var figs2 = [].slice.call(document.querySelectorAll('[data-id="Q2"] .gal.shots figure'));
    if (figs2.length) {
      figs2[0].click();
      var ly2 = dlg.querySelector('.kit-marks-layer'), lr2 = ly2.getBoundingClientRect();
      var ltouch = function (type, x) {
        ly2.dispatchEvent(new PointerEvent(type, { pointerType: 'touch', pointerId: 13, isPrimary: true, button: 0,
          clientX: lr2.left + x, clientY: lr2.top + 10, bubbles: true, cancelable: true }));
      };
      b = tile();
      ltouch('pointerdown', 75); ltouch('pointerup', 5);
      r.swLy = b + '~' + tile() + '~' + (ly2.classList.contains('readonly') ? 'ro' : 'rw');
      dlg.close();
      dlg.dispatchEvent(new Event('close'));
    }
    document.title = 'GSHOTS|' + JSON.stringify(r).replace(/[|<>]/g, ' ');
  } else document.title = 'GSHOTS|' + JSON.stringify(r);
});
</script>
HTML
GPAGE_H="$TMP/reports/gallery-shots.html"
bash "$WRAP" --title "shots" --lang es --out "$GPAGE_H" < "$TMP/gbody-shots.html" > "$TMP/gwrap-h.log" 2>&1 \
  || fail "the shots probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-h.log" | sed -n 1,4p)"
rm -rf "$TMP/profile"
chrome_dump "$TMP/gdom-h.html" "file://$GPAGE_H" 45 || true
tg="$(grep -oE '<title>[^<]*</title>' "$TMP/gdom-h.html" | sed -n 1p)"
[[ "$tg" == *GSHOTS* ]] || fail "the shots probe did not run: $tg"
[[ "$tg" == *'"figs":4'* && "$tg" == *'"cols":4'* ]] \
  || fail "an item with 4 raster figures is not a 4-column .gal grid: $tg"
[[ "$tg" == *'"svgIn":0'* && "$tg" == *'"svgOut":1'* ]] \
  || fail "the inline svg diagram was grouped into the thumbnail grid (it stays full width): $tg"
[[ "$tg" == *'"galRow":0'* ]] \
  || fail "the item with the image grid was treated as a gallery row: $tg"
[[ "$tg" == *'"open":1'* && "$tg" == *'"t1":"1 / 4"'* ]] \
  || fail "clicking a thumbnail did not open the viewer on image 1 of 4: $tg"
[[ "$tg" == *'"first":"1 / 4"'* ]] \
  || fail "Left on the item's first image did not stay on it: $tg"
[[ "$tg" == *'"t2":"2 / 4"'* && "$tg" == *'"down":"2 / 4"'* ]] \
  || fail "Right did not walk to the next image, or Down walked rows in this mode: $tg"
[[ "$tg" == *'"end":"4 / 4"'* && "$tg" == *'"left":"3 / 4"'* ]] \
  || fail "the walk wrapped past the item's last image, or Left did not step back: $tg"
[[ "$tg" == *'"cmpHidden":"none"'* ]] \
  || fail "the viewer offers compare/mark tools in the item-images mode: $tg"
[[ "$tg" == *'"swR":"2 / 4"'* && "$tg" == *'"swL":"3 / 4"'* && "$tg" == *'"swS":"3 / 4"'* ]] \
  || fail "a swipe did not walk the images (or a 20 px drag did): $tg"
[[ "$tg" == *'"upPass":1'* && "$tg" == *'"downPass":1'* ]] \
  || fail "Up/Down were swallowed in the item-images mode, so a tall capture cannot scroll by keyboard: $tg"
[[ "$tg" == *'"swV":"3 / 4"'* && "$tg" == *'"swE":"4 / 4"'* && "$tg" == *'"swN":"4 / 4"'* ]] \
  || fail "a mostly vertical drag, or a drag at 1:1 size, walked the images instead of panning: $tg"
[[ "$tg" == *'"swD":"4 / 4"'* ]] \
  || fail "a diagonal drag that is mostly across did not walk to the next image: $tg"
[[ "$tg" == *'"swC":"3 / 4~3 / 4"'* ]] \
  || fail "a touch drag the browser cancelled (pointercancel) still walked the images on a later pointerup: $tg"
[[ "$tg" == *'"swP":"3 / 4~3 / 4"'* ]] \
  || fail "a two-finger pinch at fit size walked the images when a finger lifted: $tg"
[[ "$tg" == *'"swT":"3 / 4~3 / 4"'* ]] \
  || fail "a finger put down while another was still held started a swipe of its own and walked the images: $tg"
[[ "$tg" == *'"swX":"3 / 4~3 / 4"'* ]] \
  || fail "a mouse pointerup was measured from a touch's pointerdown and walked the images: $tg"
[[ "$tg" == *'"mkS":"nonote~nomark~ro"'* ]] \
  || fail "a mouse drag on a shots viewer image (item with a kit-marks channel) opened a note or saved a mark, or the layer is not read-only (BL-655): $tg"
[[ "$tg" == *'"swK":"4 / 4~3 / 4~nonote"'* ]] \
  || fail "a touch swipe 60 px across on a shots viewer image (item with a kit-marks channel) drew a mark instead of walking back one image (BL-655): $tg"
[[ "$tg" == *'"swLy":"1 / 2~2 / 2~ro"'* ]] \
  || fail "a touch swipe that starts on the read-only marks layer (where a finger lands on the image) no longer walks the images: $tg"
[[ "$tg" == *'"taFit":"none"'* && "$tg" == *'"taNat":"'* && "$tg" != *'"taNat":"none"'* ]] \
  || fail "the 1:1 capture cannot be panned by touch (or the fit-size swipe lost touch-action none): $tg"
[[ "$tg" == *'"native":1'* && "$tg" == *'"focus":1'* ]] \
  || fail "the viewer lost the fit/1:1 toggle or Esc did not return the focus to the item: $tg"

# ---- a SAMPLE row asks nothing, so it is not counted (BL-466) ----
# A gallery row with no verdict group by design illustrates; counting it made
# a page whose one real question was answered read "1 de 2 · en blanco: …".
cat > "$TMP/gbody-sample.html" <<HTML
<meta name="consult-visual" content="none: a gallery probe, nothing to draw">
<div class="page"><main class="main">
<header><p class="eyebrow">PROBE</p><h1>Sample probe</h1></header>
<section class="consult-group" id="R" data-id="R" data-title="Review" data-tiles="before after">
  <div class="sec-head"><h2>Review</h2></div>
  <section class="consult-item consult-gallery" data-id="audit-empty-light-desktop" data-title="audit &middot; empty &middot; light-desktop" data-variant="light-desktop">
    <h3><span class="consult-id">audit-empty-light-desktop</span>audit &middot; empty &middot; light-desktop</h3>
    <p>Before and proposed.</p>
    <div class="gal">
      <figure data-tile="before"><img src="$PX" alt="empty before"><figcaption>antes</figcaption></figure>
      <figure data-tile="after"><img src="$PX" alt="empty after"><figcaption>propuesto</figcaption></figure>
    </div>
    <div class="opts one"><label><input type="radio" name="audit-empty-light-desktop" data-label="Aprobada"><span>Aprobada</span></label><label><input type="radio" name="audit-empty-light-desktop" data-label="Necesita cambios"><span>Necesita cambios</span></label></div>
    <p class="fieldlabel">Notas</p><textarea></textarea>
  </section>
  <section class="consult-item consult-gallery" data-id="audit-loaded-light-desktop-sample" data-title="audit &middot; loaded &middot; light-desktop" data-variant="light-desktop">
    <h3><span class="consult-id">audit-loaded-light-desktop-sample</span>audit &middot; loaded &middot; light-desktop</h3>
    <p>A sample.</p>
    <div class="gal">
      <figure data-tile="before"><img src="$PX" alt="loaded before"><figcaption>antes</figcaption></figure>
      <figure data-tile="after"><img src="$PX" alt="loaded after"><figcaption>propuesto</figcaption></figure>
    </div>
    <p class="fieldlabel">Notas</p><textarea></textarea>
  </section>
</section>
<section class="consult-item consult-notes" data-id="notes" data-title="Notas"><h3>Notas</h3><textarea></textarea></section>
<div class="endbar"><button type="button" id="consult-copy-end">Copiar</button><span class="consult-status" id="consult-status-end"></span></div>
</main><aside class="rail"><nav class="raillist" id="raillist"></nav>
<div class="consult-bar"><button type="button" id="consult-copy">Copiar</button><span class="consult-status" id="consult-status"></span></div></aside></div>
<script>
window.addEventListener('load', function () {
  var r = document.querySelector('[data-id="audit-empty-light-desktop"] input[data-label="Aprobada"]');
  r.checked = true; r.dispatchEvent(new Event('change', { bubbles: true }));
  document.title = 'GSAMPLE|STATUS=' + document.getElementById('consult-status').textContent.replace(/[|<>]/g, ' ');
});
</script>
HTML
GPAGE_S="$TMP/reports/gallery-sample.html"
bash "$WRAP" --title "sample" --lang es --out "$GPAGE_S" < "$TMP/gbody-sample.html" > "$TMP/gwrap-s.log" 2>&1 \
  || fail "the sample probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-s.log" | sed -n 1,4p)"
rm -rf "$TMP/profile"
chrome_dump "$TMP/gdom-s.html" "file://$GPAGE_S" 45 || true
tg="$(grep -oE '<title>[^<]*</title>' "$TMP/gdom-s.html" | sed -n 1p)"
[[ "$tg" == *"GSAMPLE|STATUS=1 de 1 respondidas"* ]] \
  || fail "a sample row (no verdict by design) was counted as a question: $tg"

# ---- BL-454: a select=many item, built from a SPEC, pastes every checked option
# Only radios could be built, so "which of these go to the queue" let the reader
# tick one. The page is built by spec_build.py, the route an author takes, so
# this proves the chain spec -> checkboxes -> composed reply end to end.
cat > "$TMP/many.spec.md" <<'SPEC'
::: masthead {eyebrow="PROBE" visual="none: a multi-select probe, nothing to draw"}
# Multi-select probe

Which films go to the queue.
:::

::: group {#G1 title="Cola"}
Una sola pregunta cuya respuesta es un conjunto.

::: item {#Q1 title="Cola de publicación" select=many}
¿Qué películas entran en la cola?

- Uno {recommended}
- Dos
- Tres
:::
:::

::: notes {title="Notas"}
:::
SPEC
python3 "$SKILL/scripts/spec_build.py" "$TMP/many.spec.md" > "$TMP/mbody.html" 2> "$TMP/mbuild.log" \
  || fail "BL-454: the select=many spec did not build: $(head -3 "$TMP/mbuild.log")"
cat >> "$TMP/mbody.html" <<'HTML'
<script>
window.addEventListener('load', function () {
  function pick(label, on) {
    var i = document.querySelector('[data-id="Q1"] .opts input[data-label="' + label + '"]');
    if (!i) return;
    i.checked = on; i.dispatchEvent(new Event('change', { bubbles: true }));
  }
  function state() {
    return [].map.call(document.querySelectorAll('[data-id="Q1"] .opts input:checked'),
      function (i) { return i.getAttribute('data-label'); }).join('+') || '-';
  }
  function copy() {
    var cap = '';
    Object.defineProperty(navigator, 'clipboard', { configurable: true,
      value: { writeText: function (x) { cap = x; return Promise.resolve(); } } });
    document.getElementById('consult-copy').click();
    return cap;
  }
  var types = [].map.call(document.querySelectorAll('[data-id="Q1"] .opts input'),
    function (i) { return i.type; });
  pick('Tres', true); pick('Uno', true);
  var paste = copy();
  var order = paste.indexOf('- Uno') !== -1 && paste.indexOf('- Uno') < paste.indexOf('- Tres');
  pick('Otra — lo explico en las notas', true);
  var withOther = state();
  pick('[not-now]', true);
  var afterNotNow = state();
  var pasteNotNow = copy();
  pick('Dos', true);
  var afterDos = state();
  pick('Dos', false);
  document.title = 'MANY|TYPES=' + types.join(',')
    + '|ORDER=' + (order ? '1' : '0')
    + '|OTHER=' + withOther + '|NOTNOW=' + afterNotNow + '|DOS=' + afterDos
    + '|PASTENN=' + pasteNotNow.replace(/[|<>\n]/g, ' ') + '|ENDNN'
    + '|STATUS=' + document.getElementById('consult-status').textContent.replace(/[|<>]/g, ' ')
    + '|PASTE=' + paste.replace(/[|<>\n]/g, ' ');
});
</script>
HTML
MPAGE="$TMP/reports/many.html"
bash "$WRAP" --title "many" --lang es --out "$MPAGE" < "$TMP/mbody.html" > "$TMP/mwrap.log" 2>&1 \
  || fail "BL-454: the select=many probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/mwrap.log" | sed -n 1,4p)"
rm -rf "$TMP/profile"
chrome_dump "$TMP/mdom.html" "file://$MPAGE" 45 || true
tm="$(grep -oE '<title>[^<]*</title>' "$TMP/mdom.html" | sed -n 1p)"
[[ "$tm" == *"MANY|"* ]] || fail "BL-454: the multi-select phase did not run: $tm"
[[ "$tm" == *"TYPES=checkbox,checkbox,checkbox,checkbox,checkbox"* ]] \
  || fail "BL-454: a select=many item's options (and the injected Otra / Todavía no) are not all checkboxes: $tm"
[[ "$tm" == *"- Uno"*"- Tres"* && "$tm" == *"ORDER=1"* ]] \
  || fail "BL-454: the copied reply does not list BOTH checked options, in page order: $tm"
[[ "$tm" == *"PASTE="*"- Dos"* ]] && fail "BL-454: an unchecked option reached the paste: $tm"
[[ "$tm" == *"OTHER=Uno+Tres+Otra — lo explico en las notas|"* ]] \
  || fail "BL-454: 'Otra' does not combine with the checked options of a many item: $tm"
[[ "$tm" == *"NOTNOW=[not-now]|"* ]] \
  || fail "BL-454: 'Todavía no' did not release the answers of a many item (deferring is exclusive with answering): $tm"
# BL-492a: copy() above ran once, before [not-now] was ticked; the paste taken
# AFTER it must carry Q1 as '- [not-now]' alone, none of the earlier ticks.
pnn="${tm#*PASTENN=}"; pnn="${pnn%%|ENDNN*}"
[[ "$pnn" == *"- [not-now]"* && "$pnn" != *"- Uno"* && "$pnn" != *"- Tres"* && "$pnn" != *"Otra"* ]] \
  || fail "BL-492: after [not-now] the paste does not carry Q1 as '- [not-now]' alone: $pnn"
[[ "$tm" == *"DOS=Dos|"* ]] \
  || fail "BL-454: checking an option did not release 'Todavía no' in a many item: $tm"
[[ "$tm" == *"STATUS=Sin responder"* ]] \
  || fail "BL-454: a many item with every box unticked is not blank again: $tm"

# ---- LOOP-006 group-item-id-collision: the composer never makes an id twice ----
# It gives every item its data-id as an id at run time, and its own chrome three
# fixed ids (sec-decided, consult-restored, kit-theme). Ways that id can already
# be taken: a block's own id (W1), any authored anchor (W4 and the three kit
# ids), and a block nested in a container section that has only a data-id,
# which the rail gives it as an id before its items (W3; invisible to every
# source check). The page is assembled with the kit inlined rather than
# wrapped: the source checks refuse these shapes, and this cell is about the
# composer's answer to them. Two pages, with and without a rail, because the
# two item-id paths are separate code. With a rail, the settled block W5 is
# moved into the Decided section and gets no id: the fold is its way in (BL-373). Each page loads twice on one profile:
# ?fill types into W2 so the second load restores it and draws the banner.
kit="$SKILL/assets/artifact-kit"
ids_page() {  # ids_page <out> <rail-markup>
  { printf '<!doctype html><html lang="en"><head><meta charset="utf-8"><title>ids</title><style>\n'
    cat "$kit/tokens.css" "$kit/components.css"
    printf '</style></head><body>\n'
    cat <<HTML
<div class="page"><main class="main">
<header><h1>Ids</h1><p id="W4">An authored anchor.</p><p id="sec-decided">x</p><p id="consult-restored">x</p><p id="kit-theme">x</p></header>
<section class="consult-group" id="W1" data-id="W1" data-title="Block one"><div class="sec-head"><h2>Block one</h2></div>
  <section class="consult-item" data-id="W1" data-title="Same as its block"><h3>One</h3><textarea></textarea></section>
  <section class="consult-item" data-id="W4" data-title="Same as an anchor"><h3>Four</h3><textarea></textarea></section>
</section>
<section class="consult-group" id="G2" data-id="G2" data-title="Block two"><div class="sec-head"><h2>Block two</h2></div>
  <section class="consult-item" data-id="W2" data-title="Typed and restored"><h3>Two</h3><textarea></textarea></section>
</section>
<section class="consult-group" id="G5" data-id="G5" data-title="Settled block"><div class="sec-head"><h2>Settled block</h2></div>
  <section class="consult-item" data-id="W5" data-title="Decided" data-decided><h3>Five</h3>
    <div class="opts one"><label><input type="radio" name="W5" data-label="A" checked><span>A</span></label><label><input type="radio" name="W5" data-label="B"><span>B</span></label></div></section>
</section>
<section id="sec-b"><div class="sec-head"><h2>Container</h2></div>
  <section class="consult-group" data-id="W3" data-title="Nested block"><h3>Nested block</h3>
    <section class="consult-item" data-id="W3" data-title="Same as its nested block"><h3>Three</h3><textarea></textarea></section>
  </section>
</section>
<section class="consult-item consult-notes" data-id="notes" data-title="Notes"><h3>Notes</h3><textarea></textarea></section>
</main>$2</div>
<script>
window.addEventListener('load', function () {
  if (location.search.indexOf('fill') !== -1) {
    var ta = document.querySelector('[data-id="W2"] textarea');
    ta.value = 'kept'; ta.dispatchEvent(new Event('input', { bubbles: true }));
    document.title = 'FILLED'; return;
  }
  var seen = {}, dup = [];
  [].forEach.call(document.querySelectorAll('[id]'), function (e) {
    if (seen[e.id] && dup.indexOf(e.id) === -1) dup.push(e.id); seen[e.id] = 1;
  });
  var land = [].map.call(document.querySelectorAll('.consult-item:not([data-decided])'), function (el) {
    var a = [].filter.call(document.querySelectorAll('#raillist .railitem'), function (x) {
      var r = x.querySelector('.rid'); return r && r.textContent === el.dataset.id;
    })[0];
    var t = a && document.getElementById(a.getAttribute('href').slice(1));
    return el.dataset.id + ':' + (a ? (t === el ? 'ok' : 'miss') : 'nolink');
  });
  var ids = [].map.call(document.querySelectorAll('.consult-item'), function (e) { return e.dataset.id + '=' + e.id; });
  /* The authored holders keep their ids, and the kit's own chrome exists, so
   * an empty DUP is not an absent banner or theme button passing for a fix. */
  var kept = ['W1', 'W4', 'sec-decided', 'consult-restored', 'kit-theme'].map(function (i) {
    var e = document.getElementById(i); return i + ':' + (e ? e.tagName + (e.classList.contains('consult-group') ? '.grp' : '') : 'none');
  });
  var chrome = [document.querySelector('section.decided'), document.querySelector('.note[role="status"]'),
                document.querySelector('button.kit-theme')].map(function (e) { return e ? '1' : '0'; });
  document.title = 'IDS|DUP=' + dup.join(',') + '|LAND=' + land.join(',') + '|IDS=' + ids.join(',')
    + '|KEPT=' + kept.join(',') + '|CHROME=' + chrome.join('');
});
</script>
HTML
    printf '<script>\n'; cat "$kit/composer.js"; printf '</script>\n</body></html>\n'
  } > "$1"
}
ids_run() {  # ids_run <page> — fill on a fresh profile, then the measured load
  rm -rf "$TMP/profile"
  chrome_dump "$TMP/idom.html" "file://$1?fill" 45 || true
  chrome_dump "$TMP/idom.html" "file://$1" 45 || true
  grep -oE '<title>[^<]*</title>' "$TMP/idom.html" | sed -n 1p
}
ids_page "$TMP/reports/ids.html" '<aside class="rail"><p class="railhead">Contents</p><nav class="raillist" id="raillist"></nav></aside>'
ids_page "$TMP/reports/ids-norail.html" ''
kept='|KEPT=W1:SECTION.grp,W4:P,sec-decided:P,consult-restored:P,kit-theme:P|CHROME=111<'
ti="$(ids_run "$TMP/reports/ids.html")"
[[ "$ti" == *"IDS|DUP=|"* ]] \
  || fail "group-item-id-collision: the composer gave two elements one id (a block's id, an authored anchor, a nested block's data-id or a kit id taken again): $ti"
[[ "$ti" == *"|LAND=W1:ok,W4:ok,W2:ok,W3:ok,notes:ok|"* ]] \
  || fail "group-item-id-collision: an item's rail link does not land on the item: $ti"
[[ "$ti" == *"|IDS=W5=,W1=W1-2,W4=W4-2,W2=W2,W3=W3-2,notes=notes|"* ]] \
  || fail "group-item-id-collision: an item did not get its data-id, or the first free suffix when that was taken: $ti"
[[ "$ti" == *"$kept"* ]] \
  || fail "group-item-id-collision: an authored holder lost its id, or the kit chrome was not drawn: $ti"
ti="$(ids_run "$TMP/reports/ids-norail.html")"
[[ "$ti" == *"IDS|DUP=|"* ]] \
  || fail "group-item-id-collision: with no rail, the composer gave two elements one id: $ti"
[[ "$ti" == *"|IDS=W5=W5,W1=W1-2,W4=W4-2,W2=W2,W3=W3,notes=notes|"* ]] \
  || fail "group-item-id-collision: with no rail, an item did not get its data-id or the first free suffix: $ti"
[[ "$ti" == *"$kept"* ]] \
  || fail "group-item-id-collision: with no rail, an authored holder lost its id, or the kit chrome was not drawn: $ti"
rm -rf "$TMP/profile"

# ---- LOOP-006 text-style-drift: item prose is one size wherever it sits -----
# A paragraph directly in an item, one inside a wrapper div and a list item
# read at one size; a div.note's paragraph keeps the note's size and the field
# label its own. Before kit 27 only a DIRECT child p took the item size (15.2
# px) and a wrapped one fell back to the body's 17 px. Kit CSS only: the
# cascade decides this, the composer has no part in it.
{ printf '<!doctype html><html lang="en"><head><meta charset="utf-8"><title>prose</title><style>\n'
  cat "$kit/tokens.css" "$kit/components.css"
  cat <<'HTML'
</style></head><body><div class="page"><main class="main">
<section class="consult-item" data-id="P1" data-title="Prose">
  <p id="p-direct">Direct.</p>
  <div class="ctx"><p id="p-wrapped">Wrapped.</p></div>
  <ul><li id="p-li">Listed.</li></ul>
  <div class="note"><p id="p-note">In a note.</p></div>
  <p class="fieldlabel" id="p-label">Label</p>
</section></main></div>
<script>
window.addEventListener('load', function () {
  document.title = 'PROSE|' + ['p-direct', 'p-wrapped', 'p-li', 'p-note', 'p-label'].map(function (i) {
    return i + '=' + getComputedStyle(document.getElementById(i)).fontSize;
  }).join(',');
});
</script></body></html>
HTML
} > "$TMP/reports/prose.html"
chrome_dump "$TMP/pdom.html" "file://$TMP/reports/prose.html" 45 || true
tp="$(grep -oE '<title>[^<]*</title>' "$TMP/pdom.html" | sed -n 1p)"
[[ "$tp" == *"PROSE|p-direct=15.2px,p-wrapped=15.2px,p-li=15.2px,p-note=13.12px,p-label=11.52px<"* ]] \
  || fail "text-style-drift: item prose is not one size wherever it sits (or a note/label lost its own size): $tp"
rm -rf "$TMP/profile"

# ---- no kit class reaches an author's SVG <text> ----------------------------
# An author's figure names its labels with words the kit also uses (`note`,
# `mono`, `eyebrow`...). A kit class rule beats the label's own presentation
# attributes (font-size="12", fill="currentColor"), so before kit 29 such a
# label was hidden (consult-clear, kit-swipe-layer), recoloured, resized or
# re-set in another face. Each class a kit selector names gets one <text>,
# compared by computed style with a classless twin, in both themes, in a
# figure and in a figure inside an item. The list is read from the kit's own
# rules, so a new class is covered the day it is written; the classes the kit
# styles ON PURPOSE inside an svg (`figure svg .acc`) are its figure
# vocabulary and are left out. `display` is compared as drawn / not drawn:
# flex or grid on an svg text changes nothing.
{ printf '<!doctype html><html lang="en"><head><meta charset="utf-8"><title>svgclass</title><style>\n'
  cat "$kit/tokens.css" "$kit/components.css"
  cat <<'HTML'
</style></head><body><div class="page"><main class="main">
<figure><svg id="svg-top" viewBox="0 0 400 40" width="400"></svg></figure>
<section class="consult-item" data-id="S1" data-title="Svg"><figure><svg id="svg-item" viewBox="0 0 400 40" width="400"></svg></figure></section>
</main></div>
<script>
window.addEventListener('load', function () {
  var cls = /\.-?[_a-zA-Z][-_a-zA-Z0-9]*/g, all = {}, svgVocab = {};
  (function walk(rules) {
    Array.prototype.forEach.call(rules, function (r) {
      if (r.cssRules && !r.selectorText) return walk(r.cssRules);
      if (!r.selectorText) return;
      r.selectorText.split(',').forEach(function (part) {
        var inSvg = /\bsvg\b/.test(part.replace(/:not\(svg \*\)/g, ''));
        (part.match(cls) || []).forEach(function (c) { all[c.slice(1)] = 1; if (inSvg) svgVocab[c.slice(1)] = 1; });
      });
    });
  })(document.styleSheets[0].cssRules);
  var names = Object.keys(all).filter(function (n) { return !svgVocab[n]; }).sort();
  var props = ['display', 'visibility', 'opacity', 'font-family', 'font-size', 'font-weight',
               'font-style', 'text-transform', 'letter-spacing', 'fill', 'stroke'];
  var NS = 'http://www.w3.org/2000/svg', bad = [];
  function label(svg, c) {
    var e = document.createElementNS(NS, 'text');
    e.setAttribute('x', '4'); e.setAttribute('y', '20'); e.setAttribute('font-size', '12');
    e.setAttribute('fill', 'currentColor'); if (c) e.setAttribute('class', c);
    e.textContent = 'label'; svg.appendChild(e); return e;
  }
  function style(e) {
    var s = getComputedStyle(e);
    return props.map(function (p) {
      var v = s.getPropertyValue(p);
      return p + ':' + (p === 'display' ? (v === 'none' ? 'none' : 'drawn') : v);
    });
  }
  ['light', 'dark'].forEach(function (theme) {
    document.documentElement.setAttribute('data-theme', theme);
    ['svg-top', 'svg-item'].forEach(function (host) {
      var svg = document.getElementById(host), base = style(label(svg, ''));
      names.forEach(function (n) {
        var got = style(label(svg, n)), diff = got.filter(function (v, i) { return v !== base[i]; });
        if (diff.length) bad.push(theme + ' ' + host + ' .' + n + ' {' + diff.join('; ') + '}');
      });
    });
  });
  document.title = 'SVGCLASS|' + names.length + '|' + (bad.join(' ') || 'none') + '|';
});
</script></body></html>
HTML
} > "$TMP/reports/svgclass.html"
chrome_dump "$TMP/svdom.html" "file://$TMP/reports/svgclass.html" 45 || true
ts="$(grep -oE '<title>[^<]*</title>' "$TMP/svdom.html" | sed -n 1p)"
[[ "$ts" =~ SVGCLASS\|([0-9]+)\| && ${BASH_REMATCH[1]} -ge 50 ]] \
  || fail "svg-class-leak: the kit's class list was not read (fewer than 50 classes): $ts"
[[ "$ts" == *"|none|"* ]] \
  || fail "svg-class-leak: a kit class restyles an author's svg <text> of the same name: $ts"
rm -rf "$TMP/profile"

# ---- an ALTERNATIVES row: visible zoom label, compact answer (BL-466, BL-516) ----
# Built by the real generator, so the markup under test is the markup shipped.
# Three things only a browser decides: the tile shows a zoom WORD without hover
# (CSS ::after from data-zoom, so a tap reads the same as a click); the row's
# extra options (the generator's "none of them" and the composer's injected
# Other / Not now / ask chips) sit in CLOSED <details>; and a mark made inside
# one still pastes, restores after a reload and opens the details it sits in.
ALT_ROOT="$TMP/altroot"
mkdir -p "$ALT_ROOT/shots"
python3 "$SKILL/tests/png_fixture.py" "$ALT_ROOT/shots/a.png" 16 9
python3 "$SKILL/tests/png_fixture.py" "$ALT_ROOT/shots/d.png" 16 9 96
cat > "$TMP/alt-rows.json" <<'JSON'
{"gallery": "skel", "variants": ["light-desktop"],
 "alternatives": [{"id": "a", "label": "Esqueleto A"}, {"id": "drawer", "label": "Con cajón"}],
 "rows": [{"cell": "list", "variant": "light-desktop", "kind": "alternatives", "look": "El botón de crear",
           "captures": {"a": "shots/a.png", "drawer": "shots/d.png"}}]}
JSON
GPAGE_A="$TMP/reports/gallery-alt.html"
{
  cat <<'HTML'
<meta name="consult-visual" content="none: a gallery probe, nothing to draw">
<div class="page"><main class="main">
<header><p class="eyebrow">PROBE</p><h1>Alternatives probe</h1></header>
HTML
  bash "$SKILL/scripts/gallery-items.sh" "$TMP/alt-rows.json" --root "$ALT_ROOT" --page "$GPAGE_A" \
    --group-id S --group-title "Esqueletos" --lang es
  cat <<'HTML'
<section class="consult-item consult-notes" data-id="notes" data-title="Notas"><h3>Notas</h3><textarea></textarea></section>
<div class="endbar"><button type="button" id="consult-copy-end">Copiar</button><span class="consult-status" id="consult-status-end"></span></div>
</main><aside class="rail"><nav class="raillist" id="raillist"></nav>
<div class="consult-bar"><button type="button" id="consult-copy">Copiar</button><span class="consult-status" id="consult-status"></span></div></aside></div>
<script>
window.addEventListener('load', function () {
  var ROW = 'skel-list-light-desktop-alternatives';
  var row = document.querySelector('[data-id="' + ROW + '"]');
  var dlg = document.querySelector('dialog.kit-zoom');
  var paste = function () {
    var cap = '';
    Object.defineProperty(navigator, 'clipboard', { configurable: true,
      value: { writeText: function (s) { cap = s; return Promise.resolve(); } } });
    document.getElementById('consult-copy').click();
    return cap.replace(/[|<>\n]/g, ' ');
  };
  var dets = function () { return [].map.call(row.querySelectorAll('details'), function (d) { return d.className.split(' ')[0] + ':' + (d.open ? 'open' : 'closed'); }).join(','); };
  var q = location.search;
  if (q.indexOf('phase=aset') !== -1) {
    var f = row.querySelector('figure[data-tile="drawer"]');
    var lab = getComputedStyle(f, '::after').content;
    var vis = row.querySelector('details.opts-more').open ? 'open' : 'closed';
    var otherIn = row.querySelectorAll('details.opts-more .kit-other, details.opts-more .kit-notnow').length;
    var askIn = row.querySelectorAll('details.kit-ask-more .kit-ask').length;
    var before = dets();
    var none = row.querySelector('details.opts-more input[data-label="Ninguna"]');
    none.checked = true; none.dispatchEvent(new Event('change', { bubbles: true }));
    var after = dets();
    document.title = 'GALTSET|LABEL=' + lab + '|DETS=' + before + '|OTHERIN=' + otherIn + '|ASKIN=' + askIn
      + '|OPENED=' + after + '|PASTE=' + paste();
  } else if (q.indexOf('phase=aget') !== -1) {
    document.title = 'GALTGET|DETS=' + dets() + '|SUMW=' + getComputedStyle(row.querySelector('details.opts-more > summary')).fontWeight
      + '|PASTE=' + paste();
  } else if (q.indexOf('phase=azoom') !== -1) {
    row.querySelector('figure[data-tile="a"]').click();
    var t0 = dlg.querySelector('.kit-zoom-tile').textContent;
    dlg.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true, cancelable: true }));
    var t1 = dlg.querySelector('.kit-zoom-tile').textContent;
    var cmpOff = [].every.call(dlg.querySelectorAll('.kit-zoom-cmp'), function (b) { return b.disabled; }) ? 'disabled' : 'enabled';
    dlg.querySelector('.kit-zoom-close').click();
    document.title = 'GALTZOOM|T0=' + t0 + '|T1=' + t1 + '|CMP=' + cmpOff;
  }
});
</script>
HTML
} > "$TMP/gbody-alt.html"
bash "$WRAP" --title "alt" --lang es --out "$GPAGE_A" < "$TMP/gbody-alt.html" > "$TMP/gwrap-a.log" 2>&1 \
  || fail "the alternatives probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-a.log" | sed -n 1,4p)"
arun() { chrome_dump "$TMP/gdom-a.html" "file://$GPAGE_A?$1" 45 || true; grep -oE '<title>[^<]*</title>' "$TMP/gdom-a.html" | sed -n 1p; }
rm -rf "$TMP/profile"
tg="$(arun 'phase=aset')"
[[ "$tg" == *GALTSET* ]] || fail "the alternatives phase did not run: $tg"
[[ "$tg" == *'LABEL="Ampliar"'* ]] \
  || fail "a tile shows no visible zoom word without hover (::after content of data-zoom): $tg"
[[ "$tg" == *"DETS=opts-more:closed,kit-more:closed|"* ]] \
  || fail "the row's extra options are not exactly two closed details (the generator's and the ask row's): $tg"
[[ "$tg" == *"OTHERIN=2"* && "$tg" == *"ASKIN=1"* ]] \
  || fail "the injected Other / Not now (2) and the ask row (1) are not inside the row's <details>: $tg"
[[ "$tg" == *"OPENED=opts-more:open,"* ]] \
  || fail "ticking an option inside the closed details did not open it: $tg"
[[ "$tg" == *"- Ninguna"* ]] \
  || fail "a mark made inside the collapsed details is missing from the paste: $tg"
tg="$(arun 'phase=aget')"
[[ "$tg" == *"SUMW=600"* ]] \
  || fail "a folded group holding a mark does not say so on its summary: $tg"
[[ "$tg" == *"DETS=opts-more:open,"* && "$tg" == *"- Ninguna"* ]] \
  || fail "the mark inside the details did not survive a reload (restored, its details open): $tg"
rm -rf "$TMP/profile"
tg="$(arun 'phase=azoom')"
[[ "$tg" == *"T0=a"* && "$tg" == *"T1=drawer"* ]] \
  || fail "the zoom walk does not follow the alternatives' own tiles: $tg"
[[ "$tg" == *"CMP=disabled"* ]] \
  || fail "compare is offered on alternatives, which have no before/after pair: $tg"
rm -rf "$TMP/profile"

# ---- a gallery row written BEFORE the generator folded its third verdict keeps its answer ----
# The question fingerprint must not move when the row gains the generator's
# <details> and its summary word (kit 33): a reader's unsent answer stored
# against the flat row has to restore onto the folded one.
cat > "$TMP/fp-rows.json" <<'JSON'
{"gallery": "audit", "variants": ["light-desktop"],
 "rows": [{"cell": "empty", "variant": "light-desktop", "kind": "review",
           "before": "shots/a.png", "after": "shots/d.png"}]}
JSON
fp_page() {  # fp_page <out> <folded 0|1>: the row is the generator's own markup
  bash "$SKILL/scripts/gallery-items.sh" "$TMP/fp-rows.json" --root "$ALT_ROOT" --page "$TMP/reports/fp.html" \
    --group-id R --group-title Review --lang es > "$TMP/fp-group.html" 2>/dev/null \
    || fail "the generator refused the fingerprint fixture"
  # Both pages link the SAME copies (fp-assets/): the capture src is part of the fingerprint.
  # The flat shape is what the generator wrote before kit 33: no <details>, no summary.
  [[ "$2" == 1 ]] || python3 - "$TMP/fp-group.html" <<'PY'
import re, sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
t = re.sub(r'<details class="opts-more"><summary>[^<]*</summary>', '', t).replace('</details>', '')
open(p, 'w', encoding="utf-8").write(t)
PY
  cat > "$TMP/fp-body.html" <<HTML
<meta name="consult-visual" content="none: a fingerprint probe, nothing to draw">
<div class="page"><main class="main">
<header><p class="eyebrow">PROBE</p><h1>Fingerprint probe</h1></header>
$(cat "$TMP/fp-group.html")
<section class="consult-item consult-notes" data-id="notes" data-title="Notas"><h3>Notas</h3><textarea></textarea></section>
<div class="endbar"><button type="button" id="consult-copy-end">Copiar</button><span class="consult-status" id="consult-status-end"></span></div>
</main><aside class="rail"><nav class="raillist" id="raillist"></nav>
<div class="consult-bar"><button type="button" id="consult-copy">Copiar</button><span class="consult-status" id="consult-status"></span></div></aside></div>
<script>
window.addEventListener('load', function () {
  var q = location.search, KEY = 'aidex-kit-answers:' + location.pathname;
  var row = document.querySelector('[data-id="audit-empty-light-desktop"]');
  var ta = row.querySelector('textarea:not(.kit-marks)');
  if (q.indexOf('phase=fpset') !== -1) {
    ta.value = 'typed before the fold'; ta.dispatchEvent(new Event('input', { bubbles: true }));
    var st = JSON.parse(localStorage.getItem(KEY) || '{}')['audit-empty-light-desktop'] || {};
    document.title = 'FPSET|H=' + st.h;
  } else if (q.indexOf('phase=fpseed') !== -1) {
    var h = q.match(/h=([0-9a-z]+)/)[1], o = {};
    o['audit-empty-light-desktop'] = { m: [], a: ['typed before the fold'], h: h };
    localStorage.setItem(KEY, JSON.stringify(o));
    document.title = 'FPSEED|DONE';
  } else if (q.indexOf('phase=fpget') !== -1) {
    document.title = 'FPGET|VAL=' + ta.value;
  }
});
</script>
HTML
  bash "$WRAP" --title "fp" --lang es --out "$1" < "$TMP/fp-body.html" > "$TMP/fp-wrap.log" 2>&1 \
    || fail "the fingerprint probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/fp-wrap.log" | sed -n 1,4p)"
}
FP_FLAT="$TMP/reports/fp-flat.html"; FP_FOLD="$TMP/reports/fp-fold.html"
fp_page "$FP_FLAT" 0; fp_page "$FP_FOLD" 1
fprun() { chrome_dump "$TMP/fp.dom" "file://$1?$2" 45 || true; grep -oE '<title>[^<]*</title>' "$TMP/fp.dom" | sed -n 1p; }
rm -rf "$TMP/profile"
tg="$(fprun "$FP_FLAT" 'phase=fpset')"
fph="$(sed -nE 's/.*FPSET\|H=([0-9a-z]+).*/\1/p' <<<"$tg")"
[[ -n "$fph" ]] || fail "the flat row stored no fingerprint: $tg"
fprun "$FP_FOLD" "phase=fpseed&h=$fph" > /dev/null
tg="$(fprun "$FP_FOLD" 'phase=fpget')"
[[ "$tg" == *"FPGET|VAL=typed before the fold"* ]] \
  || fail "an answer stored against the flat row was dropped once the row folded its third verdict (the fingerprint moved): $tg"
rm -rf "$TMP/profile"

# ---- BL-577 addendum: folded decided rows show the heading, never the row slug
# Layer: browser (the fold is built by the kit's own script). One block of two
# decided rows (folds as a group), one standalone decided row, one decided row with
# no heading (control: keeps its id), one open question so the page is not all-decided.
SLUGPAGE="$TMP/reports/slug.html"
cat > "$TMP/slugbody.html" <<HTML
<meta name="consult-visual" content="none: a layout probe, nothing to draw">
<div class="page">
<main class="main">
<header><p class="eyebrow">PROBE</p><h1>Slug probe</h1></header>
<section id="sec-ask">
  <div class="sec-head"><h2>Questions</h2></div>
<section class="consult-group" id="GA" data-id="GA" data-title="Menus"><div class="sec-head"><h2>Menus</h2></div><p>Contexto.</p>
  <section class="consult-item" data-id="g-users-list-menu-light-desktop" data-title="menu light" data-heading="Men&uacute; de usuarios" data-decided="Option A">
    <h3><span class="consult-id">g-users-list-menu-light-desktop</span>Men&uacute; de usuarios</h3>
    <div class="opts one"><label><input type="radio" name="g-users-list-menu-light-desktop" data-label="Option A" checked><span>Option A</span></label><label><input type="radio" name="g-users-list-menu-light-desktop" data-label="Option B"><span>Option B</span></label></div>
    <textarea></textarea>
  </section>
  <section class="consult-item" data-id="g-users-list-menu-dark-desktop" data-title="menu dark" data-heading="Men&uacute; oscuro" data-decided="Option A">
    <h3><span class="consult-id">g-users-list-menu-dark-desktop</span>Men&uacute; oscuro</h3>
    <div class="opts one"><label><input type="radio" name="g-users-list-menu-dark-desktop" data-label="Option A" checked><span>Option A</span></label><label><input type="radio" name="g-users-list-menu-dark-desktop" data-label="Option B"><span>Option B</span></label></div>
    <textarea></textarea>
  </section>
</section>
<section class="consult-group" id="GB" data-id="GB" data-title="Mixed"><div class="sec-head"><h2>Mixed</h2></div><p>Contexto.</p>
  <section class="consult-item" data-id="g-users-list-access-link-tooltip-light-desktop" data-title="tip" data-heading="Tooltip de acceso" data-decided="Option A">
    <h3><span class="consult-id">g-users-list-access-link-tooltip-light-desktop</span>Tooltip de acceso</h3>
    <div class="opts one"><label><input type="radio" name="g-users-list-access-link-tooltip-light-desktop" data-label="Option A" checked><span>Option A</span></label><label><input type="radio" name="g-users-list-access-link-tooltip-light-desktop" data-label="Option B"><span>Option B</span></label></div>
    <textarea></textarea>
  </section>
  <section class="consult-item" data-id="plain-row-id" data-title="Plain title" data-decided="Option A">
    <h3><span class="consult-id">plain-row-id</span>Plain title</h3>
    <div class="opts one"><label><input type="radio" name="plain-row-id" data-label="Option A" checked><span>Option A</span></label><label><input type="radio" name="plain-row-id" data-label="Option B"><span>Option B</span></label></div>
    <textarea></textarea>
  </section>
  <section class="consult-item" data-id="OPEN1" data-title="Open one">
    <h3><span class="consult-id">OPEN1</span>Open question</h3>
    <div class="opts one"><label><input type="radio" name="OPEN1" data-label="Option A"><span>Option A</span></label><label><input type="radio" name="OPEN1" data-label="Option B"><span>Option B</span></label></div>
    <textarea></textarea>
  </section>
</section>
<section class="consult-item consult-notes" data-id="notes" data-title="Notas generales">
  <h3><span class="consult-id">notes</span>Notas generales</h3>
  <textarea></textarea>
</section>
<div class="endbar"><button type="button" id="consult-copy-end">Copiar mis respuestas</button><span class="consult-status" id="consult-status-end"></span></div>
</main>
<aside class="rail">
  <p class="railhead">Contenido</p>
  <nav class="raillist" id="raillist"></nav>
  <div class="consult-bar">
    <button type="button" id="consult-copy">Copiar mis respuestas</button>
    <span class="consult-status" id="consult-status"></span>
  </div>
</aside>
</div>
<script>
window.addEventListener('load', function () {
  var sums = [].map.call(document.querySelectorAll('details.decided-unit > summary'), function (d) { return d.textContent.replace(/[|]/g, '/').replace(/\n/g, '; '); });
  var emptyId = [].filter.call(document.querySelectorAll('details.decided-unit > summary > .consult-id'), function (e) { return !e.textContent; }).length;
  document.title = 'SLUG|SUMS=' + sums.join(';;') + '|EMPTYID=' + emptyId;
});
</script>
HTML
bash "$WRAP" --title "slug" --lang es --out "$SLUGPAGE" < "$TMP/slugbody.html" > "$TMP/slugwrap.log" 2>&1 \
  || fail "the slug probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/slugwrap.log" | sed -n 1,4p)"
chrome_dump "$TMP/slugdom.html" "file://$SLUGPAGE" 45 || true
tsl="$(grep -oE '<title>[^<]*</title>' "$TMP/slugdom.html" | sed -n 1p)"
[[ "$tsl" == *"SLUG|SUMS="*"de usuarios"* ]] \
  || fail "BL-577: the decided-group summary does not show the row headings: $tsl"
[[ "$tsl" != *"users-list-menu"* ]] \
  || fail "BL-577: a folded decided row still shows its raw slug (group summary or its own fold): $tsl"
[[ "$tsl" != *"access-link-tooltip"* ]] \
  || fail "BL-577: a decided row folded in place still shows its slug: $tsl"
[[ "$tsl" == *"Tooltip de acceso"* ]] \
  || fail "BL-577: a decided row folded in place lost its heading: $tsl"
[[ "$tsl" == *"EMPTYID=0"* ]] \
  || fail "BL-577: a headed fold carries an empty .consult-id span (margin, misalignment): $tsl"
[[ "$tsl" == *"plain-row-id"* ]] \
  || fail "BL-577: a decided row with no heading must keep its id as the label: $tsl"

# ---- BL-635: a tab that another tab outdated says so ------------------------
# Layer: browser (the storage event and the banner node are the engine's).
t="$(run 'phase=stale')"
[[ "$t" == *"OWN=0"* ]] || fail "BL-635: a tab marked itself stale on load: $t"
[[ "$t" == *"EQ=0"* ]] || fail "BL-635: an EQUAL built stamp from another tab showed the stale banner: $t"
[[ "$t" == *"OLD=0"* ]] || fail "BL-635: an OLDER built stamp from another tab showed the stale banner: $t"
[[ "$t" == *"XKEY=0"* ]] || fail "BL-635: a newer stamp under ANOTHER path's key showed the banner: $t"
[[ "$t" == *"EQOLD=0"* ]] || fail "BL-635: equal built and round with an older file mtime showed the banner: $t"
[[ "$t" == *"NEWR=1"* ]] || fail "BL-635: equal built with a later round (same-minute re-wrap) did not show the banner: $t"
[[ "$t" == *"NEWM=1"* ]] || fail "BL-635: equal built and round with a later file mtime did not show the banner: $t"
[[ "$t" == *"NEW=1"* ]] || fail "BL-635: a NEWER built stamp for this path did not show the stale banner: $t"
[[ "$t" == *"N=1"* ]] || fail "BL-635: the stale banner is not a single node: $t"
[[ "$t" == *"BTN=1"* && "$t" == *"recárgala"* ]] || fail "BL-635: the stale banner has no reload action or is not in the page language (es): $t"
[[ "$t" == *"SHOWN=1"* ]] || fail "BL-635: the stale banner has no box on screen: $t"
[[ "$t" == *'STORED={"b":"2'* && "$t" == *'"m":1'* ]] || fail "BL-635: the load did not record this page's built stamp under its path: $t"
t="$(CHROME_WINDOW=390,800 run 'phase=stale')"
[[ "$t" == *"|NEW=1"* && "$t" == *"SHOWN=1"* ]] || fail "BL-635: the stale banner is not visible at 390: $t"

# ---- a highlighted figure (BL-619): same size as a plain one, outline on its region ----
# Layout only a browser decides: (a) a png figure with highlight= renders its
# img at exactly the width a plain one gets, at 1280 and 390; (b) in an item's
# thumbnail grid (cropped 4:3 by the kit) a highlighted figure is shown whole,
# so every .gal-hl box lies inside its own img.
FHL="$TMP/fhl"
mkdir -p "$FHL/figures"
python3 "$SKILL/tests/png_fixture.py" "$FHL/figures/mid.png" 800 500
python3 "$SKILL/tests/png_fixture.py" "$FHL/figures/small.png" 300 200
python3 "$SKILL/tests/png_fixture.py" "$FHL/figures/tall.png" 390 844
python3 "$SKILL/tests/png_fixture.py" "$FHL/figures/wide.png" 1200 400
cat > "$FHL/p.spec.md" <<'SPEC'
::: masthead {visual="none: probe"}
# Probe

Probe page.
:::

::: group {#G title="Grupo"}
::: item {#Q1 title="Mid plain"}
Texto.

::: figure {src="figures/mid.png" alt="mid"}
:::

- A — bien
- B — mal
:::

::: item {#Q2 title="Mid highlighted"}
Texto.

::: figure {src="figures/mid.png" alt="mid" highlight="300,200,200,100"}
:::

- A — bien
- B — mal
:::

::: item {#Q3 title="Small plain"}
Texto.

::: figure {src="figures/small.png" alt="small"}
:::

- A — bien
- B — mal
:::

::: item {#Q4 title="Small highlighted"}
Texto.

::: figure {src="figures/small.png" alt="small" highlight="100,50,100,50"}
:::

- A — bien
- B — mal
:::

::: item {#Q5 title="Shots highlighted"}
Texto.

::: figure {src="figures/wide.png" alt="wide" highlight="100,100,300,100" title="wide"}
:::

::: figure {src="figures/tall.png" alt="tall" highlight="20,700,200,100" title="tall"}
:::

- A — bien
- B — mal
:::
:::

::: notes {title="Notas generales"}
:::
SPEC
python3 "$SKILL/scripts/spec_build.py" "$FHL/p.spec.md" > "$FHL/body.html" 2> "$FHL/build.log" \
  || fail "BL-619: the highlighted-figure probe spec failed to build: $(head -3 "$FHL/build.log")"
cat >> "$FHL/body.html" <<'HTML'
<script>
window.addEventListener('load', function () {
  (function () {
    var w = function (id) { return document.querySelector('[data-id="' + id + '"] figure img').getBoundingClientRect().width; };
    var inside = 0, outside = 0;
    [].forEach.call(document.querySelectorAll('[data-id="Q5"] .gal.shots figure'), function (f) {
      var ir = f.querySelector('img').getBoundingClientRect();
      [].forEach.call(f.querySelectorAll('.gal-hl'), function (b) {
        var r = b.getBoundingClientRect();
        if (r.left >= ir.left - 1 && r.right <= ir.right + 1 && r.top >= ir.top - 1 && r.bottom <= ir.bottom + 1) inside++; else outside++;
      });
    });
    document.title = 'FHL|mid=' + Math.round(w('Q1')) + ',' + Math.round(w('Q2')) +
      '|small=' + Math.round(w('Q3')) + ',' + Math.round(w('Q4')) +
      '|in=' + inside + '|out=' + outside + '|';
  })();
});
</script>
HTML
FHL_PAGE="$TMP/reports/fhl.html"
bash "$WRAP" --title "fhl" --lang es --out "$FHL_PAGE" < "$FHL/body.html" > "$FHL/wrap.log" 2>&1 \
  || fail "BL-619: the probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$FHL/wrap.log" | sed -n 1,4p)"
for vp in 1280,900 390,900; do
  rm -rf "$TMP/profile"
  CHROME_WINDOW=$vp chrome_dump "$TMP/fhl-$vp.dom" "file://$FHL_PAGE" 45 || true
  tf="$(grep -oE '<title>[^<]*</title>' "$TMP/fhl-$vp.dom" | sed -n 1p)"
  [[ "$tf" =~ mid=([0-9]+),([0-9]+)\|small=([0-9]+),([0-9]+)\|in=([0-9]+)\|out=([0-9]+) ]] \
    || fail "BL-619 $vp: the highlighted-figure probe did not report: $tf"
  [[ "${BASH_REMATCH[1]}" -gt 0 && "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]] \
    || fail "BL-619 $vp: a highlighted 800x500 figure's img is not as wide as a plain one: $tf"
  [[ "${BASH_REMATCH[3]}" -gt 0 && "${BASH_REMATCH[3]}" == "${BASH_REMATCH[4]}" ]] \
    || fail "BL-619 $vp: a highlighted 300x200 figure's img is not as wide as a plain one: $tf"
  [[ "${BASH_REMATCH[5]}" == 2 && "${BASH_REMATCH[6]}" == 0 ]] \
    || fail "BL-619 $vp: in a thumbnail grid an outline leaves its image (want in=2 out=0): $tf"
done

# ---- BL-692: a decided item the reader has not answered is a PROPOSAL, kept in place ----
# "decidido, corrígeme si no" items (data-decided + data-proposal) were folded into the bottom
# "N preguntas ya resueltas" section like an earlier round's settled answers, so a proposal read as
# settled and its correction box was hidden and sealed. Layer: browser, because where the item is
# drawn, whether its notes box is live and what the copied reply carries are the composer's calls.
PRP="$TMP/prp"; mkdir -p "$PRP"
item692() {  # item692 <id> <title> <attrs>; an asks-nothing row is shaped like the generator's sample row: no controls, one .gal-asks-nothing line
  if [[ "$3" == *data-asks-nothing* ]]; then
    printf '<section class="consult-item" data-id="%s" data-title="%s" %s>\n<h3><span class="consult-id">%s</span>%s?</h3>\n<p class="gal-asks-nothing">Esta fila no pide respuesta.</p>\n</section>\n' "$1" "$2" "$3" "$1" "$2"
    return
  fi
  printf '<section class="consult-item" data-id="%s" data-title="%s" %s>\n<h3><span class="consult-id">%s</span>%s?</h3>\n<div class="opts one"><label><input type="radio" name="%s" data-label="Si" checked><span>Si</span></label><label><input type="radio" name="%s" data-label="No"><span>No</span></label></div>\n<p class="fieldlabel">Notas</p><textarea placeholder="Escribe aqui"></textarea>\n</section>\n' "$1" "$2" "$3" "$1" "$2" "$1" "$1"
}
{
  printf '%s\n' '<meta name="consult-visual" content="none: a layout probe, nothing to draw">' \
    '<div class="page"><main class="main"><header><p class="eyebrow">PROBE</p><h1>Proposal</h1></header>' \
    '<section id="sec-ask"><div class="sec-head"><h2>Questions</h2></div>'
  printf '<section class="consult-group" data-id="G1" data-title="Propuestas"><p>Contexto</p>\n'
  item692 P1 "Primera propuesta" 'data-decided="Si" data-proposal'
  item692 P2 "Segunda propuesta" 'data-decided="Si" data-proposal'
  printf '</section>\n<section class="consult-group" data-id="G2" data-title="Ya resueltas"><p>Contexto</p>\n'
  item692 S1 "Primera resuelta" 'data-decided="Si"'
  item692 S2 "Segunda resuelta" 'data-decided="No"'
  printf '</section>\n<section class="consult-group" data-id="G3" data-title="Abiertas"><p>Contexto</p>\n'
  item692 A1 "Fila de muestra" 'data-asks-nothing data-free="yes"'
  item692 A2 "Pregunta normal" ''
  printf '</section>\n'
  printf '%s\n' '<div class="endbar"><button type="button" id="consult-copy-end">Copy</button><span class="consult-status" id="consult-status-end"></span></div>' \
    '<section class="consult-item consult-notes" data-id="notes" data-title="Notas generales"><h3>Notas generales</h3><textarea></textarea></section>' \
    '</section></main><aside class="rail"><p class="railhead">Contenido</p><nav class="raillist" id="raillist"></nav>' \
    '<div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div></aside></div>'
  cat <<'PROBE'
<script>window.addEventListener("load", function () {
  var p1 = document.querySelector('[data-id="P1"]'), sec = document.getElementById("sec-decided");
  var ta = p1.querySelector("textarea"), cap = "";
  var i3 = document.querySelector('[data-id="P2"]'), p3 = i3.querySelector("textarea");
  var has = function (n) { return n.classList.contains("has-answer") ? 1 : 0; };
  if (location.search.indexOf("phase=reload") > -1) {
    document.title = "PRPRELOAD|P1=" + ta.value + "|P3=" + p3.value + "|HAS3=" + has(i3) + "|STAT=" + document.getElementById("consult-status").textContent + "|";
    return;
  }
  var done0 = has(i3);
  /* Before anything is typed: the EMPTY box and its label must be drawn (the settled-item rule
   * that hides an empty reply box must not reach a proposal). */
  var lbl = ta.previousElementSibling;
  var emptyVis = (ta.checkVisibility() && getComputedStyle(ta).display !== "none"
    && lbl.checkVisibility() && getComputedStyle(lbl).display !== "none") ? 1 : 0;
  p3.value = "zzzloose"; p3.dispatchEvent(new Event("input", { bubbles: true }));
  var done1 = has(i3);
  var statTyped = "";
  Object.defineProperty(navigator, "clipboard", { configurable: true,
    value: { writeText: function (s) { cap = s; return Promise.resolve(); } } });
  ta.value = "zzzcorrection mejor No"; ta.dispatchEvent(new Event("input", { bubbles: true }));
  statTyped = document.getElementById("consult-status").textContent;
  document.getElementById("consult-copy").click();
  var lab = p1.querySelector(".consult-proposal");
  var sum = sec ? sec.querySelector("summary") : null;
  document.title = "PRP|INSEC=" + (sec && sec.contains(p1) ? 1 : 0)
    + "|INFOLD=" + (p1.closest("details.decided-unit") ? 1 : 0)
    + "|VISIBLE=" + (p1.checkVisibility() ? 1 : 0)
    + "|LABEL=" + (lab ? lab.textContent.trim() : "none")
    + "|LIVE=" + (ta.disabled ? 0 : 1)
    + "|SETTLED=" + (sec && sec.contains(document.querySelector('[data-id="S1"]')) ? 1 : 0)
    + "|SECUNITS=" + (sec ? sec.querySelectorAll(".decided-unit").length : -1)
    + "|SECHEAD=" + (sec ? sec.querySelector(".eyebrow").textContent : "none")
    + "|LINES=" + (sum ? sum.textContent.trim().split("\n").length : -1)
    + "|SEMI=" + (sum && sum.textContent.indexOf("; ") > -1 ? 1 : 0)
 + "|ASKS=" + document.querySelectorAll('[data-id="A1"] .kit-ask').length + "/" + document.querySelectorAll('[data-id="A2"] .kit-ask').length
    + "|STATTYPED=" + statTyped
    + "|EMPTYVIS=" + emptyVis
    + "|RADIOOFF=" + (p1.querySelectorAll("input[type=radio]:disabled").length ? 1 : 0)
    + "|DONE0=" + done0 + "|DONE1=" + done1
    + "|REPLY=" + cap.replace(/[|<>\n]/g, " ") + "|";
});</script>
PROBE
} > "$PRP/body.html"
bash "$WRAP" --title "prp" --lang es --out "$TMP/reports/prp.html" < "$PRP/body.html" > "$PRP/wrap.log" 2>&1 \
  || fail "BL-692: the proposal probe failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$PRP/wrap.log" | sed -n 1,4p)"
rm -rf "$TMP/profile"
CHROME_WINDOW=1280,900 chrome_dump "$PRP/dom.html" "file://$TMP/reports/prp.html" 45 || true
tp="$(grep -oE '<title>[^<]*</title>' "$PRP/dom.html" | sed -n 1p)"
[[ "$tp" == *"|INSEC=0|INFOLD=0|VISIBLE=1|"* ]] \
  || fail "BL-692: a proposal (data-decided + data-proposal) was folded into the settled section instead of staying in place, visible: $tp"
[[ "$tp" == *"|LABEL=Decidido, corrígeme si no|LIVE=1|"* ]] \
  || fail "BL-692: the proposal carries no 'Decidido, corrígeme si no' label, or its correction box is sealed: $tp"
[[ "$tp" == *"|SETTLED=1|SECUNITS=1|SECHEAD=2 preguntas ya resueltas|"* ]] \
  || fail "BL-692: an earlier round's settled group must still fold alone into 'N preguntas ya resueltas' (want 2, not 4): $tp"
[[ "$tp" == *"|LINES=2|SEMI=0|"* ]] \
  || fail "BL-692: the folded group's summary is not one line per point (want 2 lines, no '; '): $tp"
[[ "$tp" == *"|REPLY="*"P1"*"zzzcorrection mejor No"* ]] \
  || fail "BL-692: the correction typed on the proposal did not land in the copied reply: $tp"
[[ "$tp" == *"|STATTYPED="*"2 correcciones listas para copiar|"* ]] \
  || fail "BL-692: the status must count the typed corrections beside the questions (want '2 correcciones listas para copiar'): $tp"
[[ "$tp" == *"|DONE0=0|DONE1=1|"* ]] \
  || fail "BL-692: a proposal with no correction must not read as answered (has-answer), and must once something is typed: $tp"
[[ "$tp" == *"|EMPTYVIS=1|RADIOOFF=0|"* ]] \
  || fail "BL-692/BL-700: an EMPTY proposal must show its correction box and label (EMPTYVIS=1), with its options live (RADIOOFF=0, BL-700): $tp"
[[ "$tp" == *"|REPLY="*"### P2"*"zzzloose"* && "${tp%%## G3*}" != *"- Si"* && "$tp" != *"### S1"* && "$tp" != *"### S2"* ]] \
  || fail "BL-692: the reply must carry P2's correction and neither the proposal's sealed '- Si' nor the settled S1/S2: $tp"
[[ "$tp" == *"|ASKS=0/1|"* ]] \
  || fail "BL-693: an item marked data-asks-nothing must get no ask chips while a normal open item gets its row (want ASKS=0/1): $tp"
# BL-693: a gallery sample row (data-asks-nothing) keeps no mark-mode box: it still has tiles to look at, but nothing to answer.
# The sample row comes from the generator (kind: sample), so it has the real shape: tiles, no controls, the asks-nothing line.
gen629 "$TMP/g629/marks.html" "$(row629 empty '')" "$(row629 loaded '' | sed 's/"kind": "review"/"kind": "sample"/')"
MARKS_PROBE='<script>window.addEventListener("load", function () {
  var n = function (id) { return document.querySelectorAll("[data-id=" + id + "] textarea.kit-marks").length; };
  document.title = "MARKS|NORMAL=" + n("audit-empty-light-desktop") + "|SAMPLE=" + n("audit-loaded-light-desktop") + "|";
});</script>'
PROBE629="$MARKS_PROBE"
page629 "$TMP/g629/marks.html" "$TMP/reports/marks692.html"
tmk="$(title629 "$TMP/reports/marks692.html")"
[[ "$tmk" == *"|NORMAL=1|SAMPLE=0|"* ]] \
  || fail "BL-693: a tiled gallery row marked data-asks-nothing must get no mark-mode box while a normal one does (want NORMAL=1|SAMPLE=0): $tmk"
# A page whose only remaining items are proposals is not "all decided": status and copy count say so.
{
  printf '%s\n' '<meta name="consult-visual" content="none: a layout probe, nothing to draw">' \
    '<div class="page"><main class="main"><header><p class="eyebrow">PROBE</p><h1>Only proposals</h1></header>' \
    '<section id="sec-ask"><div class="sec-head"><h2>Questions</h2></div>'
  printf '<section class="consult-group" data-id="G1" data-title="Propuestas"><p>Contexto</p>\n'
  item692 P1 "Primera propuesta" 'data-decided="Si" data-proposal'
  item692 P2 "Segunda propuesta" 'data-decided="Si" data-proposal'
  printf '</section>\n'
  printf '%s\n' '<div class="endbar"><button type="button" id="consult-copy-end">Copy</button><span class="consult-status" id="consult-status-end"></span></div>' \
    '<section class="consult-item consult-notes" data-id="notes" data-title="Notas generales"><h3>Notas generales</h3><textarea></textarea></section>' \
    '</section></main><aside class="rail"><p class="railhead">Contenido</p><nav class="raillist" id="raillist"></nav>' \
    '<div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div></aside></div>'
  cat <<'PROBE'
<script>window.addEventListener("load", function () {
  var st = document.getElementById("consult-status"), rail = document.querySelector(".rail");
  var s0 = st.textContent, set0 = rail.classList.contains("settled") ? 1 : 0;
  document.getElementById("consult-copy").click();
  var s1 = st.textContent;
  var ta = document.querySelector('[data-id="P1"] textarea');
  Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText: function () { return { then: function (f) { f(); return { catch: function () {} }; } }; } } });
  ta.value = "zzzfix"; ta.dispatchEvent(new Event("input", { bubbles: true }));
  var sPart = st.textContent;
  var tb = document.querySelector('[data-id="P2"] textarea');
  tb.value = "zzzfix2"; tb.dispatchEvent(new Event("input", { bubbles: true }));
  var sTyped = st.textContent;
  document.getElementById("consult-copy").click();
  document.title = "ONLYP|S0=" + s0 + "|SETTLED0=" + set0 + "|S1=" + s1 + "|SPART=" + sPart + "|STYPED=" + sTyped + "|S2=" + st.textContent + "|";
});</script>
PROBE
} > "$PRP/body2.html"
bash "$WRAP" --title "prp2" --lang es --out "$TMP/reports/prp2.html" < "$PRP/body2.html" > "$PRP/wrap2.log" 2>&1 \
  || fail "BL-692: the proposals-only probe failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$PRP/wrap2.log" | sed -n 1,4p)"
CHROME_WINDOW=1280,900 chrome_dump "$PRP/dom3.html" "file://$TMP/reports/prp2.html" 45 || true
tp3="$(grep -oE '<title>[^<]*</title>' "$PRP/dom3.html" | sed -n 1p)"
[[ "$tp3" == *"|S0=Quedan puntos decididos por confirmar o corregir|SETTLED0=0|S1=Nada que copiar: si estás de acuerdo con todo, escríbelo en la nota general|"* ]] \
  || fail "BL-692: a page whose only items are proposals must say points are left to confirm (not 'Todas las preguntas están decididas'), keep the bar pinned (SETTLED0=0), and tell a copy with nothing typed to use the general note: $tp3"
[[ "$tp3" == *"|SPART=Quedan puntos decididos por confirmar o corregir · 1 corrección lista para copiar|"* ]] \
  || fail "BL-692: with some proposals corrected and others not, the status must show both the points left and the corrections count: $tp3"
[[ "$tp3" == *"|STYPED=2 correcciones listas para copiar|"* ]] \
  || fail "BL-692: once every proposal has a correction the status must not keep saying points are left (want '2 correcciones listas para copiar'): $tp3"
[[ "$tp3" == *"|S2=2 copiada(s)"* ]] \
  || fail "BL-692: after copying a correction the status must count it (2 copiada(s), not 0): $tp3"
# Reload on the same profile (same path, so the same store): the typed corrections must come back.
CHROME_WINDOW=1280,900 chrome_dump "$PRP/dom2.html" "file://$TMP/reports/prp.html?phase=reload" 45 || true
tp2="$(grep -oE '<title>[^<]*</title>' "$PRP/dom2.html" | sed -n 1p)"
[[ "$tp2" == *"|P1=zzzcorrection mejor No|P3=zzzloose|HAS3=1|STAT="*"2 correcciones listas para copiar|"* ]] \
  || fail "BL-692: a correction typed on a proposal did not survive a reload (or its has-answer mark / the status line did not): $tp2"
# BL-692: round 1 left an UNSENT answer ("No" + a note) on the open P1; in round 2 P1 is a proposal
# written "Si". It must load with "Si" checked and the round-1 note NOT restored into the proposal.
R2="$TMP/r2692"; mkdir -p "$R2"
body692() {  # body692 <open|proposal>
  local attr=""; [[ "$1" == proposal ]] && attr='data-decided="Si" data-proposal'
  { printf '%s\n' '<meta name="consult-visual" content="none: a layout probe, nothing to draw">' \
      '<div class="page"><main class="main"><header><p class="eyebrow">PROBE</p><h1>Two rounds</h1></header>' \
      '<section id="sec-ask"><div class="sec-head"><h2>Questions</h2></div>'
    printf '<section class="consult-group" data-id="G1" data-title="Uno"><p>Contexto</p>\n'
    # Same markup either way (the question hash is whitespace-sensitive): the open item is
    # the proposal's markup with no verdict and nothing pre-checked.
    if [[ "$1" == open ]]; then
      item692 P1 "Punto" "" | sed 's/ checked//'
    else
      item692 P1 "Punto" "$attr"
    fi
    printf '</section>\n'
    printf '%s\n' '<div class="endbar"><button type="button" id="consult-copy-end">Copy</button><span class="consult-status" id="consult-status-end"></span></div>' \
      '<section class="consult-item consult-notes" data-id="notes" data-title="Notas generales"><h3>Notas generales</h3><textarea></textarea></section>' \
      '</section></main><aside class="rail"><p class="railhead">Contenido</p><nav class="raillist" id="raillist"></nav>' \
      '<div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div></aside></div>'
    cat <<'PROBE'
<script>window.addEventListener("load", function () {
  var p1 = document.querySelector('[data-id="P1"]'), ta = p1.querySelector("textarea");
  if (location.search.indexOf("phase=fill") > -1) {
    var no = p1.querySelector('input[data-label="No"]'); no.checked = true; no.dispatchEvent(new Event("change", { bubbles: true }));
    ta.value = "zzznoteround1"; ta.dispatchEvent(new Event("input", { bubbles: true }));
    document.title = "FILLED"; return;
  }
  var on = [].filter.call(p1.querySelectorAll("input[type=radio]:checked"), function () { return true; }).map(function (i) { return i.dataset.label; }).join("+");
  document.title = "R2|CHECKED=" + on + "|NOTE=" + ta.value + "|REST=" + ((document.getElementById("consult-restored")||{}).textContent||"none").slice(0, 60) + "|";
});</script>
PROBE
  } > "$R2/body.html"
}
body692 open
bash "$WRAP" --title "r2" --lang es --out "$TMP/reports/r2692.html" < "$R2/body.html" > "$R2/wrap1.log" 2>&1 \
  || fail "BL-692: the round-1 page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$R2/wrap1.log" | sed -n 1,4p)"
rm -rf "$TMP/profile"
CHROME_WINDOW=1280,900 chrome_dump "$R2/dom1.html" "file://$TMP/reports/r2692.html?phase=fill" 45 || true
printf 'P1: ok\n' | bash "$SKILL/scripts/save-reply.sh" "$TMP/reports/r2692.html" - >/dev/null 2>&1 \
  || fail "BL-692: save-reply.sh failed on the round-1 page"
body692 proposal
bash "$WRAP" --title "r2" --lang es --out "$TMP/reports/r2692.html" < "$R2/body.html" > "$R2/wrap2.log" 2>&1 \
  || fail "BL-692: the round-2 page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$R2/wrap2.log" | sed -n 1,4p)"
CHROME_WINDOW=1280,900 chrome_dump "$R2/dom2.html" "file://$TMP/reports/r2692.html" 45 || true
tr2b="$(grep -oE '<title>[^<]*</title>' "$R2/dom2.html" | sed -n 1p)"
[[ "$tr2b" == *"|CHECKED=Si|NOTE=|REST=none|"* ]] \
  || fail "BL-692: a round-2 proposal restored round 1's unsent answer (want CHECKED=Si, empty NOTE, and no restored/stale banner about it): $tr2b"
# Same round (no saved reply between the wraps): the open P1 with a stored "No" is rebuilt as a proposal "Si".
# BL-700: its options are live, so the stored "No" is the reader's own unsent answer (given this
# round, on the open item) and comes back as a correction over the proposed Si.
rm -rf "$TMP/profile"
body692 open
bash "$WRAP" --title "r2b" --lang es --out "$TMP/reports/r2b692.html" < "$R2/body.html" > "$R2/wrap3.log" 2>&1 \
  || fail "BL-692: the same-round page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$R2/wrap3.log" | sed -n 1,4p)"
CHROME_WINDOW=1280,900 chrome_dump "$R2/dom3.html" "file://$TMP/reports/r2b692.html?phase=fill" 45 || true
body692 proposal
bash "$WRAP" --title "r2b" --lang es --out "$TMP/reports/r2b692.html" < "$R2/body.html" > "$R2/wrap4.log" 2>&1 \
  || fail "BL-692: the same-round proposal page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$R2/wrap4.log" | sed -n 1,4p)"
CHROME_WINDOW=1280,900 chrome_dump "$R2/dom4.html" "file://$TMP/reports/r2b692.html" 45 || true
tr2c="$(grep -oE '<title>[^<]*</title>' "$R2/dom4.html" | sed -n 1p)"
[[ "$tr2c" == *"|CHECKED=No|"* ]] \
  || fail "BL-700: an open item rebuilt as a proposal in the SAME round must restore the reader's stored 'No' over the proposed Si (want only No checked): $tr2c"

# ---- BL-700: a proposal keeps its radios LIVE, the proposed option pre-selected ----
# Owner read the sealed radios as broken (twice). Layer: browser, because whether an input is
# enabled and what the copied reply carries are the composer's calls. A changed selection is a
# correction that reaches the reply (same shape as an answered item); an unchanged one sends nothing
# and stays pending; changing back is the unchanged case again; a reload keeps the change only.
L700="$TMP/l700"; mkdir -p "$L700"
{
  printf '%s\n' '<meta name="consult-visual" content="none: a layout probe, nothing to draw">' \
    '<div class="page"><main class="main"><header><p class="eyebrow">PROBE</p><h1>Live proposals</h1></header>' \
    '<section id="sec-ask"><div class="sec-head"><h2>Questions</h2></div>'
  printf '<section class="consult-group" data-id="G1" data-title="Propuestas"><p>Contexto</p>\n'
  item692 P1 "Primera propuesta" 'data-decided="Si" data-proposal'
  item692 P2 "Segunda propuesta" 'data-decided="Si" data-proposal'
  printf '</section>\n'
  printf '%s\n' '<div class="endbar"><button type="button" id="consult-copy-end">Copy</button><span class="consult-status" id="consult-status-end"></span></div>' \
    '<section class="consult-item consult-notes" data-id="notes" data-title="Notas generales"><h3>Notas generales</h3><textarea></textarea></section>' \
    '</section></main><aside class="rail"><p class="railhead">Contenido</p><nav class="raillist" id="raillist"></nav>' \
    '<div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div></aside></div>'
  cat <<'PROBE'
<script>/* Runs BEFORE the composer. formrestore: the browser restored the reader's "No" into the form on a
   * same-tab reload. notnow: a stored [not-now] on an item rebuilt as a proposal. */
(function () {
  var q = location.search;
  if (q.indexOf("phase=formrestore") > -1) document.querySelector('[data-id="P1"] input[data-label="No"]').checked = true;
  if (q.indexOf("phase=notnow") > -1) localStorage.setItem("aidex-kit-answers:" + location.pathname, JSON.stringify({ P1: { m: ["[not-now]"] } }));
})();</script>
<script>window.addEventListener("load", function () {
  var p1 = document.querySelector('[data-id="P1"]'), p2 = document.querySelector('[data-id="P2"]');
  var radio = function (it, l) { return it.querySelector('input[data-label="' + l + '"]'); };
  var checked = function (it) { return [].filter.call(it.querySelectorAll("input[type=radio]"), function (i) { return i.checked; }).map(function (i) { return i.dataset.label; }).join("+"); };
  var st = document.getElementById("consult-status"), cap = null;
  var has = function (n) { return n.classList.contains("has-answer") ? 1 : 0; };
  Object.defineProperty(navigator, "clipboard", { configurable: true,
    value: { writeText: function (s) { cap = s; return Promise.resolve(); } } });
  var copy = function () { cap = null; document.getElementById("consult-copy").click(); return (cap || "NONE").replace(/[|<>\n]/g, " "); };
  var ph = location.search.match(/phase=(\w+)/); ph = ph ? ph[1] : "";
  if (ph === "reload" || ph === "formrestore" || ph === "notnow") {
    document.title = "L700R|P1=" + checked(p1) + "|P2=" + checked(p2) + "|HAS1=" + has(p1) + "|STAT=" + st.textContent + "|REPLY=" + copy() + "|";
    return;
  }
  var fire = function (el) { el.dispatchEvent(new Event("change", { bubbles: true })); };
  var live = p1.querySelectorAll("input[type=radio]:disabled").length === 0 ? 1 : 0;
  var pre = checked(p1);
  var stat0 = st.textContent, r0 = copy();
  radio(p1, "No").checked = true; fire(radio(p1, "No"));
  var h1 = has(p1), statChanged = st.textContent, r1 = copy();
  radio(p1, "Si").checked = true; fire(radio(p1, "Si"));
  var h2 = has(p1), statBack = st.textContent, r2 = copy();
  radio(p1, "No").checked = true; fire(radio(p1, "No"));
  var lab2 = radio(p2, "Si").parentNode;
  lab2.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }));
  radio(p2, "Si").click();
  var confirmKept = radio(p2, "Si").checked ? 1 : 0;
  document.title = "L700|CONFIRM=" + confirmKept + "|LIVE=" + live + "|PRE=" + pre + "|STAT0=" + stat0 + "|R0=" + r0
    + "|H1=" + h1 + "|STATCH=" + statChanged + "|R1=" + r1
    + "|H2=" + h2 + "|STATBACK=" + statBack + "|R2=" + r2 + "|";
});</script>
PROBE
} > "$L700/body.html"
bash "$WRAP" --title "l700" --lang es --out "$TMP/reports/l700.html" < "$L700/body.html" > "$L700/wrap.log" 2>&1 \
  || fail "BL-700: the live-proposal probe failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$L700/wrap.log" | sed -n 1,4p)"
rm -rf "$TMP/profile"
CHROME_WINDOW=1280,900 chrome_dump "$L700/dom.html" "file://$TMP/reports/l700.html" 45 || true
tl="$(grep -oE '<title>[^<]*</title>' "$L700/dom.html" | sed -n 1p)"
[[ "$tl" == *"|LIVE=1|PRE=Si|"* ]] \
  || fail "BL-700: a proposal's radios must be live with the proposed option pre-selected (want LIVE=1|PRE=Si): $tl"
[[ "$tl" == *"|R0=NONE|"* && "$tl" == *"|STAT0=Quedan puntos decididos por confirmar o corregir|"* ]] \
  || fail "BL-700: an untouched proposal must send nothing and stay pending (want R0=NONE and 'Quedan puntos...'): $tl"
[[ "$tl" == *"|H1=1|"* && "$tl" == *"|R1="*"### P1"*"- No"* && "$tl" != *"|R1="*"### P2"* ]] \
  || fail "BL-700: a changed selection on a proposal must reach the reply as '### P1' with '- No' (and not P2), and read as answered: $tl"
[[ "$tl" == *"|STATCH="*"1 corrección lista para copiar|"* ]] \
  || fail "BL-700: a changed selection must count as a correction in the status line: $tl"
[[ "$tl" == *"|H2=0|"* && "$tl" == *"|R2=NONE|"* && "$tl" == *"|STATBACK=Quedan puntos decididos por confirmar o corregir|"* ]] \
  || fail "BL-700: changing back to the proposed option must return the item to the unchanged case (nothing sent, pending): $tl"
# Reload on the same profile: the changed selection comes back as a change; the baseline is not an answer.
CHROME_WINDOW=1280,900 chrome_dump "$L700/dom2.html" "file://$TMP/reports/l700.html?phase=reload" 45 || true
tl2="$(grep -oE '<title>[^<]*</title>' "$L700/dom2.html" | sed -n 1p)"
[[ "$tl2" == *"|P1=No|P2=Si|HAS1=1|"* && "$tl2" == *"|REPLY="*"### P1"*"- No"* && "$tl2" != *"|REPLY="*"### P2"* ]] \
  || fail "BL-700: a changed proposal selection must survive a reload (and copy as '### P1' with '- No', not P2) while the untouched P2 keeps only its pre-selected Si: $tl2"
[[ "$tl" == *"|CONFIRM=1|"* ]] \
  || fail "BL-700: clicking the already-checked proposed radio is the reader confirming it and must keep it checked (releasableRadios must not release a proposal): $tl"
# Same-tab reload: the browser restores the reader's "No" into the form BEFORE the composer runs.
rm -rf "$TMP/profile"
CHROME_WINDOW=1280,900 chrome_dump "$L700/dom3.html" "file://$TMP/reports/l700.html?phase=formrestore" 45 || true
tl3="$(grep -oE '<title>[^<]*</title>' "$L700/dom3.html" | sed -n 1p)"
[[ "$tl3" == *"|P1=No|"*"|HAS1=1|"* && "$tl3" == *"|REPLY="*"### P1"*"- No"* ]] \
  || fail "BL-700: a selection the browser restored into the form before the composer ran is the reader's change, not the proposed baseline (want P1=No, has-answer, '### P1' + '- No' in the reply): $tl3"
# A stored [not-now] (no such option on the proposal) must not clear the proposed option.
rm -rf "$TMP/profile"
CHROME_WINDOW=1280,900 chrome_dump "$L700/dom4.html" "file://$TMP/reports/l700.html?phase=notnow" 45 || true
tl4="$(grep -oE '<title>[^<]*</title>' "$L700/dom4.html" | sed -n 1p)"
[[ "$tl4" == *"|P1=Si|P2=Si|HAS1=0|"* ]] \
  || fail "BL-700: a stored selection matching no option of the proposal must leave the proposed Si checked: $tl4"

# ---- BL-701: each block's own notes box reaches the reply under the block's `## ` heading ----
# Free text exists at three levels (page, block, item); the block level had no box. Layer: browser,
# because what the copied reply carries, what counts as "something to copy" and what a reload gives
# back are the composer's calls. Newlines are shown as "~" in the probe's title.
L701="$TMP/l701"; mkdir -p "$L701"
{
  printf '%s\n' '<meta name="consult-visual" content="none: a layout probe, nothing to draw">' \
    '<div class="page"><main class="main"><header><p class="eyebrow">PROBE</p><h1>Block notes</h1></header>' \
    '<section id="sec-ask"><div class="sec-head"><h2>Questions</h2></div>'
  for g in "G1 Uno Q1" "G2 Dos Q2"; do
    set -- $g
    printf '<section class="consult-group" id="%s" data-id="%s" data-title="%s"><p>Contexto</p>\n' "$1" "$1" "$2"
    printf '<section class="consult-item" data-id="%s" data-title="Pregunta %s"><h3><span class="consult-id">%s</span>Pregunta?</h3>\n<div class="opts one"><label><input type="radio" name="%s" data-label="Si"><span>Si</span></label><label><input type="radio" name="%s" data-label="No"><span>No</span></label></div>\n<p class="fieldlabel">Notas sobre esto</p><textarea></textarea></section>\n' "$3" "$3" "$3" "$3" "$3"
    printf '<div class="group-notes"><p class="fieldlabel">Notas de este bloque</p><textarea></textarea></div>\n</section>\n'
  done
  printf '%s\n' '<div class="endbar"><button type="button" id="consult-copy-end">Copy</button><span class="consult-status" id="consult-status-end"></span></div>' \
    '<section class="consult-item consult-notes" data-id="notes" data-title="Notas generales"><h3>Notas generales</h3><p class="fieldlabel">Notas de la p&aacute;gina</p><textarea></textarea></section>' \
    '</section></main><aside class="rail"><p class="railhead">Contenido</p><nav class="raillist" id="raillist"></nav>' \
    '<div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div></aside></div>'
  cat <<'PROBE'
<script>/* Runs BEFORE the composer. spent: a block note stored as SENT in an earlier round.
   * formrestore: the browser put the text into the box on a same-tab reload before the composer ran. */
(function () {
  var q = location.search;
  if (q.indexOf("phase=spent") > -1) localStorage.setItem("aidex-kit-answers:" + location.pathname,
    JSON.stringify({ "group:G1": { a: ["ya enviada"], r: "0", x: 1 }, "group:G2": { a: ["sin enviar"], r: "0" } }));
  if (q.indexOf("phase=formrestore") > -1) document.querySelector('#G2 .group-notes textarea').value = "del navegador";
  /* settled: G1's items are all decided (page l701s). renamed: G2's stored note carries another title's hash. */
  if (q.indexOf("phase=settled") > -1) localStorage.setItem("aidex-kit-answers:" + location.pathname,
    JSON.stringify({ "group:G1": { a: ["vieja"], r: "0" } }));
  if (q.indexOf("phase=partial") > -1) localStorage.setItem("aidex-kit-answers:" + location.pathname,
    JSON.stringify({ "group:G1": { a: ["viva"], r: "0" } }));
  if (q.indexOf("phase=renamed") > -1) localStorage.setItem("aidex-kit-answers:" + location.pathname,
    JSON.stringify({ "group:G2": { a: ["bajo otro nombre"], h: "deadbeef" } }));
})();</script>
<script>window.addEventListener("load", function () {
  var box = function (g) { return document.querySelector("#" + g + " .group-notes textarea"); };
  var cap = null;
  Object.defineProperty(navigator, "clipboard", { configurable: true,
    value: { writeText: function (s) { cap = s; return Promise.resolve(); } } });
  var copy = function () { cap = null; document.getElementById("consult-copy").click(); return (cap || "NONE").replace(/\n/g, "~").replace(/[|<>]/g, " "); };
  var type = function (el, v) { el.value = v; el.dispatchEvent(new Event("input", { bubbles: true })); };
  var ph = location.search.match(/phase=(\w+)/); ph = ph ? ph[1] : "";
  if (ph === "notesset") {
    type(document.querySelector(".consult-notes textarea"), "nota general");
    document.title = "L701N|SET|";
    return;
  }
  if (ph) {
    document.title = "L701R|G1=" + box("G1").value + "|G2=" + box("G2").value + "|G1OFF=" + (box("G1").disabled ? 1 : 0) + "|REPLY=" + copy() + "|";
    return;
  }
  var r0 = copy();
  type(box("G1"), "   ");
  var rBlank = copy();
  type(box("G1"), "nota uno");
  var rOnly = copy();
  var q2 = document.querySelector('[data-id="Q2"] input[data-label="No"]');
  q2.checked = true; q2.dispatchEvent(new Event("change", { bubbles: true }));
  var rBoth = copy();
  var q1 = document.querySelector('[data-id="Q1"] input[data-label="Si"]');
  q1.checked = true; q1.dispatchEvent(new Event("change", { bubbles: true }));
  type(box("G2"), "nota dos");
  var rAll = copy();
  document.title = "L701|LAB=" + document.querySelectorAll(".group-notes .fieldlabel").length
    + "|R0=" + r0 + "|RBLANK=" + rBlank + "|RONLY=" + rOnly + "|RBOTH=" + rBoth + "|RALL=" + rAll + "|";
});</script>
PROBE
} > "$L701/body.html"
bash "$WRAP" --title "l701" --lang es --out "$TMP/reports/l701.html" < "$L701/body.html" > "$L701/wrap.log" 2>&1 \
  || fail "BL-701: the block-notes probe failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$L701/wrap.log" | sed -n 1,4p)"
rm -rf "$TMP/profile"
CHROME_WINDOW=1280,900 chrome_dump "$L701/dom.html" "file://$TMP/reports/l701.html" 45 || true
t1="$(grep -oE '<title>[^<]*</title>' "$L701/dom.html" | sed -n 1p)"
[[ "$t1" == *"|R0=NONE|RBLANK=NONE|"* ]] \
  || fail "BL-701: empty and whitespace-only block notes must add nothing (want R0=NONE|RBLANK=NONE): $t1"
[[ "$t1" == *"|RONLY=## G1 · Uno~~nota uno|"* ]] \
  || fail "BL-701: a block note with no answered item must still be sendable, under the block's heading and with no ### block (want 'RONLY=## G1 · Uno~~nota uno'): $t1"
[[ "$t1" == *"|RBOTH=## G1 · Uno~~nota uno~~## G2 · Dos~~### Q2 · Pregunta Q2~~- No|"* ]] \
  || fail "BL-701: a note-only block and an answered block must come out in page order, the empty G2 note adding nothing: $t1"
[[ "$t1" == *"|RALL=## G1 · Uno~~nota uno~~### Q1 · Pregunta Q1~~- Si~~## G2 · Dos~~nota dos~~### Q2 · Pregunta Q2~~- No|"* ]] \
  || fail "BL-701: a block note must sit under its '## ' heading, before that block's '### ' items: $t1"
# Reload: the notes come back from storage and are copied again.
CHROME_WINDOW=1280,900 chrome_dump "$L701/dom2.html" "file://$TMP/reports/l701.html?phase=reload" 45 || true
t2="$(grep -oE '<title>[^<]*</title>' "$L701/dom2.html" | sed -n 1p)"
[[ "$t2" == *"|G1=nota uno|G2=nota dos|"* && "$t2" == *"|REPLY=## G1 · Uno~~nota uno~~### Q1"*"## G2 · Dos~~nota dos~~### Q2"* ]] \
  || fail "BL-701: block notes must survive a reload and reach the reply again: $t2"
# Same-tab reload: the browser restored the text into the box before the composer ran, nothing in storage.
rm -rf "$TMP/profile"
CHROME_WINDOW=1280,900 chrome_dump "$L701/dom3.html" "file://$TMP/reports/l701.html?phase=formrestore" 45 || true
t3="$(grep -oE '<title>[^<]*</title>' "$L701/dom3.html" | sed -n 1p)"
[[ "$t3" == *"|G2=del navegador|"* && "$t3" == *"|REPLY=## G2 · Dos~~del navegador|"* ]] \
  || fail "BL-701: a note the browser restored into the box before the composer ran is the reader's own and must be copied: $t3"
# A later round: a note already SENT is not handed back, an unsent one is.
rm -rf "$TMP/profile"
CHROME_WINDOW=1280,900 chrome_dump "$L701/dom4.html" "file://$TMP/reports/l701.html?phase=spent" 45 || true
t4="$(grep -oE '<title>[^<]*</title>' "$L701/dom4.html" | sed -n 1p)"
[[ "$t4" == *"|G1=|G2=sin enviar|"* ]] \
  || fail "BL-701: a block note sent in an earlier round must not come back, an unsent one must (want G1= empty, G2=sin enviar): $t4"
# A block renamed since the note was typed: the stored fingerprint no longer matches, so it is stale.
rm -rf "$TMP/profile"
CHROME_WINDOW=1280,900 chrome_dump "$L701/dom7.html" "file://$TMP/reports/l701.html?phase=renamed" 45 || true
t7="$(grep -oE '<title>[^<]*</title>' "$L701/dom7.html" | sed -n 1p)"
[[ "$t7" == *"|G1=|G2=|G1OFF=0|REPLY=NONE|"* ]] \
  || fail "BL-701: a stored block note whose title fingerprint differs (block renamed) must come back stale, not restored: $t7"
# A block whose items are ALL settled folds away: its stored note is not restored, pasted or editable.
sed 's|data-id="Q1" data-title="Pregunta Q1"|data-id="Q1" data-title="Pregunta Q1" data-decided="Si"|' "$L701/body.html" > "$L701/body-settled.html"
bash "$WRAP" --title "l701s" --lang es --out "$TMP/reports/l701s.html" < "$L701/body-settled.html" > "$L701/wrap-s.log" 2>&1 \
  || fail "BL-701: the settled-block probe failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$L701/wrap-s.log" | sed -n 1,3p)"
rm -rf "$TMP/profile"
CHROME_WINDOW=1280,900 chrome_dump "$L701/dom8.html" "file://$TMP/reports/l701s.html?phase=settled" 45 || true
t8="$(grep -oE '<title>[^<]*</title>' "$L701/dom8.html" | sed -n 1p)"
[[ "$t8" == *"|G1=|"* && "$t8" == *"|G1OFF=1|"* && "$t8" != *"## G1"* && "$t8" != *vieja* ]] \
  || fail "BL-701: a note stored for a block whose items are all settled must not be restored into the hidden box or pasted, and the box is disabled (want G1= empty, G1OFF=1, no '## G1'): $t8"
# A block with one settled item and one OPEN item is still asked: its stored note comes back and is pasted.
perl -0pe 's{(<section class="consult-item" data-id="Q1".*?</section>)}{my $x = $1; $x . ($x =~ s/Q1/Q3/gr =~ s/ data-decided="Si"//r)}se' "$L701/body-settled.html" > "$L701/body-partial.html"
bash "$WRAP" --title "l701p" --lang es --out "$TMP/reports/l701p.html" < "$L701/body-partial.html" > "$L701/wrap-p.log" 2>&1 \
  || fail "BL-701: the partly settled block probe failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$L701/wrap-p.log" | sed -n 1,3p)"
rm -rf "$TMP/profile"
CHROME_WINDOW=1280,900 chrome_dump "$L701/dom9.html" "file://$TMP/reports/l701p.html?phase=partial" 45 || true
t9="$(grep -oE '<title>[^<]*</title>' "$L701/dom9.html" | sed -n 1p)"
[[ "$t9" == *"|G1=viva|"* && "$t9" == *"|G1OFF=0|"* && "$t9" == *"|REPLY=## G1 · Uno~~viva"* ]] \
  || fail "BL-701: a block with one settled and one open item is still asked: its stored note must be restored and pasted (want G1=viva, '## G1 · Uno~~viva'): $t9"
[[ "$t1" == *"|LAB=2|"* ]] \
  || fail "BL-701: each block's notes box carries a visible label (want LAB=2): $t1"
# The page-level label changed wording (BL-701). A general note typed under the OLD label, on a page
# rebuilt at the same path with the new one, is the same question and must come back, not read as stale.
#   composer's old es default (a hand-written page) and spec_build's old es label (a spec-built page).
n=0
for legacy in 'Cualquier cosa que no encaje arriba' 'Lo que no encaja arriba'; do
  n=$((n + 1)); lp="$TMP/reports/l701b$n.html"
  sed "s|Notas de la p&aacute;gina|$legacy|" "$L701/body.html" > "$L701/body-legacy$n.html"
  bash "$WRAP" --title "l701" --lang es --out "$lp" < "$L701/body-legacy$n.html" > "$L701/wrap-b1-$n.log" 2>&1 \
    || fail "BL-701: the legacy-label probe ($legacy) failed to wrap"
  rm -rf "$TMP/profile"
  CHROME_WINDOW=1280,900 chrome_dump "$L701/dom5-$n.html" "file://$lp?phase=notesset" 45 || true
  bash "$WRAP" --title "l701" --lang es --out "$lp" < "$L701/body.html" > "$L701/wrap-b2-$n.log" 2>&1 \
    || fail "BL-701: the rebuilt page failed to wrap"
  CHROME_WINDOW=1280,900 chrome_dump "$L701/dom6-$n.html" "file://$lp?phase=reload" 45 || true
  t6="$(grep -oiE '<title>[^<]*</title>' "$L701/dom6-$n.html" | sed -n 1p)"
  [[ "$t6" == *"|REPLY="*"### notes · Notas generales~~nota general"* ]] \
    || fail "BL-701: a general note typed under the old page label '$legacy' must be restored on the rebuilt page (label reworded, question unchanged): $t6"
done

# ---- BL-690: a row waiting on an open consult item is not settled ----
# The waiting rows ask nothing and are NOT data-decided, so the composer must leave them in their block:
# a block of only waiting rows used to move into the decided section above the open question it waits on.
# The gallery block is written by gallery-items.sh (the CLI reads every depends_on as open), so a generator
# regression (a data-decided on a waiting row) reaches the browser assertions below.
# Layer: browser, because where the block is drawn and which controls are injected are the composer's calls.
WTG="$TMP/wtg"; mkdir -p "$WTG/root/shots"
python3 "$SKILL/tests/png_fixture.py" "$WTG/root/shots/a.png" 16 9
python3 "$SKILL/tests/png_fixture.py" "$WTG/root/shots/b.png" 16 9 96   # the before: differs from a.png, the builder refuses identical pairs
wtg_page() {  # wtg_page <name> <rows json path>; Q14 open in G0, then the generated gallery E
  local n="$1"
  bash "$SKILL/scripts/gallery-items.sh" "$2" --root "$WTG/root" --page "$TMP/reports/$n.html" \
    --group-id E --group-title Revision > "$WTG/$n.gal.html" 2> "$WTG/$n.gal.err" \
    || fail "BL-690: gallery-items failed for $n: $(cat "$WTG/$n.gal.err")"
  {
    printf '%s\n' '<meta name="consult-visual" content="none: a layout probe, nothing to draw">' \
      '<div class="page"><main class="main"><header><p class="eyebrow">PROBE</p><h1>Waiting</h1></header>' \
      '<section id="sec-ask"><div class="sec-head"><h2>Questions</h2></div>'
    printf '<section class="consult-group" data-id="G0" data-title="Decision"><p>Contexto</p>\n'
    item692 Q14 "Forma de Inicio" ''
    printf '</section>\n'
    cat "$WTG/$n.gal.html"
    printf '%s\n' '<div class="endbar"><button type="button" id="consult-copy-end">Copy</button><span class="consult-status" id="consult-status-end"></span></div>' \
      '<section class="consult-item consult-notes" data-id="notes" data-title="Notas generales"><h3>Notas generales</h3><textarea></textarea></section>' \
      '</section></main><aside class="rail"><p class="railhead">Contenido</p><nav class="raillist" id="raillist"></nav>' \
      '<div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div></aside></div>'
    cat <<'PROBE'
<script>window.addEventListener("load", function () {
  var q = document.querySelector('[data-id="Q14"]'), e = document.getElementById("E");
  var sec = document.getElementById("sec-decided");
  var w = document.querySelectorAll("[data-waits-on]");
  var inFold = 0, clear = 0, closed = 0;
  w.forEach(function (n) {
    if (n.closest("details.decided-unit")) inFold++;
    clear += n.querySelectorAll(".consult-clear").length;
    var d = n.querySelector("details.gal-waiting"); if (d && !d.open) closed++;
  });
  document.title = "WTG|WAITING=" + w.length
    + "|INSEC=" + (sec ? sec.querySelectorAll("[data-waits-on]").length : 0)
    + "|INFOLD=" + inFold
    + "|Q14FIRST=" + ((q.compareDocumentPosition(e) & Node.DOCUMENT_POSITION_FOLLOWING) ? 1 : 0)
    + "|CLEAR=" + clear
    + "|Q14CLEAR=" + q.querySelectorAll(".consult-clear").length
    + "|CLOSED=" + closed + "|";
});</script>
PROBE
  } > "$WTG/$n.body.html"
  bash "$WRAP" --title "wtg" --lang es --out "$TMP/reports/$n.html" < "$WTG/$n.body.html" > "$WTG/$n.log" 2>&1 \
    || fail "BL-690: the waiting-row probe $n failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$WTG/$n.log" | sed -n 1,4p)"
  rm -rf "$TMP/profile"
  CHROME_WINDOW=1280,900 chrome_dump "$WTG/$n.dom.html" "file://$TMP/reports/$n.html" 45 || true
  grep -oE '<title>[^<]*</title>' "$WTG/$n.dom.html" | sed -n 1p
}
cat > "$WTG/rows1.json" <<'J'
{"gallery": "audit", "variants": ["light-desktop"], "rows": [
 {"cell": "inicio", "variant": "light-desktop", "kind": "review", "depends_on": "Q14", "look": "El inicio",
  "before": "shots/b.png", "after": "shots/a.png"}]}
J
t1="$(wtg_page wtg1 "$WTG/rows1.json")"
[[ "$t1" == *"|WAITING=1|INSEC=0|INFOLD=0|Q14FIRST=1|CLEAR=0|Q14CLEAR=1|"* ]] \
  || fail "BL-690: a block whose only row waits on Q14 must stay in place after Q14, not move into the decided section, and carry no Limpiar button while Q14 keeps its own (want WAITING=1|INSEC=0|INFOLD=0|Q14FIRST=1|CLEAR=0|Q14CLEAR=1): $t1"
cat > "$WTG/rows2.json" <<'J'
{"gallery": "audit", "variants": ["light-desktop"], "rows": [
 {"cell": "earlier", "variant": "light-desktop", "kind": "review", "decided": "Aprobada", "look": "Antes",
  "before": "shots/b.png", "after": "shots/a.png"},
 {"cell": "loaded", "variant": "light-desktop", "kind": "unrequested", "depends_on": "Q14", "look": "Las filas",
  "before": "shots/b.png", "after": "shots/a.png"}]}
J
t2="$(wtg_page wtg2 "$WTG/rows2.json")"
[[ "$t2" == *"|WAITING=1|INSEC=0|INFOLD=0|Q14FIRST=1|CLEAR=0|Q14CLEAR=1|CLOSED=1|"* ]] \
  || fail "BL-690: beside a row decided in an earlier round, the waiting unrequested row must stay out of the decided section and its fold, as a closed details (want INSEC=0|INFOLD=0|CLOSED=1): $t2"

# ---- C-c08: a short-value box is any text-like <input>, not only a literal type="text" ----
# check_artifact accepts an <input> with no type as an item's reply surface, but the composer read
# only input[type="text"]: a value typed into a typeless or number box was not counted, pasted or
# stored. Layer: browser, because what counts as answered, what the copy carries and what a reload
# gives back are the composer's calls. V3 (type="text") is the control.
SV="$TMP/sv"; mkdir -p "$SV"
{
  printf '%s\n' '<meta name="consult-visual" content="none: a layout probe, nothing to draw">' \
    '<div class="page"><main class="main"><header><p class="eyebrow">PROBE</p><h1>Short values</h1></header>' \
    '<section id="sec-ask"><div class="sec-head"><h2>Questions</h2></div>'
  printf '<section class="consult-group" data-id="G1" data-title="Valores"><p>Contexto</p>\n'
  for v in 'V1|<input name="v1">' 'V2|<input name="v2" type="number">' 'V3|<input name="v3" type="text">'; do
    printf '<section class="consult-item" data-id="%s" data-title="Valor %s" data-free><h3><span class="consult-id">%s</span>Valor?</h3>\n%s\n<p class="fieldlabel">Notas</p><textarea></textarea></section>\n' \
      "${v%%|*}" "${v%%|*}" "${v%%|*}" "${v#*|}"
  done
  printf '</section>\n'
  printf '%s\n' '<div class="endbar"><button type="button" id="consult-copy-end">Copy</button><span class="consult-status" id="consult-status-end"></span></div>' \
    '<section class="consult-item consult-notes" data-id="notes" data-title="Notas generales"><h3>Notas generales</h3><textarea></textarea></section>' \
    '</section></main><aside class="rail"><p class="railhead">Contenido</p><nav class="raillist" id="raillist"></nav>' \
    '<div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div></aside></div>'
  cat <<'PROBE'
<script>window.addEventListener("load", function () {
  var box = function (n) { return document.querySelector('input[name="' + n + '"]'); };
  var has = function (id) { return document.querySelector('[data-id="' + id + '"]').classList.contains("has-answer") ? 1 : 0; };
  var cap = null;
  Object.defineProperty(navigator, "clipboard", { configurable: true,
    value: { writeText: function (s) { cap = s; return Promise.resolve(); } } });
  var copy = function () { cap = null; document.getElementById("consult-copy").click(); return (cap || "NONE").replace(/[|<>]/g, " ").replace(/\n/g, "~"); };
  if (location.search.indexOf("phase=reload") === -1) {
    [["v1", "42"], ["v2", "7"], ["v3", "hola"]].forEach(function (p) {
      box(p[0]).value = p[1]; box(p[0]).dispatchEvent(new Event("input", { bubbles: true }));
    });
  }
  document.title = "SV|VALS=" + box("v1").value + "/" + box("v2").value + "/" + box("v3").value
    + "|HAS=" + has("V1") + has("V2") + has("V3")
    + "|STAT=" + document.getElementById("consult-status").textContent + "|REPLY=" + copy() + "|";
});</script>
PROBE
} > "$SV/body.html"
bash "$WRAP" --title "sv" --lang es --out "$TMP/reports/sv.html" < "$SV/body.html" > "$SV/wrap.log" 2>&1 \
  || fail "C-c08: the short-value probe failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$SV/wrap.log" | sed -n 1,4p)"
rm -rf "$TMP/profile"
chrome_dump "$SV/dom.html" "file://$TMP/reports/sv.html" 45 || true
tsv="$(grep -oE '<title>[^<]*</title>' "$SV/dom.html" | sed -n 1p)"
[[ "$tsv" == *"|HAS=111|"* && "$tsv" == *"|REPLY="*"### V1"*"42"*"### V2"*"7"*"### V3"*"hola"* ]] \
  || fail "C-c08: a value typed into a typeless or number <input> must make its item answered and reach the reply like a type=\"text\" one (want HAS=111 and V1 42, V2 7, V3 hola in REPLY): $tsv"
chrome_dump "$SV/dom2.html" "file://$TMP/reports/sv.html?phase=reload" 45 || true
tsv2="$(grep -oE '<title>[^<]*</title>' "$SV/dom2.html" | sed -n 1p)"
[[ "$tsv2" == *"|VALS=42/7/hola|HAS=111|"* ]] \
  || fail "C-c08: a value typed into a typeless or number <input> must survive a reload like a type=\"text\" one (want VALS=42/7/hola|HAS=111): $tsv2"

[[ "$failures" -eq 0 ]] || { echo "$failures failure(s)"; exit 1; }
echo "OK — type, reload, restore proven in a real engine; rounds, sent answers, per-item clear, the recommendation badge, the item count, the releasable radio, the injected other, the not-now choice, the multi-select item built from a spec, the ask row and the provisional state, the explicit theme, v4 answer sets, the all-decided page, the half-answered block, the gallery zoom dialog with its keyboard walk, the block filters that never reach the paste, the light/dark compare with its slider kept out of the paste, and the localised chrome included"
