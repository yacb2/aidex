#!/usr/bin/env bash
# approve-ready-when.sh — OWNER ONLY: approve a `cmd:` ready_when for this project.
#
# sweep-eligible.py runs a `cmd:` front-matter value only when sha256(project-root \n command)
# is a line of the local, untracked allowlist (~/.claude/aidex/ready-when-allow.txt, a fixed path).
# A backlog item can be cloned or written by an agent, so approval is a human act: this script
# prints the root and the exact command, asks on /dev/tty, and refuses (exit 2, nothing written)
# when stdin or /dev/tty is not a terminal.
#
# Usage:
#   approve-ready-when.sh <BL-id | slug | filename | path>

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../conventions/scripts" && pwd -P)/_lib.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/_backlog-lib.sh"

[[ "${1:-}" == "backlog" ]] && shift
case "${1:-}" in -h|--help) usage_from_header "$0"; exit 0 ;; "") die "target required: <BL-id | slug | filename | path>" ;; esac
TARGET="$1"

if ! [[ -t 0 ]] || ! { : </dev/tty; } 2>/dev/null; then
  echo "error: approval needs an interactive terminal; an agent must not approve a command" >&2
  exit 2
fi

ROOT="$(find_project_root)"
BACKLOG_DIR="$ROOT/.context/backlog"
FILE="$(resolve_backlog_target "$BACKLOG_DIR" "$TARGET" read_id fuzzy)"
[[ -n "$FILE" && -f "$FILE" ]] || FILE="$(resolve_backlog_target "$BACKLOG_DIR/_deferred" "$TARGET" read_id fuzzy)"
[[ -n "$FILE" && -f "$FILE" ]] || die "cannot resolve backlog item: $TARGET"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# prints "<realpath root>\n<cmd text>" for the item's ready_when
INFO="$(cd "$ROOT" && python3 -I - "$FILE" "$SCRIPT_DIR" <<'PY'
import importlib, os, re, sys
sys.path.insert(0, sys.argv[2])
se = importlib.import_module('sweep-eligible')
fm = se.define_check.parse(sys.argv[1])['fm']
rw = se.ready_when_of(sys.argv[1], fm)
if not rw.startswith('cmd:') or not rw[4:].strip():
    sys.exit('no cmd: ready_when on this item')
print(os.path.realpath(se.define_check.find_root()))
if re.search(r'[\t\r\n]', rw):
    sys.exit('the command holds a tab, CR or LF: it cannot be approved')
print(rw[4:].strip(), end='')
PY
)" || die "no cmd: ready_when on $(basename "$FILE")"
REAL_ROOT="${INFO%%$'\n'*}"; CMD="${INFO#*$'\n'}"
HASH="$(python3 -I -c 'import hashlib,sys; print(hashlib.sha256((sys.argv[1] + "\n" + sys.argv[2]).encode()).hexdigest())' "$REAL_ROOT" "$CMD")"

SHOWN="$(python3 -I -c 'import sys
print("".join(c if c.isprintable() else c.encode("unicode_escape").decode() for c in sys.argv[1]), end="")' "$CMD")"
printf 'Project root: %s\nCommand:      %s\n' "$REAL_ROOT" "$SHOWN"
printf 'Approve this command for this project? [y/N] '
read -r ANS </dev/tty || ANS=""
[[ "$ANS" == y || "$ANS" == Y ]] || { echo "not approved"; exit 1; }

ALLOW="$HOME/.claude/aidex/ready-when-allow.txt"
case "$(python3 -I -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$ALLOW")" in
  "$REAL_ROOT"/*) die "the allowlist $ALLOW is inside the project; refusing" ;;
esac
mkdir -p "$(dirname "$ALLOW")"; touch "$ALLOW"
grep -qxF "$HASH" "$ALLOW" || printf '%s\n' "$HASH" >> "$ALLOW"
ok "approved for $REAL_ROOT"
