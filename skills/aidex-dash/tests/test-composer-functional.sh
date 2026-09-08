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
# $2, when given, is `data-decided` and it is stamped on Q1 AND Q2 — the page
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
    <p class="fieldlabel">Notas sobre esta</p>
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
  <section class="consult-item" data-id="Q2" data-title="The untouched question" $dec>
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
      /* Since v15 the group ends with the explain escape, so "other" is the
       * last ANSWER choice — the row immediately before it — not the last node. */
      + '|OTHERLAST=' + (other && lastLabel && lastLabel.contains(other) ? '1' : '0')
      + '|OTHERBEFOREEX=' + (other && other.closest('label').nextElementSibling
          && other.closest('label').nextElementSibling.classList.contains('kit-explain') ? '1' : '0')
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
    /* BL-325: the reader who cannot answer because the QUESTION is unreadable.
     * Of 26 items in one real round, 12 came back as free text saying some form
     * of "no entiendo bien esta tarea" — the closed-list escape ("Other") only
     * covers "none of these options", never "I cannot tell what is being asked".
     * Probed on Q2, which has NO option group on purpose: an item with no closed
     * list is exactly the one the per-group injection cannot reach.
     *
     * The paste is captured the same way phase=send does it, because the marker
     * travelling back is the whole point — a control the session never sees is
     * a checkbox that does nothing. */
    var exs = document.querySelectorAll('[data-id="Q1"] .opts .kit-explain input');
    var ex = exs[0];            /* [explain-state]   */
    var ex2 = exs[1];           /* [explain-options] */
    /* Pick an ANSWER first, then the escapes: in a radio group each must release
     * whatever was picked — the answer (the point of v15 making it a radio) and
     * each other (the point of v16 making them two). Wanting both gaps closed in
     * one round is not a third answer; it is the mis-shaped item the ceiling
     * covers, so the group's shared "name" has to refuse it. */
    var pre = document.querySelector('[data-id="Q1"] input[data-label="Option A"]');
    if (pre) { pre.checked = true; pre.dispatchEvent(new Event('change', { bubbles: true })); }
    if (ex2) {
      ex2.checked = true;
      ex2.dispatchEvent(new Event('change', { bubbles: true }));
    }
    var preReleased = pre && !pre.checked;
    if (ex) {
      ex.checked = true;
      ex.dispatchEvent(new Event('change', { bubbles: true }));
    }
    var xcap = '';
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: function (s) { xcap = s; return Promise.resolve(); } }
    });
    document.getElementById('consult-copy').click();
    document.title = 'EXPLAINED|EX=' + (ex ? '1' : '0')
      + '|EX2=' + (ex2 ? '1' : '0')
      + '|EXTYPE=' + (ex ? ex.type : '')
      + '|EXNAME=' + (ex ? ex.name : '')
      + '|EX2NAME=' + (ex2 ? ex2.name : '')
      + '|EXRELEASED=' + (preReleased ? '1' : '0')
      + '|EX2RELEASED=' + (ex2 && !ex2.checked ? '1' : '0')
      + '|EXLAST=' + (ex2 && ex2.closest('.opts').lastElementChild === ex2.closest('label') ? '1' : '0')
      + '|EXNOGROUP=' + document.querySelectorAll('[data-id="Q2"] .kit-explain').length
      + '|EXNOTES=' + document.querySelectorAll('.consult-notes .kit-explain').length
      + '|EXCOUNT=' + document.querySelectorAll('.consult-item .kit-explain').length
      + '|EXITEMS=' + document.querySelectorAll('.consult-item').length
      + '|EXTEXT=' + (ex ? ex.closest('label').textContent.replace(/[|<>]/g, ' ').trim() : '')
      + '|EX2TEXT=' + (ex2 ? ex2.closest('label').textContent.replace(/[|<>]/g, ' ').trim() : '')
      + '|PASTE=' + xcap.replace(/[|<>\n]/g, ' ')
      + '|STATUS=' + document.getElementById('consult-status').textContent.replace(/[|<>]/g, ' ');
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
      + '|EXKEPT=' + ((document.querySelector('[data-id="Q1"] .opts .kit-explain input') || {}).checked ? '1' : '0')
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
  || fail "BL-268: the 'other' option is not the last ANSWER choice of its group — since v15 the explain escape follows it, and nothing else may: $t"
[[ "$t" == *"OTHERTEXT=Otra"* ]] \
  || fail "BL-268: the 'other' option is not labelled in the page's language: $t"
[[ "$t" == *"|A=-"* ]] || fail "BL-268: picking 'other' left the recommended option checked too: $t"
# It persists like any other mark, and the paste names it.
t="$(run 'phase=verify')"
[[ "$t" == *"MARK=O"* ]] || fail "BL-268: the 'other' mark did not survive a reload: $t"
t="$(run 'phase=send')"
[[ "$t" == *"- Otra"* ]] || fail "BL-268: the copied reply does not name the 'other' choice: $t"

