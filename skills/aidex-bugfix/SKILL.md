---
name: aidex-bugfix
description: >
  Use when fixing a bug, resolving a reported issue, or when something is broken and needs a
  test-driven fix — investigate root cause, write a failing regression test (RED), implement the
  minimum fix, confirm the test passes (GREEN), then commit test and fix together. Fires on "fix
  this bug", "this is broken", "it's not working", "there's a regression", "resolve this issue",
  or a reference to a bug report. Not for: planning multi-step work (aidex-plan); executing a
  written plan phase-by-phase (aidex-plan-exec); recording why a fix was chosen as an ADR
  (aidex-decision); pure refactors with no bug.
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-bugfix"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Bug Fix Workflow

Test-driven bug fixing methodology that ensures every fix includes a regression test.

## When to Use

- User reports a bug or broken behavior
- User references a bug report or issue tracker
- You discover a bug while working on something else
- User says `/aidex-bugfix`

## Core Principle

**Every bug fix MUST include a regression test.** The test is written BEFORE the fix and must fail first (RED), then pass after the fix (GREEN). This is non-negotiable.

## Workflow

The bug-fix workflow is these seven steps — the agent table and prose below key to their step numbers:

1. Investigate root cause (don't guess)
2. Write test that reproduces bug (must FAIL) — **read**
   `~/.claude/skills/aidex-bugfix/references/test-patterns.md` **before choosing the
   test type**: it holds the signal→type decision matrix, the naming convention, the
   regression-test structure, and the cases where an automated test is the wrong call.
   The summary below is the first column of that matrix, not a substitute for it.
3. Confirm test fails **for the right reason** — the failure message names the buggy behavior, not an import/syntax/setup error. Verify this before writing the fix.
4. Implement minimum fix
5. Confirm test passes — capture the GREEN output as proof (see *Proof of done*)
6. Run surrounding tests (no regressions)
7. Commit test + fix together

## Agent Configuration

This skill uses specialized agents for parallel investigation:

| Agent | Model | Purpose | When |
|-------|-------|---------|------|
| `bug-investigator` | Sonnet | Trace root cause through code | Step 1 |
| `test-scout` | Sonnet | Find related tests and patterns | Step 1 |
| `regression-checker` | Sonnet | Verify no regressions after fix | Step 6 |
| Main session | Opus | Write test, write fix, decisions | Steps 2-5, 7 |

Agent definitions: `agents/` directory in this skill folder.

## Test Type Decision Guide

Summary of the matrix in `test-patterns.md` (step 2 reads the full file). Adapt the
categories to your stack — the framework names below are examples; the `test-scout` agent
detects the project's actual runners from its config files:
- **Unit test**: Pure functions, utilities, formatters, validators (e.g. Vitest, Jest, pytest)
- **Component/integration test**: UI component rendering or API endpoint behavior (e.g.
  Vitest + Testing Library, pytest + a test client)
- **E2E test**: Full user flows, multi-page interactions (e.g. Playwright, Cypress)

## Integration with Other Skills

- Apply root-cause-first investigation in Step 1 (don't patch the symptom)
- Defer to the project's own testing helpers/patterns for how to write the test
- Follow the project's commit conventions for Step 7 (detect them; `git-commit` if present)
- If Step 7 needs a new branch (e.g. you were on the default branch), resolve and state its
  base first — default branch unless explicitly confirmed otherwise (aidex-worktree's branch-base rule)
- If the project tracks coverage (`.context/audits/test-coverage/module-map.json`
  exists) and the bug lived in a mapped module, note in the wrap-up: a real bug here is
  evidence of a coverage hole — suggest `/aidex-audit coverage-sweep` and, if the fix
  revealed a flow with no depth coverage, a `COV-<module>-<n>` finding.
- If the project tracks a changelog, update it per the project's own rules
- **Proof of done.** The RED→GREEN pair *is* the proof the bug is fixed — don't
  claim it without it. Record it as one commit-body line naming (a) the RED
  failure reason and (b) the GREEN command + result — e.g.
  `RED: AssertionError expected full IBAN / GREEN: vitest 730/730`. For a rare
  larger capture, save it under `.context/proofs/<slug>/` and reference it via
  `proof_links` per `aidex-conventions` (`00-global.md` §7.1). This is a
  byproduct of Steps 3 and 5, not a separate step.
- **Loop (opt-in):** once the RED test exists *and* the root cause is understood, a fix that needs
  many mechanical variations to land green can be spec'd as an `aidex-loop` loop-spec (stop
  condition = the RED test passes **and** the full suite stays green) and handed to `/goal` or
  `ralph-loop`. Default stays the in-session RED→fix→GREEN cycle — do **not** make this skill a
  loop runner. **Guardrail:** a single green test rewards overfitting, not a real fix — the gate
  must be the test **plus** the Step-1 root-cause hypothesis **plus** the full suite, ideally with
  a maker≠checker split, and only once the RED test failed **for the right reason** (the failure
  message named the buggy behavior, not an import/syntax/setup error). Green-one-test ≠ bug fixed.

## Exception: Visual/CSS-only Bugs

When a bug is purely visual (CSS layout, spacing, colors) and cannot be tested programmatically:
1. Still investigate root cause
2. Document the visual issue clearly
3. Fix it
4. Write a smoke test if any aspect is testable (e.g., component renders, class is applied)
5. Commit with clear description of what was visually broken
