#!/usr/bin/env bash
# Archiving an artifact must take its rendered companions with it — or say so when it cannot.
#
# The regression this locks (BL-234, 2026-08-25): archive-on-close (D-10) exists so that
# inbound `<type>/<filename>` references keep resolving. A rendered companion joins its
# anchor through a `<meta name="artifact-anchor">` in the page, not through the filesystem,
# so `mv` carries only the pages that happen to sit INSIDE a folder that moves. Closing
# `plan/2026-08-22-suite-speed-and-coverage-rollout` moved the plan folder and the two
# companions inside it, and left the third — the plan's own outcomes report — behind in
# `plans/`. `validate.py` reported 0 violations and the regenerated index looked complete;
# it was found by listing the directory by hand.
#
# Single-file artifacts are the worse half: a backlog item's or a single-file plan's
# companion is ALWAYS a sibling, never inside it, so `mv` left every one of them behind.
#
# What this test proves, and what it does not:
#   PROVES  — close-plan.sh, close-item.sh and close-dated-artifact.sh each move the
#             companions anchored to what they archived; a page already carried inside a
#             moved folder is not moved twice; an unrelated page is not swept up; and a
#             companion that cannot be moved is REPORTED rather than silently dropped.
#   DOES NOT — cover close-audit.sh, whose runs are folders whose companions travel with
#             them; the sibling case there is exercised by the same shared helper.
#
# Run with: bash tests/test-archive-moves-companions.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILLS="$SCRIPT_DIR/../skills"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PROJ="$TMP/proj"
CTX="$PROJ/.context"
mkdir -p "$CTX/plans" "$CTX/backlog" "$CTX/requests"

page() {  # $1 = path, $2 = anchor ("" writes no meta)
  mkdir -p "$(dirname "$1")"
  { printf '<!doctype html><meta charset="utf-8"><title>C</title>\n'
    [[ -n "$2" ]] && printf '<meta name="artifact-anchor" content="%s">\n' "$2"
    printf '<h1>C</h1>\n'
  } > "$1"
}
artifact() {  # $1 = path, $2 = extra front-matter lines
  mkdir -p "$(dirname "$1")"
  { printf -- '---\ntitle: "A thing"\nstatus: open\ncreated: 2026-01-01\nupdated: 2026-01-01\n'
    [[ -n "$2" ]] && printf '%s\n' "$2"
    printf -- '---\n\nBody.\n'
  } > "$1"
}

# (a) modular plan: one companion INSIDE the folder, one BESIDE it in plans/
mkdir -p "$CTX/plans/2026-01-01-modular-plan"
artifact "$CTX/plans/2026-01-01-modular-plan/00-index.md" ""
page "$CTX/plans/2026-01-01-modular-plan/inside.html"  "plan/2026-01-01-modular-plan"
page "$CTX/plans/2026-01-01-modular-plan-outcomes.html" "plan/2026-01-01-modular-plan"
# (b) an unrelated page in plans/, anchored elsewhere — must not be swept up
page "$CTX/plans/2026-01-09-unrelated.html" "plan/2026-01-09-some-other-plan"
# (c) backlog item with a sibling companion
artifact "$CTX/backlog/2026-01-02-bl-001-an-item.md" "id: BL-001"$'\n'"priority: P2"$'\n'"type: task"
page "$CTX/backlog/2026-01-02-bl-001-report.html" "backlog/2026-01-02-bl-001-an-item.md"
# (d) request with a sibling companion, plus a name collision already in the archive
artifact "$CTX/requests/2026-01-03-a-request.md" ""
page "$CTX/requests/2026-01-03-a-request-report.html" "request/2026-01-03-a-request"
mkdir -p "$CTX/requests/_archive"
printf 'an older page that already owns this name\n' \
  > "$CTX/requests/_archive/2026-01-03-a-request-report.html"

cd "$PROJ" || exit 1
bash "$SKILLS/aidex-plan/scripts/close-plan.sh" 2026-01-01-modular-plan --status done \
  >/dev/null 2>&1
