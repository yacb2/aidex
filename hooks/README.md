# Durability Stop-hook (optional, opt-in — NOT auto-installed)

The **enforcement** half of execution durability. The `durability-arbiter`
(`skills/aidex-conventions/agents/`) is the *judgment* layer — but it only fires if the
agent *chooses* to consult it before stopping. The failure mode we actually see is the
agent **just stopping** ("the rest needs your decision"). The only surface that fires on
that involuntary stop is a Claude Code **Stop hook**. This directory holds the
implementations — the judge-gated command hook (C) is the active one.

> **Why this is not shipped active by `install.sh`.** `install.sh` copies these files to
> `~/.aidex/hooks/` but wires nothing. A Stop hook is an environment-wide behavioral change
> (it fires at every turn-end in every session it's configured for). **Activation is your
> explicit call**: you add the hook to `~/.claude/settings.json` yourself.

## What is actually configured today (2026-07-04)

`~/.claude/settings.json` runs **hook C** (`type:"command"` →
`durability-stop-hook.sh`). It was swapped in on 2026-07-02 (hook A demoted for
per-turn cost) and, per BL-044, hook C is now **judge-gated**: cheap deterministic
gates first, then a model judge — see below. If your `settings.json` entry still
carries `"timeout": 30`, raise it to **90** so the judge (internal 60s cap) is
never killed by the hook timeout.

## C. Judge-gated command hook (`type:"command"`) — ACTIVE

[`durability-stop-hook.sh`](durability-stop-hook.sh). Decision ladder, cheapest first:

1. **Recursion guard** — `AIDEX_STOP_JUDGE=1` (set for the judge subprocess) → allow.
2. **Anti-deadlock** — `stop_hook_active` → allow (blocks at most once per cycle).
3. **Inert gate** — no/expired `<cwd>/.context/.durability/active-run.json` → allow.
   This is the cost gate: casual sessions never reach the judge. Zero model calls.
4. **Background tasks** running → allow (not a real end).
5. **LEGIT terminal regex** (publish ask / hard blocker / plan complete) → fast allow.
6. **Model judge (BL-044)** — `claude -p --model claude-sonnet-5` (full id REQUIRED;
   the alias `"sonnet"` silently breaks model-backed hooks — see commit 20b8d56) with
   the [`durability-stop-prompt.md`](durability-stop-prompt.md) policy + the hook input
   (last_assistant_message, cwd, transcript_path, active-run state) on stdin, asking for
   a strict `{"block": bool, "reason": "..."}` verdict (the prompt's native
   `{"ok": ...}` shape is also accepted defensively). The judge catches what the regex
   cannot: novel stop phrasings, e.g. a mid-plan summary with **no question** (the
   documented 2026-07-02T20:29 regex miss — verified blocked live). Judge command is
   injectable via **`AIDEX_JUDGE_CMD`** (tests mock it); internal timeout 60s.
7. **Regex fallback** — any judge failure/timeout/unparseable output falls back to the
   original OVERSTOP/enforce regex logic. The hook is fail-open overall.

Every decision made while a run is ACTIVE is appended to
`~/.aidex/durability/events.jsonl` with `matched` = `legit-terminal` | `judge` |
`judge-fallback-regex` — grep for `"matched": "judge"` to field-verify the judge path.

Activate (in `~/.claude/settings.json` → `"hooks"`):
```jsonc
"Stop": [ { "hooks": [ { "type": "command",
                         "command": "bash \"$HOME/.aidex/hooks/durability-stop-hook.sh\"",
                         "timeout": 90 } ] } ]
```

## A. Native AGENT hook (`type:"agent"`) — heavier alternative (validated 2026-06-27, demoted 2026-07-02)

A Claude **subagent** judges every stop — same policy, but it runs at **every turn-end in
every session** (no active-run cost gate), which is why it was demoted: ~one Sonnet call
per turn-end, everywhere. It blocked 28 premature stops 06-26→07-01 and remains the
documented option if you want judge quality without declaring runs via `durability-run.sh`.

- **Prompt:** [`durability-stop-prompt.md`](durability-stop-prompt.md) is the canonical
  source (English-only, judges by substance). `settings.json` carries an inline copy;
  edit the `.md` then re-inject (snippet below).
- **Contract:** the subagent returns `{"ok": true}` (allow) or `{"ok": false, "reason": "..."}`
  (block → Claude continues). On block CC injects **only the reason** (prefixed
  `Stop hook feedback: Agent hook condition was not met:`), NOT the prompt — confirmed clean.
- **Model:** set via `model`. **MUST be the full id (`claude-sonnet-5`)** — the alias
  `"sonnet"` silently breaks the hook (it does not run). Default if omitted is **Haiku**
  (`claude-haiku-4-5`).
- **Anti-loop:** the prompt returns `{"ok": true}` when `stop_hook_active` is true; CC also caps
  consecutive blocks. Marked **experimental** in the CC docs.
- **Audit:** a block's reason begins with `[durability-arbiter]` → greppable in transcripts.

Activate (in `~/.claude/settings.json` → `"hooks"`):
```jsonc
"Stop": [
  { "hooks": [ { "type": "agent", "model": "claude-sonnet-5",
                 "prompt": "<contents of durability-stop-prompt.md>", "timeout": 120 } ] }
]
```
Re-inject the prompt after editing the `.md`:
```bash
python3 - <<'PY'
import json, os
s = json.load(open(os.path.expanduser("~/.claude/settings.json")))
p = open(os.path.expanduser("~/.aidex/hooks/durability-stop-prompt.md")).read().strip()
s["hooks"]["Stop"] = [{"hooks": [{"type": "agent", "model": "claude-sonnet-5", "prompt": p, "timeout": 120}]}]
json.dump(s, open(os.path.expanduser("~/.claude/settings.json"), "w"), indent=2)
PY
```

## B. Native PROMPT hook (`type:"prompt"`) — DO NOT USE (broken in CC 2.1.x)

Tried 2026-06-27 and reverted: instead of a silent judge, CC **injected the entire prompt text
into the conversation as a visible `Stop hook feedback` user message on every stop**. The
judgment fired, but dumping the prompt into the chat is unusable. The documented `{"ok":...}` /
`$ARGUMENTS` contract did not match observed behavior for this type. Kept only as a cautionary
note; use C (or A) instead.

> **Never chain blockers as siblings.** When multiple Stop hooks run, the most-restrictive answer
> wins — a regex *block* would override a model *allow*. Wire exactly one at a time.

## Supporting scripts

- `durability-run.sh` — `start <type> [--mode remind|enforce] [--ttl-min N]` / `stop` / `status`.
  Writes `<project-root>/.context/.durability/active-run.json` — the root is the OUTERMOST
  `.context` ancestor of cwd, so start/stop/status agree from any subdirectory and a workspace
  of sibling repos has one marker, not one per repo (BL-075). Hook C resolves the same anchor.
  This is a deliberate divergence from `_lib.sh`'s nearest-ancestor `find_project_root`. Logs
  run-start/stop to
  `~/.aidex/durability/events.jsonl`. The durable skills call this at their start/end. With hook
  C active it is **the activation gate** (no run declared → no judge, no cost); with hook A it
  would be audit only.
- `test-durability-hook.sh` — 35 isolated stdin tests for hook C: regex/gate tests (run with
  the judge mocked as unavailable, exercising the fallback path) + judge tests (mocked block,
  mocked allow overriding the regex, garbage output → regex fallback, marker-absent → judge not
  invoked) + retro-run4 tests (last_user_message extracted from a fixture transcript with the
  noise shapes skipped, answer-to-user allowed, ES gated-publish-only summary allowed) + marker
  lifecycle tests (`durability-run.sh stop` from a subdir removes the root marker; `start` from a
  subdir anchors at the root and `stop` at the root clears it; a sibling-repo start anchors at the
  workspace root; a subdir session cwd still finds the anchored marker; a no-marker stop warns). Hooks A and B are only validatable **live** (model-backed).

## Sunset criterion (falsifiable — retire the hook if it fails)

The hook stays only while it earns its keep. Usage-retro run 4 (2026-07-23) found the
judge produced **6 misfire blocks vs 1 justified catch** — all 6 traced to the judge never
seeing the user's last message. Retro-run4 (this change) fixes the input: the judge now
receives `last_user_message`, the policy allows answer-to-user and gated-publication
terminals, and the marker can no longer leak across subdirs. That is the hook's last chance.

**Retirement rule — measured at the next usage-retro window:** grep
`~/.aidex/durability/events.jsonl` for `"decision": "block"` events since this change and
review each against its transcript. If the hook produced **≥1 misfire block** (blocked a turn
that was a correct answer-to-user, a terminal gated-publication ask, or a genuinely finished
task) **OR 0 justified blocks** (it caught nothing real), remove the `Stop` entry from
`~/.claude/settings.json` and rely on skill-side autonomy + the voluntary durability-arbiter
alone. The measurement is scheduled as a P2 backlog item, so it is done, not remembered.

## Status

**RETIRED 2026-08-03 — the sunset criterion above fired.** The `Stop` entry was removed from
`~/.claude/settings.json`, and the `durability-run.sh start/stop` call sites were removed from
`aidex-audit`, `aidex-backlog`, `aidex-loop`, `aidex-workflow` and `aidex-plan-exec` — the marker
they wrote had exactly one consumer (`durability-stop-hook.sh`), so leaving them would have meant
five skills writing state nobody reads. Durability now rests on skill-side autonomy plus the
voluntary durability-arbiter, which is what the retirement rule designates as the successor.

**Measured verdict (window: blocks since 2026-07-23):** 4 real blocks, **0 justified**, 4 misfires
— all four were answer-to-user terminals, the class the post-retro policy was supposed to allow.
Both arms of the rule fired (≥1 misfire OR 0 justified). Full evidence and the four quoted
terminals are recorded in BL-067.

**Measurement caveat for anyone re-running this:** 435 of the 439 logged blocks in that window came
from the hook's own test suite (`cwd` under `/T/tmp.*`) — the contamination `c2aa1cb` fixed on
2026-08-01, though the historical log stays polluted. Filter by `cwd` or the number is meaningless.
In production the hook never reached `enforce`; all 78 `enforce` blocks were tests.

The scripts (`durability-stop-hook.sh`, `durability-run.sh`, `test-durability-hook.sh`) are kept as
scaffolding, unwired — same disposition as the router. Hook A is the heavier always-on alternative;
hook B is broken (kept as a warning). Re-wiring requires a new falsifiable criterion, not a
recollection that it used to help.

## aidex-router.sh — deterministic prompt router (UserPromptSubmit)

Regex-routes natural ES+EN create-intent phrases ("crea un plan para...", "parkea esto", "usa un worktree") to the matching aidex skill by injecting a routing directive via `hookSpecificOutput.additionalContext`. Precision-first: only taught phrases route (~100%); everything else is a silent no-op. Never blocks — any failure (no jq, malformed payload) exits 0 with no output.

**Intents (ordered, first-match-wins):** aidex-decision, aidex-request, aidex-loop, aidex-backlog, aidex-worktree, aidex (ecosystem), aidex-audit, aidex-skill, aidex-research, aidex-reference, aidex-plan. `aidex-loop` deliberately precedes `aidex-backlog`: "crea un loop ... cerrar backlogs" names backlogs as the loop's target (BL-045).

**False-positive guards (BL-042):**
- `/command` and `<`-prefixed (injected/system-shaped) prompts never route.
- Transcript guard: prompts longer than 700 normalized chars never route — pasted transcripts and multi-topic feedback almost always contain some verb+noun pair.
- Meta-discussion/hypothetical guard: opinion/hypothesis markers ("supongo que", "me imagino", "analices", "que podemos mejorar", "consideras que", "dame tu opinion", ...) skip routing — discussing an artifact is not a create intent.
- Proximity conjunction (`m2`): a rule's noun and verb must co-occur within the same sentence-ish segment (split on `.!?;` + whitespace and newlines), so a noun in one sentence can no longer conjoin with a verb in an unrelated one.

**Registration (opt-in, not done by install.sh):** wire it as a `UserPromptSubmit` hook in settings.json pointing at `~/.aidex/hooks/aidex-router.sh`.

### eval/ — router eval harness

`eval/run-eval.sh [cases.tsv]` pipes every labeled case in `eval/router-cases.tsv` (113 cases: per-skill positives, field-miss positives, live-FP negatives) through the router and prints accuracy, per-class precision/recall/F1, and the negative-case false-positive count. Defaults to the sibling `../aidex-router.sh`; set `AIDEX_ROUTER=/path/to/aidex-router.sh` to eval an installed copy. Gate: 100% accuracy, 0 false positives. TSV format: `expected<TAB>phrase`, `NONE` = must not route; `#` comments and blank lines ignored.

## context-depth-nudge.sh — context-depth band notice (UserPromptSubmit)

> **Opt-in, like every hook here.** `install.sh` copies this file to
> `~/.aidex/hooks/` and wires nothing — `is_symlinkable()` excludes `hooks/*`, so
> it never reaches `~/.claude/`, and settings.json is never touched. Installing or
> updating aidex therefore activates nothing. It runs only if you add it to your
> own `~/.claude/settings.json` yourself (see Registration below). The thresholds
> below were tuned on one person's corpus; treat them as a starting point, not a
> default anyone should inherit.

Surfaces how deep the session's context has grown, once per band, as one line of
`hookSpecificOutput.additionalContext`. Bands: **200k** warn, **250k** advise,
**300k** urgent. Silent below 200k and silent on every later prompt in a band it
already announced. Never blocks; any failure (no jq, missing/malformed transcript,
malformed payload) exits 0 with no output.

**Where the numbers come from.** Measured over 674 Opus 5 sessions / 86,800 turns
(`.context/research/2026-08-13-session-token-threshold-handoff.md`): 87.9% of all
input tokens are spent at depth >=150k; a within-session paired test puts turns at
150-200k at 1.41x the seconds-per-output-token of the same session below 100k,
rising to 1.73x at 400-600k; and a counterfactual replay puts the marginal knee
(tokens saved per additional handoff) between 200k and 250k depending on how
expensive re-entry is assumed to be. 150k was rejected — worst marginal return of
the candidates.

**Why it counts but does not decide.** It does not judge whether to hand off and
does not fire one. The retired durability Stop hook (`2ca548a`) ran a `claude -p`
judge over exactly that call and measured 4 real blocks, 0 justified, 4 misfires,
all on terminals the policy was supposed to allow. Counting tokens is arithmetic
and cannot misfire; judging whether a thread is mid-hypothesis is what did.
`UserPromptSubmit` rather than `Stop` for the same reason — `Stop` can only act by
blocking, the retired failure mode — and because a prompt boundary is where a
handoff is cheapest anyway.

**Depth is `max` over `usage.iterations`, not the top-level sum.** Top-level
`usage` *adds* the iterations of a multi-iteration turn: one observed turn reported
`cache_read_input_tokens: 1,170,043` against a 1M window because its three
iterations (584k/588k/585k) were summed. That figure is what was billed, not what
occupied the window; using it would fire the 300k band at ~100k of real depth on
any turn that iterated three times. Reads the last 400 lines only, so cost does not
grow with transcript size.

**Registration (opt-in, not done by install.sh):** wire it as a `UserPromptSubmit`
hook in settings.json pointing at `~/.aidex/hooks/context-depth-nudge.sh`. Pairs
with a statusline that colours on absolute depth rather than percent-of-window —
on a 1M model, 400k reads as 40% and colours green under a percentage scheme.

> **If you build that statusline, do not use `context_window.total_input_tokens`.**
> It carries the same iteration-summing inflation as the transcript's top-level
> `usage`. Observed 2026-08-13: Claude Code reported 394,807 while the window held
> 198,928 — a 1.98x overstatement that read as red on a green session. The visible
> symptom is a number that *drops*: across 96 consecutive turns in that session,
> real occupancy never fell once, while the reported figure fell 5 times, each time
> a multi-iteration turn was followed by a single-pass one. Compute depth from
> `transcript_path` with the same `max`-over-iterations rule this hook uses, and
> fall back to `context_window` only when no transcript is available.

**Tests:** `python3 test-context-depth-nudge.py` — 22 checks, self-contained
(synthetic transcripts, no dependency on real ones). Covers exact band boundaries,
the max-over-iterations rule, post-compaction depth drops, once-per-band gating
with escalation, six fail-open paths, and the non-blocking output shape.

### Sunset criterion (falsifiable — retire if it fails)

Handoffs already fire at a median depth of 337k on Opus 5, but that depth is not a
choice: trigger depth tracks session *peak* depth at ~1.0x, so no depth-based
trigger is operating today at all. There is therefore no evidence a depth cue will
change timing. Due **2026-09-03**:

> Re-run the predecessor->successor trigger query over Opus 5 sessions started
> after 2026-08-13. **Keep** if the median trigger depth falls below 300k *and*
> below that window's median session peak — the second clause is the real test,
> since merely dropping alongside peak would prove nothing. **Retire** if the
> median trigger still tracks peak within +/-10%, or if the nudge fires more than
> 3x in a median session (noise, not signal).
