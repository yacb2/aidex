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

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "$AIDEX_TRIGGER_EVAL_MARKER"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Bug Fix Workflow

Test-driven bug fixing methodology that ensures every fix includes a regression test.

## When to Use

- User reports a bug or broken behavior
- User references a bug report or issue tracker
- You discover a bug while working on something else
- User says `/aidex-bugfix` (full guided workflow)

## Core Principle

**Every bug fix MUST include a regression test.** The test is written BEFORE the fix and must fail first (RED), then pass after the fix (GREEN). This is non-negotiable.

## Quick Reference

If not using the full `/aidex-bugfix` command, follow this checklist:

1. Investigate root cause (don't guess)
2. Write test that reproduces bug (must FAIL)
3. Confirm test fails
4. Implement minimum fix
5. Confirm test passes
6. Run surrounding tests (no regressions)
7. Commit test + fix together

## Agent Configuration

This skill uses specialized agents for parallel investigation:

| Agent | Model | Purpose | When |
|-------|-------|---------|------|
| `bug-investigator` | Sonnet | Trace root cause through code | Phase 1 |
| `test-scout` | Sonnet | Find related tests and patterns | Phase 1 |
| `regression-checker` | Sonnet | Verify no regressions after fix | Phase 5 |
| Main session | Opus | Write test, write fix, decisions | Phases 2-4, 6 |

Agent definitions: `agents/` directory in this skill folder.

## Test Type Decision Guide

Read `references/test-patterns.md` for detailed guidance on choosing the fastest reliable
test type. Adapt the categories to your stack — the framework names below are examples; the
`test-scout` agent detects the project's actual runners from its config files:
- **Unit test**: Pure functions, utilities, formatters, validators (e.g. Vitest, Jest, pytest)
- **Component/integration test**: UI component rendering or API endpoint behavior (e.g.
  Vitest + Testing Library, pytest + a test client)
- **E2E test**: Full user flows, multi-page interactions (e.g. Playwright, Cypress)

## Integration with Other Skills

- Apply root-cause-first investigation in Phase 1 (don't patch the symptom)
- Defer to the project's own testing helpers/patterns for how to write the test
- Follow the project's commit conventions for Phase 6 (detect them; `git-commit` if present)
- If the project tracks a changelog, update it per the project's own rules

## Exception: Visual/CSS-only Bugs

When a bug is purely visual (CSS layout, spacing, colors) and cannot be tested programmatically:
1. Still investigate root cause
2. Document the visual issue clearly
3. Fix it
4. Write a smoke test if any aspect is testable (e.g., component renders, class is applied)
5. Commit with clear description of what was visually broken
