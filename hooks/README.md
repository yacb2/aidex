# Durability Stop-hook (optional, opt-in — NOT auto-installed)

The **enforcement** half of execution durability. The `durability-arbiter`
(`skills/aidex-conventions/agents/`) is the *judgment* layer — but it only fires if the
agent *chooses* to consult it before stopping. The failure mode we actually see is the
agent **just stopping** ("the rest needs your decision"). The only surface that fires on
that involuntary stop is a Claude Code **Stop hook**. This directory holds three
implementations — A is the validated active one.

> **Why this is not shipped active by `install.sh`.** `install.sh` copies these files to
> `~/.aidex/hooks/` but wires nothing. A Stop hook is an environment-wide behavioral change
> (it fires at every turn-end in every session it's configured for). **Activation is your
> explicit call**: you add the hook to `~/.claude/settings.json` yourself.

## A. Native AGENT hook (`type:"agent"`) — ACTIVE (validated 2026-06-27)

A Claude **subagent** judges the stop with criterion — it can read the transcript and inspect
the project before deciding, so it handles the many different ways a premature stop is phrased
(which a regex cannot). Validated live in isolation: allow-case clean, block-case blocks with a
sensible reason, **no prompt leak** into the conversation, no infinite loop.

- **Prompt:** [`durability-stop-prompt.md`](durability-stop-prompt.md) is the canonical source
  (English-only, no hardcoded phrases — the agent judges by substance). `settings.json` carries
  an inline copy; edit the `.md` then re-inject (snippet below).
- **Contract:** the subagent returns `{"ok": true}` (allow) or `{"ok": false, "reason": "..."}`
  (block → Claude continues). On block CC injects **only the reason** (prefixed
  `Stop hook feedback: Agent hook condition was not met:`), NOT the prompt — confirmed clean.
- **Model:** set via `model`. **MUST be the full id (`claude-sonnet-4-6`)** — the alias
  `"sonnet"` silently breaks the hook (it does not run). Default if omitted is **Haiku**
  (`claude-haiku-4-5`). We run Sonnet for better judgment.
- **Cost/latency:** a subagent runs at **every turn-end in every session** it is configured
  for (Sonnet, can read the transcript) — heavier than a single completion. Watch this during
  evaluation; if too heavy, drop to Haiku (omit `model`) or scope it.
- **Anti-loop:** the prompt returns `{"ok": true}` when `stop_hook_active` is true; CC also caps
  consecutive blocks. Marked **experimental** in the CC docs.
- **Audit:** a block's reason begins with `[durability-arbiter]` → greppable in transcripts.

Activate (in `~/.claude/settings.json` → `"hooks"`):
```jsonc
"Stop": [
  { "hooks": [ { "type": "agent", "model": "claude-sonnet-4-6",
                 "prompt": "<contents of durability-stop-prompt.md>", "timeout": 120 } ] }
]
```
Re-inject the prompt after editing the `.md`:
```bash
python3 - <<'PY'
import json, os
s = json.load(open(os.path.expanduser("~/.claude/settings.json")))
p = open(os.path.expanduser("~/.aidex/hooks/durability-stop-prompt.md")).read().strip()
s["hooks"]["Stop"] = [{"hooks": [{"type": "agent", "model": "claude-sonnet-4-6", "prompt": p, "timeout": 120}]}]
json.dump(s, open(os.path.expanduser("~/.claude/settings.json"), "w"), indent=2)
PY
```

## B. Native PROMPT hook (`type:"prompt"`) — DO NOT USE (broken in CC 2.1.x)

Tried 2026-06-27 and reverted: instead of a silent judge, CC **injected the entire prompt text
into the conversation as a visible `Stop hook feedback` user message on every stop**. The
judgment fired, but dumping the prompt into the chat is unusable. The documented `{"ok":...}` /
`$ARGUMENTS` contract did not match observed behavior for this type. Kept only as a cautionary
note; use A instead.

## C. Deterministic command hook (`type:"command"`) — SWAP-BACK FALLBACK

[`durability-stop-hook.sh`](durability-stop-hook.sh) — a regex over the last assistant message.
No model, no cost, can't-fail, testable by piping JSON. Weakness: a fixed term list misses
novel stop phrasings and can trip on casual endings. Inert unless
`<cwd>/.context/.durability/active-run.json` exists (scoped to declared runs). Use if A proves
too heavy or flaky:
```jsonc
"Stop": [ { "hooks": [ { "type": "command", "command": "~/.aidex/hooks/durability-stop-hook.sh" } ] } ]
```

> **Never chain blockers as siblings.** When multiple Stop hooks run, the most-restrictive answer
> wins — a regex *block* would override a model *allow*. Wire exactly one at a time.

## Supporting scripts

- `durability-run.sh` — `start <type> [--mode remind|enforce] [--ttl-min N]` / `stop` / `status`.
  Writes `<cwd>/.context/.durability/active-run.json` and logs run-start/stop to
  `~/.aidex/durability/events.jsonl`. The durable skills call this at their start/end. With hook
  A active it is **audit only** (A judges by content); with C active it is the activation gate.
- `test-durability-hook.sh` — 11 isolated stdin tests for the command hook (C). Hooks A and B are
  only validatable **live** (model-backed) — A was validated via isolated `claude -p` runs.

## Status

**Hook A (`type:"agent"`, Sonnet) is the active default**, validated live (no leak, blocks with
criterion). Takes effect on the next Claude Code session start. Hook B is broken (kept as a
warning). Hook C is the deterministic fallback (11/11). After a durable run, grep transcripts for
`[durability-arbiter]` to see enforced continuations.