# ---- BL-325 (v15): "explain this one better" is a CHOICE in the option group -
#
# The escape the closed list already has, for the other failure: not "none of
# these options" but "I cannot answer this as written". v12 put it on the ITEM,
# as a checkbox; the owner asked for it to be "un radio al igual que el resto de
# opciones", and for the general-notes box — which asks nothing — not to carry
# one. Both fall out of ONE change: inject it into every `.opts` group, with the
# group's own input type, and nowhere else. It still travels back as a fixed
# ASCII marker, never a translated label, because the session greps it.
#
# The cost is real and is pinned here too: an item with no option group (Q2)
# loses the escape it had in v12-v14.
rm -rf "$TMP/profile"
write_body "$Q1_V1"
wrap_page
t="$(run 'phase=explain')"
[[ "$t" == *EXPLAINED* ]] || fail "the explain phase did not run: $t"
[[ "$t" == *"EX=1"* && "$t" == *"EX2=1"* ]] \
  || fail "BL-325: the two explain choices were not both injected into the option group: $t"
[[ "$t" == *"EXTYPE=radio"* ]] \
  || fail "BL-325 v15: the explain choice is not a radio in a radio group: $t"
[[ "$t" == *"EXNAME=Q1"* && "$t" == *"EX2NAME=Q1"* ]] \
  || fail "BL-325 v15: an explain choice is not in the group's own radio name, so it cannot be exclusive with the answers: $t"
[[ "$t" == *"EXRELEASED=1"* ]] \
  || fail "BL-325 v15: picking an explain choice left the previous answer selected — asking for a rewrite is not compatible with having answered: $t"
# Q4 (v16): the two marks are exclusive with EACH OTHER too. Asking for the state
# and the alternatives in the same round is not a third answer — it is the
# mis-shaped item d11 caps, and it comes back as a different instrument or as two
# questions. Sharing the group's `name` is the whole enforcement.
[[ "$t" == *"EX2RELEASED=1"* ]] \
  || fail "v16: picking one explain mark left the other one selected — two gaps in one round is the shape the ceiling refuses: $t"
[[ "$t" == *"EXLAST=1"* ]] \
  || fail "BL-325: the explain choices are not the last rows of their group, after the 'other' one: $t"
[[ "$t" == *"EXNOGROUP=0"* ]] \
  || fail "BL-325 v15: an item with no option group still got an explain control: $t"
[[ "$t" == *"EXNOTES=0"* ]] \
  || fail "BL-325 v15: the general-notes item got an explain control — it asks no question to explain: $t"
excount="$(printf '%s' "$t" | sed -nE 's/.*EXCOUNT=([0-9]+).*/\1/p')"
[[ "$excount" == "2" ]] \
  || fail "v16: the option item does not carry exactly the two explain choices ($excount): $t"
[[ "$t" == *"EXTEXT=Explícame primero el estado"* ]] \
  || fail "BL-325: the explain control stayed in English on a lang=es page: $t"
[[ "$t" == *"EX2TEXT=Explícame primero las alternativas"* ]] \
  || fail "v16: the second explain control stayed in English on a lang=es page: $t"
# The marker, under the id it belongs to. Machine-readable is the requirement:
# the reply names WHICH items to rewrite — and since v16 WHICH WAY — so the next
# round rewrites exactly those, in that direction, instead of the whole set.
[[ "$t" == *"### Q1 · The probed question  - [explain-state]"* ]] \
  || fail "BL-325: the copied reply does not carry the picked explain marker under its item's id: $t"
[[ "$t" == *"[explain-options]"* ]] \
  && fail "v16: the paste carries the marker that was NOT picked — the next round would answer the wrong gap: $t"
# Asking for an explanation IS a response — an item left in the blank list would
# tell the reader they still owe an answer to a question they just said they
# cannot read. The denominator is 2, not 3: the general-notes box is not a
# question (C, below).
[[ "$t" == *"STATUS=1 de 2 respondidas"* ]] \
  || fail "BL-325: an item whose only mark is the explain request is still counted blank, or the notes box is still in the denominator: $t"

t="$(run 'phase=verify')"
[[ "$t" == *"EXKEPT=1"* ]] \
  || fail "BL-325: the explain request did not survive a reload in its own round: $t"
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
write_body "$Q1_V1" 'data-decided'
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

[[ "$failures" -eq 0 ]] || { echo "$failures failure(s)"; exit 1; }
echo "OK — type, reload, restore proven in a real engine; rounds, sent answers, per-item clear, the recommendation badge, the item count, the releasable radio, the injected other and the two explain choices, the explicit theme, v4 answer sets, the all-decided page, the half-answered block and the localised chrome included"
