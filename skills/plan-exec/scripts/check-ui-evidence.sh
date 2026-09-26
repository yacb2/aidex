#!/usr/bin/env bash
# check-ui-evidence.sh — refuse a UI phase whose Execution log does not carry the three
# parts of "verified" in the exact grammar below.
#
# Why this exists: "verified" for a screen is three things (ui-contract/SKILL.md §
# "Verified" is three things), and until this script they were skill prose that plan-exec
# never read. A model looking at its own screenshots has claimed "verified in light and
# dark" and been disproved in three sessions. Two review rounds then showed that a parser
# reading free text with word lists leaks a new spelling every round ("approved? no",
# "44 passed, 1 timed out", "reviewer: me · PASS"). So the record is a GRAMMAR, not
# prose: each line matches exactly or it fails, naming the part and quoting the format.
#
# It reads text only. It never runs the gate, never opens the page, never judges a screen.
#
# WHICH PLAN IS UI — the one rule, written here and nowhere else. It fails toward UI:
#   A plan is UI when, outside ``` fences, it carries the UI-contract SECTION — the one
#   /ui-contract writes (Step 3) — marked by either of:
#   (a) a heading line (any level, optionally behind `>`) whose text, with inline code and
#       [links](…) removed, has "ui contract" within its first four words: `## UI contract`,
#       `### 3.1 UI Contract (level 2)`, `## Section 4: UI contract`, `# UI Contract 9/10 …`;
#   (b) a line that starts, after an optional `>` and list marker, with a bold span whose
#       text begins "ui contract": `**UI contract:**`, `- **UI contract:** level 2`.
#   Any case; any run of spaces, hyphens or en dashes between the words (UIcontract,
#   UI–contract). A mention — in prose, inline code, a link, a plain list item, or a bold
#   span not at the line start — is not the section and marks nothing.
#   Every phase of a UI plan is a UI phase; one that renders no screen records a skip.
#   Chosen over `surface: ui` on the originating backlog item because the trigger sits in
#   the file this check reads, many plans have no originating item, `surface` is a
#   registration-time guess that owns another gate, and the section exists exactly when
#   /ui-contract — the skill that owes the three parts — was asked for this plan.
#   A non-UI plan exits 0 before anything else is read: its log may be absent or headed
#   any way. A visual bugfix has no plan; bugfix calls this with `--visual`.
#
# THE GRAMMAR — one line per part in the plan's `## Execution log…` section (any heading
# that starts `## Execution log`; outside it, or inside a ``` fence, nothing counts). A
# record starts the line, optionally after `- `. Separators are exactly " · ". The LAST
# record of a label for a phase wins. Nothing may follow the final token.
#
#   ui-surface: phase <N> · <path>.html · owner: approved
#   ui-surface: phase <N> · <path>.html · owner: approved <k>/<k>        (both k equal, k >= 1)
#   ui-surface: phase <N> · <path>.html · owner: <n>/10                 (n is 9 or 10)
#   ui-gate: phase <N> · no-snapshot-update · passed=<n> failed=0       (n >= 1)
#   ui-gate: phase <N> · no-snapshot-update · passed=<n> failed=0 meta=<k>/<k>
#   ui-predicates: phase <N> · reviewer: <name> · PASS
#   ui-evidence: phase <N> · skipped — <reason>
#
#   <N> is the phase id ([0-9A-Za-z._-]+); `phase 3` never matches `phase 3.1` or `3b`.
#   <path> has no spaces and no < >. `meta=` is the harness meta-suite count (every
#   predicate red on its seeded defect): optional, and when present it must be k/k.
#   verify-ui prints the ui-gate line ready-made. Any snapshot-update token on a gate line
#   fails it by grammar; the message names it.
#   <name> is one token ([A-Za-z0-9][A-Za-z0-9._-]*) and not self, me, none, nobody, tbd,
#   todo, pass, fail or ship: the reviewer is someone other than the author.
#   A skip's <reason> has at least 3 distinct words and does not open with a placeholder
#   (tbd, todo, n/a, see, pending, awaiting, later). A skip next to any other record for
#   the same phase fails. Step 3b's skeleton phase writes
#   `skipped — skeleton only, owner review pending in phase <n+1>`.
#
# In `--visual` mode the whole proof file is the log, records drop `phase <N> · `, and a
# skip's reason must contain the whole phrase `no gallery harness`.
#
# Usage:
#   check-ui-evidence.sh <plan.md> <phase>     # plan-exec, between-phase checkpoint
#   check-ui-evidence.sh --visual <proof.md>   # bugfix, a visual bug
#
# Exit codes: 0 all three records match, a valid skip, or not a UI plan
#             1 a record is missing or off-grammar — each part named with its format
#             2 refused: usage, unreadable or empty file, a phase file instead of the plan,
#               a UI plan with no or an empty Execution log

