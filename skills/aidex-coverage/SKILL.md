---
name: aidex-coverage
description: 'Use when writing, placing, or running tests in any project — which layer a behaviour belongs in ("unit or E2E for X", "component test or browser test"), which tests to run for a change instead of the whole suite, when to extract a fixture, setting up an isolated disposable E2E environment, or the per-project testing profile and the stack pack it names for the concrete test shapes (Django, Vue, Playwright, Payload, Svelte). Fires on "write a test for", "add a regression test", "which tests should I run", "run only the affected tests", "set up E2E for this project", "generate test-e2e.sh", "how do we test this stack". Not for: running a coverage audit, the module map / coverage matrix, tracking a finding, or suite-speed measurement — all of that is aidex-audit''s test-coverage playbook.'
allowed-tools: Bash Read Grep Glob Write Edit
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-coverage"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Coverage

> **Scope.** Model-invocable since 2026-08-26 (`decision/2026-08-26-coverage-canon-consolidation-and-targeted-runs.md`, D1). Stack-agnostic since 2026-08-27 (`decision/2026-08-27-aidex-is-stack-agnostic-stack-packs.md`): this skill carries the doctrine — layers, selection, fixtures, the boundary gate, the profile — and no framework content; the concrete test shapes live in the stack packs the project's profile names. Precision against `aidex-audit` is the `Not for` clause; the eval set in `evals/` is owed a run against this description.

