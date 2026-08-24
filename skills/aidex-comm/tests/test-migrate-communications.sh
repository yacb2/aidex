#!/usr/bin/env bash
# test-migrate-communications.sh — cells for the legacy-body-filename migrate pass (BL-223).
#
# Lives in tests/ on purpose: run-all.sh's `skills/*/scripts/` globs are underscore-only,
# so a hyphenated test under scripts/ would never run and the suite would report green
# over an unwired guard — the exact blind spot documented in run-all.sh's own header.

set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)/migrate-communications.sh"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$*"; }

# A throwaway project root: .git makes find_project_root stop here.
mk_project() {
  local root; root="$(mktemp -d)"
  mkdir -p "$root/.git" "$root/.context/communications"
  printf '%s' "$root"
}

body() {
  cat <<'EOF'
---
channel: email
direction: received
from: "Ana"
to: "Equipo"
subject: "x"
date: 2026-06-19
status: sent
related: []
created: 2026-06-19
updated: 2026-06-19
---

Body.
EOF
}

# --- Cell 1: legacy names are renamed, in every folder, and reported ---------------
ROOT="$(mk_project)"
mkdir -p "$ROOT/.context/communications/received/2026-06-19-legacy" \
         "$ROOT/.context/communications/sent/2026-06-20-legacy" \
         "$ROOT/.context/communications/meetings/2026-06-21-legacy"
body > "$ROOT/.context/communications/received/2026-06-19-legacy/email.md"
body > "$ROOT/.context/communications/sent/2026-06-20-legacy/conversation.md"
body > "$ROOT/.context/communications/meetings/2026-06-21-legacy/email.md"

OUT="$(cd "$ROOT" && NO_COLOR=1 bash "$SCRIPT" 2>&1)"; RC=$?
[[ $RC -eq 0 ]] || fail "cell 1: expected exit 0, got $RC"
for f in received/2026-06-19-legacy sent/2026-06-20-legacy meetings/2026-06-21-legacy; do
  [[ -f "$ROOT/.context/communications/$f/body.md" ]] \
    || fail "cell 1: $f/body.md was not produced"
done
[[ -f "$ROOT/.context/communications/received/2026-06-19-legacy/email.md" ]] \
  && fail "cell 1: the legacy file survived the rename"
[[ "$(grep -c 'RENAMED' <<<"$OUT")" -eq 3 ]] \
  || fail "cell 1: expected 3 RENAMED lines, got: $OUT"
grep -q '3 file(s) renamed' <<<"$OUT" || fail "cell 1: summary did not report 3 renames: $OUT"
pass "renames email.md and conversation.md across all three folders and reports each"
rm -rf "$ROOT"

# --- Cell 2: never clobbers an existing body.md ------------------------------------
ROOT="$(mk_project)"
E="$ROOT/.context/communications/received/2026-06-19-both"
mkdir -p "$E"
body > "$E/email.md"
printf 'the real body\n' > "$E/body.md"

OUT="$(cd "$ROOT" && NO_COLOR=1 bash "$SCRIPT" 2>&1)"; RC=$?
[[ $RC -eq 1 ]] || fail "cell 2: a refused rename must exit 1, got $RC"
[[ "$(cat "$E/body.md")" == "the real body" ]] || fail "cell 2: existing body.md was overwritten"
[[ -f "$E/email.md" ]] || fail "cell 2: the legacy file was removed despite the refusal"
grep -q 'REFUSED' <<<"$OUT" || fail "cell 2: the refusal was not reported: $OUT"
pass "refuses and reports when body.md already exists, touching neither file"
rm -rf "$ROOT"

# --- Cell 3: leaves canonical trees, attachments and non-entry files alone ---------
ROOT="$(mk_project)"
E="$ROOT/.context/communications/received/2026-06-19-clean"
mkdir -p "$E" "$ROOT/.context/communications/received/not-a-dated-entry"
body > "$E/body.md"
printf 'attachment\n' > "$E/transcript.md"
printf 'html copy\n' > "$E/email.html"
# An undated folder is not an entry folder — out of scope by construction.
printf 'stray\n' > "$ROOT/.context/communications/received/not-a-dated-entry/email.md"

OUT="$(cd "$ROOT" && NO_COLOR=1 bash "$SCRIPT" 2>&1)"; RC=$?
[[ $RC -eq 0 ]] || fail "cell 3: expected exit 0 on a clean tree, got $RC"
grep -q 'no pre-canonical body filenames found' <<<"$OUT" \
  || fail "cell 3: expected a clean report, got: $OUT"
[[ -f "$E/transcript.md" && -f "$E/email.html" ]] || fail "cell 3: an attachment was renamed"
[[ -f "$ROOT/.context/communications/received/not-a-dated-entry/email.md" ]] \
  || fail "cell 3: a file outside a dated entry folder was renamed"
pass "leaves attachments, email.html and undated folders untouched"
rm -rf "$ROOT"

# --- Cell 4: a project with no communications/ is not an error ---------------------
ROOT="$(mk_project)"
rm -rf "$ROOT/.context/communications"
OUT="$(cd "$ROOT" && NO_COLOR=1 bash "$SCRIPT" 2>&1)"; RC=$?
[[ $RC -eq 0 ]] || fail "cell 4: a project with no communications/ must exit 0, got $RC"
pass "exits clean when the project has no communications/"
rm -rf "$ROOT"

if [[ $FAILURES -gt 0 ]]; then
  printf '\n%d cell(s) failed\n' "$FAILURES"
  exit 1
fi
printf '\nOK — migrate-communications.sh: 4 cells passed\n'
