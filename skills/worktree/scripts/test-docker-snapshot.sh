#!/usr/bin/env bash
# test-docker-snapshot.sh — docker-snapshot.sh's verdicts, against a stub `docker`.
# Layer 1 (script, no daemon): the stub is the whole Docker surface; no container
# is ever started.

set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SNAP="$SCRIPTS/docker-snapshot.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"

# STUB_UP=1 -> the daemon answers; STUB_IDS -> the image IDs; STUB_TAG -> the single image's first RepoTag.
cat > "$BIN/docker" <<'STUB'
#!/bin/sh
case "$1" in
  info) [ "${STUB_UP:-0}" = 1 ] ; exit $? ;;
  images) for i in ${STUB_IDS:-abc123}; do echo $i; done ;;
  inspect) case "$*" in *RepoTags*) echo "${STUB_TAG:-<none>}" ;; esac ;;
esac
exit 0
STUB
chmod +x "$BIN/docker"
snap() { PATH="$BIN:$PATH" bash "$SNAP" "$@" 2>&1; }

# worktree-c20: no daemon at take AND at diff -> two identical placeholder files.
# That is "could not look", not "nothing leaked": it must not read ZERO RESIDUE.
STUB_UP=0 snap take "$TMP/down.snap" >/dev/null
out="$(STUB_UP=0 snap diff "$TMP/down.snap")"; rc=$?
grep -q 'ZERO RESIDUE' <<<"$out" && fail "an unreachable daemon at both ends printed ZERO RESIDUE: $out"
[[ $rc -eq 2 ]] || fail "an unreachable daemon at both ends must exit 2 (no verdict), got $rc: $out"

# Control: with the daemon up, an unchanged state is still ZERO RESIDUE.
STUB_UP=1 STUB_TAG=app:1 snap take "$TMP/up.snap" >/dev/null
out="$(STUB_UP=1 STUB_TAG=app:1 snap diff "$TMP/up.snap")"; rc=$?
[[ $rc -eq 0 ]] && grep -q 'ZERO RESIDUE' <<<"$out" || fail "control: identical state must be ZERO RESIDUE (rc=$rc): $out"

# worktree-c39: the same image ID under another tag is a retag, not residue.
out="$(STUB_UP=1 STUB_TAG=app:2 snap diff "$TMP/up.snap")"; rc=$?
[[ $rc -eq 0 ]] || fail "a retag of an existing image ID read as residue (rc=$rc): $out"

# A real new image ID is still residue (exit 1), whatever its tag.
out="$(STUB_UP=1 STUB_IDS="abc123 def456" STUB_TAG=app:1 snap diff "$TMP/up.snap")"; rc=$?
[[ $rc -eq 1 ]] || fail "a new image ID must exit 1 (got $rc): $out"

# An empty baseline is not "no state": one image after it is residue, not a clean run.
: > "$TMP/empty.snap"
out="$(STUB_UP=1 snap diff "$TMP/empty.snap")"; rc=$?
[[ $rc -eq 1 ]] || fail "an empty baseline plus one image must exit 1 (got $rc): $out"

# Baseline taken with the daemon up, diff with it down: no verdict either way.
out="$(STUB_UP=0 snap diff "$TMP/up.snap")"; rc=$?
[[ $rc -eq 2 ]] || fail "up at take, down at diff must exit 2 (got $rc): $out"

if [[ $failures -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — docker-snapshot: unreachable daemon is not clean, a retag is not residue"