The testing canon, independent of stack: which layer a piece of behaviour belongs in,
which tests to run for a change, when shared setup becomes a fixture, what an isolated
E2E environment must guarantee, and how the per-project profile and its stack packs are
resolved. What a test *looks like* in a given framework is not here: the project's
`.context/testing-profile.md` names its **stack packs** (`testing_packs`), and this skill
reads them — see [Resolving the stack packs](#resolving-the-stack-packs). Per-project
facts (ports, database names, commands, personas) live in that profile, never here — see
[references/14-testing-profile.md](references/14-testing-profile.md).

**The full suite is a boundary gate, not a phase gate.** Per change, run the narrowest
selection that can observe it (`/aidex-audit affected-tests --command`, or the profile's
single-test command, or one spec via `./test-e2e.sh e2e/<spec>.spec.ts`); the whole suite
runs once, at plan close-out or pre-merge (D4). Measured before this rule: 32% of test
runs inside unattended sessions were full suites, E2E at ~5 min each.

**What this skill is not.** It does not run an audit, does not build or read
`module-map.json` or `coverage-matrix.json`, does not track a finding through its
lifecycle, and does not carry the suite-speed measurement procedure. All of that is
`aidex-audit`'s `test-coverage` playbook (`skills/aidex-audit/assets/templates/methodology/test-coverage.md.template`).
The split is by type, not by overlap: this skill owns the reference corpus and authoring
rules — including the per-module judgment-pass checklist (`references/06-judgment-pass.md`)
that the playbook's judged layer runs; the playbook owns inventory, finding lifecycle,
matrix, sweep and escalation, and is the one that executes that checklist. The
one rule with a foot in both — "a coverage percentage without a declared denominator is
not a measurement" (`m7`) — is not duplicated: the playbook runs it as an inventory-time
check ("is the denominator declared? can coverage even run?"), this skill states it as an
authoring rule for anyone writing a new coverage-bearing test.

## When to read what

| Question | Read |
|---|---|
| Which layer does this test belong in? | [references/01-layer-model.md](references/01-layer-model.md) |
| What does current upstream documentation say about a stack-independent correctness or cost trap? | [references/02-best-practices.md](references/02-best-practices.md) |
| When do I extract a fixture? | [references/03-fixtures-convention.md](references/03-fixtures-convention.md) |
| When does a frontend test file move to `__tests__/`? | [references/03-fixtures-convention.md](references/03-fixtures-convention.md) |
| How do I run a full-scale layer audit of an E2E suite? (template + row format) | [references/04-e2e-layer-audit.md](references/04-e2e-layer-audit.md) |
| How do I check changed-lines coverage on a branch? | [references/05-diff-cover.md](references/05-diff-cover.md) |
| What is the per-module checklist the playbook's judged layer runs (endpoint census, scaffold sweep, cross-layer duplicates)? | [references/06-judgment-pass.md](references/06-judgment-pass.md) |
| Which tests do I run for this change, and when does the selection widen? | [references/13-affected-tests-expansion.md](references/13-affected-tests-expansion.md) |
| What goes in the per-project profile, which stack packs exist, and what never goes in the profile? | [references/14-testing-profile.md](references/14-testing-profile.md) |
| How do I write a backend / component / store / E2E test, which helpers exist, how is the disposable E2E environment built and `test-e2e.sh` generated, how do seed generators work? | The stack pack named by the profile — see below |

This is the only table of references; [references/00-index.md](references/00-index.md)
records which plan phase produced each file.

## Resolving the stack packs

1. Read `<project>/.context/testing-profile.md`. If it does not exist, seed it:
   `python3 ~/.claude/skills/aidex-coverage/scripts/profile-init.py <project>` (never
   `--force` over an existing one; blank keys are unanswered, not zero).
2. Take `testing_packs` — a space-separated list of skill names — and read each pack's
   `~/.claude/skills/<pack>/SKILL.md`; its "Question -> file" table says which of its
   references answers the question at hand. Read with Read; a pack is never invoked as a
   skill (`disable-model-invocation: true`), so nothing fires on its own.
3. Apply the doctrine here first — layer, selection, gate — then the pack's shape. When
   the two disagree, the doctrine wins and the disagreement is a project decision, not a
   profile line.
4. `testing_packs` blank or naming a pack that is not installed: say so and name the
   missing pack; do not improvise the framework content from memory, and do not add it
   to this skill. A stack with no pack gets a new `testing-<framework>` pack in
   `myskills` (the shape is in `references/14-testing-profile.md`).

The full pack table is in [references/14-testing-profile.md](references/14-testing-profile.md).

## How to use the layer model

1. Read [references/01-layer-model.md](references/01-layer-model.md)'s six layers and the
   assignment rubric.
2. Apply the rubric's maxim: **test the decision, not the pixels — except when the browser
   is what decides.** If the correctness question is "did the right thing happen" (a total
   computed, a row persisted, a permission enforced), it belongs at the lowest layer that
   can observe that. If the correctness question is "did the browser render, lay out, or
   navigate correctly" — CSS-dependent behaviour, focus order, a router transition — or
   "does the real frontend + backend + database integration hold", which a mock cannot
   vouch for, no layer below E2E can answer it, so that is where it belongs.
3. State the layer and the one-sentence reason when proposing where a new test goes; do
   not silently default to E2E because it is the layer that can see everything — that is
   exactly the over-assignment the rubric exists to prevent.

## How to use the best-practices corpus

[references/02-best-practices.md](references/02-best-practices.md) holds the
stack-independent entries: item 5 quotes a fetched primary source with its check date, item
1 records the sweep itself, item 4 is flagged `unverified`, items 7 and 8 point to
`01-layer-model.md`, and items 2, 3 and 6 are stubs pointing at the stack pack that now
carries them (a framework trap lives with its framework). **Do not extend this file by transcribing anything from a chat, a consultation
artifact, or a session transcript.** A new item is only added once its primary source has
been fetched and quoted, with a version and a date attached — that constraint is the reason
this file exists rather than a copy of an unverifiable draft. Items marked `unverified` are
flagged as such deliberately and must not be promoted to a stated fact without re-checking
the source.

## How to use the fixtures convention

[references/03-fixtures-convention.md](references/03-fixtures-convention.md) states the
rule-of-three trigger (extract to `__fixtures__/` at the third test repeating the same
setup), the authoring form of `m7`, and the `__tests__/` layout ratchet (`s4`): a test file
moves to `__tests__/` when the code it covers is touched, never as a scheduled mass move.
All three are mechanical, not a judgment call — apply them while writing or moving tests,
not only when reviewing them later.

## How to use the E2E layer audit

[references/04-e2e-layer-audit.md](references/04-e2e-layer-audit.md) is the template:
scope discipline, row format, and how a verdict is argued against the rubric above —
`E2E` (stays) or `candidate` (a lower layer could observe the same failure). A completed
table is project data and lives in that project's own `.context/`, never in this skill
(BL-211). It is an audit, not a queue — a `candidate` verdict names the reason and the
likely lower layer; deciding to move a spec, and moving it, is separate work.

## How to use diff-cover

[references/05-diff-cover.md](references/05-diff-cover.md) documents the on-demand
changed-lines coverage check: the exact host-run command, the recorded threshold and its
ADR, and why it is never a hook or CI gate (`q4`). Point someone here when a `gap` finding
is being closed with new tests, or when asked "did the branch I just wrote test its own
changes" — never propose wiring this into a hook or pipeline; the reference states why not.