bash "$SKILLS/aidex-backlog/scripts/close-item.sh" BL-001 --status done >/dev/null 2>&1
REQ_OUT="$(bash "$SKILLS/aidex-conventions/scripts/close-dated-artifact.sh" \
  requests 2026-01-03-a-request --status done 2>&1)"

# ---------- (1) a companion BESIDE a modular plan follows it into the archive ----------
[[ -f "$CTX/plans/_archive/2026-01-01-modular-plan-outcomes.html" ]] \
  || fail "(1) the companion beside the modular plan was left in plans/ — this is the exact orphan BL-234 was filed for"
[[ ! -f "$CTX/plans/2026-01-01-modular-plan-outcomes.html" ]] \
  || fail "(1b) the companion was copied rather than moved — plans/ still holds the original"

# ---------- (2) a companion INSIDE the folder travelled with it, and only once ----------
[[ -f "$CTX/plans/_archive/2026-01-01-modular-plan/inside.html" ]] \
  || fail "(2) the companion inside the plan folder is gone — a page that already travelled must be left alone, not moved again"

# ---------- (3) an unrelated page is not swept up ----------
[[ -f "$CTX/plans/2026-01-09-unrelated.html" ]] \
  || fail "(3) a page anchored to a DIFFERENT plan was archived — the sweep must join on the anchor, not on living in the same folder"

# ---------- (4) a single-file artifact's sibling companion follows it ----------
[[ -f "$CTX/backlog/_archive/2026-01-02-bl-001-report.html" ]] \
  || fail "(4) the backlog item's companion stayed in backlog/ — a single-file artifact's companion is always a sibling, so mv alone never carries it"

# ---------- (5) a companion that cannot move is REPORTED, and the close still succeeds ----------
[[ -f "$CTX/requests/_archive/2026-01-03-a-request.md" ]] \
  || fail "(5) the request was not archived — a companion that cannot move must never fail a close that already happened"
if ! grep -qi "companion left behind" <<<"$REQ_OUT"; then
  fail "(5b) a companion blocked by a name collision was dropped silently — the item asks for the move OR for it to say out loud that it did not: got: $REQ_OUT"
fi
[[ -f "$CTX/requests/2026-01-03-a-request-report.html" ]] \
  || fail "(5c) the blocked companion vanished — reporting it must not also destroy it"
grep -q "an older page" "$CTX/requests/_archive/2026-01-03-a-request-report.html" \
  || fail "(5d) the pre-existing archived page was overwritten — a collision must never clobber"

# ---------- (6) an anchor cannot inject a second field and steer the move ----------
# scan_artifact_anchors emits "<anchor>\t<path>", and the anchor is arbitrary text read
# out of a page. A TAB inside content="…" shifts the fields, so companions_of prints the
# injected text instead of the real path and `mv` acts on it. Verified 2026-08-25:
# content="plan/x<TAB>../outside.txt" made companions_of return `../outside-the-context.txt`,
# a path outside `.context/` entirely. A newline injects a whole fake record the same way.
# Not only a security bug — a stray control character silently corrupts the stream.
LIB="$SKILLS/aidex-conventions/scripts/_lib.sh"
INJ="$TMP/inject"; mkdir -p "$INJ/.context/plans"
printf 'a file that lives outside .context/
' > "$INJ/outside-the-context.txt"
printf '<meta name="artifact-anchor" content="plan/x	../outside-the-context.txt">
'   > "$INJ/.context/plans/tab.html"
printf '<meta name="artifact-anchor" content="plan/x
../outside-the-context.txt	plan/x">
'   > "$INJ/.context/plans/newline.html"
got="$(bash -c '. "$1"; companions_of "$(scan_artifact_anchors "$2/.context")" "plan/x"'         _ "$LIB" "$INJ" 2>/dev/null)"
if [[ -n "$got" ]]; then
  fail "(6) a control character in an anchor steered the companion stream: companions_of returned [$got] — an anchor must be validated to the <type>/<filename> shape before it is emitted"
fi

if [[ $failures -eq 0 ]]; then
  echo "OK: closes carry their companions into _archive/, skip pages that already travelled, report the ones they cannot move, and refuse anchors that try to steer the move"
  exit 0
fi
printf '\n%d assertion(s) failed\n' "$failures"
exit 1
