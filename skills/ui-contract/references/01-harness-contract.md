# The harness contract — what a project must expose

What `gallery-builder` and `verify-ui` need to find in a project before either can do
anything. Written from the first shipped implementation (a Vue 3 + Playwright frontend);
every item is stated as the **property** the harness relies on, not as that project's
spelling of it. **Detect the names — never assume them.** Where this file shows a literal
(`runListGallery`, `--demo`, `__screenshots__/`), it is an example of the shape, and the
project's own source is the authority.

Read this before briefing either agent. If a project exposes none of it, the answer is
not to improvise a gallery — it is to say the harness is missing and stop.

---

## Contents

- [Presence check — before saying "absent"](#presence-check--before-saying-absent)
- [1. The harness module and its matrix validation](#1-the-harness-module-and-its-matrix-validation)
- [1b. The meta-suite — every predicate proven able to fail, before the galleries](#1b-the-meta-suite--every-predicate-proven-able-to-fail-before-the-galleries)
- [1c. Flakes: a fix needs a named cause](#1c-flakes-a-fix-needs-a-named-cause)
- [2. The runner invocation — ALWAYS with a spec path](#2-the-runner-invocation--always-with-a-spec-path)
- [2b. Iterating versus the closing run](#2b-iterating-versus-the-closing-run)
- [3. The four projects: light/dark x desktop/mobile](#3-the-four-projects-lightdark-x-desktopmobile)
- [4. Where baselines live](#4-where-baselines-live)
- [4b. A scroll-owning shell: the cell captures the full content](#4b-a-scroll-owning-shell-the-cell-captures-the-full-content)
- [5. Known-defect entries need `projects`, and there is a rot guard](#5-known-defect-entries-need-projects-and-there-is-a-rot-guard)
- [6. The contact sheet](#6-the-contact-sheet)
- [7. Who owns the style-lint allowlist](#7-who-owns-the-style-lint-allowlist)
- [Limits the gate is known NOT to cover](#limits-the-gate-is-known-not-to-cover)

## Presence check — before saying "absent"

Run these in the repo (quote globs; in zsh an unmatched glob is an error, so use `find`).
One marker found means the harness is present: continue and cite the file.

1. The testing profile's `gallery_gate_cmd` and `gallery_scripts` keys, if set.
2. A gallery spec set: `find <frontend> -path '*/node_modules' -prune -o -name '*.demo.spec.ts' -print`
   (shipped tree: `frontend/tests/demo/`).
3. The harness module and its meta-suite: `state-gallery.ts` and
   `state-gallery.meta.demo.spec.ts` in that directory, plus `meta-count-reporter.ts`.
4. The runner config: `playwright.demo.config.ts` next to `playwright.config.ts`.
5. The contact-sheet scripts: `gallery_board.py` / `gallery_contact_sheet.py` (shipped
   tree: `_scripts/` or the repo's scripts directory).

A research note or memory saying "missing" is not evidence; the repo is.

## 1. The harness module and its matrix validation

One module, imported by every gallery spec, that turns a declared matrix into one test
per cell. What it must guarantee:

- **A gallery is declared, not scripted.** The spec supplies an object: a suite name, a
  short `slug` (the baseline file-name prefix, and what the contact-sheet script takes as
  its argument), the route to navigate to, and one entry per state.
- **A cell is either driven or explicitly absent.** A driven cell supplies the route
  mocks that put the page in that state, an optional interaction, and the locator whose
  visibility means "this cell rendered". An absent cell is
  `{ notApplicable: true, reason: '...' }`.
- **Two layers of matrix validation, and the runtime one is the one that gates.** Types
  catch a missing cell at compile time (an exhaustive record over the state union), but
  the test runner does not type-check specs — so the module also refuses, at run time, a
  matrix with a missing cell and a not-applicable cell whose reason is blank.
- **`ready` is specific to the state.** It is the locator whose visibility means "this cell
  rendered", so it must not be able to resolve in a neighbouring state: a submitting cell
  whose `ready` is also present in the plain open state gets a baseline for a state that
  was never applied. The harness refuses a `ready` visible before the cell's action ran,
  or another cell's `ready` visible in this cell's final state. A cell with no element of
  its own is declared not applicable, with its reason.
- **Every matrix clause is proved by something.** The plan's state matrix carries a
  **"proved by"** column: a pixel (the cell), an assertion, or a unit test id. A clause
  that lives out of the picture (an action disabled inside a closed menu) never reaches a
  pixel, and deleting the code that implements it keeps the whole gate green; the column
  makes that gap visible before the gate runs. The reviewer's brief on a gallery spec
  carries both: this column, and each cell's `ready` to check against the rule above.
- **Overlays have a runner.** Modal, panel, menu and confirm cells run through the
  overlay runner, which keeps the list and form runners' order (open, check, shoot); a
  hand-assembled cell in that order is a second copy to keep in step. Same rule for a
  not-applicable cell: a reason.
- **A public page has a mode.** A page outside the app shell (login, invitation accept)
  declares it, its layout and overflow checks use the page's own roots, and the harness
  asserts the shell is absent, so the declaration cannot be a way out of the checks.
- **A toast-only state is declared, not skipped.** The toaster is removed before the shot
  on purpose. A state whose only signal is a toast is either declared not applicable with
  the reason "accepted design: toast only", or recorded as a defect finding. The harness
  can picture one when the cell asks (the toaster stays in and is held open); that is an
  opt-in per cell.
- **Per cell it drives one screenshot baseline plus deterministic checks**: horizontal
  overflow, a layout-stability sample, and an accessibility contrast pass.
- **Horizontal overflow scans every scroller on the page**, not only the shell's scroll
  roots: any descendant that scrolls sideways is a finding. A table scrolling inside a
  card at the mobile width passed a roots-only check (the roots never grew). The one
  opt-out is the page's to declare: a scroller that is MEANT to scroll sideways (a
  carousel, a code block, a wide grid whose design is a sideways scroll) carries a marker
  on the scrolling element itself — `data-scroll-x="intended"` in the shipped tree; read
  the name from the harness. The roots cannot opt out. A project adopting the harness
  marks its own intended scrollers; its first run names every one it has not marked. Console errors and uncaught page errors fail the cell
  unless the cell allow-lists a pattern, which narrows the assertion instead of disabling
  it.
- **It reads the colour mode off the runner's project metadata and throws when it is
  absent.** That is deliberate: a missing mode is a config mistake, not a default to
  paper over. It is also why the runner config below is part of the same contract.
- **A gallery PAGE may mark a dev-only affordance so the harness removes it** — in the
  shipped tree, a `data-gallery-exclude` attribute; read the name from the harness. The
  node is removed from the DOM (not hidden) BEFORE the screenshot AND before all three
  verdicts, so it is out of review entirely: no pixels, no overflow, no layout sample, no
  contrast scan. It is for chrome that exists only to drive the gallery (a brand switch).
  **Never wrap product UI in it** — an excluded subtree is a hole in the gate, and a
  state's own markup inside one passes every check by not being looked at. Something
  that must merely not move a baseline (a clock, a version string) belongs in the
  volatile-region or mask list below, where the checks still see it.
- Volatile regions (a ticking timer panel, an auto-dismissing toaster) are removed from
  the DOM for the evidence pass, and a version string in the chrome is masked. Both exist
  because they otherwise decide whether a run is green. **A mask is painted in the
  colour of what it covers**: pass `maskColor` (Playwright's `toHaveScreenshot` /
  `screenshot` option) set to the surrounding background token, never the default
  `#FF00FF`. A magenta bar on every capture reads to a reviewer as a leftover highlight
  and gets explained page by page; a background-coloured mask reads as nothing.

## 1b. The meta-suite — every predicate proven able to fail, before the galleries

A required property, not an extra. A gate check that has never been red has not shown it
can be, and this harness shipped several vacuous checks under a fully green gate (the
SKILL's § "Verified", part 3). So the harness ships with a **meta-suite**:

- **Every predicate has a seeded defect it must catch.** A real rendered fixture page
  takes a defect switch (in the shipped tree, a dev-only route with `?defect=<name>`), and
  one row per predicate asserts the predicate FAILS with the defect on; the clean rows
  assert every predicate PASSES with it off. Nothing is stubbed: the rows call the exact
  functions every gallery cell runs — overflow, layout, contrast, pixels, the known-defect
  scoping and its rot guard, and the runtime matrix validation. A new predicate is not
  done until it has its row.
- **It runs before the galleries, and a red row stops them.** The gallery projects
  depend on the meta project, so a gallery run cannot skip it.
- **The fixture route is dev-only** and asserted absent from a production build, like any
  gallery route.
- **Its baselines are not shipped** (the fixture shot contains the project's own shell).
  The first run writes them and fails those rows once; look at them, then the next run is
  the gate. A project that commits its baselines moves them by deleting them and
  re-running without a snapshot update, because the pixel rows skip under
  `--update-snapshots` and cannot rewrite them.
- **The pixel rows skip themselves under a snapshot update** (`--update-snapshots
  all|changed` in the shipped tree): a defect row would write its defect over the clean
  baseline, and the dependent galleries would then not run at all.

**The closing line carries a count: `meta: N/N`** (in the shipped tree a second reporter
prints it as the run's last line, and it pins the number of rows the suite declares).
Read it before reading anything else:

| The line reads | It means |
|---|---|
| `meta: N/N`, bare | every pinned row ran, none skipped — a gate run |
| `meta: 0/0` and "did not run" | the meta project did not run at all (`--no-deps`, dependencies skipped, or only non-gallery specs selected) — not a gate run |
| a count labelled "filtered" | fewer rows than pinned ran (a grep, a last-failed or line filter) — not a gate run |
| a count labelled "skipped" | rows were skipped, typically the pixel rows under a snapshot update — not a gate run |
| a count asking to update the pin | the suite declares more rows than the reporter pins — bump the pin |

Only the bare form is part 2 of "verified". The count covers the browser predicates; a
predicate that is not a browser verdict (the style-lint allowlist's rot guard) is proven
by its own unit suite instead, and the count does not include it.

## 1c. Flakes: a fix needs a named cause

A cold first run can fail on timing (a login timeout on the first server start, a cell
that passes 4 of 5). **A flake fix needs a named cause, or three clean runs**; changing a
locator until it passes, with no cause, is neither. The harness warms the dev server before
the first cell and one retry absorbs a host hiccup; the closing line prints the retries
(`retries: N`), so a green run that retried is visible. Read it beside `meta:`.

**Charts animate in JavaScript, which the freeze does not reach.** Freezing CSS motion
and `reducedMotion` stop CSS transitions only; a d3/unovis chart (or any JS-driven
transition) keeps animating, so a shot can land between frames and a cell passes some
runs and fails others. Fix the cause: set the chart's animation duration to 0 under the
gallery, or make the cell's `ready` mean the final frame (a marker set when the animation
ends). Never a fixed `waitForTimeout`, which is a guess about speed, not a cause.

## 2. The runner invocation — ALWAYS with a spec path

Galleries run through a dedicated runner config, inside the project's existing isolated
E2E environment (one rendering environment is the whole premise of a pixel baseline).

**Detect the entry point** — the project's testing profile, its package scripts, or its
E2E wrapper script. In the shipped tree it is a `--demo` flag on the repo's E2E script
that swaps in the gallery config and forwards every remaining argument.

**One gate invocation for all the galleries of the change.** The gallery projects depend
on the meta project, which runs once per invocation: pass every gallery spec in the same
call, not one call per gallery (six galleries, six meta runs). A project filter narrows
the run to the runner projects the change reviews or captures (in the shipped tree
`--projects light-desktop`); the meta project still runs, once, as a dependency.

## 2b. Iterating versus the closing run

The meta-suite is the slow part of one invocation. While iterating, skip it with
Playwright's `--no-deps`: the closing line then reads `meta: 0/0` and "did not run", and
the run is labelled **"not a gate run"** in the Execution log. Only the closing evidence
run omits `--no-deps` and reports the bare `meta: N/N`.

**Always pass a spec path.** With no path, the mode also runs everything else that lives
in that test directory — in the shipped tree, a demo tour recording. A path matching no
file is an error ("no tests found"), which is the right failure and not a silent pass.

## 3. The four projects: light/dark x desktop/mobile

The gallery specs run under exactly four runner projects — `light-desktop`,
`dark-desktop`, `light-mobile`, `dark-mobile` in the shipped tree — each carrying the
colour mode in its metadata and its own viewport. Properties that matter:

- The mobile viewport must sit **below** the layout's own breakpoint, or the run
  screenshots the desktop layout twice.
- The theme is planted before the first paint (an init script on every document in the
  context), because a store defaulting to "system" makes the mode a property of the
  machine running the test.
- Any non-gallery spec in the same directory runs in a **separate, baseline-less**
  project. Without that split, every cell gets a fifth copy with nothing to compare.
- The four gallery projects **depend on the meta-suite's project** (§ 1b), so it runs
  first and a red predicate stops the galleries. The meta project in turn depends on a
  one-page `vite-warmup` project, so a cold Vite is paid before the first cell.
- **Light and dark are the only two modes this contract renders**, also in a project that
  ships more themes (a shared template may allow several): the gate compares two modes per
  cell, and a third theme is reviewed by hand when it is introduced, never as extra
  baselines.
- In a project with no gallery spec yet, the four projects select nothing and the run is
  clean — adopting the config costs nothing before the first gallery exists. The
  meta-suite still runs whenever its path, or any gallery's, is passed.

## 4. Where baselines live

One tree, `<test dir>/__screenshots__/<project>/<gallery>-<cell>-<platform>.png` in the
shipped tree, set by an explicit snapshot-path template rather than the runner's default
per-spec sibling directory. Two reasons, both load-bearing:

- the contact-sheet composer reads this layout;
- the platform suffix stays in the file name on purpose, so a run on another OS fails as
  "missing snapshot" instead of as an unreadable whole-page pixel diff.

The first run writes the baselines with an update flag. **Read them before committing —
a baseline is worth exactly what the first look at it was worth.** After that, never
update snapshots without saying which baselines moved and why.

The pixel verdict has **two numbers**, and both are bracketed in the project's own runner:

- **the per-pixel threshold** — how different one pixel must be to count at all;
- **the diff ratio** — how many counted pixels a shot may differ by. A ratio, not a pixel
  count, because desktop and mobile frames differ by several times in area.

In the shipped tree they are **ratio 0.00002 with per-pixel threshold 0.02**. The first
pair (ratio 0.0005 with the default threshold 0.2) was shown vacuous: at 0.2 a 1px
light-mode border or a dropped tint counts as no difference, and 0.0005 of a mobile frame
allowed more pixels than a whole layout fix. The bracket, in that one runner:

- **below** — three consecutive runs of every cell with NO tolerance at all (ratio 0,
  threshold 0) differed by 0 px; the runner renders deterministically, so the tolerance is
  a cushion, not a noise floor;
- **above** — the smallest real change, one button's 1px border, is 8.6x what the ratio
  allows on a desktop cell and 12x (desktop) / 53x (mobile) on the meta-suite's fixture,
  whose "a 1px border change fails" rows hold that line.

**A project adopting the harness re-brackets both numbers in its own runner** — the
no-tolerance runs below, its own smallest real change above — rather than inheriting
them.

## 4b. A scroll-owning shell: the cell captures the full content

When the app scrolls inside a panel (the shell owns the scroll, so the document never grows),
a viewport shot sees only the first screen. **The cell makes the gate's own baseline
full-page; the review images are those baselines, never a second hand-written capture
script** (a throwaway script with its own login, scenarios and paths drifts from the gate
and shows pixels the gate never compared). The recipe, in the cell, after `ready` and
before the shot:

1. Measure the scrolling panel: `extra = scroller.scrollHeight - scroller.clientHeight`.
2. Set the viewport height to `innerHeight + extra` (`page.setViewportSize`), width
   unchanged, and wait for the layout to settle (the same `ready`).
3. Assert `scroller.scrollHeight === scroller.clientHeight`: the panel no longer scrolls,
   so nothing is below the fold. A panel that still scrolls fails the cell instead of
   shipping a partial baseline.
4. Screenshot. Overflow, layout and contrast now see the whole panel too.

A baseline taller than the viewport is expected (about 1600x1455 on a 900 px viewport).
A change below the old fold now fails as a pixel diff. The "Viewport-only shots" and
"Contrast judged on the first screenful" limits below apply only to a project that has
not adopted this rule.

## 5. Known-defect entries need `projects`, and there is a rot guard

A defect the gate finds that this work will not fix is registered per cell, never
silenced globally. An entry carries three things and none is optional:

- **`target`** — the offending node exactly as the check prints it.
- **`why`** — a file:line and the owning module.
- **`projects`** — the runner projects the defect was **measured** in, and the only ones
  where it is excused. This one is the finding, not a nicety: left unscoped, an entry for
  a light-desktop defect also excuses the same target regressing in dark mode, which is
  the one thing the light/dark cross exists to catch. It shipped unscoped and green.

**The rot guard:** an applicable entry that matches nothing **fails the cell**. Either
the defect was fixed (delete the entry) or the selector it pins has changed, and the
check is now blind to the defect it was written for. A list nobody prunes stops
describing the app.

The same shape applies to the cell's console-error allowlist: anything a listed pattern
does not match still fails.

## 6. The contact sheet

**The review surface may be a generated board instead of one image** (ADR, second
amendment of 2026-09-21): a static HTML file over the same baselines, one tile per cell
and project, in the shipped tree a sibling script of the composer that imports its lists.
Every property below holds for it unchanged; detect which one the project has. Either is the
developer's lens, never what the Execution log records as the review surface (SKILL.md, "Verified" part 1).

**The owner's review surface is a consultation page, not the board** (ADR, fourth amendment of 2026-09-23; rows reshaped by the 2026-09-27 consultation, D1-D3). The board script also prints the owner's review rows as JSON — in the shipped tree `--rows-json <gallery> --variants <v,v> --changed <cell,cell> --actual-dir <run output>`, the variants and cells being item 5 of the plan's UI-contract section. What the emitter owes: one row per declared cell in each chosen variant, paths relative to the repo root, deterministic output, a declared cell with no baseline refused like the board does, and for a NEW screen a `--new` cell list (refused for a cell that already has a baseline) that reads baselines only for the chosen variants. Everything else about a row is the artifact kit's: the schema, the `look` line every shown row carries, `noBefore`, `decided_note`, unrequested rows, alternatives, the highlight rule and the reply parsing are in [Gallery rows](../../artifact/references/gallery-rows.md#gallery-rows-screenshots-the-reader-rules-on-one-row-per-screen-state) and the [`gallery` block table](../../artifact/references/04-block-vocabulary.md#gallery--scriptsdashgallery_itemspy-rows-json-in); a key the emitter does not write is added by the author before the page is built. For highlights the capture step writes `<capture>.regions.json` next to every PNG (a `{"name": {"x","y","w","h"}}` map from Playwright `locator.boundingBox()` in the capture's own pixels, plus the scroll offset on a full-page shot) so the author can write `"highlight": "@name"`. The board and the image remain the developer's lens while building: nothing reads a page built from them, and a session never opens one in the owner's browser (BL-705); after a UI fix the owner is handed the consultation artifact.

**A component-scoped consultation** (owner 2026-10-02): when only one component changes
(a button's hover, tooltip, loading and disabled states; a dialog; a card; a section; a
menu) and the surrounding screen adds nothing to the decision, the cell captures only that
component, with a locator-scoped screenshot (`locator.screenshot()`), and the consultation
carries ONE item with every state of it, the owner approving all or some of them
(checkboxes), not one full-screen item per state. The full screen stays the default
whenever context matters (placement, neighbours, the AFTER beside the BEFORE). The
component's cells still go through the gate like any other (a distinct render each, `ready`
specific to the state). The gallery rows document carries it as
one row of `kind: "states"` (N captures, a checkbox per state; `gallery-reply.sh --rows` returns which were approved): [`gallery` block table](../../artifact/references/04-block-vocabulary.md#gallery--scriptsdashgallery_itemspy-rows-json-in).

A small composer script turns one gallery's baselines into a single image: rows are the
matrix cells, columns the four projects.

- **It reads the committed baselines, not a run's actuals.** The baselines are what the
  gate defends and what review is being asked about; actuals only exist after a failing
  run.
- **A declared cell with no image is an error, not a gap in the grid.** A sheet that
  quietly renders five of six cells is worse than no sheet.
- **The output path is the last line of stdout**, into a gitignored scratch directory.
  That path is for the caller (verify-ui reads it); the word "verified" points at the
  consultation page, not at this image (SKILL.md, "Verified" part 1).
- Desktop tiles are scaled down and mobile tiles stay native: a desktop frame squeezed to
  a mobile column is unreadable evidence.
- `gallery_board.py` and `gallery_contact_sheet.py` are tracked shared infrastructure in a
  project that adopted the harness: they read the fork's own gallery matrix (cells,
  not-applicable reasons and the per-row look sentences) from its `frontend/tests/demo/*-gallery.demo.spec.ts`,
  so a project adopting them edits no list, it keeps its specs. They need `uv` and `pillow`.

## 7. Who owns the style-lint allowlist

The lint rules (no raw interactive elements outside the primitive directories; no hex
colours or arbitrary size/colour values in templates) are **upstream-owned and synced**.
The **allowlist is project-owned and never synced**. Consequences the agents must respect:

- The config tolerates an **absent** allowlist file and nothing else — a file that exists
  and is broken still fails loudly. So the first run is made with everything on, and that
  run's findings *are* the project's list.
- An entry is `{files, rules, reason}` and **the reason is mandatory**: an exemption
  nobody wrote a reason for is indistinguishable from one nobody remembers.
- The rot guard is **per file**, not per glob: an exempted file carrying no finding
  fails. A blanket directory entry fails with the count of stale exemptions.
- Never add an exemption to make a run green without saying, in the report, which files
  were exempted and why.

---

## Limits the gate is known NOT to cover

Stated up front so nobody reads a green run as wider than it is; a project that adopts
the harness copies this table into its own record and edits the rows its setup changes. Repeat these to the owner when reporting a pass.

| Limit | What it means |
|---|---|
| **Viewport-only shots** (unless the full-height cell rule of § 4b is adopted) | The app shell owns the scroll, so the document never grows and a full-page capture is byte-identical to a viewport one. **A change below the fold reds nothing.** |
| **`-darwin` baselines only** | Baselines exist for one platform. On any other OS every cell fails as a missing snapshot. |
| **Contrast judged on the first screenful** (unless § 4b is adopted) | The accessibility pass sees what is rendered in the viewport; anything below it is reported as "incomplete" and is not gated. |
| **The layout check is a settle check, not a layout-shift metric** | Both samples are taken *after* the cell reports ready, so a shift between first paint and ready is invisible to it. Its positive control is the meta-suite's seeded moving element; it has not fired on a real gallery cell. |
| **Breakpoint duplicated** | The harness restates the CSS framework's breakpoint as a number; a theme that changes it drifts silently. |
| **Known-defect guards proven on seeded input only** | The meta-suite exercises the scoping and the rot guard against seeded defects; a list with no real entry has still never been exercised against real input. |
| **The lockstep test parses source by regex** | A reformat is a false red, not a false green — but it is still a red nobody caused. |
| **Overflow does not see clipped or spilling boxes** | An `overflow: hidden`/`clip` box (a truncated label is wider than its box on purpose) and a visible-overflow child spilling out without growing any scroller are not findings; the pixels have to show them. |
| **JS-driven animation is not frozen** | Freezing CSS motion and `reducedMotion` do not stop d3/unovis chart transitions; a cell whose `ready` resolves mid-animation gets a baseline of an intermediate frame and flakes. The chart's duration must be 0 under the gallery, or `ready` must mean the final frame (§ 1c). |
| **Taste is not gated** | Overflow, contrast, layout churn and pixel drift, and nothing else. Whether the screen is good is the owner's call on the consultation page. |
