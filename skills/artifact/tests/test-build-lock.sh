#!/usr/bin/env bash
# test-build-lock.sh — while an agent is still writing a page, the page carries a
# build lock at `.aidex-artifact-prev/<page>.building`, and `artifact-open-once.sh`
# refuses to open it (the hook's own half is in hooks/test-artifact-open-once.py).
#
# The incident (.context/research/2026-09-20-artifact-seen-before-the-agent-finishes.md):
# an artifact agent writes its final `--out` path two or three times mid-run, so a
# file watcher fires while it is still working — and the INTERMEDIATE wrap passes the
# contract, which is why nothing already here could catch it. The main session opened
# the page 1 min 41 s before the hand-back.
#
# Why the lock is opt-in (`--building`) rather than written by every wrap: the
# ordinary path is a session wrapping its own page and opening it in the same breath.
# A lock on by default would block that, i.e. the guard would misfire on its most
# common input — the failure that unwired three of this repo's four hooks. Only a
# delegated build passes the flag.
#
# Why the flag rides on EVERY wrap of the build and not on the first one only: the
# agent cannot be trusted to remember a first step either, and the lock has to be
# fresh (< 20 min) at the moment the page is opened. `--done` is the single last
# step, and a forgotten one costs at most one stale window, not a permanent block.
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
printf '<div class="page"><main class="main"><h1>Bad</h1><h2>No section</h2></main></div>\n' \
  > "$TMP/bad.html"
PREV="$TMP/reports/.aidex-artifact-prev"
LOCK="$PREV/page.html.building"

# 1. the ordinary wrap is unchanged: no flag, no lock.
bash "$WRAP" --title Probe --lang en --in "$TMP/body.html" --out "$TMP/reports/page.html" \
  >/dev/null 2>"$TMP/err1" || fail "the probe page does not pass the contract: $(tail -3 "$TMP/err1")"
[[ ! -e "$LOCK" ]] && ok "a wrap without --building leaves no lock" \
                   || fail "a plain wrap locked the page"

# 2. --building marks the page as in progress, beside the baseline.
bash "$WRAP" --building --title Probe --lang en --in "$TMP/body.html" \
  --out "$TMP/reports/page.html" >/dev/null 2>&1
[[ -f "$LOCK" ]] && ok "--building writes .aidex-artifact-prev/page.html.building" \
                 || fail "no lock at $LOCK after a --building wrap"

# 3. a FAILING wrap of the same build keeps the lock. The page was rolled back to the
#    previous version, which is exactly the state the reader must not be shown as
#    final — the build is still running.
bash "$WRAP" --building --title Probe --lang en --in "$TMP/bad.html" \
  --out "$TMP/reports/page.html" >/dev/null 2>&1
[[ -f "$LOCK" ]] && ok "a failing wrap of the build keeps the lock" \
                 || fail "the lock was dropped by a failing wrap"

# 4. every wrap REFRESHES it, so a long build never goes stale under its own agent.
touch -t 200001010000 "$LOCK"
bash "$WRAP" --building --title Probe --lang en --in "$TMP/body.html" \
  --out "$TMP/reports/page.html" >/dev/null 2>&1
[[ -n "$(find "$LOCK" -mmin -5 2>/dev/null)" ]] \
  && ok "a later wrap refreshes the lock's age" \
  || fail "the lock kept its old mtime, so a long build blocks nothing"

# 5. --done removes the lock and does NOT re-wrap: no content on stdin, no --title,
#    and the page on disk is byte-for-byte what the last wrap left.
cp "$TMP/reports/page.html" "$TMP/page-before-done.html"
bash "$WRAP" --done --out "$TMP/reports/page.html" >"$TMP/out5" 2>"$TMP/err5"
rc=$?
[[ $rc -eq 0 && ! -e "$LOCK" ]] && ok "--done clears the lock and exits 0" \
  || fail "--done exited $rc / lock still at $LOCK: $(tail -2 "$TMP/err5")"
cmp -s "$TMP/page-before-done.html" "$TMP/reports/page.html" \
  && ok "--done does not touch the page itself" \
  || fail "--done rewrote the page"

# 6. --done on a page that was never locked is a no-op that says so, not an error:
#    the agent must be able to end every build the same way.
bash "$WRAP" --done --out "$TMP/reports/page.html" >/dev/null 2>"$TMP/err6"
[[ $? -eq 0 ]] && ok "--done twice is not an error" || fail "a second --done failed"
grep -qi "no build lock" "$TMP/err6" \
  && ok "and says there was no lock to clear" \
  || fail "a --done with nothing to clear is silent: $(cat "$TMP/err6")"

# 7. --building with no --out has no page to lock. Refuse rather than wrap silently
#    unlocked, which is the one state that looks finished and is not.
printf 'x' | bash "$WRAP" --building --title Probe --lang en >/dev/null 2>"$TMP/err7"
[[ $? -eq 2 ]] && ok "--building without --out is refused" \
               || fail "--building without --out was accepted"

# 8. the hygiene sweep does not call a live page's lock an orphaned baseline. The
#    sweep runs on every wrap, so a false note here is printed on every build.
bash "$WRAP" --building --title Probe --lang en --in "$TMP/body.html" \
  --out "$TMP/reports/page.html" >/dev/null 2>&1