set -uo pipefail

refuse() { printf 'check-ui-evidence: refused — %s\n' "$*" >&2; exit 2; }
usage() { printf 'check-ui-evidence: usage: check-ui-evidence.sh <plan.md> <phase> | --visual <proof.md>\n' >&2; exit 2; }

visual=0
if [ "${1:-}" = "--visual" ]; then
  visual=1; file="${2:-}"; phase=""
  [ -n "$file" ] || usage
else
  file="${1:-}"; phase="${2:-}"
  [ -n "$file" ] && [ -n "$phase" ] || usage
  [[ "$phase" =~ ^[0-9A-Za-z._-]+$ ]] || usage
fi

[ -f "$file" ] && [ -r "$file" ] || refuse "cannot read '$file'"
grep -q '[^[:space:]]' "$file" || refuse "'$file' is empty — nothing to check is not a pass"

# Lines outside ``` fences, CR stripped.
body="$(tr -d '\r' < "$file" | awk '/^[[:space:]]*```/{fence=!fence; next} !fence')"

if [ "$visual" -eq 1 ]; then
  log="$body"; where="visual bugfix ($file)"; pfx=""
else
  [ "$(basename "$file")" != 00-index.md ] && grep -qF '](00-index.md)' <<<"$body" \
    && refuse "'$file' is a phase file (it links back to 00-index.md) — pass the plan's 00-index.md"
  # The UI-contract SECTION marker (header: WHICH PLAN IS UI). One awk pass.
  is_ui() {
    awk 'BEGIN { uic = "ui([[:space:]]|–|-)*contract" }
      { l = tolower($0)
        if (l ~ ("^[[:space:]]*(>[[:space:]]*)*(([-*+]|[0-9]+[.)])[[:space:]]+)?(\\*\\*|__)[[:space:]]*" uic)) { found = 1; exit }
        if (l ~ /^[[:space:]]*(>[[:space:]]*)*#/) {
          t = l; sub(/^[[:space:]]*(>[[:space:]]*)*#+[[:space:]]*/, "", t)
          gsub(/`[^`]*`/, " ", t); gsub(/\[[^]]*\]\([^)]*\)/, " ", t); sub(/^[[:space:]]+/, "", t)
          n = split(t, w, /[[:space:]]+/); h = ""
          for (i = 1; i <= n && i <= 4; i++) h = h " " w[i]
          if (h ~ uic) { found = 1; exit }
        } }
      END { exit !found }' <<<"$body"
  }
  if ! is_ui; then
    echo "check-ui-evidence: not a UI plan (no UI-contract section) — phase $phase left alone"
    exit 0
  fi
  grep -qE '^##[[:space:]]+Execution log' <<<"$body" \
    || refuse "UI plan '$file' has no '## Execution log' section to read"
  log="$(awk '/^##[[:space:]]+Execution log/{f=1; next} f && /^##[[:space:]]/{f=0} f' <<<"$body")"
  grep -q '[^[:space:]]' <<<"$log" || refuse "UI plan '$file' has an empty Execution log — phase $phase recorded nothing"
  where="phase $phase"; pfx="phase $phase · "
fi

# record <label> — the last line that starts as a record of <label> for this phase, with
# the `[- ]ui-<label>: [phase <N> · ]` prefix removed. Empty when there is none.
record() {
  local line
  line="$(awk -v p="ui-$1: $pfx" '{ l = $0; sub(/^- /, "", l); if (index(l, p) == 1) last = substr(l, length(p) + 1) } END { if (last != "") print last }' <<<"$log")"
  printf '%s' "$line"
}

missing=0
miss() { printf 'check-ui-evidence: %s — MISSING %s\n' "$where" "$*" >&2; missing=1; }
found() { [ -n "$1" ] && printf "found '%s'" "$1" || printf 'no such line'; }

s="$(record surface)"; g="$(record gate)"; p="$(record predicates)"; k="$(record evidence)"

# ---- a skip closes the phase without the three records ----
if [ -n "$k" ]; then
  reason=""
  [[ "$k" =~ ^skipped\ —\ (.*)$ ]] && reason="${BASH_REMATCH[1]}"
  distinct="$(grep -oE '[[:alpha:]]+' <<<"$reason" | tr '[:upper:]' '[:lower:]' | sort -u | wc -l | tr -d ' ')"
  fmt="'ui-evidence: ${pfx}skipped — <reason, 3+ distinct words>'"
  if [ -n "$s$g$p" ]; then
    miss "a valid skip: a skip and ui-* evidence are both recorded for $where — one or the other"
  elif [ -z "$reason" ] || [ "$distinct" -lt 3 ] \
       || grep -qiE '^(tbd|todo|tba|n/?a|see|pending|awaiting|later)([^[:alnum:]]|$)' <<<"$reason"; then
    miss "a valid skip: expected $fmt, $(found "$k")"
  elif [ "$visual" -eq 1 ] && ! grep -qE '(^|[^[:alnum:]-])no gallery harness([^[:alnum:]-]|$)' <<<"$reason"; then
    miss "a valid skip: a visual bugfix skips only as 'ui-evidence: skipped — no gallery harness in this project', $(found "$k")"
  else
    echo "check-ui-evidence: $where — UI evidence skipped: $reason"
    exit 0
  fi
  exit 1
fi

# ---- part 1: the review page and the owner's approval ----
ok=0
if [[ "$s" =~ ^[^[:space:]\<\>·]+\.html\ ·\ owner:\ (approved|approved\ ([1-9][0-9]*)/([1-9][0-9]*)|(9|10)/10)$ ]]; then
  ok=1
  [ -n "${BASH_REMATCH[2]}" ] && [ "${BASH_REMATCH[2]}" != "${BASH_REMATCH[3]}" ] && ok=0
fi
[ "$ok" -eq 1 ] || miss "part 1 (review surface): expected 'ui-surface: ${pfx}<path>.html · owner: approved | approved <k>/<k> | 9/10 | 10/10', $(found "$s")"

# ---- part 2: the gate's counts, from a run with NO snapshot update ----
ok=0
if [[ "$g" =~ ^no-snapshot-update\ ·\ passed=[1-9][0-9]*\ failed=0(\ meta=([1-9][0-9]*)/([1-9][0-9]*))?$ ]]; then
  ok=1
  [ -n "${BASH_REMATCH[1]}" ] && [ "${BASH_REMATCH[2]}" != "${BASH_REMATCH[3]}" ] && ok=0
fi
if [ "$ok" -eq 0 ]; then
  why=""
  grep -qiE '(^|[^[:alnum:]])(-u|--update[[:alnum:]-]*|--snapshot-update|update-snapshots|snapshots? updated)([^[:alnum:]]|$)' <<<"$g" \
    && why=" (a snapshot update is on the line — that run proves the code agrees with itself)"
  miss "part 2 (gate)$why: expected 'ui-gate: ${pfx}no-snapshot-update · passed=<n> failed=0[ meta=<k>/<k>]', $(found "$g")"
fi

# ---- part 3: someone else's PASS on the harness predicates ----
ok=0
if [[ "$p" =~ ^reviewer:\ ([A-Za-z0-9][A-Za-z0-9._-]*)\ ·\ PASS$ ]]; then
  case "$(tr '[:upper:]' '[:lower:]' <<<"${BASH_REMATCH[1]}")" in
    self|me|none|nobody|tbd|todo|pass|fail|ship) ;;
    *) ok=1 ;;
  esac
fi
[ "$ok" -eq 1 ] || miss "part 3 (predicates): expected 'ui-predicates: ${pfx}reviewer: <name, not self/me/none/nobody/tbd> · PASS', $(found "$p")"

[ "$missing" -eq 0 ] || exit 1
echo "check-ui-evidence: $where — all three parts of \"verified\" recorded"
