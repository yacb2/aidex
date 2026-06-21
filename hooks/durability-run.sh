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
# State lives at  <cwd>/.context/.durability/active-run.json  and always carries an
# expiry (default 180 min) so a forgotten run can never trap future sessions.

set -euo pipefail
DIR=".context/.durability"
STATE="$DIR/active-run.json"
CMD="${1:-status}"

case "$CMD" in
  start)
    TYPE="${2:-run}"; MODE="remind"; TTL=180
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
import sys, json, datetime
path, typ, mode, ttl = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
now = datetime.datetime.now(datetime.timezone.utc)
json.dump({
    "type": typ, "mode": mode,
    "started": now.isoformat(),
    "expires": (now + datetime.timedelta(minutes=ttl)).isoformat(),
}, open(path, "w"), indent=2)
print(f"durable run '{typ}' active (mode={mode}, ttl={ttl}min) -> {path}")
PY
    ;;
  stop)
    rm -f "$STATE" && echo "durable run cleared" || true
    ;;
  status)
    if [ -f "$STATE" ]; then cat "$STATE"; else echo "no active durable run"; fi
    ;;
  *)
    echo "usage: durability-run.sh start <type> [--mode remind|enforce] [--ttl-min N] | stop | status" >&2
    exit 2
    ;;
esac
