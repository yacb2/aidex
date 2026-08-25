#!/usr/bin/env bash
# remediation-loop-spec.sh — emit ONE remediation loop-spec from a run's
# unresolved findings, grouped by severity, ready for aidex-loop to execute
# without hand-editing. The reverse direction (a single bulk finding -> a loop)
# is escalate-finding-to-loop.sh; this is the run-level forward direction.
#
# Usage:
#   remediation-loop-spec.sh <run-slug | run-path> [--dry-run]
#   remediation-loop-spec.sh <run-slug | run-path> --check
#
#   --check     the loop's GATE: exit 0 when the run has no unresolved finding
#               left, 1 (listing them) while any remains. It reads the audit
#               INVENTORY, so completing an item only counts once the row moves
#               -- a spec-internal checklist cannot satisfy it.
#   --dry-run   print what would be emitted; write nothing.
#
# Unresolved statuses: open, doing (+ read-tolerated legacy triaged/in-progress).
#
# Re-emit is refused while a previous remediation spec still holds the rows: the
# marker is only written into an EMPTY cell, so a second emit would leave the
# rows pointing at spec #1 while spec #2 lists them. Archive the old spec (and
# clear its markers) first.

set -euo pipefail
. "$(dirname "$0")/_lib.sh"

TARGET="" DRY_RUN=0 CHECK=0
for arg in "$@"; do
  case "$arg" in
    remediate) ;;                       # dispatcher token — ignore
    --dry-run) DRY_RUN=1 ;;
    --check)   CHECK=1 ;;
    -*) die "unknown flag: $arg" ;;
    *) [[ -z "$TARGET" ]] && TARGET="$arg" || die "unexpected extra argument: $arg" ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  cat <<EOF >&2
Usage: /aidex-audit remediate <run> [--check] [--dry-run]

Emit a remediation loop-spec from a run's unresolved findings.

Example:
  /aidex-audit remediate 2026-06-21-3mo-retro
  /aidex-audit remediate 2026-06-21-3mo-retro --check   # the loop's gate
EOF
  exit 2
fi

ROOT="$(find_project_root)"
AUDITS_DIR="$ROOT/.context/audits"

# --- resolve the run folder (same resolution as close-audit.sh) ---
RUN_PATH=""
if [[ -d "$TARGET" ]]; then RUN_PATH="$TARGET"
elif [[ -d "$AUDITS_DIR/$TARGET" ]]; then RUN_PATH="$AUDITS_DIR/$TARGET"
else RUN_PATH="$(find "$AUDITS_DIR" -maxdepth 2 -type d -name "$TARGET" 2>/dev/null | head -1)"; fi
[[ -n "$RUN_PATH" && -d "$RUN_PATH" ]] || die "cannot resolve audit run: $TARGET"

RUN_SLUG="$(basename "$RUN_PATH")"
RUN_DATE="${RUN_SLUG:0:10}"
PARENT="$(dirname "$RUN_PATH")"

METHODOLOGY=""
[[ "$PARENT" != "$AUDITS_DIR" && "$(basename "$PARENT")" != "_archive" ]] && METHODOLOGY="$(basename "$PARENT")"

# --- the governing inventory (run's parent, else the audits root) ---
INV=""
[[ -f "$PARENT/00-inventory.md" ]] && INV="$PARENT/00-inventory.md"
[[ -z "$INV" && -f "$AUDITS_DIR/00-inventory.md" ]] && INV="$AUDITS_DIR/00-inventory.md"
[[ -z "$INV" && -f "$AUDITS_DIR/INVENTORY.md" ]] && INV="$AUDITS_DIR/INVENTORY.md"
[[ -n "$INV" ]] || die "no inventory governs $RUN_SLUG (expected $PARENT/00-inventory.md)"

