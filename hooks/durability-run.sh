#!/usr/bin/env bash
# durability-run.sh — declare/clear an active durable run for the Stop hook.
#
# The durability Stop hook is INERT unless this state file exists, so a durable
# skill (plan-exec / loop / audit / backlog sweep) marks its run at start and
# clears it at the end. Manual use is fine too.
#
#   durability-run.sh start <type> [--mode remind|enforce] [--ttl-min N]
#   durability-run.sh stop
#   durability-run.sh status
#
# State lives at  <project-root>/.context/.durability/active-run.json  — the root is
# discovered from cwd, so start/stop/status agree from any subdirectory — and always
# carries an expiry (default 90 min) so a forgotten run can never trap future sessions.

set -euo pipefail

# The marker belongs to the PROJECT, not to whatever directory the run happened
# to start in. Anchoring it at raw cwd planted markers in backend/, frontend/ and
# even .context/backlog/ (6 orphans across 5 projects, 2026-07-24), which `stop`'s
# upward search can never reach from the root. Same rule as the suite's
# find_project_root, inlined: hooks install standalone into ~/.claude/hooks/ and
# cannot source the skills tree.
project_root() {
  local start dir stop outermost=""
  start="$(pwd -P)"; stop="${HOME:-}"
  # The OUTERMOST .context ancestor, not the nearest: in a workspace whose root
  # is not a repo (echo_lab_ws/ with backend/ and frontend/ as sibling repos,
  # each with its own .context), one run spans the repos and must have one
  # marker — the nearest-ancestor rule would give each subrepo its own.
  dir="$start"
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    [ -n "$stop" ] && [ "$dir" = "$stop" ] && break
    [ -d "$dir/.context" ] && outermost="$dir"
    dir="$(dirname "$dir")"
  done
  [ -n "$outermost" ] && { printf '%s\n' "$outermost"; return 0; }
  dir="$start"
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    [ -n "$stop" ] && [ "$dir" = "$stop" ] && break
    { [ -e "$dir/.git" ] || [ -f "$dir/CLAUDE.md" ]; } && { printf '%s\n' "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  printf '%s\n' "$start"
}

ROOT="$(project_root)"
REL_DIR=".context/.durability"
STATE_REL="$REL_DIR/active-run.json"
DIR="$ROOT/$REL_DIR"
STATE="$DIR/active-run.json"
CMD="${1:-status}"

case "$CMD" in
  start)
    TYPE="${2:-run}"; MODE="remind"; TTL=90
    shift 2 || shift $#
    while [ $# -gt 0 ]; do
      case "$1" in
        --mode) MODE="$2"; shift 2;;
        --ttl-min) TTL="$2"; shift 2;;
        *) shift;;
      esac
    done
    mkdir -p "$DIR"
    python3 - "$STATE" "$TYPE" "$MODE" "$TTL" <<'PY'
import sys, json, datetime, os
path, typ, mode, ttl = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
now = datetime.datetime.now(datetime.timezone.utc)
# If an unexpired run is already declared here, overwriting it silently resets the
# TTL and can mask a run that was never cleared. Warn loudly instead (fail-soft).
if os.path.exists(path):
    try:
        prev = json.load(open(path))
        exp = prev.get("expires")
        if exp and datetime.datetime.fromisoformat(exp.replace("Z", "+00:00")) > now:
            sys.stderr.write(
                f"WARNING: an unexpired durable run ('{prev.get('type','?')}', "
                f"expires {exp}) already exists at {path}; resetting its TTL.\n")
    except Exception:
        pass
json.dump({
    "type": typ, "mode": mode,
    "started": now.isoformat(),
    "expires": (now + datetime.timedelta(minutes=ttl)).isoformat(),
}, open(path, "w"), indent=2)
# Append-only audit log (best-effort; never fail the command on a log error).
log_path = os.environ.get("AIDEX_DURABILITY_LOG") \
    or os.path.expanduser("~/.claude/aidex/durability/events.jsonl")
