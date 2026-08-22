#!/usr/bin/env bash
# check-worktree-runner.sh — can a test harness invoked directly from a worktree
# drive, or destroy, the MAIN tree's test environment?
#
# The isolation of an E2E stack usually lives entirely inside the project's
# `test-e2e.sh`, which sources the worktree `.env` and exports what the harness
# reads. That protects the harness only when it is reached THROUGH that script.
# The harness config is also directly invokable — and it is the exact command
# `test-e2e.sh` itself ends up running:
#
#   cd <worktree>/frontend && pnpm exec playwright test --config=playwright.e2e.config.ts
#
# Every variable those configs read falls back to a DEV literal when unset, and
# a global-setup routinely does `DROP DATABASE <name>_e2e` + clone. So that
# command, run from a worktree, drops and recreates the MAIN TREE's e2e database
# and runs the worktree's specs against dev's containers. The name guards do not
# help: the name is right, the INSTANCE is wrong, and a worktree isolates by
# instance.
#
# ---------------------------------------------------------------------------
# THE RULE
#
# A harness config is a finding when it carries a port fallback literal and
# nothing loads the worktree's slot environment into `process.env` first:
#
#   fallback-to-dev   `process.env.X || 3710` / `?? 3710` / `Number(...) || 3710`
#                     with no slot resolution anywhere in the harness directory
#
# The exemption is the same discriminator that survived refutation for
# `check-worktree-ports.sh`: a file that LOADS the slot's `.env` can be
# overridden by the slot, whatever it defaults to below. Here the load may live
# in a sibling module (a shared `test-config.ts`), so the exemption is evaluated
# across the whole harness directory rather than per file.
#
# Why not a static AST walk for `process.env.X || <literal>`: the real configs
# read `process.env[name]` through a `port(name, fallback)` helper, so the
# variable name never appears literally next to its default. Keying on the
# fallback LITERAL is decidable and matches the shape that actually ships. Do
# not "improve" this into a walk that finds nothing.
#
# Usage:
#   check-worktree-runner.sh [project-root]    # exit 1 on findings
#   check-worktree-runner.sh --census          # one line per project
#
# Exit 0 = no directly-invokable harness can reach the main tree's stack.

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

# Does anything in this directory actually LOAD the worktree root `.env` into
# the process environment? Evaluated per DIRECTORY, not per file: the load
# belongs in one shared module and the fallbacks live in another.
#
# The first draft matched any mention of `.env` and exempted work_hours, whose
# global-setup merely names the file in an error message. Mentioning a file is
# not reading it. So: either the dotenv package, or a file that BOTH reads a
# path ending in .env AND writes into process.env.
dir_loads_slot_env() {
  local f
  # Vendored trees are pruned: the dotenv package itself and dozens of its
  # dependents live under node_modules, so an unpruned recursive grep matches
  # every real frontend and exempts the whole directory before a single fallback
  # is examined -- a blocking gate reporting green having looked at nothing.
  grep -rqE --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.venv \
    "require\\(['\"]dotenv|from ['\"]dotenv|dotenv\\.config\\(" "$1" 2>/dev/null && return 0
  # Three conditions in the SAME file: it reads a file, it names `.env`, and it
  # writes into process.env. Requiring the literal `.env` INSIDE the read call
  # was too strict -- real loaders build the path into a variable first, so the
  # canonical `slot-env.ts` this mechanism ships failed its own check. Requiring
  # only a mention of `.env` was too loose and exempted a global-setup that names
  # the file in an error string. Field-checked: the mention-only files call no
  # file-reading function at all, so the read requirement separates them cleanly.
  while IFS= read -r f; do
    grep -qE '(readFileSync|readFile|existsSync)\(' "$f" 2>/dev/null \
      && grep -qF '.env' "$f" 2>/dev/null \
      && grep -qE 'process\.env\[' "$f" 2>/dev/null && return 0
  done < <(find "$1" -maxdepth 1 -type f -name '*.ts' 2>/dev/null)
  return 1
}

# The project's declared dev ports: every ${VAR:-<literal>} default in the
# compose file and in the scripts a worktree links. A harness naming one of
# these is naming DEV, whatever syntax it uses -- which is how the helper form
# `port('E2E_BACKEND_PORT', 8710)` is caught. A `||`-only rule missed it, and
# missed it on the very project the defect was reported from.
dev_literals() {  # dev_literals <project-root> -> one literal per line
  local root="$1" cfg="$1/.context/worktrees/config.env" links
  links="$(sed -n 's/^[[:space:]]*WT_LINKS=["'"'"']\{0,1\}\([^"'"'"']*\).*/\1/p' "$cfg" | head -1)"
  {
    ( cd "$root" && docker compose --profile '*' config --no-interpolate --format json 2>/dev/null ) \
      | grep -oE '\$\{[A-Z0-9_]+:-[0-9]{4,5}\}' | grep -oE '[0-9]{4,5}'
    local l
    for l in $links; do
      [[ -f "$root/$l" ]] || continue
      grep -ohE '\$\{[A-Z0-9_]+:-[0-9]{4,5}\}' "$root/$l" 2>/dev/null | grep -oE '[0-9]{4,5}'
    done
  } | sort -un
}

