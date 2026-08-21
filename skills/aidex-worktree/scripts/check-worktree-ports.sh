#!/usr/bin/env bash
# check-worktree-ports.sh — can a command run INSIDE a worktree bind, or kill the
# holder of, the MAIN tree's host ports?
#
# Compose-published ports are covered by the slot allocator and
# check-compose-isolation.sh. This is the other half: ports a project binds
# OUTSIDE compose — a dev server, a Metro/Expo runner, anything a linked script
# starts on the host. Nothing checked those, and the result was the most
# destructive defect in the mechanism:
#
#   `./dev.sh` in a worktree calls `free_port 3700`, which is `kill` then
#   `kill -9` on whoever holds it — DEV's Vite — and then binds 3700 itself,
#   serving worktree code on the main tree's URL.
#
# The scripts this examines are the ones in WT_LINKS: they are DELIBERATELY
# reachable from inside the worktree, which is what makes a literal in them a
# cross-tree hazard rather than a style problem.
#
# ---------------------------------------------------------------------------
# THE RULE, AND WHY IT IS SHAPED LIKE THIS
#
# The naive rule — "a linked script must not name a port literal" — fires on
# 5 of 5 projects and is WRONG on 5 of them. Every project's `test-e2e.sh`
# assigns `DB_PORT=<dev>` near the top and then sources the worktree `.env`
# sixty lines further down, so the slot's value wins. By design, with a comment
# saying so. What survives is the third condition:
#
#   A script is EXEMPT if it sources the worktree root `.env`.
#
# That single condition excludes all five test-e2e.sh files and none of the
# dev.sh files. Verified against the field, 2026-08-21: 0 false positives.
#
# A finding is then a port literal the environment cannot override, in one of
# two shapes:
#
#   pinned-assignment   <VAR>=<literal> for a VAR named in WT_PORT_VARS, with no
#                       ${VAR:-...} form anywhere in the file.
#   inline-literal      a bare port literal in a kill or bind call site
#                       (`lsof -ti :3911`, `--port 3911`, `free_port 3424`).
#                       This shape has NO variable at all, so it is strictly
#                       worse: there is nothing for an environment to override.
#
# The third of those patterns was added after the first two MISSED
# `free_port 3424` in work_hours/dev.sh:279,306 — a project's own kill helper,
# called with a literal. Matching only the shapes a specific script happens to
# use is how a checker reports clean on a defect it was written to catch, so the
# pattern is any identifier containing "port" called with a bare literal.
#
# The second shape is here because the first alone MISSES it. An earlier draft
# of this check reported loom_lab and ns_backoffice clean; both embed the
# literal directly in `lsof -ti :<port>` — loom_lab at six sites, on its start
# path. A rule that only inspects assignments reports "clean" on precisely the
# projects where the defect is hardest to fix.
#
# Usage:
#   check-worktree-ports.sh [project-root]    # one project; exit 1 on findings
#   check-worktree-ports.sh --census          # every project with a worktree
#                                             # config; prints one line each
#
# Exit 0 = no command in a worktree can reach the main tree's host ports.

set -uo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

CENSUS=false
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --census) CENSUS=true; shift ;;
    -h|--help) sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
    *) TARGET="$1"; shift ;;
  esac
done

# A script that sources the worktree root `.env` can always be overridden by the
# slot, whatever it pins above that line. This is the whole false-positive
# defence — keep it first, and keep it broad.
sources_slot_env() {
  grep -qE '^[[:space:]]*(\.|source)[[:space:]]+"?\$\{?(PROJECT_ROOT|WORKSPACE_ROOT|WT_ROOT)\}?/\.env"?' "$1"
}

