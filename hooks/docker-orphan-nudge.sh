#!/bin/sh
# SessionStart hook (matcher: startup) — say, at most once a day per project and config
# dir, that compose projects whose working directory no longer exists still have
# containers (BL-810, BL-811). Only the session's own project is shown (BL-903): the
# stdin cwd resolves, as the worktree skill does (find_project_root, compose_project_name),
# to <project>; a candidate is shown when it is <project> or <project>-wt-*. The scan
# stays machine-wide; only the display parses names.
#
# It reports; it deletes nothing and prints no removal command. Its only pointer is the
# read-only `orphan-sweep.sh --all` listing, never `/aidex:worktree status`: that runs the
# default, workspace-scoped sweep, which prints `down` (no -v) / `rmi` / `network rm` for a
# -wt- project not at $WS_PARENT/$WS_NAME-wt-* whose working_dir is gone and no container
# is running (a live worktree moved with a plain `mv` keeps its old one).
# The judgement is `orphan-sweep.sh --all` (skills/worktree/scripts/orphan-sweep-all.sh);
# this hook makes ZERO docker calls on the start path. It reads the summary that scan
# wrote under ${CLAUDE_CONFIG_DIR:-~/.claude}/tmp/docker-orphans/ and, when that summary is missing or older
# than 20 h, launches the scan detached for the next session to read.
#
# Fails open and silent: no jq, no summary, zero candidates -> exit 0. A docker-less or
# failed scan writes no summary (the last good one stays).

IN=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# Trimmed of surrounding ASCII whitespace (never [:space:], which in a UTF-8 locale also
# matches U+00A0, unlike the Python hooks); a leading ~ or ~/ is the home directory (never
# ~user); anything still relative means the default, never a tree under the cwd.
WS=$(printf ' \t\n\r\v\f.'); WS=${WS%.}
CFG="${CFG#"${CFG%%[!$WS]*}"}"; CFG="${CFG%"${CFG##*[!$WS]}"}"
case "$CFG" in "~"|"~/"*) CFG="$HOME${CFG#\~}" ;; esac
case "$CFG" in /*) ;; *) CFG="$HOME/.claude" ;; esac
DIR="$CFG/tmp/docker-orphans"
SUMMARY="$DIR/summary"
LOCK="$DIR/scan.lock"
PLUGIN="$(cd "$(dirname "$0")/.." && pwd -P)"
SWEEP="$PLUGIN/skills/worktree/scripts/orphan-sweep.sh"
mkdir -p "$DIR" 2>/dev/null || exit 0

if [ ! -f "$SUMMARY" ] || [ -n "$(find "$SUMMARY" -mmin +1200 2>/dev/null)" ]; then
  # A scan killed mid-way leaves its lock; one older than an hour is not a scan any more.
  find "$DIR" -maxdepth 1 -name scan.lock -mmin +60 -exec rmdir {} \; 2>/dev/null
  if mkdir "$LOCK" 2>/dev/null; then
    # docker lives in /usr/local/bin or /opt/homebrew/bin, absent from a hook's PATH on
    # macOS: without the prefix the scan would report "docker not found" forever.
    # Own process group and no inherited stdio, so the session neither waits for it
    # nor takes it down with the hook.
    PATH="/usr/local/bin:/opt/homebrew/bin:$PATH" nohup perl -e 'setpgrp(0,0); exec @ARGV' \
      sh -c 'bash "$1" --all --write-summary; rmdir "$2"' _ "$SWEEP" "$LOCK" \
      </dev/null >/dev/null 2>&1 &
  fi
fi

[ -f "$SUMMARY" ] || exit 0
get() { sed -n "s/^$1=//p" "$SUMMARY" | head -n 1; }
[ "$(get status)" = ok ] || exit 0
N=$(get candidates)
case "$N" in ''|0|*[!0-9]*) exit 0 ;; esac

# The stamp is per project: a session that shows nothing, or another project's notice,
# must not silence this project's notice for the day.
PROJ=$(bash -c 'cd "$1" && . "$2" && compose_project_name "$(basename "$(find_project_root)")"' \
  _ "$(printf '%s' "$IN" | jq -r '.cwd // empty' 2>/dev/null)" \
  "$PLUGIN/skills/conventions/scripts/_lib.sh" 2>/dev/null)
N=0 NAMES=""
for p in $(get candidate_projects); do
  case "$p" in "$PROJ"|"$PROJ"-wt-*) N=$((N + 1)); NAMES="$NAMES $p" ;; esac
done
[ "$N" -gt 0 ] || exit 0

TODAY=$(date +%Y-%m-%d)
STAMP="$DIR/nudged-$PROJ"
LAST_DAY=""
[ -f "$STAMP" ] && read -r LAST_DAY < "$STAMP"
[ "$LAST_DAY" = "$TODAY" ] && exit 0
printf '%s\n' "$TODAY" > "$STAMP" 2>/dev/null

WHEN=$(date -r "$(get scanned_at)" '+%Y-%m-%d %H:%M' 2>/dev/null)
jq -n --arg m "Docker: $N compose project(s) whose working directory no longer exists still have containers (${NAMES# }), scanned ${WHEN:-recently}. Nothing was deleted; verify by hand before removing anything. Read-only listing: bash \"$SWEEP\" --all" \
  '{systemMessage: $m}'
exit 0
