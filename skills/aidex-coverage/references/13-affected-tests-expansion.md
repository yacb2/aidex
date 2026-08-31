# Affected-tests expansion

**The rule this file is written under:** escalation never means "run the full suite
now". It means "widen the selection to the named module set". The full suite runs
**once, at the integration boundary** — plan close-out, pre-merge — and never as the
answer to a mid-loop "what do I run?" (decision
`2026-08-26-coverage-canon-consolidation-and-targeted-runs.md`; the script's own header
says the same: "The full suite gates integration, never the inner loop"). A change to
the auth store widens the E2E selection to every authenticated spec's module set; it
does not turn a two-minute loop into a twenty-minute one.

## What the script does

`/aidex-audit affected-tests [--since <ref>] [--command]`
(`skills/aidex-audit/scripts/affected-tests.sh`, logic in `coverage/affected_tests.py`):

- collects changed files per repo (working tree + staged; or `--since <ref>`);
- maps each file to a module in `module-map.json`
  (`.context/audits/test-coverage/`), two tiers: a changed file with a **colocated**
  test narrows to that test, all-or-nothing per module; otherwise module-level impact;
- keeps the module tier **repo-aware**: a module that maps both repos of a two-repo
  workspace emits only the unit-kind globs owned by the repo of a changed file (a
  Django-only edit prints the pytest line, not the module's Vitest globs too); `e2e`
  globs cross repos by nature and stay advisory; a change in both repos emits both;
- prints the affected modules with their test paths and the rendered `test_hint`, plus
  an "Unmapped changes" section for files that matched nothing;
- with `--command`, prints **one runnable unit-test command per repo** and nothing
  else, refusing any map entry that is not a plain path or glob;
- exit 3 means "no selection available" — the caller falls back to the full suite and
  **says so**.

## What it does not do

- It never executes tests. E2E in particular runs only behind the project's
  `test-e2e.sh` (`rules/e2e-testing.md`).
- It does not expand across dependencies. The map is per module; a signal, a mixin, or
  a shared component is not followed. That expansion is the human step below.
- It does not widen across the API contract. The repo-aware tier drops the other repo's
  unit tests because the changed code is not what they import — a serializer field
  rename still needs the frontend tests, and that widening is a `blindspot_expansions`
  line in the profile ([14-testing-profile.md](14-testing-profile.md)), not this tier.
- It does not do per-line test-impact analysis — a non-goal, stated in the header.
- It does not read the profile's `e2e_test_cmd` yet; an E2E-only match is an advisory,
  and the E2E spec to run is named by hand from the module's row.

## The expansion heuristics

Applied on top of the script's output, using the project's cross-dependency map (the
profile's `cross_deps_ref`, [14-testing-profile.md](14-testing-profile.md)). Each hop
lowers confidence one step.

| Changed | Widen to |
|---|---|
| A signal | every model the receiver writes to, and their layer-2 tests |
| A mixin / base class | every subclass's module |
| A shared component (`lib/components/*`) | every page that imports it |
| A model | models holding an FK / M2M to it; serializers that nest it |
| A serializer | the views that use it; the E2E spec of the page they back |
| The API client layer | the whole layer-5 set, and the E2E module set of every page that fetches |
| A store | its consumers; the E2E specs of those pages |
| A test helper (`helpers/*.ts`) | every E2E spec importing it |

## Confidence matrix

| Change | Same module | Adjacent (1 hop) | Shared consumers (2+ hops) |
|---|---|---|---|
| Model | HIGH | MEDIUM (FK-related models) | LOW (pages using the model) |
| Serializer / API view | HIGH | MEDIUM (that page's E2E) | — |
| Signal | HIGH | HIGH (connected models) | MEDIUM (their E2E) |
| Service | HIGH | MEDIUM (views using it) | LOW (E2E) |
| Page (Vue) | HIGH (its E2E) | — | — |
| Component / composable / store | MEDIUM (consumers) | LOW (consumers' E2E) | — |
| Test file | HIGH (itself, plus what it tests) | — | — |
| Shared lib / config / infra | see the catalog below | | |

Deduplicate keeping the highest confidence; a broader path subsumes a narrower one;
three or more sub-modules of one app become the app. Present HIGH first, LOW collapsed,
and always list changed files with no mapped test — silence there is the failure mode.

## Escalation catalog (widen to the named set)

| Trigger | Widen the selection to |
|---|---|
| `apps/core/*`, base mixins | every backend module inheriting from the touched class |
| `config/settings/*`, root `urls.py` | every backend module whose tests exercise settings-dependent behaviour (auth, storage, email); in practice the backend set |
| API client (`lib/api/client.ts`) | every layer-5 suite and the E2E module set of every fetching page |
| Auth / workspace stores, router guards | every E2E module that logs in — the authenticated set, named from `cross_deps_ref` |
| App shell / layout components | every page's component tests; E2E smoke per top-level page |
| `helpers/*.ts`, `playwright.e2e.config.ts`, seed generators | the E2E module set importing the helper; a generator change also means `--setup-template` first |
| `docker-compose.yml`, `Dockerfile*`, dependency files | rebuild, then the same widened set the other changes in the diff imply — the infra change itself names no module |
| 15+ files changed | stop widening by hand; run the selection the script prints, and note that the integration-boundary run is the real check |

Each row names a set the loop can afford; the one thing no row says is "everything,
now". The integration-boundary run covers what widening missed, and it is scheduled,
not triggered.

## Output

Per group: scope, module, confidence, one-line WHY, exact CMD. The CMD is the
profile's `backend_test_cmd` / `frontend_test_cmd` / `e2e_test_cmd` with the path
substituted — never bare `pytest` or `npx playwright test`. Backend first, then
frontend unit, then E2E.
