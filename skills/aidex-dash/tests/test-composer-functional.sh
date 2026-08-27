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
write_body() {  # write_body <q1-question-sentence>
cat > "$TMP/body.html" <<HTML
<meta name="consult-visual" content="none: a persistence probe, nothing to draw">
<div class="page">
<main class="main">
<header><p class="eyebrow">PROBE</p><h1>Persistence probe</h1></header>
<section id="sec-ask">
  <div class="sec-head"><h2>Questions</h2></div>
$gopen
  <section class="consult-item" data-id="Q1" data-title="The probed question">
    <h3><span class="consult-id">Q1</span>$1</h3>
    <div class="opts one">
      <label><input type="radio" name="Q1" data-label="Option A" data-recommended><span>Option A <span class="hint">why</span></span></label>
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
$gclose
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
      + '|LABEL=' + btn.textContent;
  } else if (q.indexOf('phase=verify') !== -1) {
    var banner = document.getElementById('consult-restored');
    document.title = 'RESTORED=' + ta.value
      + '|MARK=' + (radio.checked ? 'A' : (document.querySelector('[data-id="Q1"] input[data-label="Option B"]').checked ? 'B' : '-'))
      + '|CE=' + ce.textContent
      + '|BANNER=' + (banner ? '1' : '0')
      + '|NOTE=' + (banner ? banner.textContent.replace(/[|<>]/g, ' ') : '')
      + '|STATUS=' + document.getElementById('consult-status').textContent.replace(/[|<>]/g, ' ')
      + '|BTN=' + document.getElementById('consult-copy').textContent
      + '|RAIL=' + document.querySelector('.railhead').textContent
      + '|ROUND=' + ((document.querySelector('meta[name="consult-round"]') || {}).content || '')
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
[[ "$t" == *"RAIL_ORDER=sec:#sec-ask,G:#G1,sub:#Q1,sub:#Q2,item:#notes"* ]] \
  || fail "BL-247: the rail does not nest the block's items under the block (context once, decisions indented, loose notes after): $t"
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
# BL-247: the pasted reply keeps the block — `## G1 · title` precedes the first
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
[[ "$t" == *"CLEARED=1"* ]] || fail "BL-242: no per-item clear control was injected: $t"
[[ "$t" == *"LABEL=Limpiar"* ]] \
  || fail "BL-242: the clear control stayed in English on a lang=es page: $t"
[[ "$t" == *"|TA=|"* ]] || fail "BL-242: clearing left the textarea filled: $t"
[[ "$t" == *"MARK=-"* ]] \
  || fail "BL-242: clearing did not un-check the radio — the one thing a reader cannot undo by hand: $t"
[[ "$t" == *"persisted-answer-123"* ]] \
  && fail "BL-242: the cleared item is still in localStorage, so it returns on the next reload: $t"

[[ "$failures" -eq 0 ]] || { echo "$failures failure(s)"; exit 1; }
echo "OK — type, reload, restore proven in a real engine; rounds, sent answers, per-item clear, the recommendation badge, v4 answer sets and the localised chrome included"
