#!/usr/bin/env bash
# Skill agents are registered subagent types, launched by `subagent_type: aidex:<name>`.
#
# Claude Code registers only the plugin-level agents/ directory. A skill-local
# skills/<skill>/agents/*.md is not registered, so a skill that "reads the file and passes it
# as the prompt" runs a generic agent and the definition's model:/effort:/tools: configure
# nothing (plan 2026-09-29-agent-roster-trial-and-readout, phase 5). Fails when:
#   (a) any skills/*/agents/*.md other than an *.eval.md fixture exists;
#   (b) a skill text names `subagent_type: aidex:<x>` (or any `aidex:<x>` that is neither a
#       skill nor an agent) where agents/<x>.md does not exist;
#   (c) a skill text still tells the model to read an agent file and pass it as the prompt;
#   (d) an agent file has no `name:` equal to its filename; a skill-launched agent has no
#       "Launched by /aidex:" scope; a routed agent (listed in ROUTED_AGENTS) has none of
#       "Launched by" / "not for direct use" (it is chosen by description, so it must say
#       when to use it).
#
#   (e) backlog-reader states the per-line "written for this line" field (BL-809);
#   (f) an agent front matter has no key outside the plugin-agent parser's set (a skill-only
#       key such as user-invocable or context is silently ignored on an agent: a false contract).
#
# Run with: bash tests/test-agent-registration.sh   (ROOT=<dir> to point at another tree;
# needs only `git` on PATH, not a git repo: the scans use git grep --no-index)

set -uo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
fail=0
err() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }

# (a) no skill-local agent definitions
while IFS= read -r f; do
  case "$f" in *.eval.md) continue ;; esac
  err "(a) skill-local agent not registered by Claude Code, move it to agents/: ${f#"$ROOT"/}"
done < <(find "$ROOT/skills" -path '*/agents/*.md' -type f 2>/dev/null | sort)

# Skill and reference texts (markdown, templates, shell scripts that print instructions),
# searched in one `git grep` pass each: --no-index reads the working tree whether or not ROOT
# is a git repo. No --exclude-standard: a .gitignore must not hide a tracked file, nor blank
# the scan when ROOT itself sits under an ignored dir (<tree>/_tmp/copy).
TEXT_SPECS=(':(glob)skills/**/*.md' ':(glob)skills/**/*.template' ':(glob)skills/**/*.sh'
            ':(exclude,glob)skills/**/evals/**' ':(exclude,glob)skills/**/tests/**'
            ':(exclude,glob)skills/**/test-*.sh' ':(exclude,glob)skills/**/test_*.sh')
tgrep() { git -C "$ROOT" grep --no-index "$@" -- "${TEXT_SPECS[@]}"; }

TAB=$'\t'
# Sentinel: a scan that saw no file proves nothing.
tgrep -l . >/dev/null || err "scanned no files under $ROOT/skills"

# (b) every aidex:<x> is a skill or an agent; in a launch context it must be an agent:
#     any name on a `subagent_type` line (bare, backtick or quoted) and any agent-table row
#     that starts with `aidex:<x>`.
while IFS=$'\t' read -r f x; do
  [[ -f "$ROOT/agents/$x.md" ]] || err "(b) launch of aidex:$x in $f has no agents/$x.md"
done < <(tgrep -nE 'subagent_type|^\| *`aidex:' \
  | awk '{ match($0, /:[0-9]+:/); f = substr($0, 1, RSTART - 1); l = substr($0, RSTART + RLENGTH)
           while (match(l, /aidex:[a-z][a-z0-9-]*/)) { print f "\t" substr(l, RSTART + 6, RLENGTH - 6); l = substr(l, RSTART + RLENGTH) } }' \
  | sort -u)
while IFS=$'\t' read -r f x; do
  [[ -f "$ROOT/agents/$x.md" || -f "$ROOT/skills/$x/SKILL.md" ]] \
    || err "(b) aidex:$x in $f is neither a skill nor agents/$x.md"
done < <(tgrep -noE '(^|[^a-z0-9/_.-])aidex:[a-z][a-z0-9-]*' | sed -E 's/^(.*):[0-9]+:.*aidex:/\1'"$TAB"'/' | sort -u)

# (c) the old mechanism: read the agent file, pass it as the prompt
PASTE='as the prompt|as a \*prompt\*|read the file and adopt|point a subagent at that definition|Read \$SKILL_ROOT/agents/|skills/[a-z-]+/agents/[a-z-]+\.md'
while IFS=: read -r f n _; do
  err "(c) old launch-by-prompt text in $f:$n"
