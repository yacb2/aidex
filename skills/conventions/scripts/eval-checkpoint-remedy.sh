#!/usr/bin/env bash
# eval-checkpoint-remedy.sh — does the checkpoint's "address findings by remedy" rule
# change what the model DOES with a finding? (BL-314)
#
# Each fixture in fixtures/checkpoint-remedy/<case>/ is a unit acceptance, the diff the
# unit introduced, one review finding, and the expected move. The model is put at the
# checkpoint with the canon's rule section and must answer one word:
#   MOVE: fix | defer | block, and EDIT: the concrete change. An expected "remove" is
#   MOVE fix whose EDIT deletes the component instead of guarding it.
#
# --control omits the rule section. A rule that scores the same with and without it is
# applicability, not effect (memory: rule-ablation). Run both before citing the rule.
#
# Usage: eval-checkpoint-remedy.sh [--control] [--runs N] [--model M]
# Exit: 0 every case met its expectation in every run · 1 otherwise · 3 usage
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CANON="$HERE/../references/checkpoint-conventions.md"
FIX="$HERE/fixtures/checkpoint-remedy"
RUNS=1 MODEL=claude-sonnet-5 CONTROL=0
while [ $# -gt 0 ]; do case "$1" in
  --control) CONTROL=1; shift ;;
  --runs) RUNS="$2"; shift 2 ;;
  --model) MODEL="$2"; shift 2 ;;
  -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
  *) echo "usage: unknown arg $1" >&2; exit 3 ;;
esac; done
command -v claude >/dev/null || { echo "claude not on PATH" >&2; exit 3; }

# The rule section, from its heading to the next "###".
rule="$(awk '/^\*\*Address findings by their remedy/{f=1} /^### /{if(f)exit} f' "$CANON")"
[ -n "$rule" ] || { echo "rule section not found in canon" >&2; exit 3; }
[ "$CONTROL" -eq 1 ] && rule="Address findings."

fail=0 total=0
for d in "$FIX"/*/; do
  name="$(basename "$d")"; expected="$(cat "$d/expected")"
  prompt="You are an unattended agent at the between-phase checkpoint of a plan run. The phase passed verification; you are addressing the code-review findings before committing. Nobody can answer questions.

Checkpoint rule for findings:
$rule

Phase acceptance (the unit's stated goal):
$(cat "$d/acceptance.md")

Diff this phase introduced:
$(cat "$d/diff.patch")

Review finding:
$(cat "$d/finding.md")

What do you do with this finding? Answer with exactly two lines and nothing else:
MOVE: one lowercase word — fix (edit the code now), defer (register it, do not edit now), block (leave the unit uncommitted as a hard blocker)
EDIT: one sentence naming the concrete code change you make (or 'none' when deferring or blocking)"
  for r in $(seq 1 "$RUNS"); do
    total=$((total+1))
    out="$(printf '%s' "$prompt" | claude -p --model "$MODEL" --output-format text 2>/dev/null)"
    move="$(printf '%s' "$out" | grep -i '^MOVE:' | head -1 | sed 's/^[Mm][Oo][Vv][Ee]:[[:space:]]*//' | tr 'A-Z' 'a-z' | tr -d '[:space:]')"
    edit="$(printf '%s' "$out" | grep -i '^EDIT:' | head -1 | sed 's/^[Ee][Dd][Ii][Tt]:[[:space:]]*//')"
    # expected is either a move word set (fix|block) or "remove": move=fix AND the
    # edit deletes the component rather than guarding it.
    if [ "$expected" = remove ]; then
      if [ "$move" = fix ] && printf '%s' "$edit" | grep -qiE 'remov|delet|drop' && ! printf '%s' "$edit" | grep -qiE 'add (a |an )?(check|filter|guard|validat)|restrict|only accept|reject'; then verdict=ok; else verdict=FAIL; fail=$((fail+1)); fi
    else
      if printf '%s' "$move" | grep -qxE "$expected"; then verdict=ok; else verdict=FAIL; fail=$((fail+1)); fi
    fi
    printf '%-20s run %d  expected %-9s move %-6s %s\n    edit: %s\n' "$name" "$r" "$expected" "${move:-<none>}" "$verdict" "${edit:-<none>}"
  done
done
mode=rule; [ "$CONTROL" -eq 1 ] && mode=control
echo "$mode: $((total-fail))/$total met expectation"
[ "$fail" -eq 0 ]