try:
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, "a") as fh:
        fh.write(json.dumps({"ts": now.isoformat(), "event": "run-start",
                             "type": typ, "mode": mode, "cwd": os.getcwd()}) + "\n")
except Exception:
    pass
print(f"durable run '{typ}' active (mode={mode}, ttl={ttl}min) -> {path}")
PY
    ;;
  stop)
    # Both sides now anchor at the project root, so the symmetric case is exact.
    # The upward walk remains for markers written by earlier versions at a raw
    # subdir cwd. Ceiling: the git root if in a repo, else $HOME;
    # `/` is the ultimate backstop so a marker outside $HOME (e.g. a test dir under
    # /var or /tmp) is still found. `git rev-parse` is guarded — an unguarded call
    # aborts under `set -euo pipefail` when cwd is not a repo.
    GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    CEILING="${GITROOT:-$HOME}"
    FOUND=""
    # The project anchor is where `start` writes, so check it first; the upward
    # walk stays as the fallback that clears markers left by older versions.
    [ -f "$STATE" ] && FOUND="$STATE"
    dir="$(pwd -P)"
    while [ -z "$FOUND" ]; do
      if [ -f "$dir/$STATE_REL" ]; then FOUND="$dir/$STATE_REL"; break; fi
      [ "$dir" = "$CEILING" ] && break     # stop AFTER checking the ceiling
      [ "$dir" = "/" ] && break            # backstop when cwd is outside the ceiling
      dir="$(dirname "$dir")"
    done
    python3 - <<'PY'
import json, datetime, os
log_path = os.environ.get("AIDEX_DURABILITY_LOG") \
    or os.path.expanduser("~/.claude/aidex/durability/events.jsonl")
try:
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, "a") as fh:
        fh.write(json.dumps({"ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                             "event": "run-stop", "cwd": os.getcwd()}) + "\n")
except Exception:
    pass
PY
    if [ -n "$FOUND" ]; then
      rm -f "$FOUND"
      echo "durable run cleared -> $FOUND"
    else
      echo "WARNING: no active-run marker found (searched from $(pwd -P) up to $CEILING); nothing cleared." >&2
    fi
    ;;
  status)
    if [ -f "$STATE" ]; then cat "$STATE"; else echo "no active durable run"; fi
    ;;
  sweep)
    # Report every marker under a root, at ANY depth, with its expiry state.
    # Read-only by design: it prints the `rm` lines rather than running them, per
    # the verify-before-any-delete rule. Depth matters — a `-maxdepth 4` census
    # reported "no markers on disk" on 2026-08-01 while five existed at depths 5-7,
    # residue of the raw-cwd anchoring bug this script's _anchor() now prevents.
    SWEEP_ROOT="${2:-$HOME}"
    find "$SWEEP_ROOT" -type f -path '*/.context/.durability/active-run.json' 2>/dev/null \
      | while IFS= read -r m; do
          python3 - "$m" <<'PY'
import datetime, json, sys
m = sys.argv[1]
try:
    d = json.load(open(m))
except Exception:
    print(f"UNREADABLE  {m}"); sys.exit(0)
exp = d.get("expires")
state = "LIVE"
if exp:
    try:
        if datetime.datetime.fromisoformat(exp.replace("Z", "+00:00")) \
           < datetime.datetime.now(datetime.timezone.utc):
            state = "EXPIRED"
    except Exception:
        state = "UNPARSEABLE-EXPIRY"
print(f"{state:18} type={d.get('type','?'):10} expires={str(exp)[:19]}  {m}")
PY
        done
    echo "-- read-only. To clear an EXPIRED marker, remove that exact path yourself." >&2
    ;;
  *)
    echo "usage: durability-run.sh start <type> [--mode remind|enforce] [--ttl-min N] | stop | status | sweep [root]" >&2
    exit 2
    ;;
esac