done < <(tgrep -nE "$PASTE")

# Agents exempt from the "Launched by /aidex:" description scope, each with its reason.
DESC_EXEMPT=(
  "artifact-grader: registered before this guard; scoped by 'Used by the artifact skill' and calibrated (34ffb28)"
)
is_desc_exempt() { local e; for e in "${DESC_EXEMPT[@]}"; do [[ "${e%%:*}" == "$1" ]] && return 0; done; return 1; }

# Routed agents: chosen by the main session from their description, not launched by a skill.
# Explicit list rather than a frontmatter key: an unlisted agent defaults to the strict
# skill-launched check, so a new agent cannot opt out of "Launched by" by accident.
ROUTED_AGENTS=(artifact-sonnet backlog-filer bugfix-opus figure-sonnet gate-runner impl-sonnet lookup-sonnet
               research-sonnet review-diff-opus smoke-sonnet synthesis-sonnet task-general
               verify-browser-opus verify-browser-sonnet)
is_routed() { local r; for r in "${ROUTED_AGENTS[@]}"; do [[ "$r" == "$1" ]] && return 0; done; return 1; }

# (d) each agent is named after its file and scopes itself
for f in "$ROOT"/agents/*.md; do
  n="$(basename "$f" .md)"
  head="$(awk 'NR>1 && /^---$/ {exit} NR>1 {print}' "$f")"
  grep -qx "name: $n" <<<"$head" || err "(d) agents/$n.md front matter has no 'name: $n'"
  if is_routed "$n"; then
    desc="$(grep '^description:' <<<"$head")"
    # the whole front-matter head, so a wrapped YAML continuation line cannot hide the phrase
    grep -qiE 'Launched by|not for direct use' <<<"$head" \
      && err "(d) routed agent agents/$n.md describes itself as skill-launched; a routed description states when to use it"
    grep -qE '^description: Use ' <<<"$desc" || err "(d) routed agent agents/$n.md description does not start with 'Use ' (when to use it)"
    continue
  fi
  is_desc_exempt "$n" && continue
  grep -q '^description: Launched by /aidex:' <<<"$head" || err "(d) agents/$n.md description does not start 'Launched by /aidex:'"
done

# (f) agent front matter keys are the plugin-agent parser's set (2.1.302). Flipped predicate:
#     every non-indented, non-blank front matter line must be `<known key>:` (quotes stripped,
#     digits allowed in names); anything else is reported, so `x2: y` and `"context": fork` fail.
AGENT_KEYS=' name description when_to_use tools disallowedTools model effort maxTurns skills memory background omitClaudeMd isolation autoCompactWindow color '
fm_bad_lines() {
  awk -v known="$AGENT_KEYS" 'NR>1 && /^---$/ {exit}
    NR>1 && !/^[ \t]/ && !/^[ \t]*$/ {
      k = $0
      if (match(k, /^["\x27]?[A-Za-z0-9_-]+["\x27]?[ \t]*:/)) {
        k = substr(k, 1, RLENGTH - 1); gsub(/["\x27 \t]/, "", k)
        if (index(known, " " k " ")) next
      }
      print
    }'
}
# Self-check: the detector must flag exactly these two on every run, or (f) could not go red.
selfcheck="$(fm_bad_lines <<'EOS'
---
name: probe
description: Use when probing
  wrapped continuation: stays indented
"model": opus
context: fork
x2: y
tools: Read
---
EOS
)"
[[ "$selfcheck" == $'context: fork\nx2: y' ]] || err "(f) self-check: detector must flag exactly 'context: fork' and 'x2: y', got: $selfcheck"
for f in "$ROOT"/agents/*.md; do
  while IFS= read -r k; do
    err "(f) agents/$(basename "$f") front matter line '$k' is not a known agent key"
  done < <(fm_bad_lines < "$f")
done

# (e) BL-809: backlog-reader states the per-line "written for this line" field and the rule that
#     partially/resolved needs a yes line (a partially resting on "no" lines was the live-run defect)
br="$ROOT/agents/backlog-reader.md"
grep -q 'written for this line: yes|no' "$br" || err "(e) agents/backlog-reader.md lacks the per-line 'written for this line: yes|no' field"
grep -q 'needs at least one line marked `yes`' "$br" || err "(e) agents/backlog-reader.md lacks the rule that partially/resolved needs a yes line"

[[ $fail -eq 0 ]] && echo "PASS: agents registered flat under agents/, launched by aidex:<name>, no launch-by-prompt text" || exit 1
