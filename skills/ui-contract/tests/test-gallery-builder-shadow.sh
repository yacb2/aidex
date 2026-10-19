#!/usr/bin/env bash
# test-gallery-builder-shadow.sh — BL-820: the sonnet/medium shadow of gallery-builder stays
# a shadow: pinned to sonnet/medium, pointed at from SKILL.md's first build, with its log
# fields, gate run, isolation, evidence copy, failed-shadow row and readout clauses owned by one
# reference, and the live builder untouched.
# Layer: text contract (the flow is prose); the agent frontmatter is the only machine-read part.
set -u
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ROOT="$SKILL_DIR/../.."
SKILL="$SKILL_DIR/SKILL.md"
REF="$SKILL_DIR/references/05-gallery-builder-shadow.md"
SHADOW="$ROOT/agents/gallery-builder-shadow.md"
LIVE="$ROOT/agents/gallery-builder.md"
FAILURES=0
fail() { echo "  FAIL: $*"; FAILURES=$((FAILURES + 1)); }
# has: match against the file with whitespace (line wraps included) collapsed to one space, so a
# pinned sentence cannot be inverted by a word on the next line.
flat() { { tr -s '[:space:]' ' ' < "$1"; } 2>/dev/null; }
has() { flat "$1" | grep -qF -- "$2" || fail "$3"; }
hasnt() { if flat "$1" | grep -qF -- "$2"; then fail "$3"; fi; }
fm() { awk 'NR>1 && /^---$/ {exit} NR>1 {print}' "$1" 2>/dev/null; }

fm "$SHADOW" | grep -qx 'model: sonnet' || fail "shadow is not model: sonnet"
fm "$SHADOW" | grep -qx 'effort: medium' || fail "shadow is not effort: medium"
fm "$LIVE" | grep -qx 'model: opus' || fail "live gallery-builder left opus"
fm "$LIVE" | grep -qx 'effort: high' || fail "live gallery-builder left high effort"
has "$SHADOW" 'gallery-builder.md' "shadow does not point at the live builder's brief"
has "$SHADOW" '.gbshadow/' "shadow agent lacks the kit/profile redirect"

grep -B1 -A2 -F 'aidex:gallery-builder-shadow' "$SKILL" | grep -qF 'references/05-gallery-builder-shadow.md' \
  || fail "SKILL.md first build lacks the pointer to the shadow reference"

for f in live_gate_green shadow_gate_green cells_live cells_shadow evidence; do
  has "$REF" "\`$f\`" "reference lacks log field $f"
done
for f in live_fix_rounds shadow_fix_rounds live_final_green shadow_final_green; do
  hasnt "$REF" "$f" "reference still carries fix-round field $f"
done
has "$REF" 'gallery-builder-shadow/log.jsonl' "reference lacks the log path"
has "$REF" 'mkdir -p ~/.claude/aidex/gallery-builder-shadow' "reference lacks mkdir -p of the log directory"
has "$REF" 'never applied' "reference lost the never-applied rule"
has "$REF" 'Never on a re-capture.' "reference lets the shadow run on a re-capture"
# launch: background, in the live builder's message, never awaited, no setup before the live launch
has "$REF" 'with `run_in_background: true`' "shadow launch is not backgrounded, so the turn waits on it"
has "$REF" "the consultation page opens on the live builder's hand-back alone" "the page may wait on the shadow's hand-back"
has "$REF" 'The shadow creates and sets up this worktree itself' "shadow worktree setup runs before, and delays, the live launch"
has "$SHADOW" 'worktree setup' "shadow agent is not told to set up its own worktree"

