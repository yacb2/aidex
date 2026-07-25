#!/usr/bin/env bash
# test-find-project-root.sh — regression test for _lib.sh's find_project_root.
#
# The bug (field-observed 2026-07-25, found by the worktree sandbox on its very
# first command): the upward walk had no boundary, so a stray `~/.context/`
# captured every project that had not been initialised yet. A fresh project
# resolved its root to $HOME, which made `orphan-sweep` scan for
# `<username>-wt-*` and report a clean workspace it was never looking at, and
# would have written that project's worktree overview into `~/.context/`.
# 33 scripts across every skill call this function.
#
# $HOME is overridden per-case so the boundary is exercised without touching
# the real home directory.
#
# Run with: bash skills/aidex-conventions/scripts/test-find-project-root.sh

set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/_lib.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
# macOS mktemp returns /var/... which is a symlink to /private/var; the function
# reports the resolved path, so resolve the expectations the same way.
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# run <cwd> <home> -> prints the resolved root
run() { ( cd "$1" && HOME="$2" bash -c ". '$LIB'; find_project_root" ); }

FAKEHOME="$TMP/home"
mkdir -p "$FAKEHOME/.context/references"          # the stray ancestor .context
mkdir -p "$FAKEHOME/projects"

# --- case 1: THE BUG — a project with no .context under a home that has one ---
P1="$FAKEHOME/projects/fresh"
mkdir -p "$P1/backend"; : > "$P1/CLAUDE.md"
got="$(run "$P1" "$FAKEHOME")"
[[ "$got" == "$P1" ]] || fail "fresh project resolved to '$got', expected '$P1' — an ancestor .context must never capture an uninitialised project"
[[ "$got" == "$FAKEHOME" ]] && fail "resolved to \$HOME: artifacts would be written to the home directory"

# --- case 2: an initialised project still resolves exactly as before ---
P2="$FAKEHOME/projects/inited"
mkdir -p "$P2/.context" "$P2/sub/deeper"
got="$(run "$P2/sub/deeper" "$FAKEHOME")"
[[ "$got" == "$P2" ]] || fail "initialised project resolved to '$got', expected '$P2'"

# --- case 3: the nearest .context wins over an outer one ---
P3="$FAKEHOME/projects/inited/nested"
mkdir -p "$P3/.context"
got="$(run "$P3" "$FAKEHOME")"
[[ "$got" == "$P3" ]] || fail "nested .context should win, got '$got'"

# --- case 4: no .context anywhere, marker is a git repo ---
P4="$FAKEHOME/projects/repoonly"
mkdir -p "$P4/.git" "$P4/src"
got="$(run "$P4/src" "$FAKEHOME")"
[[ "$got" == "$P4" ]] || fail "repo root should be the fallback marker, got '$got'"

# --- case 5: no .context and no marker at all -> cwd, never an ancestor ---
P5="$FAKEHOME/projects/bare"
mkdir -p "$P5"
got="$(run "$P5" "$FAKEHOME")"
[[ "$got" == "$P5" ]] || fail "markerless dir should fall back to cwd, got '$got'"

# --- case 6: .context BELOW the project but above cwd still resolves upward ---
# (guards against the boundary being applied too aggressively)
P6="$FAKEHOME/projects/inited/sub"
got="$(run "$P6" "$FAKEHOME")"
[[ "$got" == "$P2" ]] || fail "an existing .context above cwd must still be found, got '$got'"

# --- case 7: HOME unset is DEGRADED, not broken ---
# With no $HOME there is no boundary to apply, so an ancestor .context wins
# again — the pre-fix behaviour. What must still hold is that the function
# terminates and returns an absolute path rather than crashing or emitting "/".
got="$( cd "$P1" && env -u HOME bash -c ". '$LIB'; find_project_root" )"
[[ -n "$got" && "$got" == /* && "$got" != "/" ]] \
  || fail "with HOME unset, expected a sane absolute path, got '$got'"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — find_project_root: stops at \$HOME, nearest .context wins, marker fallback, cwd last resort"
