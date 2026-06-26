# Durability Stop-hook (optional, opt-in — NOT auto-installed)

The **enforcement** half of execution durability. The `durability-arbiter`
(`skills/aidex-conventions/agents/`) is the *judgment* layer — but it only fires if the
agent *chooses* to consult it before stopping. The failure mode we actually see is the
agent **just stopping** ("the rest needs your decision"). The only surface that fires on
that involuntary stop is a Claude Code **Stop hook**. This directory holds two
implementations of that hook — pick one.

> **Why this is not shipped active by `install.sh`.** `install.sh` copies these files to
> `~/.aidex/hooks/` but wires nothing. A Stop hook is an environment-wide behavioral change
> (it fires at every turn-end in every session it's configured for) with real blast radius —
> it caused a deadlock before. **Activation is your explicit call**: you add the hook to
> `~/.claude/settings.json` yourself.

## Two implementations — judge with criterion vs. deterministic fallback

### A. Native model hook (`type:"prompt"`) — PRIMARY

The stop decision is made by a **Claude model**, not a regex. The model reads the situation
and applies the durability-arbiter policy with judgment — so it handles the *many different
ways* an agent phrases a premature stop, which a fixed term list cannot.

- **Prompt:** [`durability-stop-prompt.md`](durability-stop-prompt.md) is the canonical
  source. `settings.json` carries an **inline copy** of it (the `prompt` field is a string;
  CC has no prompt-file include). Edit the `.md`, then re-inject into settings (see below) —
  they are a single-source-with-copy, like the workflow CORE.
- **Contract:** the model returns `{"ok": true}` (allow the stop) or
  `{"ok": false, "reason": "..."}` (block → Claude continues, `reason` injected).
- **Scope is by CONTENT, not a flag.** A `type:"prompt"` hook cannot read files, so it does
  NOT gate on `active-run.json`. Instead the prompt itself allows naturally-complete casual
  turns and blocks only a premature pause inside an ongoing autonomous task. It fires a model
  call at **every** turn-end in every project it is configured for — that is the cost of this
  option (default model is Haiku: fast + cheap).
- **Anti-deadlock:** the prompt returns `{"ok": true}` whenever `stop_hook_active` is true →
  at most one forced continuation per stop cycle (CC also caps consecutive blocks).
- **Audit:** a block's `reason` begins with the literal marker `[durability-arbiter]`, so
  every enforced continuation is greppable in the session transcripts (reuse the usage-retro
  miner) — no per-turn log file needed.

Activate (your call):
```jsonc
// ~/.claude/settings.json  ->  "hooks": { ... , "Stop": [...] }
"Stop": [
  { "hooks": [ { "type": "prompt", "prompt": "<contents of durability-stop-prompt.md>" } ] }
]
```
Re-inject the prompt after editing the `.md`:
```bash
python3 - <<'PY'
import json, os
s = json.load(open(os.path.expanduser("~/.claude/settings.json")))
p = open(os.path.expanduser("~/.aidex/hooks/durability-stop-prompt.md")).read().strip()
s["hooks"]["Stop"] = [{"hooks": [{"type": "prompt", "prompt": p}]}]
json.dump(s, open(os.path.expanduser("~/.claude/settings.json"), "w"), indent=2)
PY
```

> **`type:"agent"`** is a heavier variant (multi-turn, can run tools to verify before
> deciding) and is marked **experimental** in the CC docs — not used here, but the same prompt
> would drop in if you want a tool-using judge later.

### B. Deterministic command hook (`type:"command"`) — SWAP-BACK FALLBACK

[`durability-stop-hook.sh`](durability-stop-hook.sh) — a regex over the last assistant
message. No model, no cost, can't-fail, **testable by piping JSON**. Its weakness is exactly
why A exists: a fixed term list misses novel stop phrasings (false negatives) and can trip on
casual endings (false positives). Use it if the native hook proves flaky, or for a zero-cost
deterministic baseline.

- **Inert** unless `<cwd>/.context/.durability/active-run.json` exists (scoped to declared
  runs — written by `durability-run.sh start`, cleared by `stop`). This is the regex hook's
  scoping mechanism; the native hook does not use it.
- `remind` mode (default) blocks only on explicit over-stop phrases; `enforce` is aggressive.
- Logs every decision to `~/.aidex/durability/events.jsonl`.

To use B instead of A, point the `Stop` entry at the script:
```jsonc
"Stop": [ { "hooks": [ { "type": "command", "command": "~/.aidex/hooks/durability-stop-hook.sh" } ] } ]
```

> **Do not chain A and B as siblings.** When multiple Stop hooks run, the most-restrictive
> answer wins — so B's regex *block* would override A's model *allow*, reintroducing the false
> positives A removes. Wire exactly one at a time. (B's script can still run as a log-only
> sibling if you neuter its blocking, but that is not the default.)

## Supporting scripts

- `durability-run.sh` — `start <type> [--mode remind|enforce] [--ttl-min N]` / `stop` /
  `status`. Writes `<cwd>/.context/.durability/active-run.json` (TTL default 180 min) and logs
  run-start/stop to `~/.aidex/durability/events.jsonl`. The durable skills (plan-exec / loop /
  audit / backlog) call this at their start/end. With hook **A** active it is **audit + fallback
  only** (A judges by content, not the file); with **B** active it is the activation gate.
- `test-durability-hook.sh` — 11 isolated stdin tests for the command hook (B). No activation
  needed. The native hook (A) is only validatable **live** (a model-backed hook can't be unit
  tested by piping JSON).

## Status

Hook A (native prompt) is wired as primary. Its live behavior is confirmed only in a real
session (by design — model-backed hooks aren't pipe-testable); if the schema is off it fails
open (allows the stop). Hook B is unit-tested (11/11) and validated by direct invocation.
Recommended check: after a durable run, grep the transcript for `[durability-arbiter]` to see
the enforced continuations.
