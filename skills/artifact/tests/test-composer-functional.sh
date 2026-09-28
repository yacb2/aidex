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
# tall the BL-326 spy cell reads BOTTOM=#Q2). Same default viewport on both.
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
    document.title = 'SPY|TOP=' + atTop + '|BOTTOM=' + atBottom
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
      + '|AFTERNOTES=' + st1.replace(/[|<>]/g, ' ')
      + '|DECIDED=' + document.querySelectorAll('.consult-item[data-decided]').length
      + '|OPEN=' + document.querySelectorAll('.consult-item:not([data-decided])').length
      + '|BARH=' + (barH > 0 ? '1' : '0')
      + '|BARDISP=' + (bar ? getComputedStyle(bar).display : 'none')
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
        exQuestion = ask('[question]'), exReframe = ask('[reframe]'), exShow = ask('[show-me]');
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
      + '|CHIPS=' + [exState, exOpts, exWhy, exSimpler, exQuestion, exReframe, exShow].filter(Boolean).length
      + '|TERMCHIP=' + (row && row.querySelector('input[data-label="[explain-term]"]') ? '1' : '0')
      + '|TERMBOX=' + document.querySelectorAll('[data-id="Q1"] .kit-term').length
      + '|PROVBEFORE=' + provBefore + '|PROVON=' + provOn + '|PROVOFF=' + provOff
      + '|PROVTEXT=' + provText
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
    || { fail "the probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/wrap.log" | head -4)"; echo "1 failure(s)"; exit 1; }
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
# Q0 is a DECIDED item: it leaves the question set but stays in the rail, which
# is the index of the page and not a list of what is still owed. Q0 is decided,
# so since v18 (BL-380) it has no entry of its own: the block is the way in.
[[ "$t" == *"RAIL_ORDER=sec:#sec-ask,G:#G1,sub:#Q1,sub:#Q2,item:#notes"* ]] \
  || fail "BL-247: the rail does not nest the block's items under the block (context once, decisions indented, loose notes after): $t"
# The trap: a fingerprint over the item's RAW textContent would include this
# text, so a plain reload with no regeneration would already fail to match.
[[ "$t" == *"CE=typed-into-contenteditable-789"* ]] \
  || fail "text typed into a contenteditable did not survive the reload: $t"

# ---- BL-326: the rail says where the reader is, and keeps it in view --------
# Its own variable, not $t: the assertions below this block read the title of
# the `phase=verify` run above, so reusing $t here silently retargets five
# localisation checks at this page instead.
ts="$(run 'phase=spy')"
[[ "$ts" == *SPY* ]] || fail "the spy phase did not run: $ts"
[[ "$ts" == *"TOP=#sec-ask"* ]] \
  || fail "BL-326: nothing was marked current at the top of the page: $ts"
[[ "$ts" == *"BOTTOM=#notes"* ]] \
  || fail "BL-326: the current entry did not follow the page to its last section: $ts"
# The half that makes the cap survivable: a marked entry the reader cannot see
# inside a now-scrollable rail is the original complaint moved indoors.
[[ "$ts" == *"VIS=1"* ]] \
  || fail "BL-326: the current entry was outside the rail's visible box: $ts"
[[ "$ts" == *"BACK=#sec-ask"* ]] \
  || fail "BL-326: scrolling back up did not move the current entry back: $ts"

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

wrap_page                                   # same content, new round
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
wrap_page                                   # a new round arrives with the upgrade
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
[[ "$t" == *"CHIPS=7"* ]] \
  || fail "BL-381 + census 2026-09-20: the ask row does not carry the seven tagged asks (state, options, why, simpler, question, reframe, show-me): $t"
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
wrap_page                                   # same content, new round
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
# The bar stays. Measured as a real box, not as an attribute: at the harness
# width the rail collapses to a bottom bar, and a display-only assertion would
# pass on a bar of zero height.
[[ "$td" == *"BARH=1"* ]] \
  || fail "BL-341: the copy bar was hidden on an all-decided page — the notes box is no longer sendable: $td"
[[ "$td" == *"ENDH=1"* ]] \
  || fail "BL-341: the end-of-page copy bar was hidden on an all-decided page: $td"

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
  || fail "the surfaces probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/swrap.log" | head -4)"