# --- collect this run's unresolved rows as "severity<TAB>id<TAB>module<TAB>summary" ---
# Column width branches like close-audit.sh: the canonical 9-column board parses
# as NF==11, the pre-2026-08-06 board (First Seen / Last Updated) as NF==13.
# Reading a fixed index on the wrong width silently returns another cell.
collect_rows() {
  awk '
    BEGIN { in_comment = 0 }
    {
      line = $0
      while (1) {
        if (in_comment) {
          e = index(line, "-->"); if (e == 0) { line = ""; break }
          line = substr(line, e + 3); in_comment = 0
        } else {
          s = index(line, "<!--"); if (s == 0) break
          before = substr(line, 1, s - 1); after = substr(line, s + 4)
          e = index(after, "-->")
          if (e == 0) { line = before; in_comment = 1; break }
          line = before substr(after, e + 3)
        }
      }
      if (line !~ /^\|/) next
      n = split(line, c, "|")
      if (n < 11) next
      id = c[2]; summ = c[5]; status = c[6]; sev = c[7]
      module = c[4]
      runs = (n >= 13 ? c[10] : c[8])
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", summ)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", status)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", sev)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", module)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", runs)
      if (id == "" || id == "ID" || id == "—") next
      if (status !~ /^(open|doing|done|dropped|triaged|in-progress|closed|escalated)$/) next
      if (status !~ /^(open|doing|triaged|in-progress)$/) next
      if (index(runs, run) == 0 && index(runs, rundate) == 0) next
      if (sev == "" || sev == "—") sev = "P?"
      print sev "\t" id "\t" module "\t" summ
    }
  ' run="$RUN_SLUG" rundate="$RUN_DATE" "$INV"
}
ROWS="$(collect_rows || true)"

# --- --check: the gate. Reads the inventory, never the spec. ---
if [[ "$CHECK" -eq 1 ]]; then
  if [[ -z "$ROWS" ]]; then
    ok "$RUN_SLUG: no unresolved findings remain — gate GREEN"
    exit 0
  fi
  printf 'gate RED — %s still has unresolved findings:\n' "$RUN_SLUG" >&2
  printf '%s\n' "$ROWS" | awk -F'\t' '{ printf "  - %s (%s) %s\n", $2, $1, $4 }' >&2
  exit 1
fi

[[ -n "$ROWS" ]] || die "$RUN_SLUG has no unresolved findings — nothing to remediate"

# Refuse a second emit while a live remediation spec still owns these rows.
HELD="$(awk -v run="$RUN_SLUG" -v rundate="$RUN_DATE" '
  /^\|/ {
    n = split($0, c, "|"); if (n < 11) next
    i_runs = (n >= 13 ? 10 : 8); i_esc = (n >= 13 ? 11 : 9)
    runs = c[i_runs]; esc = c[i_esc]
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", runs)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", esc)
    if (index(runs, run) == 0 && index(runs, rundate) == 0) next
    if (esc ~ /^loop\/.*-remediate-/) { print esc; exit }
  }
' "$INV")"
if [[ -n "$HELD" ]]; then
  die "$RUN_SLUG is already held by $HELD — archive that spec and clear its markers before re-emitting"
fi

COUNT="$(printf '%s\n' "$ROWS" | wc -l | tr -d ' ')"
RUN_REF="$RUN_SLUG"
[[ -n "$METHODOLOGY" ]] && RUN_REF="$METHODOLOGY/$RUN_SLUG"
ORIGIN_REF="audit/$RUN_REF"
INV_REL="${INV#"$ROOT"/}"

# Priority-ordered work-list. P0 first; unknown severity last, never dropped.
render_worklist() {
  local sev
  for sev in P0 P1 P2 P3 "P?"; do
    local block
    block="$(printf '%s\n' "$ROWS" | awk -F'\t' -v s="$sev" '$1 == s { printf "- [ ] **%s** (%s) — %s\n", $2, $3, $4 }')"
    [[ -z "$block" ]] && continue
    if [[ "$sev" == "P?" ]]; then
      printf '\n### Unrated\n\n%s\n' "$block"
    else
      printf '\n### %s\n\n%s\n' "$sev" "$block"
    fi
  done
}

SLUG="remediate-$(slugify "${RUN_SLUG:11}")"
[[ "$SLUG" == "remediate-" ]] && SLUG="remediate-$(slugify "$RUN_SLUG")"
is_valid_slug "$SLUG" || die "could not derive a valid slug from run '$RUN_SLUG'"

GATE_CMD="/aidex-audit remediate $RUN_SLUG --check"

if [[ "$DRY_RUN" -eq 1 ]]; then
  info "[dry-run] remediate $RUN_SLUG"
  log "  loop-spec  : $ROOT/.context/loops/$(today_iso)-$SLUG.md"
  log "  origin_ref : $ORIGIN_REF"
  log "  inventory  : $INV_REL"
  log "  gate       : $GATE_CMD"
  log "  findings   : $COUNT unresolved"
  render_worklist >&2
  log ""
  log "[dry-run] nothing written."
  exit 0
fi

