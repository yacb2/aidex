#!/usr/bin/env bash
# test_verifier_bare_run.sh — BL-339: the CORE verifier prompt must tell the agent to run
# the gate BARE and report the command's own exit status, never a pipeline's.
#
# Why this is a gate and not a note. Measured 2026-09-07 over 12 verifier runs across three
# model cells (BL-335, `.context/proofs/bl-335/verifier.tsv`): 5 of them ran the gate as
# `bash <gate> 2>&1 | tail -30; echo EXIT:$?`, where `$?` is tail's status and never the
# gate's. One returned `EXIT:0` on a target whose true exit was 1. The verdict survived
# because that model read the FAIL lines instead of its own annotation, but PROOF_SCHEMA
# carries an `exit_code` field and runPhase interpolates it into the retry feedback — so a
# phase can be told it failed with "exit 0". Pipe use by cell: sonnet 2/4, haiku 3/4,
# fable 0/4; it is a tendency, not a one-off.
#
# The instruction is asserted at every site the block lives: the canonical doc and every
# owned workflow asset. test_workflow_core_drift.sh already proves those copies are
# byte-identical; this test proves the sentence is in them at all, so a re-embed that
# silently drops it fails here rather than in production.
#
# Run:  bash skills/conventions/scripts/test_verifier_bare_run.sh
# Exit: 0 if every site carries the instruction; 1 otherwise.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
CANON="$REPO_ROOT/skills/conventions/references/workflow-core.md"
. "$SCRIPT_DIR/_owned-skills.sh"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# Both halves of the instruction, kept as two separate assertions so a partial edit is
# reported as a partial edit.
BARE_RE='never through a pipe'
OWN_STATUS_RE='exit status of that command itself'

check_site() {
  local f="$1" label="$2"
  grep -q 'Run exactly this command in the repo' "$f" || return 0   # no verifier here
  grep -qF "$BARE_RE" "$f" \
    || fail "$label: verifier prompt does not forbid running the gate through a pipe"
  grep -qF "$OWN_STATUS_RE" "$f" \
    || fail "$label: verifier prompt does not demand the command's own exit status"
}

[ -f "$CANON" ] || { echo "FAIL: canonical doc not found: $CANON"; exit 1; }
check_site "$CANON" "workflow-core.md"
sites=1

OWNED=()
while IFS= read -r d; do
  OWNED+=("$d")
done < <(aidex_owned_skill_dirs "$REPO_ROOT")
[ "${#OWNED[@]}" -gt 0 ] || { echo "FAIL: no aidex-owned skills found under $REPO_ROOT/skills"; exit 1; }

while IFS= read -r f; do
  check_site "$f" "${f#$REPO_ROOT/}"
  sites=$((sites + 1))
done < <(find "${OWNED[@]}" -type f -path '*/assets/workflows/*.workflow.js' | sort)

[ "$sites" -ge 4 ] || fail "expected the canon plus at least 3 workflow assets, saw $sites"

if [ "$failures" -gt 0 ]; then echo "$failures failure(s) across $sites site(s)"; exit 1; fi
echo "OK — verifier bare-run instruction present at all $sites sites"