# gate: one no-update run per arm, read-only, no fix rounds, off the owner's critical path
has "$REF" 'separate no-write gate run' "reference does not name the separate no-write gate run"
# one executor only: a verify-ui run goes out with no flag and writes a missing baseline
hasnt "$REF" 'verify-ui` run' "reference names verify-ui as the gate run's executor"
# Playwright's flagless default is 'missing', which writes an absent baseline into the worktree
has "$REF" "Each arm's command is the kit's scoped command with \`--update-snapshots=none\`" "a gate run can write a missing baseline into the live worktree"
has "$REF" 'run by the main session as a background command, not through `aidex:verify-ui`' "gate run goes through verify-ui, which forbids the =none flag and cannot be killed"
has "$REF" 'never as the hardening gate' "reference does not exclude the hardening gate"
hasnt "$REF" "hardening gate's run" "reference calls the trial run the hardening gate's run"
has "$REF" 'Neither arm gets a fix round' "reference lets an arm take fix rounds"
has "$REF" 'The live arm runs in the live sketch worktree and only reads' "reference does not keep the live arm's run read-only"
has "$REF" 'The gate runs and the log line come after the consultation page is open and never delay it' "trial work may delay the consultation page"
# the live run shares the live worktree with the next round's implementer
has "$REF" "The next round is not briefed while the live arm's run is in flight" "the next round may run beside the trial's live gate run"
has "$REF" 'If the owner answers first, the live run is killed and the screen is logged with `live_gate_green` null and does not count toward the 5' "an owner answer can wait on, or race, the live gate run"

# isolation: start point, sketch worktree setup, redirect of kit/profile/rows
has "$REF" '--branch gbshadow/<screen> --base <live sketch branch>' "worktree command lacks the live sketch branch start point"
has "$REF" 'worktree.sh new gbshadow-<screen>' "shadow setup does not go through worktree.sh (port slot, compose name)"
has "$SHADOW" 'worktree.sh new' "shadow agent setup does not go through worktree.sh"
has "$REF" 'worktree.sh down gbshadow-<screen> --delete-branch' "shadow teardown leaves its stack and volumes behind"
has "$REF" '02-sketch-round-kit.md` § The sketch worktree' "reference does not point at the sketch worktree setup"
has "$REF" '<shadow worktree>/.gbshadow/' "reference lacks the shadow-only destination for kit/profile/rows"

# evidence: same copy point for both arms, before the gate run, and before the worktree removal
has "$REF" '~/.claude/aidex/gallery-builder-shadow/<project>/<screen>/{live,shadow}' "reference lacks the persistent evidence path"
has "$REF" 'Each side is copied when its builder hands back, before its gate run' "evidence copy point differs between the arms"
flat "$REF" | awk '{ k = index($0, "then copy into"); r = index($0, "Only after both copies exist and the log line is written, remove the shadow worktree"); exit !(k && r && k < r) }' \
  || fail "shadow worktree removal does not wait for the evidence copy and the log line"

# a shadow that never hands back is logged as a failed arm, never skipped
has "$REF" 'A shadow that errors, stalls or returns no gallery by the start of the next round (re-capture or hardening) is still logged' "a failed shadow can go unlogged"
has "$REF" '`shadow_gate_green` false, `cells_shadow` 0 and an empty `shadow/` directory' "failed-shadow log values are not fixed"
has "$REF" 'still running is stopped with `TaskStop` before' "a stalled background shadow keeps writing into a removed worktree"

# adjudication and readout clauses, pinned through their tails
has "$REF" 'fresh opus reader' "reference does not name the adjudicator"
has "$REF" 'model opus' "adjudicator is not pinned to opus"
has "$REF" 'At **5 distinct (project, screen) pairs** logged' "readout lacks the 5 distinct (project, screen) condition"
has "$REF" 'A screen counts whatever its gate results' "readout does not say red screens count"
has "$REF" 'Adopt sonnet/medium only if both hold on every one of them' "readout lacks the both-on-every-screen rule"
has "$REF" '`shadow_gate_green` is true wherever `live_gate_green` is true (a shadow green where live is red does not reject)' "readout gate clause lost or inverted"
has "$REF" 'the shadow'"'"'s adjudicated defect count is at most the live gallery'"'"'s, with no shadow-only wrong-state or identical-cell defect.' "readout adjudication clause lost or inverted"
has "$REF" 'One screen failing either clause rejects.' "readout lacks the one-screen-rejects rule"

if [ "$FAILURES" -eq 0 ]; then echo "PASS: gallery-builder shadow trial"; exit 0; fi
echo "FAIL: $FAILURES cell(s)"; exit 1
