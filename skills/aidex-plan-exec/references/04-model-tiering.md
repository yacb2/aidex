# Model tiering — which model does which step

Standing preference for multi-phase execution: the heavy model only where design
judgment matters, cheap models for the mechanical steps, and the orchestration itself
deterministic.

| Step | Model |
|---|---|
| Orchestration in the main loop — between-phase review, commit per plan-exec discipline | the orchestrator model |
| Implementation agents — code that requires design judgment | `opus` |
| Mechanical work — running suites, updating plan checkboxes, number swaps, adding mocks, `beforeEach` setup | `sonnet`, or `haiku` for the purely mechanical |

Default to one workflow per phase with this tiering.

## The prompt trap

An agent prompt that starts `TASK: Plan task 2.4 — …` is read as the imperative
*produce a plan*, and the agent returns a spec with no code. Phrase implementation
prompts as **"IMPLEMENT plan task X (write actual code — not a planning task)"**.

## Constraints that override the tiering

- Chains that touch a database stay **sequential** — a shared Postgres is one resource.
- No parallel agents editing a repo's shared files (`__init__.py`, routers), and note
  that parallel sessions share one git working tree.
- Embed the operating rules in every agent prompt: `docker compose run --rm`, never
  `exec`; no commits or pushes from agents.

## The bulk-fixture loop

For refreshing stale test fixtures in bulk after production has outpaced the tests, the
orchestrator does **not** edit test files — it reads the failing test, diagnoses the
exact delta against current production code, writes a surgical prompt naming file paths
and expected changes, delegates, verifies GREEN independently, and commits. One commit
per fixture group. Run `/simplify` before committing only when the diff is substantive.
After editing shared test infrastructure, run the whole suite before committing. When a
cheap model adds scope creep, check it against the actual source before reverting — a
mock it added may be one the component genuinely imports.
