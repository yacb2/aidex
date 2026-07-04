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
# JUDGE-GATED (BL-044) — when a durable run IS active and the message is not an
# obvious terminal state, the stop is judged by a model (`claude -p`, policy in
# durability-stop-prompt.md) instead of the regex, so novel stop phrasings (e.g.
# a long summary with no question) are caught. Any judge failure/timeout falls
# back to the regex logic — the hook stays fail-open and zero-cost in idle
# sessions. The judge command is injectable via AIDEX_JUDGE_CMD (tests mock it).
#
# NOT auto-installed. Activation is the user's call — see hooks/README.md.

set -euo pipefail
INPUT="$(cat)"
# The judge prompt lives next to this script (repo hooks/ or installed ~/.aidex/hooks/).
export AIDEX_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 - "$INPUT" <<'PY'
import sys, json, os, re, datetime

try:
    ev = json.loads(sys.argv[1])
except Exception:
    print("{}"); sys.exit(0)               # unparseable -> allow stop

def allow():  print("{}"); sys.exit(0)
def block(reason):
    print(json.dumps({"decision": "block", "reason": reason})); sys.exit(0)

# 0. Recursion guard: the judge is itself a `claude -p` session whose Stop hook
#    would re-enter this script. The judge subprocess runs with this var set.
if os.environ.get("AIDEX_STOP_JUDGE") == "1":
    allow()

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

# Append-only audit log — records every decision made while a run is ACTIVE (this point is
# reached only past the inert/expiry gates). Wrapped so a log failure can never abort the hook
# or corrupt its decision output (the shell runs `set -euo pipefail`).
LOG_PATH = os.path.expanduser("~/.aidex/durability/events.jsonl")
def log_event(decision, matched):
    try:
        os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
        rec = {
            "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "event": "stop-hook", "decision": decision, "matched": matched,
            "type": run_type, "mode": mode, "cwd": cwd, "msg": msg[:160],
        }
        with open(LOG_PATH, "a") as fh:
            fh.write(json.dumps(rec) + "\n")
    except Exception:
        pass

# Legitimate terminal states — used ONLY on the regex fallback path. When the
# judge is available it sees these messages too: a keyword like "deploy" inside
# an over-stop ("the next phase touches the deploy config — should I proceed?")
# must not short-circuit the judge (review finding, 2026-07-04).
LEGIT = [
    r"\bpush\b", r"\bdeploy", r"\brelease\b", r"\bpublic", r"\bpublish",
    r"missing cred", r"hard block", r"\bblocked\b", r"cannot proceed", r"no puedo",
    r"stop condition", r"condici[oó]n de (parada|fin)", r"all phases? (are )?(done|complete)",
    r"plan (is )?complete", r"todas? las fases", r"run complete", r"final summary",
    r"awaiting your (ok|approval|decision) (on|for) (the )?(publish|deploy|release)",
]
is_legit = any(re.search(p, msg) for p in LEGIT)

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

# Model judge (BL-044). Reached only during an ACTIVE, non-terminal stop, so a
# judge call costs nothing in casual sessions. Returns {"block": bool, "reason": str}
# or None on any failure (missing prompt, timeout, non-JSON output) — never raises.
def run_judge():
    try:
        import subprocess
        policy = open(os.path.join(os.environ["AIDEX_HOOK_DIR"],
                                   "durability-stop-prompt.md")).read()
        payload = {
            "last_assistant_message": ev.get("last_assistant_message") or "",
            "stop_hook_active": ev.get("stop_hook_active", False),
            "cwd": cwd,
            "transcript_path": ev.get("transcript_path") or "",
            "active_run": state,
        }
        prompt = (
            policy
            + "\n\nHook input JSON (this is the $ARGUMENTS referenced above):\n"
            + json.dumps(payload)
            + "\n\nOutput-format override for this invocation: return ONLY the JSON object "
              '{"block": <bool>, "reason": "<string>"} — "block": true means the stop must '
              "be blocked and the agent told to continue."
        )
        # shell=True is safe here: `cmd` is a trusted constant or the operator-set
        # AIDEX_JUDGE_CMD; untrusted message content goes in via stdin only.
        cmd = os.environ.get("AIDEX_JUDGE_CMD") or "claude -p --model claude-sonnet-5"
        env = dict(os.environ, AIDEX_STOP_JUDGE="1")
        # Inner cap MUST stay below the Stop hook's settings.json timeout (90s):
        # if the outer timeout fires first the whole hook is killed and the
        # regex fallback below never runs (live judge call measured ~20s).
        out = subprocess.run(cmd, shell=True, input=prompt, env=env,
                             capture_output=True, text=True, timeout=45)
        if out.returncode != 0:
            return None
        m = re.search(r"\{.*\}", out.stdout, re.S)   # tolerate fences/preamble
        if not m:
            return None
        verdict = json.loads(m.group(0))
        # LLM judges sometimes quote booleans ({"block": "false"}). bool("false")
        # is True — that would block a stop the judge meant to allow. Coerce
        # real bools and "true"/"false" strings; anything else -> regex fallback.
        def as_bool(v):
            if isinstance(v, bool):
                return v
            if isinstance(v, str) and v.strip().lower() in ("true", "false"):
                return v.strip().lower() == "true"
            return None
        reason = str(verdict.get("reason") or "")
        if "block" in verdict:
            b = as_bool(verdict["block"])
            return None if b is None else {"block": b, "reason": reason}
        if "ok" in verdict:   # type:agent contract shape — accept defensively
            ok = as_bool(verdict["ok"])
            return None if ok is None else {"block": not ok, "reason": reason}
        return None
    except Exception:
        return None

verdict = run_judge()
if verdict is not None:
    if verdict["block"]:
        log_event("block", "judge")
        block(verdict["reason"] or REASON)
    log_event("allow", "judge")
    allow()

# Judge unavailable — deterministic regex fallback (fail open overall).
if is_legit:
    log_event("allow", "legit-terminal")
    allow()

if mode == "enforce":
    # Aggressive: block unless the message read as a legit terminal state (above).
    log_event("block", "judge-fallback-regex")
    block(REASON)

# Default "remind": block only on an explicit over-stop signal.
if is_overstop:
    log_event("block", "judge-fallback-regex")
    block(REASON)

log_event("allow", "judge-fallback-regex")
allow()
PY
