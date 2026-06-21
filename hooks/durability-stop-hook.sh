#!/usr/bin/env bash
# durability-stop-hook.sh — Stop-hook enforcement for execution durability.
#
# The judgment layer (durability-arbiter) only fires if the agent *chooses* to
# consult it before stopping. The failing case is the agent just stopping ("todo
# requiere tu decisión"). A Stop hook is the only surface that fires on that
# involuntary stop. This hook blocks-to-continue when a durable run is active and
# the agent is over-stopping on safe work.
#
# SAFE BY DESIGN — it does nothing unless a run is explicitly declared:
#   - Inert unless  <cwd>/.context/.durability/active-run.json  exists & is unexpired.
#   - Anti-deadlock: honors `stop_hook_active` (blocks at most once per stop cycle);
#     Claude Code itself caps consecutive stop-blocks at 8.
#   - Never blocks a legitimate terminal state (publication ask / hard blocker / done).
#   - Default mode "remind" only blocks on explicit over-stop signals; "enforce" is opt-in.
#
# NOT auto-installed. Activation is the user's call — see hooks/README.md.

set -euo pipefail
INPUT="$(cat)"

python3 - "$INPUT" <<'PY'
import sys, json, os, re, datetime

try:
    ev = json.loads(sys.argv[1])
except Exception:
    print("{}"); sys.exit(0)               # unparseable -> allow stop

def allow():  print("{}"); sys.exit(0)
def block(reason):
    print(json.dumps({"decision": "block", "reason": reason})); sys.exit(0)

# 1. Anti-deadlock: if we already blocked once this cycle, allow the stop now.
if ev.get("stop_hook_active") is True:
    allow()

cwd = ev.get("cwd") or os.getcwd()
state_path = os.path.join(cwd, ".context", ".durability", "active-run.json")

# 2. Inert unless a durable run is declared in this project.
if not os.path.isfile(state_path):
    allow()
try:
    state = json.load(open(state_path))
except Exception:
    allow()

# 3. Expiry safety valve — a stale state file never traps a session.
exp = state.get("expires")
if exp:
    try:
        if datetime.datetime.fromisoformat(exp.replace("Z", "+00:00")) \
           < datetime.datetime.now(datetime.timezone.utc):
            allow()
    except Exception:
        pass

# 4. If background work is still running, this isn't really an end — don't interfere.
if ev.get("background_tasks"):
    allow()

msg = (ev.get("last_assistant_message") or "").lower()
mode = (state.get("mode") or "remind").lower()
run_type = state.get("type", "run")

# Legitimate terminal states — always allow the stop.
LEGIT = [
    r"\bpush\b", r"\bdeploy", r"\brelease\b", r"\bpublic", r"\bpublish",
    r"missing cred", r"hard block", r"\bblocked\b", r"cannot proceed", r"no puedo",
    r"stop condition", r"condici[oó]n de (parada|fin)", r"all phases? (are )?(done|complete)",
    r"plan (is )?complete", r"todas? las fases", r"run complete", r"final summary",
    r"awaiting your (ok|approval|decision) (on|for) (the )?(publish|deploy|release)",
]
if any(re.search(p, msg) for p in LEGIT):
    allow()

# Over-stop signals — the agent is pausing on (apparently) safe work.
OVERSTOP = [
    r"\bshould i\b", r"\bwould you like\b", r"\blet me know\b", r"\bdo you want\b",
    r"¿(quieres|deseas|te gustar[ií]a|procedo|contin[uú]o|sigo|avanzo)",
    r"necesito tu (ok|aprobaci[oó]n|confirmaci[oó]n|decisi[oó]n)",
    r"requiere (tu|su) (decisi[oó]n|aprobaci[oó]n)", r"esperando tu (ok|respuesta)",
    r"te dejo (que )?decid", r"d[ií]me (c[oó]mo|si)", r"\bconfirm(as|a|e)?\b",
    r"qu[eé] prefieres", r"\bavanzo\?", r"\bcontin[uú]o\?",
]
is_overstop = any(re.search(p, msg) for p in OVERSTOP)

REASON = (
    f"An autonomous durable run ({run_type}) is active. Per the autonomy canon, do NOT "
    f"stop on safe + additive work. Continue to the run's stop condition. For any genuinely "
    f"ambiguous fork, consult the durability-arbiter "
    f"(~/.aidex/skills/aidex-conventions/agents/durability-arbiter.md) instead of stopping, "
    f"and batch real ASKs (unauthorized publish / deny-class / hard blocker) into ONE list at "
    f"the very end. If you are genuinely done or truly blocked, say so explicitly and you may stop."
)

if mode == "enforce":
    # Aggressive: block unless the message already read as a legit terminal state (handled above).
    block(REASON)

# Default "remind": block only on an explicit over-stop signal.
if is_overstop:
    block(REASON)

allow()
PY
