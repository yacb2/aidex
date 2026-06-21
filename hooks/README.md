# Durability Stop-hook (optional, opt-in — NOT auto-installed)

The **enforcement** half of execution durability. The `durability-arbiter`
(`skills/aidex-conventions/agents/`) is the *judgment* layer — but it only fires if the
agent *chooses* to consult it before stopping. The failure mode we actually see is the
agent **just stopping** ("the rest needs your decision"). The only surface that fires on
that involuntary stop is a Claude Code **Stop hook**. This is that hook.

> **Why this is not shipped by `install.sh`.** aidex ships skills + rules, never hooks. A
> Stop hook is an environment-wide behavioral change (it fires at every turn-end in every
> session it's configured for) with real blast radius — it caused a deadlock before. So
> it lives here, versioned and tested, but **activation is your explicit call.**

## Components

- `durability-stop-hook.sh` — the hook. **Inert** unless a run is declared (below). On an
  involuntary stop during an active run, it blocks-to-continue with a canon-derived reason.
- `durability-run.sh` — `start <type> [--mode remind|enforce] [--ttl-min N]` / `stop` /
  `status`. Writes `<cwd>/.context/.durability/active-run.json`, which the hook reads.
- `test-durability-hook.sh` — isolated stdin tests (11, all green). No activation needed.

## Safety (why it can't deadlock you like before)

1. **Inert by default** — does nothing unless `active-run.json` exists in the project.
2. **`stop_hook_active` guard** — blocks at most once per stop cycle; Claude Code caps
   consecutive stop-blocks at 8. A wrong block costs at most one extra turn, never a hang.
3. **Expiry** — the state file always carries a TTL (default 180 min); a forgotten run
   never traps a future session.
4. **Never blocks a legit stop** — publication asks, hard blockers, and explicit
   completion are always allowed through.
5. **Two modes** — `remind` (default): blocks only on explicit over-stop signals
   ("¿quieres que continúe?", "should I proceed?"). `enforce` (opt-in): blocks unless the
   message is a clear terminal state.

## Activate (your call — review first)

```bash
# 1. See it work, no activation:
bash hooks/test-durability-hook.sh

# 2. Add the hook to your Claude Code settings (user or project settings.json):
#    "hooks": { "Stop": [ { "hooks": [ { "type": "command",
#      "command": "/Users/yoelacevedo/Documents/projects/aidex/hooks/durability-stop-hook.sh" } ] } ] }

# 3. Mark a durable run when one starts, clear it when done:
bash hooks/durability-run.sh start plan-exec --mode remind   # at Orient
bash hooks/durability-run.sh stop                            # at completion
```

The durable skills (plan-exec / loop / audit / backlog sweep) should call
`durability-run.sh start/stop` at their Orient/Final steps once you adopt the hook — left
unwired for now so nothing changes until you opt in.

## Status

Built + unit-tested in isolation. **Not validated end-to-end in a live session** (that
needs activation). Recommended first try: `remind` mode on a single plan-exec run, then
check the next usage-retro for fewer "¿por qué te detuviste?" pauses.