srun() {  # srun <query>
  chrome_dump "$TMP/sdom.html" "file://$SPAGE?$1" 45 || true
  grep -oE '<title>[^<]*</title>' "$TMP/sdom.html" | head -1
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
      + '|DOWN=' + down1 + '|DOWNEND=' + down2 + '|UP=' + up1 + '|UPEND=' + up2 + '|RIGHT3=' + right3.trim() + '/' + (right3 === right3.trim() ? 'clean' : 'raw')
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
        + '|PETILE=' + peTile + '|TILEZOOM=' + tileZoom;
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
        'notes': { a: ['general from phase 3'], h: 'd6d63aa3' }
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
  || fail "the gallery probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap.log" | head -4)"
grun() {  # grun <query>
  chrome_dump "$TMP/gdom.html" "file://$GPAGE?$1" 45 || true
  grep -oE '<title>[^<]*</title>' "$TMP/gdom.html" | head -1
}
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
  || fail "the decided gallery probe failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-d.log" | head -4)"
chrome_dump "$TMP/gdom-d.html" "file://$GPAGE_D?phase=gdecided" 45 || true
tg="$(grep -oE '<title>[^<]*</title>' "$TMP/gdom-d.html" | head -1)"
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
  || fail "the unnamed-blocks probe failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-u.log" | head -4)"
rm -rf "$TMP/profile"
chrome_dump "$TMP/gdom-u.html" "file://$GPAGE_U?phase=gunset" 45 || true
tg="$(grep -oE '<title>[^<]*</title>' "$TMP/gdom-u.html" | head -1)"
[[ "$tg" == *"GUNSET|N=2|M0=light|M1=both"* ]] \
  || fail "the unnamed-blocks probe did not filter the first block alone: $tg"
chrome_dump "$TMP/gdom-u.html" "file://$GPAGE_U?phase=gunget" 45 || true
tg="$(grep -oE '<title>[^<]*</title>' "$TMP/gdom-u.html" | head -1)"
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
  || fail "the marks probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-m.log" | head -4)"
mrun() {  # mrun <page> <query>
  chrome_dump "$TMP/gdom-m.html" "file://$1?$2" 45 || true
  grep -oE '<title>[^<]*</title>' "$TMP/gdom-m.html" | head -1
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
b64="$(grep -oE 'data-paste="[^"]*"' "$TMP/gdom-m.html" | head -1 | sed -E 's/^data-paste="(.*)"$/\1/')"
printf '%s' "$b64" | base64 -d > "$TMP/gmarks-paste.txt" 2>/dev/null
printf '%s\n' '## E · The matrix' '' '### audit-with-data · audit · with-data' '' '- Needs changes' '' \
  'la fila se ve bien' '' \
  '[mark light-desktop 12.5,34.0 40.0x10.5] the breadcrumb wraps under the title' \
  '[mark light-desktop 0.0,0.0 25.0x25.0] the logo is cut' > "$TMP/gmarks-want.txt"
# The paste has no trailing newline; the expectation file does.
printf '\n' >> "$TMP/gmarks-paste.txt"
cmp -s "$TMP/gmarks-paste.txt" "$TMP/gmarks-want.txt" \
  || fail "the paste with two marks is not the verdict, the notes and one contract line per mark under the row heading: $(diff "$TMP/gmarks-want.txt" "$TMP/gmarks-paste.txt" | head -12)"

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

# A round that RE-CAPTURES a tile is a new question for the row (marks are
# answers, and the question-hash covers the tiles' image src): the unsent
# marks of the old capture must not come back onto a different screenshot.
# Same profile as gmedge, which left two marks on light-desktop.
PX="$PX" perl -0pe 's{(<figure data-tile="light-desktop"><img src=")[^"]*(" alt="with-data light-desktop")}{$1$ENV{PX}$2}' \
  "$TMP/gbody-marks.html" > "$TMP/gbody-marks-recap.html"
bash "$WRAP" --title "gallery" --lang es --out "$GPAGE_M" < "$TMP/gbody-marks-recap.html" > "$TMP/gwrap-mr.log" 2>&1 \
  || fail "the re-captured marks probe failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-mr.log" | head -4)"
tg="$(mrun "$GPAGE_M" 'phase=gmrecall')"
[[ "$tg" == *"GMRECALL|TILE=0"* && "$tg" == *"DLG=0"* && "$tg" != *"[mark"* ]] \
  || fail "marks drawn on the old capture came back onto a re-captured tile: $tg"
bash "$WRAP" --title "gallery" --lang es --out "$GPAGE_M" < "$TMP/gbody-marks.html" > "$TMP/gwrap-m.log" 2>&1 \
  || fail "the marks probe page failed to re-wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-m.log" | head -4)"

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
  || fail "the contenteditable marks probe failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-mc.log" | head -4)"
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
  || fail "the decided marks probe failed to wrap (a hidden kit-marks textarea beside the notes box must pass): $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-md.log" | head -4)"
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
  || fail "the pair probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-p.log" | head -4)"
