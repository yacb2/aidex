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
- **Per cell it drives one screenshot baseline plus deterministic checks**: horizontal
  overflow against the element that actually scrolls, a layout-stability sample, and an
  accessibility contrast pass. Console errors and uncaught page errors fail the cell
  unless the cell allow-lists a pattern, which narrows the assertion instead of disabling
  it.
- **It reads the colour mode off the runner's project metadata and throws when it is
  absent.** That is deliberate: a missing mode is a config mistake, not a default to
  paper over. It is also why the runner config below is part of the same contract.
- **A gallery PAGE may mark a review affordance so the harness removes it before the
  shot** — in the shipped tree, a `data-gallery-exclude` attribute, removed (not hidden)
  after the cell's assertions have already run against a page that has it. The attribute
  name is the project's; read it from the harness. This part of the shipped tree is the
  newest and was still under review at the time of writing, so treat the *mechanism* — a
  page-owned opt-out for non-state affordances — as the contract, and the exact attribute
  as something to confirm on disk.
- Volatile regions (a ticking timer panel, an auto-dismissing toaster) are removed from
  the DOM for the evidence pass, and a version string in the chrome is masked. Both exist
  because they otherwise decide whether a run is green.

## 2. The runner invocation — ALWAYS with a spec path

Galleries run through a dedicated runner config, inside the project's existing isolated
E2E environment (one rendering environment is the whole premise of a pixel baseline).

**Detect the entry point** — the project's testing profile, its package scripts, or its
E2E wrapper script. In the shipped tree it is a `--demo` flag on the repo's E2E script
that swaps in the gallery config and forwards every remaining argument.

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
- In a project with no gallery spec yet, the four projects select nothing and the run is
  clean — adopting the config costs nothing before the first gallery exists.

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

The tolerance is a **ratio**, not a pixel count, because desktop and mobile frames differ
by several times in area. In the shipped tree it is 0.0005, bracketed by two measurements
in that one runner: above it, the smallest real change anyone would make (one padding
class) moves 11x that; below it, three consecutive no-change runs are green. A project
adopting the harness re-brackets it rather than inheriting the number.

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
Every property below holds for it unchanged; detect which one the project has and record
that one's path.

A small composer script turns one gallery's baselines into a single image: rows are the
matrix cells, columns the four projects.

- **It reads the committed baselines, not a run's actuals.** The baselines are what the
  gate defends and what review is being asked about; actuals only exist after a failing
  run.
- **A declared cell with no image is an error, not a gap in the grid.** A sheet that
  quietly renders five of six cells is worse than no sheet.
- **The output path is the last line of stdout**, into a gitignored scratch directory.
  That path is what the Execution log records and what the word "verified" points at.
- Desktop tiles are scaled down and mobile tiles stay native: a desktop frame squeezed to
  a mobile column is unreadable evidence.
- In the shipped tree the composer hardcodes its galleries, their cell lists and the four
  project names, pinned to the harness sources by a lockstep test — so it describes that
  project's matrix and nothing else, and it is **not** shared infrastructure. A project
  adopting it copies and edits the two lists.

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

Stated by the boilerplate's own Execution log so nobody reads a green run as wider than
it is. Repeat these to the owner when reporting a pass.

| Limit | What it means |
|---|---|
| **Viewport-only shots** | The app shell owns the scroll, so the document never grows and a full-page capture is byte-identical to a viewport one. **A change below the fold reds nothing.** |
| **`-darwin` baselines only** | Baselines exist for one platform. On any other OS every cell fails as a missing snapshot. |
| **Contrast judged on the first screenful** | The accessibility pass sees what is rendered in the viewport; anything below it is reported as "incomplete" and is not gated. |
| **The layout check is a settle check, not a layout-shift metric** | Both samples are taken *after* the cell reports ready, so a shift between first paint and ready is invisible to it. It has fired zero times and carries no positive control. |
| **Breakpoint duplicated** | The harness restates the CSS framework's breakpoint as a number; a theme that changes it drifts silently. |
| **One known-defect list has no entry** | The overflow allowlist exists with nothing in it, so its own guards have never been exercised against real input. |
| **The lockstep test parses source by regex** | A reformat is a false red, not a false green — but it is still a red nobody caused. |
| **Taste is not gated** | Overflow, contrast, layout churn and pixel drift, and nothing else. Whether the screen is good is the owner's call on the contact sheet. |