bash "$WRAP" --title Probe --lang en --in "$TMP/body.html" \
  --out "$TMP/reports/other.html" >/dev/null 2>"$TMP/err8"
grep -q "page\.html\.building" "$TMP/err8" \
  && fail "a live page's lock is reported by the sweep: $(grep 'building' "$TMP/err8" | sed -n 1p)" \
  || ok "a fresh lock beside its page is not an orphan"

# 8b. an abandoned lock beside a page that IS there is the other half. Nothing ever
#     removes a lock on its own, and after 20 minutes artifact-open-once.sh stops
#     honouring it — so a lock nobody cleared is state the author has to know about,
#     page or no page. Fresh stays silent (asserted above), stale is reported.
touch -t 200001010000 "$LOCK"
bash "$WRAP" --title Probe --lang en --in "$TMP/body.html" \
  --out "$TMP/reports/other.html" >/dev/null 2>"$TMP/err8b"
note="$(grep "page\.html\.building" "$TMP/err8b" | sed -n 1p)"
[[ "$note" == *"build lock nobody cleared"* && "$note" == *"rm "* ]] \
  && ok "a stale lock beside a live page is reported with its rm" \
  || fail "an abandoned lock on an existing page is invisible: $note"

# 9. a lock beside NO page is the normal shape of a first build: the page does not
#    exist until the first wrap passes, and a first wrap that fails rolls the page
#    off disk while the build carries on. A FRESH lock there is live work, and the
#    sweep runs on every wrap, so reporting it would fire on every failing build.
rm -f "$TMP/reports/page.html"
touch "$LOCK"
bash "$WRAP" --title Probe --lang en --in "$TMP/body.html" \
  --out "$TMP/reports/other.html" >/dev/null 2>"$TMP/err9"
grep -q "page\.html\.building" "$TMP/err9" \
  && fail "a live build with no page yet is reported: $(grep 'building' "$TMP/err9" | sed -n 1p)" \
  || ok "a fresh lock with no page is a build in progress, not residue"

# 10. ...and once it goes stale with no page beside it, nobody is coming back for it:
#     it is leftover state like any other entry, with the rm to run.
touch -t 200001010000 "$LOCK"
bash "$WRAP" --title Probe --lang en --in "$TMP/body.html" \
  --out "$TMP/reports/other.html" >/dev/null 2>"$TMP/err10"
note="$(grep "page\.html\.building" "$TMP/err10" | sed -n 1p)"
[[ "$note" == *"build lock"* && "$note" == *"rm "* ]] \
  && ok "a stale lock whose page is gone is reported with its rm" \
  || fail "the abandoned lock of a deleted page is not reported: $note"

# 11. save-reply.sh refuses while the page is locked (BL-507), but a lock past the
#     stale window is no running build (BL-542): the refusal must say the lock is
#     stale, not that a build is still running, and name the --done that clears it.
#     Same window and bands as artifact-open-once.sh and baseline_hygiene, compared
#     on the float age: a mtime a few minutes ahead is clock skew over a live build,
#     one beyond the whole window is stale, and 1200.6 s is past 20 min. A stale lock
#     dated in the FUTURE is not "older than" anything (BL-562): the message must say
#     which side of the window it fell off.
save_out() { printf 'Q1: ok\n' | bash "$SKILL/scripts/save-reply.sh" "$TMP/reports/page.html" - 2>&1; }
lock_at() {   # lock_at OFFSET_SECONDS: lock mtime = now + offset (negative = past)
  python3 -c 'import os, sys, time; t = time.time() + float(sys.argv[2]); os.utime(sys.argv[1], (t, t))' "$LOCK" "$1"
}
bash "$WRAP" --building --title Probe --lang en --in "$TMP/body.html" --out "$TMP/reports/page.html" >/dev/null 2>&1
for cell in "fresh:running" "300:running" "1150:running" "-1200.6:stale" "1260:stale" \
            "86400:stale" "old:stale"; do
  at="${cell%%:*}" want="${cell##*:}"
  case "$at" in
    fresh) ;;
    old)   touch -t 200001010000 "$LOCK" ;;
    *)     lock_at "$at" ;;
  esac
  out="$(save_out)"; rc=$?
  if [[ $want == stale ]]; then
    [[ $rc -ne 0 && "$out" == *"stale"* && "$out" != *"still running"* \
       && "$out" == *"--done --out"* ]] \
      && ok "save-reply on a lock at $at says it is stale and names --done" \
      || fail "save-reply on a lock at $at should read stale (rc $rc): $out"
    case "$at" in
      -*|old) [[ "$out" == *"older than"* ]] \
                && ok "a past lock at $at is called older than the window" \
                || fail "a past stale lock at $at does not say older than: $out" ;;
      *)      [[ "$out" != *"older than"* && "$out" == *"future"* ]] \
                && ok "a future lock at $at is not called older than anything" \
                || fail "a future-dated lock at $at is called older (BL-562): $out" ;;
    esac
  else
    [[ $rc -ne 0 && "$out" == *"still running"* && "$out" != *"stale"* ]] \
      && ok "save-reply on a lock at $at refuses as a running build" \
      || fail "save-reply on a lock at $at should read still running (rc $rc): $out"
  fi
done

[[ $failures -eq 0 ]] && echo "PASS: build lock" || { echo "FAILED: $failures"; exit 1; }
