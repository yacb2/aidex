#!/usr/bin/env bash
# detect-topology.sh — stack-agnostic fact gatherer for the current project.
# Usage: detect-topology.sh
#
# Prints plain-text FACTS to stdout about the project's git/orchestration topology.
# No interpretation, no recommendation, no stack assumptions — the interview
# (aidex-worktree's `bootstrap` workflow) turns these facts into a decision.
# Always exits 0: this is informational and never blocks the caller.

set -uo pipefail

find_project_root() {
  local dir; dir="$(pwd -P)"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.context" ]]; then printf '%s\n' "$dir"; return 0; fi
    dir="$(dirname "$dir")"
  done
  pwd -P
}

ROOT="$(find_project_root)"

echo "== Project topology facts (root: $ROOT) =="
echo

if [[ ! -d "$ROOT/.context" ]]; then
  echo "Note: no .context/ found above the current directory; using cwd as root."
  echo "      (this may be the first time bootstrap runs in this project)"
  echo
fi

echo "-- Root git status --"
if [[ -d "$ROOT/.git" ]]; then
  echo "root has its own .git"
else
  echo "root has NO .git"
fi
echo

echo "-- Immediate subdirectories with their own .git (split-git / multi-repo signal) --"
found_subgit=0
for d in "$ROOT"/*/; do
  [[ -d "$d" ]] || continue
  name="$(basename "$d")"
  if [[ -d "$d/.git" ]]; then
    echo "$name/ has its own .git"
    found_subgit=1
  fi
done
[[ "$found_subgit" -eq 0 ]] && echo "(none found)"
echo

echo "-- Orchestration / dev-workflow files (root or one level deep, by glob) --"
found_orch=0
patterns=(
  "docker-compose*.yml" "docker-compose*.yaml"
  "Dockerfile*"
  "Procfile"
  "dev.sh" "dev.ch" "start.sh"
  "test-e2e.sh"
)
for depth_glob in "$ROOT"/ "$ROOT"/*/; do
  [[ -d "$depth_glob" ]] || continue
  for pat in "${patterns[@]}"; do
    for f in "$depth_glob"$pat; do
      [[ -e "$f" ]] || continue
      echo "${f#$ROOT/}"
      found_orch=1
    done
  done
done
[[ "$found_orch" -eq 0 ]] && echo "(none found)"
echo

echo "-- Directories that look like services (heuristic signal reported, no framework guess) --"
found_service=0
for d in "$ROOT"/*/; do
  [[ -d "$d" ]] || continue
  name="$(basename "$d")"
  signals=()
  [[ -f "$d/package.json" ]] && signals+=("package.json")
  [[ -f "$d/pyproject.toml" ]] && signals+=("pyproject.toml")
  [[ -f "$d/requirements.txt" ]] && signals+=("requirements.txt")
  [[ -f "$d/go.mod" ]] && signals+=("go.mod")
  [[ -d "$d/.git" ]] && signals+=("own .git")
  if [[ "${#signals[@]}" -gt 0 ]]; then
    joined="$(IFS=', '; echo "${signals[*]}")"
    echo "$name/ — signal(s): $joined"
    found_service=1
  fi
done
[[ "$found_service" -eq 0 ]] && echo "(none found)"

exit 0
