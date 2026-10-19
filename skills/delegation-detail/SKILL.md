---
name: delegation-detail
description: Use before writing any Agent brief or deciding whether to delegate, split or fan out work - brief shape (files to read first, what you left alone), when delegating pays, unit cap, parallel launch, liveness of a running delegate, impl loop and review/browser gates before a commit.
---

# Delegation detail

How to brief, size, launch and gate delegates. The routed agents ship with the plugin and
are named `aidex:<name>` in `subagent_type`: `aidex:artifact-sonnet`, `aidex:backlog-filer`,
`aidex:bugfix-opus`, `aidex:figure-sonnet`, `aidex:gate-runner`, `aidex:impl-sonnet`,
`aidex:lookup-sonnet`, `aidex:research-sonnet`, `aidex:review-diff-opus`,
`aidex:smoke-sonnet`, `aidex:synthesis-sonnet`, `aidex:task-general`,
`aidex:verify-browser-opus`, `aidex:verify-browser-sonnet`.

## The brief

A brief names paths, never "the file we discussed": goal, where to work, what to read first,
what is forbidden, how to verify, what to return. Use a fresh agent always; a fork only when
what the task needs exists nowhere but in this conversation (a fork costs several times a
fresh agent). Two parts are load-bearing; keep them as *named sections*, not sentences in a
paragraph:

- **"Files to read first"**, as the brief's own first step. The same sentence buried in a
  lead paragraph is not acted on; as a named first step the canon actually gets read.
  Name any file over about 25 KB as a Read-tool target: a Bash result over about 30000
  characters reaches the agent only as a ~2 KB preview, so `cat`, `sed` or `head` of it reads
  almost nothing (measured on aidex:artifact-sonnet runs).
- **"what you deliberately left alone"**, inside what to return: every defect or edge the
  delegate saw and did not touch, one line each, no fix. A delegate is fresh by
  construction, and a fresh context is the one that lacks the caution a long session builds
  up, so this section is what restores it, for a small extra cost. Say it in your own
  session's work too while the context is still young.

## When delegating pays

A delegate costs a brief (about one turn) plus a short reply. Doing the work here costs
every call times the current context depth, and that output is re-read on every later turn.
So: **delegate when re-reading your context costs more than a brief.** Early in a session,
with a small context, keep a short job here unless the part is itself token-heavy (a
transcript sweep, a long command's output). Late in a session, or on a model that charges a
lot to re-read context, the balance flips and delegating is cheaper. This skill states the
principle, not a per-model depth table: prices change and the numbers behind such a table
are the owner's own ledger.

## Unit cap

**One delegate, one unit of at most about 80 turns.** A plan phase or one backlog item,
never "phase 4 plus propagation". A bigger unit is cut into serial delegates, or parallel
ones on disjoint files. A delegate's own context grows every turn, so long runs cost more
per turn and lose more than short ones; most of the observed loss was in delegates of 120+
turns, which is why the cap matters more than any depth floor.

## Cut by size, not only by kind

When routing an implementation part, check whether it splits into N units of the same agent
type, and fan out when all three hold: (1) the units touch disjoint files and share no
stateful gate; (2) each is a real unit on its own, roughly 25+ turns with its own test;
(3) time matters now - someone is waiting or the next step is blocked on it. Any condition
missing: one delegate. The main session makes this cut; no coordinator agent does (it pays
its own context cost and cannot spawn).

## Parallel launch

**Independent units always launch together.** Units that are already separate - read-only
ones, or ones on disjoint files sharing no database, port, browser or other stateful gate -
go out in one message, whatever their size or urgency. The three conditions above govern
only whether to split ONE unit; launching units that would be delegated anyway costs no
extra tokens. **Before every launch, one line:** what this unit reads that another pending
unit writes; if anything, it waits for that hand-back.

- Writers get one worktree each; this session integrates them in order. Never let a
  delegate commit.
- Read-only or measurement units have no cap of their own, but the harness runs at most
  `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` subagents at once (default 20, configurable):
  a launch past that value errors, it is not queued. Batch a larger fan-out at that value, keep the
  rest in a scratchpad queue, and refill on each hand-back.
- ONE browser unit at a time: the shared browser page is global state.
- Writers in worktrees: soft cap of three, because this session reviews and integrates
  them serially.

## Liveness

"Is it still alive" is answered by reading the delegates' transcripts or the harness's
agent status view (0 tokens), never by pinging the agent with `SendMessage`, and never used
to decide it finished; only its own hand-back says that. Check when the user asks, or once a
delegate passes about 30 minutes of wall time, then every 15 minutes. Stale means a tool
past its timeout by a minute, or 15 minutes with no record while waiting on the model:
stop it with `TaskStop` and relaunch the same brief. Almost every delegate that looks hung
is waiting on its own shell command; the agent definitions forbid sleep-poll loops for that
reason.

A delegate whose notification says it is waiting on its own background work is not stale
and still counts as a running subagent: no handoff, no `TaskStop` while it waits. Its
liveness is its command's output file (the one the notification names, or the file the
command itself redirects to). While that file grows, it is alive. If the file already holds
the command's closing line and no hand-back came, the wake-up was lost: send it one
`SendMessage` asking for its report, the only ping this section allows, because `TaskStop`
would re-run the whole suite. If the file has not grown for 15 minutes and holds no closing
line, it is stale: `TaskStop` and relaunch.

## Gates before a commit

- **Predicate shape goes to `aidex:review-diff-opus` first:** a diff that adds or moves a
  comparison, a quantifier, a boundary or a null/empty branch inside a predicate. Gate-green
  diffs of exactly this shape hid the defects found in review, whatever model wrote them.
  Not for read-only delegates, prose, layout, file moves or config edits.
- **A diff that changes what a screen does goes through the browser before the commit:**
  `aidex:smoke-sonnet` for behaviour (the flow the diff touched), `aidex:verify-browser-sonnet`
  for measurable appearance, `aidex:verify-browser-opus` for judgment-only appearance. The
  diff reviewer reads predicates and cannot see UI behaviour.

## Implementation goes to `aidex:impl-sonnet` at medium effort

Never to a low-effort agent: a low-effort implementer repeated the same wrong quantifier and
missed boundary cases, all gate-green. `aidex:review-diff-opus` stays on opus and stays
mandatory for the predicate shape; it is the net. Lookups and syntheses keep a cheap
model at low effort. The line is the task, not the model: **anything whose correctness a
gate cannot check goes to a medium-effort agent and through `aidex:review-diff-opus`.**

## The impl loop while someone waits

Most of the wall time per answer is serial review, E2E inside the implementer and a brief
that narrowed the decision, not code writing. Five moves:

- **Brief against decision.** Before launching a brief that carries a decision from the
  user, write one line: "brief says X, user said Y". Fix any narrowing before launch.
- **No E2E in an impl brief.** "Tests that must pass" names the changed tests, the affected
  selection, the type check and lint. E2E specs the change hits run on `aidex:gate-runner`
  once per merge, in parallel with the review.
- **On an impl hand-back, launch together:** `aidex:review-diff-opus` (when its shape
  applies) and `aidex:gate-runner` for E2E (at merge). A DO NOT SHIP verdict goes back to the
  same impl agent through `SendMessage`, never a fresh one.
- **The review brief carries the diff's file:line list and the prior round's verdict**, so
  the reviewer starts where the last one stopped. It may still read beyond the list.
- **One answered page, one impl brief.** Answers to one consultation round go out as one
  brief, never one per answer.
