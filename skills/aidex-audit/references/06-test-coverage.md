# Test-Coverage Playbook: module-map and tooling

The `test-coverage` playbook tracks which parts of a codebase have tests and
which do not, using a per-project keystone artifact (`module-map.json`) and a
set of deterministic scripts derived from it.

## Two-layer model: generated vs judged

Coverage tracking splits into two layers:

- **Generated** — anything countable is produced by a script and is never
  hand-edited: the breadth matrix, the drift-based re-run suggestion, the
  affected-tests list. Regenerate these by re-running the script, not by
  editing the output file.
- **Judged** — anything requiring human or agent judgment (depth of
  assertions, severity of a gap, whether a "covered" module is covered
  *well*) is recorded as a finding with the standard audit lifecycle in
  `00-inventory.md` (see `03-lifecycle.md`).

The only hand-maintained input is `module-map.json` itself (assisted on
first run by the playbook's Preparation step). Everything downstream is
derived.

## `module-map.json`

Location: `.context/audits/test-coverage/module-map.json` (per project,
workspace-root-relative).

### Schema

```json
{
  "version": 2,
  "repos": [
    { "name": "backend",  "path": "backend",  "test_hint": "cd backend && pytest {path}" },
    { "name": "frontend", "path": "frontend", "test_hint": "./test-e2e.sh {path}" }
  ],
  "modules": [
    {
      "id": "billing-invoices",
      "title": "Billing — Invoices",
      "src": [
        "backend/apps/billing/**",
        "frontend/src/**/billing/invoices/**"
      ],
      "tests": {
        "unit": ["backend/apps/billing/tests/**"],
        "e2e":  ["frontend/tests/e2e/billing/invoices/**"]
      },
      "surfaces": {
        "routes": [
          { "path": "/billing/invoices",     "spec": "frontend/src/views/billing/InvoiceList.vue" },
          { "path": "/billing/invoices/:id", "spec": "frontend/src/views/billing/InvoiceDetail.vue" }
        ],
        "endpoints": ["backend/apps/billing/urls.py"],
        "actions": [
          { "route": "/billing/invoices", "action": "create-invoice", "endpoint": "POST /api/invoices/" }
        ]
      }
    }
  ]
}
```

### Field rules

- `version` — schema version, currently `2`. A `version: 1` map still loads and
  still produces a matrix; it simply contributes no routes to the route board
  (see `surfaces.routes` below).
- `repos[]` — the workspace's git repos. `path` is workspace-root-relative;
  use `"."` (or `""`) for a workspace whose root itself is the git repo.
  `test_hint` is optional, a shell command template with a `{path}`
  placeholder for a specific test file/glob.
- `modules[].id` — short slug, unique within the map.
- `modules[].title` — human-readable label.
- `modules[].src` — glob list of source paths this module owns.
- `modules[].tests` — glob lists keyed by test kind (`unit`, `e2e`, etc — the
  keys are open-ended, not a fixed enum). **A module's test files are the files
  matching any kind's globs**, and every tool applies that one definition: the
  matrix's `NO TESTS` note and its "unmapped test files" list, the sweep's
  test-commit count. The `unit` / `e2e` columns and the route board read those
  two kinds specifically; a third kind is mapped and counted as tests, it just
  has no column of its own.
- `unmapped_ok` — optional top-level glob list: tracked test files matching
  no module's globs but matching one of these are a *deliberate* scope-out.
  They are reported as a `scoped out: N` count (and `unmapped_scoped_out` in
  the JSON), never listed — so the unmapped list shows only new drift, not
  the ~90% intentional rows that buried echo_lab's real signal.
- `modules[].has_surfaces` (JSON output) — emitted, read by nothing (BL-210).
  Kept deliberately: the schema rule is "bump on key-set change", a bump makes
  every already-generated matrix unrenderable until regenerated, and spending
  that fleet-wide cost on deleting an unread boolean buys nothing. It leaves
  with the next real key-set change, batched into the same `/3` bump.
- `modules[].surfaces` — optional, and the one place where two value shapes
  live side by side:
  - **glob-shaped keys** (`endpoints`, and any project-specific key) — lists of
    glob **strings**, matched against tracked files exactly like `src` and
    `tests`. These, and only these, are summed into the matrix's
    `surface_files` count. The key set stays open-ended.
  - **`routes`** — a list of **objects**, one per URL route: `path` is the URL
    the router serves (`:param` segments allowed) and `spec` is the file that
    serves it (the Vue view / template / handler). A URL is not a file path, so
    `routes` is deliberately excluded from `surface_files`; a v1 map whose
    `routes` is still a list of globs keeps being counted as files, unchanged.
  - **`actions`** — a list of objects naming a per-route action and the endpoint
    it calls: `{"route": "/billing/invoices", "action": "create-invoice",
    "endpoint": "POST /api/invoices/"}`. `route` must equal a declared
    `routes[].path`; one that does not is reported under "Actions on an
    undeclared route" as a defect in the map.

  The shape is sniffed from the value, never from the key name: a list of
  strings is globs, a list of objects is typed. That is what keeps a project's
  own custom surface key counted after the bump.
- All paths are **workspace-root-relative** and may use `**` (spans any
  number of *whole* directories, including zero — `a/**/b` matches `a/b` and
  `a/x/y/b`, never `a/xb`) and `*` (matches within a single path segment)
  globs. A bare directory, with or without a trailing slash (`backend/tests`,
  `backend/tests/`), means everything under it. The same matcher attributes
  files and commits alike, so a module's file count and its commit count always
  come from one file set.
- `surfaces` is optional at the module level; omit it if not applicable.

### What counts as a test

The `unit tests` / `e2e tests` columns count **test cases**, not files: a
`test(` or `it(` call — optionally through one modifier (`test.only(`,
`it.skip(`, `test.each(`) — or a pytest `def test_`. Structural calls are not
tests: `test.describe(`, `test.beforeEach(`, `test.step(` and `RegExp.test(`
do not count. Measured 2026-08-23 on two `it()`-style projects: counting only
`test(` under-reported unit depth ~2x, and counting every `test.<x>(` inflated a
Playwright suite by one per describe/hook/step.

### Route coverage — how "reached by an E2E spec" is decided

`coverage-matrix` decides it by **text**, not by module ownership: a route is
covered when some E2E spec file mentions its path literally (`page.goto(
'/billing/invoices')` and friends). Three details change what the gap count
means, so they are stated rather than left to the reader:

- **Scope is the union of every module's `tests.e2e` globs**, not the owning
  module's. A top-level smoke spec that walks many routes belongs to no module,
  and scoping the scan per module would make the coverage it really provides
  invisible.
- **Only files that are specs are scanned** (`*.spec.ts` / `*.test.ts` /
  `test_*.py` naming), not everything an e2e glob happens to cover. Measured on
  NS 2026-08-23: the globs also pull in `tests/e2e-setup/test-routes.ts`, a
  table of route *constants*, and counting it marked 13 of 79 routes covered
  with no spec behind any of them. If a project's specs match none of those
  conventions the scan falls back to the whole glob set, so an unusual naming
  scheme degrades to the old behaviour rather than reporting every route as a
  gap.
- **`:param` segments are translated to "one path segment"** before matching, so
  `/billing/invoices/:id` is reached by a spec visiting `/billing/invoices/7`.
  Without that, every parameterised route would read uncovered forever.
- **The URL must end where the route ends** — at a closing quote/backtick, or
  at the `?`/`#` starting a query or fragment. A bare mention with no closing
  delimiter (a trailing `// go to /billing/settings` comment) is not coverage.
  `/people` is therefore *not*
  marked covered by a spec that only ever visits `/people/create`. Silent
  over-reporting is the failure this board exists to prevent, so that is the
  side that gets the strict rule; the character *before* the path only has to
  not continue a longer path or identifier, which keeps
  `` `${BASE_URL}/suppliers/invoices` `` matching. A route mentioned only
  through a constant defined outside the scanned specs reads as a gap — a false
  alarm a human resolves, which is the direction to err in.

The outputs are `route_gaps` in the JSON, a "Routes with no reaching E2E spec"
list in `coverage-matrix.md`, and the route board in the dash render. A route
the map claims but the router does not define is a defect in the map.
- `test_hint` is optional at the repo level; omit it if there's no single
  reliable one-liner to re-run tests for a path in that repo.

### Migrating a v1 map to v2

A v1 map (routes as glob strings, or no `surfaces.routes` at all) still runs and
still stamps `coverage-matrix/2` — the route board is simply empty, which is how
one project's board sat silently inert for a month. The matrix now prints a
stderr NOTE when no module declares typed routes; treat that note as "migrate
now", not as information.

To migrate:

- Routes come from the router, not from memory: Vue Router `path:` entries
  (`grep -rhoE "path:\s*['\"][^'\"]+['\"]" frontend/src/router`), Django URLConf
  `path()`/`re_path()` for API-serving pages.
- **Regex-constrained params are written bare.** The router may say
  `:projectId(\d+)`; the map must say `:projectId` — the matcher's param class
  does not swallow the constraint, and a constrained param silently matches
  nothing (every spec mention reads as a gap).
- Each route entry gets the `spec` (what the page serves) and its `actions`
  where they exist; an action's `route` must equal a declared `path` or it is
  reported as a map defect.

### Generated artifacts are never hand-edited

Anything produced by `coverage-matrix`, `coverage-sweep`, or
`affected-tests` (Phases 2-4) is regenerated by re-running the script.
Do not hand-edit their output — if it looks wrong, fix `module-map.json` or
the script and regenerate.

## `defect-prone.jsonl` — optional second input

Location: `.context/audits/test-coverage/defect-prone.jsonl` (per project).
Absent on most projects, and that is a supported state: `affected-tests`
renders nothing extra and behaves exactly as it did before.

When present, `affected-tests` names any changed file that **measurably
breaks** and has no E2E reaching it, on stderr, so the gap surfaces while the
change is still in the working tree rather than after it lands. Three gap
kinds are distinguished, worst first: the file matches no module at all (the
gap cannot be located), its module maps no e2e globs, or it maps them and no
spec file exists. A file whose module has real e2e specs is counted as
covered, not reported.

### Format

```
{"meta": {"denominator": "all", "base_rate": 0.15, "ratio": 2.0, "min_touches": 8}}
{"file": "<project-dir>/<workspace-rel-path>", "share": 0.46, "bug": 6, "touches": 13, "flagged": true}
```

The `meta` line is optional but wanted: without it the threshold behind the
flags is unverifiable, and the consumer says so.

### Producing it

The file regenerates from nothing on its own — it is Preparation step 4 of the
test-coverage playbook, run per audit (BL-199: no project had ever generated it,
so the ranking was silently inert everywhere). The exact command:

```bash
python3 ~/.aidex/skills/aidex-audit/scripts/usage-retro/mine_defect_proneness.py \
  --denominator all --projects-root <workspace-parent-dir> \
  --out .context/audits/test-coverage/defect-prone.jsonl
```

The producer is a defect-proneness miner: **bug items touching a file / all
items touching it**, compared against the corpus base rate, with a minimum
touch count and worktree copies collapsed onto the main path. Raw recurrence
counts do *not* work — they rank the files that are touched most, not the
files that break most, and flag whatever is central (i18n locale files led the
raw count and land near the base rate once normalised).

Two properties the format encodes because they are traps:

- **`file` carries a leading project-directory segment**, matching the
  producer's cross-project output. The consumer strips it against the
  workspace basename (with any `-wt-<branch>` suffix collapsed). A data file
  whose rows carry a different prefix matches nothing, so that case is
  reported as a join failure and never as an all-clear.
- **`denominator` decides everything downstream.** Counting only items that
  carry a `type:` field moves the base rate roughly 3x against counting every
  attributed item; at the high end the 2x threshold exceeds 90% and nothing
  can clear it, so a file regenerated with the wrong one is empty and looks
  correct. The consumer calls out a `typed` file rather than consuming it
  silently.

### Migrations are suppressed

A migration is touched during bug work but is not a surface an E2E spec can
cover, so asking for one is asking for a test that cannot be written.
Suppressed files are **counted** in the report, per the same convention as
`waived: N` and `ignored: N` — never silently dropped.

## Multi-repo workspace semantics

A workspace may contain more than one git repository, and the workspace
root itself may or may not be a git repo. Example (NS Backoffice):

```
ns-backoffice/            <- NOT a git repo (no .git here)
├── backend/              <- git repo, path: "backend"
└── frontend/             <- git repo, path: "frontend"
```

`module-map.json` declares each repo's `path` relative to the workspace
root. A path belongs to the repo whose `path` is a prefix of it (longest /
most specific match wins in the general case; in practice repo paths do not
overlap). Git operations (`git log`, `git ls-files`, etc.) are run with
`-C <workspace_root>/<repo.path>` so each repo's history is queried
independently — there is no single unified git history to walk when the
workspace root is not itself a repo.

If the workspace root *is* the git repo (single-repo project), declare one
entry with `"path": "."`.