# --- scaffold through aidex-loop (it owns id allocation + canon filename) ---
NEWLOOP=""
for candidate in \
  "$SKILL_DIR/../aidex-loop/scripts/new-loop-spec.sh" \
  "$ROOT/skills/aidex-loop/scripts/new-loop-spec.sh" \
  "$HOME/.aidex/skills/aidex-loop/scripts/new-loop-spec.sh" \
  "$HOME/.claude/skills/aidex-loop/scripts/new-loop-spec.sh"
do
  [[ -f "$candidate" && -x "$candidate" ]] && { NEWLOOP="$candidate"; break; }
done
[[ -n "$NEWLOOP" ]] || die "aidex-loop script not found. Run './install.sh --update' to install it."

info "Emitting remediation loop-spec for $RUN_SLUG ($COUNT unresolved findings)"
LOOP_FILE="$("$NEWLOOP" new "$SLUG")"
[[ -n "$LOOP_FILE" && -f "$LOOP_FILE" ]] || die "aidex-loop did not return a valid loop-spec path"

# The scaffold's FRONT-MATTER is kept (it owns id + dates); the BODY is written
# whole rather than injected heading-by-heading, because every section this spec
# needs is filled -- an injected body would keep the template's blanks and TODO
# prompts, which is exactly the hand-editing the spec must not need.
TMP="$(mktemp)"
awk '/^---[[:space:]]*$/ { c++ } { print } c == 2 { exit }' "$LOOP_FILE" > "$TMP"

# engine is decided here, not left "undecided"; origin_ref back-links the run.
python3 - "$TMP" "$ORIGIN_REF" <<'PY'
import sys, pathlib
p, ref = pathlib.Path(sys.argv[1]), sys.argv[2]
lines = p.read_text().splitlines()
out, seen_ref = [], False
for ln in lines:
    if ln.startswith("engine:"):
        ln = "engine: goal"
    if ln.startswith("origin_ref:"):
        ln, seen_ref = f"origin_ref: {ref}", True
    out.append(ln)
if not seen_ref:
    out.insert(len(out) - 1, f"origin_ref: {ref}")
p.write_text("\n".join(out) + "\n")
PY

