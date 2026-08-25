#!/usr/bin/env bash
# Archiving an audit run must not break inbound cross-references.
#
# Regression this locks (2026-08-24):
#   D-10 states the reason archiving exists: "Move it to `_archive/` instead so inbound
#   `<type>/<filename>` references still resolve." The audits branch of validate.py's
#   `crossref_target_exists()` did not honour that. An audit ref carries a trailing
#   finding id (`audit/<run>/HIGH-1`), which no file ever matches, so the branch resolves
#   it by stripping that segment and testing the RUN FOLDER — but it tested only
#   `audits/<rest>`, never the archive. Both archive shapes were therefore invisible:
#   `audits/_archive/<run>` (root-level run) and `audits/<methodology>/_archive/<run>`.
#
# Second regression, same family (2026-08-25): the fix above resolved a root-archived run
# only when the REF was also flat. `archive-sweep.py` moves a grouped run to
# `audits/_archive/<run>` — dropping the methodology — while the ref that points at it
# still reads `audit/<methodology>/<run>/<finding>`. Neither shape matched, so applying
# the sweep's own proposal turned two clean backlog items into violations. Cell (5).
#   Harm, observed: running `close-audit.sh` on two finished runs turned 10 previously
#   clean backlog items into `cross-ref-target-missing` violations — the validator
#   punishing exactly the housekeeping the canon mandates, which pushes a user to either
#   leave finished runs in the tree or waive away real findings.
#
# What this test proves, and what it does not:
#   PROVES  — a finding-id ref into a run resolves in all three positions (active,
#             root archive, per-methodology archive), and still fails for a run that
#             does not exist anywhere, so the check keeps its teeth.
#   DOES NOT — validate anything about finding ids themselves; they are not resolvable
#             from the filesystem and the branch deliberately settles for the folder.
#
# Run with: bash tests/test-crossref-archived-audit.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
VALIDATE="$SCRIPT_DIR/../skills/aidex-conventions/scripts/validate.py"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

[[ -f "$VALIDATE" ]] || { echo "FAIL: validate.py not found at $VALIDATE"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CTX="$TMP/.context"

# --- fixture: three runs, one per position, each with an inbound backlog ref ---
mkdir -p "$CTX/audits/active-meth/2026-01-01-live-run" \
         "$CTX/audits/_archive/2026-01-02-root-archived" \
         "$CTX/audits/meth/_archive/2026-01-03-meth-archived" \
         "$CTX/audits/_archive/2026-01-05-swept-from-a-methodology" \
         "$CTX/backlog/_archive"

seed_item() {  # $1 = slug, $2 = origin_ref
  cat > "$CTX/backlog/_archive/2026-01-01-$1.md" <<EOF
---
title: "Item referencing $1"
id: BL-001
status: done
created: 2026-01-01
updated: 2026-01-01
origin: audit
origin_ref: "$2"
priority: P2
type: task
---

Body.
EOF
}

seed_item live      "audit/active-meth/2026-01-01-live-run/HIGH-1"
seed_item rootarch  "audit/2026-01-02-root-archived/HIGH-2"
seed_item metharch  "audit/meth/2026-01-03-meth-archived/HIGH-3"
seed_item ghost     "audit/2026-01-04-never-existed/HIGH-4"
# The shape archive-sweep.py actually produces: the run left its methodology folder,
# the ref did not.
seed_item swept     "audit/some-meth/2026-01-05-swept-from-a-methodology/HIGH-5"

OUT="$(python3 "$VALIDATE" "$CTX" 2>&1)"

# ---------- (1) the control: an existing, unarchived run resolves ----------
if grep -q "2026-01-01-live-run/HIGH-1" <<<"$OUT"; then
  fail "(1) a ref into a LIVE run was reported missing — the fixture itself is wrong, not the archive handling"
fi

# ---------- (2) root-level archive: audits/_archive/<run> ----------
if grep -q "2026-01-02-root-archived/HIGH-2" <<<"$OUT"; then
  fail "(2) a ref into a run archived at audits/_archive/ was reported missing — D-10 archives precisely so inbound refs keep resolving"
fi

# ---------- (3) per-methodology archive: audits/<meth>/_archive/<run> ----------
if grep -q "2026-01-03-meth-archived/HIGH-3" <<<"$OUT"; then
  fail "(3) a ref into a run archived at audits/<methodology>/_archive/ was reported missing — close-audit.sh writes this shape whenever the run sits under a methodology"
fi

# ---------- (5) a grouped ref into a run the sweep flattened into audits/_archive/ ----
if grep -q "2026-01-05-swept-from-a-methodology/HIGH-5" <<<"$OUT"; then
  fail "(5) a methodology-qualified ref was reported missing after archive-sweep.py moved the run to audits/_archive/ — the destination the sweep writes must be a shape the resolver knows"
fi

# ---------- (4) the check must keep its teeth ----------
if ! grep -q "2026-01-04-never-existed/HIGH-4" <<<"$OUT"; then
  fail "(4) a ref into a run that exists NOWHERE was accepted — the fix widened the resolver into a rubber stamp"
fi

if [[ $failures -eq 0 ]]; then
  echo "OK: audit cross-refs resolve in active, root archive and methodology archive; a nonexistent run still fails"
  exit 0
fi
printf '\n%d assertion(s) failed\n' "$failures"
exit 1