rm -rf "$TMP/profile"
chrome_dump "$TMP/gdom-p.html" "file://$GPAGE_P" 45 || true
tg="$(grep -oE '<title>[^<]*</title>' "$TMP/gdom-p.html" | head -1)"
[[ "$tg" == *GPAIR* ]] || fail "the pair probe did not run: $tg"
[[ "$tg" == *"PAIR=2up/empty after"* ]] \
  || fail "compare on a before tile did not pair it with the row's after: $tg"
[[ "$tg" == *"LONE=disabled"* ]] \
  || fail "a new-screen row's lone capture offers a compare it has nothing for: $tg"
[[ "$tg" == *"BARS=0"* ]] \
  || fail "a before/after review block got the light/dark filter toolbar: $tg"

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
  || fail "the sample probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/gwrap-s.log" | head -4)"
rm -rf "$TMP/profile"
chrome_dump "$TMP/gdom-s.html" "file://$GPAGE_S" 45 || true
tg="$(grep -oE '<title>[^<]*</title>' "$TMP/gdom-s.html" | head -1)"
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
  pick('Dos', true);
  var afterDos = state();
  pick('Dos', false);
  document.title = 'MANY|TYPES=' + types.join(',')
    + '|ORDER=' + (order ? '1' : '0')
    + '|OTHER=' + withOther + '|NOTNOW=' + afterNotNow + '|DOS=' + afterDos
    + '|STATUS=' + document.getElementById('consult-status').textContent.replace(/[|<>]/g, ' ')
    + '|PASTE=' + paste.replace(/[|<>\n]/g, ' ');
});
</script>
HTML
MPAGE="$TMP/reports/many.html"
bash "$WRAP" --title "many" --lang es --out "$MPAGE" < "$TMP/mbody.html" > "$TMP/mwrap.log" 2>&1 \
  || fail "BL-454: the select=many probe page failed to wrap: $(grep -E '^  (FAIL|NOTE)' "$TMP/mwrap.log" | head -4)"
rm -rf "$TMP/profile"
chrome_dump "$TMP/mdom.html" "file://$MPAGE" 45 || true
tm="$(grep -oE '<title>[^<]*</title>' "$TMP/mdom.html" | head -1)"
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
  grep -oE '<title>[^<]*</title>' "$TMP/idom.html" | head -1
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
tp="$(grep -oE '<title>[^<]*</title>' "$TMP/pdom.html" | head -1)"
[[ "$tp" == *"PROSE|p-direct=15.2px,p-wrapped=15.2px,p-li=15.2px,p-note=13.12px,p-label=11.52px<"* ]] \
  || fail "text-style-drift: item prose is not one size wherever it sits (or a note/label lost its own size): $tp"
rm -rf "$TMP/profile"

[[ "$failures" -eq 0 ]] || { echo "$failures failure(s)"; exit 1; }
echo "OK — type, reload, restore proven in a real engine; rounds, sent answers, per-item clear, the recommendation badge, the item count, the releasable radio, the injected other, the not-now choice, the multi-select item built from a spec, the ask row and the provisional state, the explicit theme, v4 answer sets, the all-decided page, the half-answered block, the gallery zoom dialog with its keyboard walk, the block filters that never reach the paste, the light/dark compare with its slider kept out of the paste, and the localised chrome included"