# One project. Prints findings as <file>\t<kind>\t<what>\t<why>, and nothing when
# clean. Always exits 0: under `set -e` a non-zero return here aborted the
# caller's `out=$(scan_project ...)` assignment before it could report anything.
scan_project() {
  local root="$1" cfg="$1/.context/worktrees/config.env"
  local port_vars="" links="" pair var f rel line lit

  [[ -f "$cfg" ]] || return 0
  port_vars="$(sed -n 's/^[[:space:]]*WT_PORT_VARS=["'"'"']\{0,1\}\([^"'"'"']*\).*/\1/p' "$cfg" | head -1)"
  links="$(sed -n 's/^[[:space:]]*WT_LINKS=["'"'"']\{0,1\}\([^"'"'"']*\).*/\1/p' "$cfg" | head -1)"
  [[ -n "$links" ]] || return 0

  local names=""
  for pair in $port_vars; do names="$names ${pair%%=*}"; done

  for rel in $links; do
    f="$root/$rel"
    [[ -f "$f" ]] || continue
    head -1 "$f" | grep -q '^#!.*sh' || continue      # shell scripts only

    # -- shape 1: a pinned assignment to a slot-managed variable --------------
    # Exempt when the script sources the worktree .env: the assignment is then
    # overridden by the slot, which is exactly what every test-e2e.sh does on
    # purpose. The exemption applies to THIS SHAPE ONLY -- see shape 2.
    sources_slot_env "$f" || for var in $names; do
      grep -qE "^[[:space:]]*$var=[0-9]{2,5}([[:space:]]|$|#)" "$f" || continue
      # A ${VAR:-...} anywhere means the environment already has a path in.
      grep -qE "\\\$\{$var:-" "$f" && continue
      line="$(grep -nE "^[[:space:]]*$var=[0-9]{2,5}" "$f" | head -1 | cut -d: -f1)"
      lit="$(grep -E "^[[:space:]]*$var=[0-9]{2,5}" "$f" | head -1 | sed "s/.*$var=\([0-9]*\).*/\1/")"
      printf '%s:%s\tpinned-assignment\t%s=%s is pinned with no environment path\t%s\n' \
        "$rel" "$line" "$var" "$lit" \
        "a worktree cannot move it; write $var=\${$var:-$lit} and source the worktree .env above it"
    done

    # -- shape 2: a bare literal at a kill or bind call site ------------------
    # No variable exists here at all, so no environment can reach it. Reported
    # separately because the fix is different: a variable must be INTRODUCED.
    #
    # NEVER exempted by sources_slot_env, and that distinction is load-bearing.
    # Sourcing the worktree .env sets VARIABLES; it cannot touch a literal that
    # no variable stands in front of. Applying the exemption to this shape made
    # work_hours/dev.sh report clean the moment Task 2.2 added its `.env` line,
    # while `free_port 3424` sat two hundred lines below, unchanged and still
    # killing whatever holds dev's Metro port.
    while IFS=: read -r line _; do
      [[ -z "$line" ]] && continue
      # A COMMENT is not a call site. work_hours/dev.sh:255 documents Metro's
      # port in prose (`# \`expo start --port 3424\` in package.json`) and was
      # the check's one false positive before this line existed.
      sed -n "${line}p" "$f" | grep -qE '^[[:space:]]*#' && continue
      lit="$(sed -n "${line}p" "$f" | grep -oE '(:|--port[= ]|-p |[Pp]ort[a-zA-Z_]*[[:space:]]+)[0-9]{4,5}' | grep -oE '[0-9]{4,5}' | head -1)"
      [[ -z "$lit" ]] && continue
      printf '%s:%s\tinline-literal\tport %s is written into the call site itself\t%s\n' \
        "$rel" "$line" "$lit" \
        "there is no variable to override; introduce one (\${FRONTEND_PORT:-$lit}) and use it here"
    done < <(grep -nE 'lsof[^|]*-ti[^|]*:[0-9]{4,5}|--port[= ][0-9]{4,5}|[a-zA-Z_]*[Pp]ort[a-zA-Z_]*[[:space:]]+[0-9]{4,5}' "$f" | cut -d: -f1 | sort -un | sed 's/$/:/')
  done
  return 0
}

# ---------------------------------------------------------------- census
if $CENSUS; then
  rc=0
  for cfg in "$HOME"/Documents/projects/*/.context/worktrees/config.env; do
    [[ -f "$cfg" ]] || continue
    root="${cfg%/.context/worktrees/config.env}"
    out="$(scan_project "$root")"
    name="$(basename "$root")"
    if [[ -z "$out" ]]; then
      printf '  %-20s clean\n' "$name"
    else
      n="$(grep -c . <<<"$out")"
      printf '  %-20s %s finding(s)\n' "$name" "$n"
      while IFS=$'\t' read -r where kind what why; do
        [[ -z "$where" ]] && continue
        printf '      [%s] %s: %s\n' "$kind" "$where" "$what"
      done <<<"$out"
      rc=1
    fi
  done
  [[ $rc -eq 0 ]] && ok "host ports: every project parameterizes them — a worktree cannot reach the main tree's"
  exit $rc
fi

# ---------------------------------------------------------------- one project
ROOT="${TARGET:-$(find_project_root)}"
findings="$(scan_project "$ROOT")"
if [[ -z "$findings" ]]; then
  ok "host ports OK: $(basename "$ROOT") — no linked script can bind or kill the main tree's ports"
  exit 0
fi

n="$(grep -c . <<<"$findings")"
err "host ports: $n finding(s) in $(basename "$ROOT")"
while IFS=$'\t' read -r where kind what why; do
  [[ -z "$where" ]] && continue
  printf '  [%s] %s: %s\n' "$kind" "$where" "$what" >&2
  printf '      -> %s\n' "$why" >&2
done <<<"$findings"
exit 1
