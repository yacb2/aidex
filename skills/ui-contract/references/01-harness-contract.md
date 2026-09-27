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
  because they otherwise decide whether a run is green.

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
  the gate.
- **The pixel rows skip themselves under a snapshot update** (`--update-snapshots
  all|changed` in the shipped tree): a defect row would write its defect over the clean
  baseline, and the dependent galleries would then not run at all.

**The closing line carries a count: `meta: N/N`** (in the shipped tree a second reporter
prints it as the run's last line, and it pins the number of rows the suite declares).
Read it before reading anything else:

| The line reads | It means |
|---|---|
| `meta: N/N`, bare | every pinned row ran, none skipped — a gate run |
| `meta: 0/0` and "did not run" | the meta project did not run at all (dependencies skipped, or only non-gallery specs selected) — not a gate run |
| a count labelled "filtered" | fewer rows than pinned ran (a grep, a last-failed or line filter) — not a gate run |
| a count labelled "skipped" | rows were skipped, typically the pixel rows under a snapshot update — not a gate run |
| a count asking to update the pin | the suite declares more rows than the reporter pins — bump the pin |

Only the bare form is part 2 of "verified". The count covers the browser predicates; a
predicate that is not a browser verdict (the style-lint allowlist's rot guard) is proven
by its own unit suite instead, and the count does not include it.

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
- The four gallery projects **depend on the meta-suite's project** (§ 1b), so it runs
  first and a red predicate stops the galleries.
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

**The owner's review surface is a consultation page, not the board** (ADR, fourth
amendment of 2026-09-23; rows reshaped by the 2026-09-27 consultation, D1-D3). The board
script also prints the owner's review rows as JSON — in the shipped tree
`--rows-json <gallery> --variants <v,v> --changed <cell,cell> --actual-dir <run output>`,
the variants and cells being item 5 of the plan's UI-contract section. One row per
declared cell in each chosen variant, as `before` (the baseline the run compared against,
absent for a new screen) and `after` (the run's render), plus one `unrequested` row per
undeclared cell that rendered differently in ANY variant, the other variants where it
changed listed in `also`; a declared cell that is not applicable comes as its reason. Paths are relative to the repo root, the
output is deterministic, and a declared cell with no baseline is refused like the board
does. An empty `rows` (everything matched) means no gallery block on the page. The
artifact kit's `gallery-items.sh` turns that document into consultation items
(`/aidex:artifact`, `04-block-vocabulary.md` § `gallery` pins the shape). The board and
the image remain the developer's lens while building.

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
| **The layout check is a settle check, not a layout-shift metric** | Both samples are taken *after* the cell reports ready, so a shift between first paint and ready is invisible to it. Its positive control is the meta-suite's seeded moving element; it has not fired on a real gallery cell. |
| **Breakpoint duplicated** | The harness restates the CSS framework's breakpoint as a number; a theme that changes it drifts silently. |
| **Known-defect guards proven on seeded input only** | The meta-suite exercises the scoping and the rot guard against seeded defects; a list with no real entry has still never been exercised against real input. |
| **The lockstep test parses source by regex** | A reformat is a false red, not a false green — but it is still a red nobody caused. |
| **Overflow does not see clipped or spilling boxes** | An `overflow: hidden`/`clip` box (a truncated label is wider than its box on purpose) and a visible-overflow child spilling out without growing any scroller are not findings; the pixels have to show them. |
| **Taste is not gated** | Overflow, contrast, layout churn and pixel drift, and nothing else. Whether the screen is good is the owner's call on the contact sheet. |
