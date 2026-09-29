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
#   (d) an agent file has no `name:` equal to its filename, or no "Launched by /aidex:" scope.
#
# Run with: bash tests/test-agent-registration.sh   (ROOT=<dir> to point at another tree)

set -uo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
fail=0
err() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }

# (a) no skill-local agent definitions
while IFS= read -r f; do
  case "$f" in *.eval.md) continue ;; esac
  err "(a) skill-local agent not registered by Claude Code, move it to agents/: ${f#"$ROOT"/}"
done < <(find "$ROOT/skills" -path '*/agents/*.md' -type f 2>/dev/null | sort)

# Skill and reference texts (markdown, templates, shell scripts that print instructions).
texts() {
  find "$ROOT/skills" -type f \( -name '*.md' -o -name '*.template' -o -name '*.sh' \) \
    ! -path '*/evals/*' ! -path '*/tests/*' ! -name 'test[-_]*.sh' 2>/dev/null | sort
}

# (b) every aidex:<x> is a skill or an agent; in a launch context it must be an agent:
#     any name on a `subagent_type` line (bare, backtick or quoted) and any agent-table row
#     that starts with `aidex:<x>`.
while IFS= read -r f; do
  while IFS= read -r x; do
    [[ -f "$ROOT/agents/$x.md" ]] || err "(b) launch of aidex:$x in ${f#"$ROOT"/} has no agents/$x.md"
  done < <({ grep -E 'subagent_type' "$f"; grep -E '^\| *`aidex:' "$f"; } | grep -oE 'aidex:[a-z][a-z0-9-]*' | sed 's/aidex://')
  while IFS= read -r x; do
    [[ -f "$ROOT/agents/$x.md" || -f "$ROOT/skills/$x/SKILL.md" ]] \
      || err "(b) aidex:$x in ${f#"$ROOT"/} is neither a skill nor agents/$x.md"
  done < <(grep -oE '(^|[^a-z0-9/_.-])aidex:[a-z][a-z0-9-]*' "$f" | sed -E 's/.*aidex://' | sort -u)
done < <(texts)

# (c) the old mechanism: read the agent file, pass it as the prompt
PASTE='as the prompt|as a \*prompt\*|read the file and adopt|point a subagent at that definition|Read \$SKILL_ROOT/agents/|skills/[a-z-]+/agents/[a-z-]+\.md'
while IFS= read -r f; do
  while IFS= read -r line; do
    err "(c) old launch-by-prompt text in ${f#"$ROOT"/}:${line%%:*}"
  done < <(grep -nE "$PASTE" "$f")
done < <(texts)

# Agents exempt from the "Launched by /aidex:" description scope, each with its reason.
DESC_EXEMPT=(
  "artifact-grader: registered before this guard; scoped by 'Used by the artifact skill' and calibrated (34ffb28)"
)
is_desc_exempt() { local e; for e in "${DESC_EXEMPT[@]}"; do [[ "${e%%:*}" == "$1" ]] && return 0; done; return 1; }

# (d) each agent is named after its file and scopes itself
for f in "$ROOT"/agents/*.md; do
  n="$(basename "$f" .md)"
  head="$(awk 'NR>1 && /^---$/ {exit} NR>1 {print}' "$f")"
  grep -qx "name: $n" <<<"$head" || err "(d) agents/$n.md front matter has no 'name: $n'"
  is_desc_exempt "$n" && continue
  grep -q '^description: Launched by /aidex:' <<<"$head" || err "(d) agents/$n.md description does not start 'Launched by /aidex:'"
done

[[ $fail -eq 0 ]] && echo "PASS: agents registered flat under agents/, launched by aidex:<name>, no launch-by-prompt text" || exit 1