{
  cat <<EOF

# Loop spec — $SLUG

## Goal

Every unresolved finding of audit run \`$RUN_SLUG\` is resolved in
\`$INV_REL\` — its row moved to \`done\` (or \`dropped\` with a reason), highest
severity first.

_Emitted from audit run ${RUN_REF} ($COUNT unresolved findings at emit time)._

## Loop-suitability (step 0)

- Verifiable gate exists: yes — \`$GATE_CMD\` exits 0 only when no unresolved
  row is left for this run.
- Handing off (verification check / stop condition / trigger / whole prompt): stop condition + whole prompt
- Greenfield or existing code: existing code
- One task or many: many — $COUNT findings, independent, priority-ordered
- Must run with the machine off: no
- Budget ceiling: set by the operator before running (see Guardrails)

## Stop condition (the gate)

\`\`\`
$GATE_CMD
\`\`\`

Exit 0 = done. The gate reads the **inventory**, not this file: ticking a box
below without moving the finding's row leaves the gate RED. That is deliberate —
it is what keeps completion attached to the finding instead of to a copy of it.

## Engine

- Chosen: goal
- Why: work-until-a-condition-holds inside one session, over an existing
  codebase, with a command that gives the pass/fail signal — the documented
  default in \`references/01-loop-engines.md\`.
- Runner-up: ralph — only if the remediation turns out to need fresh context per
  finding; it needs the same hard gate either way.

## Spec / PROMPT

Work the list below top to bottom. For each finding:

1. Read it in \`$INV_REL\` and in the run's \`findings.md\`.
2. Fix it, with the project's normal verification (a bug fix carries a
   regression test — \`aidex-bugfix\`).
3. **Write back to the finding**: set its row's Status to \`done\` in
   \`$INV_REL\` and record the commit / proof in the Notes cell (\`Closed:
   <commit> — <one line>\`). Drop instead of fixing only with the reason in
   Notes.
4. Re-run the gate.

Do not batch step 3 to the end: an interrupted run must leave the inventory
telling the truth about what is finished.
$(render_worklist)

## State file

\`$INV_REL\` — the audit inventory IS this loop's state. There is no separate
progress file to keep in sync, and nothing to reconcile afterwards.

## Scope — out

- Findings of other audit runs, and findings already \`done\` / \`dropped\`.
- Re-scoping, re-severity-rating or deleting a finding: a finding that turns out
  to be wrong is \`dropped\` with the reason, never removed.
- Anything the finding does not name — no opportunistic refactors.

## Autonomy surface (the ask-set)

- **Deny (never run):** base destructive config + anything conflicting with a
  registered ADR or existing code.
- **Pre-authorized (run without asking):** \`git commit\`, dependency changes,
  additive migrations, running the test suite.
- **Always-ask (pause every time):** \`git push\` / publish / deploy / release,
  and merging into the trunk.
- **Autonomous + log:** everything else safe, additive and non-breaking.

## Guardrails

- [ ] max-iterations / turn cap set: 3 x $COUNT turns
- [ ] isolation: none — remediation lands on the working branch
- [ ] scoped credentials / budget cap: operator sets before the run
- [ ] deterministic completion marker: the gate's exit code
- [ ] human approval gate before anything irreversible (merge/deploy/dep bump): yes
- [ ] security: gate includes SAST/secret-scan if it ships code
- [ ] human checkpoint cadence: read the diffs after each severity band

## End-to-end verification step

After the gate goes green, run \`/aidex-audit validate\` — every row this loop
closed must carry its evidence — then \`/aidex-audit close $RUN_SLUG\`.

## Run command

\`\`\`
/goal "Remediate the findings listed in $(basename "$LOOP_FILE"), highest severity first, writing each result back to the inventory row. Done when \`$GATE_CMD\` exits 0."
\`\`\`

---

## Notes / iteration log

<!-- Observed failures become prompt-tuning signals. Record them here. -->
EOF
} >> "$TMP"

mv "$TMP" "$LOOP_FILE"

# --- mark the rows: status -> doing, Escalated To -> loop marker when empty ---
# NOT "done": flipping the rows at emit time would satisfy the gate at t=0 and
# make the write-back vacuous. `doing` + a marker is what canon 03-lifecycle
# requires of a finding whose work is under way (validate-audit enforces it).
MARKER="loop/$(basename "$LOOP_FILE" .md)"
TMP2="$(mktemp)"
awk -v marker="$MARKER" -v run="$RUN_SLUG" -v rundate="$RUN_DATE" '
  BEGIN { in_comment = 0 }
  {
    line = $0; skip = in_comment; probe = line
    while (1) {
      if (in_comment) {
        e = index(probe, "-->"); if (e == 0) { probe = ""; break }
        probe = substr(probe, e + 3); in_comment = 0
      } else {
        s = index(probe, "<!--"); if (s == 0) break
        after = substr(probe, s + 4); e = index(after, "-->")
        if (e == 0) { in_comment = 1; break }
        probe = substr(after, e + 3)
      }
    }
    if (skip || index($0, "<!--") > 0 || index($0, "-->") > 0) { print $0; next }
    if ($0 !~ /^\|/) { print $0; next }
    n = split($0, c, "|")
    if (n < 11) { print $0; next }
    i_status = 6; i_runs = (n >= 13 ? 10 : 8); i_esc = (n >= 13 ? 11 : 9)
    id = c[2]; status = c[i_status]; runs = c[i_runs]; esc = c[i_esc]
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", status)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", runs)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", esc)
    if (id == "" || id == "ID" || id == "—") { print $0; next }
    if (status !~ /^(open|doing|triaged|in-progress)$/) { print $0; next }
    if (index(runs, run) == 0 && index(runs, rundate) == 0) { print $0; next }
    c[i_status] = " doing "
    if (esc == "" || esc == "—") c[i_esc] = " " marker " "
    out = c[1]
    for (i = 2; i <= n; i++) out = out "|" c[i]
    print out
  }
' "$INV" > "$TMP2" && mv "$TMP2" "$INV"

ok "remediation loop-spec emitted"
printf '  loop-spec  : %s\n' "$LOOP_FILE" >&2
printf '  origin_ref : %s\n' "$ORIGIN_REF" >&2
printf '  state file : %s (the inventory itself)\n' "$INV_REL" >&2
printf '  gate       : %s\n' "$GATE_CMD" >&2
printf '  findings   : %s rows -> doing, Escalated To -> %s\n' "$COUNT" "$MARKER" >&2
cat >&2 <<EOF

Next:
  1. Review the spec (engine, guardrails, budget ceiling).
  2. Run it: see its "Run command" section.
  3. The gate: $GATE_CMD
EOF