scan_project() {  # -> <file>:<line>\t<kind>\t<what>\t<why> per finding
  local root="$1" cfg="$1/.context/worktrees/config.env"
  local parts part d f line lit devlits

  [[ -f "$cfg" ]] || return 0
  parts="$(sed -n 's/^[[:space:]]*WT_PARTICIPANTS=["'"'"']\{0,1\}\([^"'"'"']*\).*/\1/p' "$cfg" | head -1)"
  [[ -n "$parts" ]] || return 0
  devlits=" $(dev_literals "$root" | tr '\n' ' ')"

  for part in $parts; do
    # Harness directories: where a directly-invokable config and its setup live.
    for d in "$root/$part/tests/e2e-setup" "$root/$part/tests" "$root/$part"; do
      [[ -d "$d" ]] || continue
      # Only the harness configs themselves, never the specs.
      while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        dir_loads_slot_env "$(dirname "$f")" && continue
        while IFS=: read -r line _; do
          [[ -z "$line" ]] && continue
          sed -n "${line}p" "$f" | grep -qE '^[[:space:]]*(//|\*|/\*)' && continue
          lit="$(sed -n "${line}p" "$f" | grep -oE '(\|\||\?\?)[[:space:]]*[0-9]{4,5}' | grep -oE '[0-9]{4,5}' | head -1)"
          # Second source: a DECLARED dev port, in any syntax. This is what
          # catches `port('E2E_BACKEND_PORT', 8710)`, whose default never sits
          # next to a `||`. Restricted to the project's own declared ports so a
          # timeout like `30000` cannot be mistaken for one.
          if [[ -z "$lit" ]]; then
            for _c in $(sed -n "${line}p" "$f" | grep -oE '[0-9]{4,5}'); do
              case "$devlits" in *" $_c "*) lit="$_c"; break ;; esac
            done
          fi
          [[ -z "$lit" ]] && continue
          printf '%s:%s\tfallback-to-dev\tport falls back to the dev literal %s\t%s\n' \
            "${f#$root/}" "$line" "$lit" \
            "invoked directly from a worktree this reaches the MAIN tree's stack; load <root>/.env in this harness before the fallback"
        done < <(grep -nE '[0-9]{4,5}' "$f" | cut -d: -f1 | sort -un | sed 's/$/:/')
      done < <(find "$d" -maxdepth 1 -type f \( -name '*e2e*.config.ts' -o -name 'test-config.ts' -o -name 'global-setup.ts' \) 2>/dev/null)
      # No `break` here. It used to stop at the innermost EXISTING directory,
      # which left a participant-root `playwright.e2e.config.ts` -- the file this
      # check exists to catch -- unexamined whenever an inner `tests/` happened to
      # exist, and the project was reported clean. The three `find -maxdepth 1`
      # sets are disjoint, so scanning all three cannot double-report.
    done
  done
  return 0
}

if $CENSUS; then
  rc=0; seen=0
  CENSUS_ROOT="${AIDEX_PROJECTS_DIR:-$HOME/Documents/projects}"
  for cfg in "$CENSUS_ROOT"/*/.context/worktrees/config.env; do
    [[ -f "$cfg" ]] || continue
    seen=$((seen + 1))
    root="${cfg%/.context/worktrees/config.env}"
    out="$(scan_project "$root")"
    name="$(basename "$root")"
    if [[ -z "$out" ]]; then
      printf '  %-20s clean\n' "$name"
    else
      printf '  %-20s %s finding(s)\n' "$name" "$(grep -c . <<<"$out")"
      while IFS=$'\t' read -r where kind what why; do
        [[ -z "$where" ]] && continue
        printf '      [%s] %s: %s\n' "$kind" "$where" "$what"
      done <<<"$out"
      rc=1
    fi
  done
  # Enumerating zero projects is not a pass — this command is wired as a phase
  # gate, and a hardcoded path that matches nothing would print green forever.
  if [[ $seen -eq 0 ]]; then
    err "census examined 0 projects under $CENSUS_ROOT — nothing was checked."
    err "Set AIDEX_PROJECTS_DIR to the directory holding the projects."
    exit 2
  fi
  [[ $rc -eq 0 ]] && ok "test runners: all $seen project(s) resolve their own slot — none can reach the main tree's stack"
  exit $rc
fi

ROOT="${TARGET:-$(find_project_root)}"

# Examining nothing is not a pass -- the same rule the census above already
# applies. `scan_project` returns 0 when there is no config.env and when
# WT_PARTICIPANTS is empty, and the verdict below cannot tell either from a
# project whose harnesses are genuinely clean.
RUNNER_CFG="$ROOT/.context/worktrees/config.env"
if [[ ! -f "$RUNNER_CFG" ]]; then
  err "no worktree config at $RUNNER_CFG — nothing was checked."
  exit 2
fi
if [[ -z "$(sed -n 's/^[[:space:]]*WT_PARTICIPANTS=["'"'"']\{0,1\}\([^"'"'"']*\).*/\1/p' "$RUNNER_CFG" | head -1)" ]]; then
  err "WT_PARTICIPANTS is empty in $RUNNER_CFG — nothing was checked."
  exit 2
fi

findings="$(scan_project "$ROOT")"
if [[ -z "$findings" ]]; then
  ok "test runner OK: $(basename "$ROOT") — no directly-invokable harness falls back to dev"
  exit 0
fi

err "test runner: $(grep -c . <<<"$findings") finding(s) in $(basename "$ROOT")"
while IFS=$'\t' read -r where kind what why; do
  [[ -z "$where" ]] && continue
  printf '  [%s] %s: %s\n' "$kind" "$where" "$what" >&2
  printf '      -> %s\n' "$why" >&2
done <<<"$findings"
exit 1
