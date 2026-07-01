#!/usr/bin/env bash
# detect-project-commands.sh — facts-only detector for a project's review/commit/
# release/test command signals, cached at .claude/.aidex-detected-commands.json.
#
# Usage: detect-project-commands.sh [--project <path>] [--json] [--refresh]
#
# Detects, never invents:
#   - .claude/commands/*.md filenames matching *review*/*commit*/*release*/
#     *deploy*/*test* (deploy signal folds into release_command).
#   - CLAUDE.md backtick-quoted command strings as a secondary signal, only
#     used when no matching command file was found.
#
# Without --refresh, an existing cache file is read as-is (no re-scan).
# With --refresh, always re-scans and overwrites the cache.

set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$SCRIPTS_DIR/_lib.sh"

PROJECT=""
JSON=0
REFRESH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT="$2"; shift 2 ;;
    --json)
      JSON=1; shift ;;
    --refresh)
      REFRESH=1; shift ;;
    -h|--help)
      printf 'Usage: %s [--project <path>] [--json] [--refresh]\n' "$(basename "$0")"
      exit 0 ;;
    *)
      die "unknown argument: $1" ;;
  esac
done

if [[ -n "$PROJECT" ]]; then
  ROOT="$(cd "$PROJECT" && pwd -P)"
else
  ROOT="$(find_project_root)"
fi

CACHE_DIR="$ROOT/.claude"
CACHE_FILE="$CACHE_DIR/.aidex-detected-commands.json"
CACHE_RELPATH=".claude/.aidex-detected-commands.json"

emit() {
  # $1 = path to a JSON file containing detected_at/review_command/etc.
  local f="$1"
  if [[ "$JSON" -eq 1 ]]; then
    cat "$f"
  else
    python3 - "$f" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
print(f"detected_at: {d.get('detected_at')}")
for field in ("review_command", "commit_command", "release_command", "test_command"):
    val = d.get(field)
    src = d.get("source", {}).get(field)
    if val:
        print(f"{field}: {val} (source: {src})")
    else:
        print(f"{field}: (not detected)")
PYEOF
  fi
}

if [[ "$REFRESH" -ne 1 && -f "$CACHE_FILE" ]]; then
  emit "$CACHE_FILE"
  exit 0
fi

# --- Scan ---

CMD_DIR="$ROOT/.claude/commands"
CLAUDE_MD="$ROOT/CLAUDE.md"

review_command="" review_source=""
commit_command="" commit_source=""
release_command="" release_source=""
test_command="" test_source=""

find_cmd_file() {
  # $1 = pattern (e.g. "*review*"); prints first match (sorted) or nothing.
  local pat="$1"
  [[ -d "$CMD_DIR" ]] || return 0
  local match
  match="$(find "$CMD_DIR" -maxdepth 1 -type f -name "$pat" 2>/dev/null | sort | head -n1)"
  [[ -n "$match" ]] && basename "$match"
  return 0
}

f="$(find_cmd_file '*review*')"
[[ -n "$f" ]] && { review_command="$f"; review_source=".claude/commands/$f"; }

f="$(find_cmd_file '*commit*')"
[[ -n "$f" ]] && { commit_command="$f"; commit_source=".claude/commands/$f"; }

f="$(find_cmd_file '*release*')"
[[ -n "$f" ]] && { release_command="$f"; release_source=".claude/commands/$f"; }
if [[ -z "$release_command" ]]; then
  f="$(find_cmd_file '*deploy*')"
  [[ -n "$f" ]] && { release_command="$f"; release_source=".claude/commands/$f"; }
fi

f="$(find_cmd_file '*test*')"
[[ -n "$f" ]] && { test_command="$f"; test_source=".claude/commands/$f"; }

# Secondary signal: backtick-quoted command strings in CLAUDE.md, only used
# when no command file was found for that category.
if [[ -f "$CLAUDE_MD" ]]; then
  grab_claude_md() {
    # $1 = keyword (BRE alternation like 'release\|deploy'); prints first
    # backtick-quoted match containing keyword.
    grep -o '`[^`]*`' "$CLAUDE_MD" 2>/dev/null | grep -i "$1" | head -n1 | tr -d '`'
    return 0
  }
  if [[ -z "$review_command" ]]; then
    m="$(grab_claude_md 'review')"
    [[ -n "$m" ]] && { review_command="$m"; review_source="CLAUDE.md"; }
  fi
  if [[ -z "$commit_command" ]]; then
    m="$(grab_claude_md 'commit')"
    [[ -n "$m" ]] && { commit_command="$m"; commit_source="CLAUDE.md"; }
  fi
  if [[ -z "$release_command" ]]; then
    m="$(grab_claude_md 'release\|deploy')"
    [[ -n "$m" ]] && { release_command="$m"; release_source="CLAUDE.md"; }
  fi
  if [[ -z "$test_command" ]]; then
    m="$(grab_claude_md 'test')"
    [[ -n "$m" ]] && { test_command="$m"; test_source="CLAUDE.md"; }
  fi
fi

mkdir -p "$CACHE_DIR"

REVIEW_COMMAND="$review_command" REVIEW_SOURCE="$review_source" \
COMMIT_COMMAND="$commit_command" COMMIT_SOURCE="$commit_source" \
RELEASE_COMMAND="$release_command" RELEASE_SOURCE="$release_source" \
TEST_COMMAND="$test_command" TEST_SOURCE="$test_source" \
python3 - "$CACHE_FILE" <<'PYEOF'
import json, os, sys, datetime

def nn(v):
    return v if v else None

data = {
    "detected_at": datetime.datetime.now().isoformat(timespec="seconds"),
    "review_command": nn(os.environ.get("REVIEW_COMMAND", "")),
    "commit_command": nn(os.environ.get("COMMIT_COMMAND", "")),
    "release_command": nn(os.environ.get("RELEASE_COMMAND", "")),
    "test_command": nn(os.environ.get("TEST_COMMAND", "")),
    "source": {
        "review_command": nn(os.environ.get("REVIEW_SOURCE", "")),
        "commit_command": nn(os.environ.get("COMMIT_SOURCE", "")),
        "release_command": nn(os.environ.get("RELEASE_SOURCE", "")),
        "test_command": nn(os.environ.get("TEST_SOURCE", "")),
    },
}

with open(sys.argv[1], "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PYEOF

GITIGNORE="$ROOT/.gitignore"
if [[ -f "$GITIGNORE" ]] && ! grep -qxF "$CACHE_RELPATH" "$GITIGNORE"; then
  printf '%s\n' "$CACHE_RELPATH" >> "$GITIGNORE"
fi

emit "$CACHE_FILE"
