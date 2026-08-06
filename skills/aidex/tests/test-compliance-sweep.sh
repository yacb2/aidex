#!/usr/bin/env bash
# compliance-sweep.sh — the fleet drift check (BL-038).
#
# Invariants, all three of which are what make it safe to schedule:
#   1. A clean run is SILENT and exits 0. A routine that talks when nothing is
#      wrong is a routine you stop reading.
#   2. Drift names the project, says which instrument fired, and exits 1.
#   3. The run is READ-ONLY. sweep.sh used to `mkdir -p _archive` even in
#      dry-run, so merely inspecting the fleet created a directory in every
#      project it touched.
# Plus: an explicit project list overrides --root (the "named list" form).
set -euo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWEEP="$SKILL/scripts/compliance-sweep.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

# A project with no .context/ is not aidex's business — skipped, never drift.
mkdir -p "$TMP/fleet/noctx"

# ---- 1. nothing to report: silent, exit 0 ---------------------------------
out="$(bash "$SWEEP" --root "$TMP/fleet" 2>&1)" && rc=0 || rc=$?
[ "$rc" = "0" ] || err "a fleet with nothing to report exited $rc, expected 0"
[ -z "$out" ] || err "a clean run must be silent, got: $out"

# ...but --verbose still accounts for what it looked at.
out="$(bash "$SWEEP" --root "$TMP/fleet" --verbose 2>&1)" || true
echo "$out" | grep -q '1 skipped' || err "--verbose did not account for the skipped project: $out"

# ---- 2. drift is named, attributed, and fatal -----------------------------
# A done item still sitting in the active folder is the archive-on-close (D-10)
# drift sweep.sh reports.
BL="$TMP/fleet/dirty/.context/backlog"
mkdir -p "$BL"
cat > "$BL/2026-01-01-already-done.md" <<'MD'
---
title: "Already done, never archived"
id: BL-001
status: done
created: 2026-01-01
updated: 2026-01-01
---

Body.
MD

out="$(bash "$SWEEP" --root "$TMP/fleet" 2>&1)" && rc=0 || rc=$?
[ "$rc" = "1" ] || err "a drifting fleet exited $rc, expected 1"
echo "$out" | grep -q '^dirty$' || err "drift report does not name the project: $out"
echo "$out" | grep -q 'sweep: 1 done/dropped' || err "sweep drift not attributed: $out"
echo "$out" | grep -q '1 of 1 project(s) drifted' || err "missing consolidated tally: $out"

# ---- 3. read-only ---------------------------------------------------------
[ -d "$BL/_archive" ] && err "inspecting the fleet created $BL/_archive — the run is not read-only"
[ -f "$BL/2026-01-01-already-done.md" ] || err "the run moved a file it was only meant to report"

# ---- 4. an explicit project list overrides --root -------------------------
out="$(bash "$SWEEP" --root "$TMP/fleet" "$TMP/fleet/noctx" --verbose 2>&1)" && rc=0 || rc=$?
[ "$rc" = "0" ] || err "explicit list of one clean project exited $rc, expected 0"
echo "$out" | grep -q 'dirty' && err "explicit project list did not override --root: $out"

if [ "$fail" -eq 0 ]; then
  echo "OK: compliance-sweep is silent when clean, attributes drift, stays read-only"
fi
exit "$fail"
