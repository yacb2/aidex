# Architecture: sweeping what has no screen

[`01-discovery.md`](./01-discovery.md) was written against **screens**. Half of it assumes a
surface you can render and a user who can see the difference. A subsystem, a service, a library
or a CLI has no screen, so this module says which of it transfers unchanged and what the
instrument becomes when "render the branch" is not available.

**This is a substitution, not a fourth step.** Run it **instead of** rules 1, 2 and 4, and
**alongside** everything else. And note the ratio: for a library, an API service or a developer
tool, *this* is the default path and the surface protocol is the special case.

| Rule | Transfers? |
|---|---|
| The provenance ledger | **Unchanged.** The most portable thing in the methodology |
| Rule 1 — a surface is not a file | **Replaced** — §1 |
| Rule 2 — every guard is a document you have not read | **Replaced** — §2 |
| Rule 3 — a negative requires a consumer search | **Unchanged**, and it matters *more* |
| Rule 3′ — a positive requires a reachability proof | **Unchanged**, and §1 is where it bites |
| Rule 4 — a framework's limits get checked, not recalled | **Replaced and widened** — §3 |
| Rules 5, 6, 7 — release notes, field age, ask the data | **Unchanged** |

What changes is not the discipline. It is the **instrument**: the equivalent of *rendering the
screen* is **running the code path**.

---

## §1 — A mechanism is not a module

**The surface version:** a page that hands data to a shared component is describing a surface;
grepping the page proves nothing.

**The architecture version:** a mechanism is split across a **declaration** and an **execution**,
and they are in different files by design. Documenting one and calling it the mechanism is the
same mistake in a different costume.

| Declaration | Execution |
|---|---|
| the enqueuer that builds the job record | the worker body that runs it |
| a setting or environment variable | every consumer that reads it |
| a provider interface | the registry that resolves a name to an implementation |
| a model field | its constraint, its migration, and the serializer that exposes it |
| a scheduler row | the function it names, **by string** |

Search **outward** from the declaration, then reverse the direction.

**The string-reference trap is architecture's version of the props split, and it is the reason
Rule 3′ cannot be run with grep alone.** Schedulers and registries commonly name their target by
dotted path *as a string*. A rename that a type-checker and an IDE both bless leaves the row
pointing at nothing, and **nothing goes red until the job silently stops running.**

## §2 — Every branch is a configuration you have not run

**The surface version:** enumerate the conditionals; each guard is a second screen.

**The architecture version:** enumerate the things that make the same code behave differently and
give each a disposition. Four kinds, not interchangeable: settings and environment branches;
provider or strategy selection; **capability guards** (code that behaves differently when
something is absent); and defaults that only apply on one path.

The corollary differs from the surface one. There it was *disabled is not absent*. Here:

> **A default is not a decision, and an environment variable is not a default.** A value never
> set in any deployed environment and a value set to the same thing everywhere look identical in
> code and mean opposite things. Say which you checked, and where.

## §3 — Vendors, engines and containers get checked, not recalled

The same rule as Rule 4 against three larger targets:

- **The database engine's semantics.** One engine treats NULLs as distinct in a unique index,
  which is why a table needed *two partial constraints* rather than one composite. Get that
  backwards and you document a protection that does not exist.
- **The vendor's actual behaviour.** An object-storage bucket without CORS fails **only** on
  ranged media requests. `curl` cannot see it; a browser can. *"Storage is reachable"* checked
  with `curl` is not the claim the product depends on.
- **The runtime the code actually runs in.** §4.

### The corollary: a surface census cannot see a stage that has no surface

One project closed its feature documentation with a **route census** — every route in the
router, matched against a document. It worked: four undocumented screens, one documented screen
that does not exist.

It was **structurally blind** to a whole pipeline stage — six endpoints, five writers, a conflict
detector — which has **no route**, because its entire surface is two dialogs hosted inside
another screen. That stage surfaced **by accident**, when a legacy file was about to be deleted
and its mechanism half had nowhere to go.

The response was a second census along a different axis — the installed modules — and **on its
first run it found a module described nowhere.**

> **Census both axes, because the blind spot of each is exactly what the other counts.** A route
> census cannot see a stage with no route; a module census cannot see a screen. Neither can cover
> for the other, and a project needs enough axes that everything of value appears on at least one.

**The gap was found by luck. The census is what you build so that next time it is not luck.**

> **"Mentioned" is not "described", and grep cannot tell them apart.** That stage was mentioned in
> four files while described in none. This is why ownership is **declared** in `covers:`
> front-matter and diffed by `scripts/docs-census.sh`, rather than inferred from prose — the
> ambiguity is unsolvable only while ownership lives in the text.

## §4 — The environment axis (no surface equivalent)

A screen claim is true or false in the browser. **An architecture claim can be true on the host
and false in the container**, and nothing about reading the code reveals which. Three failures,
all of which produced wrong results before they were understood:

- **A worker caches imported modules at process start.** Edit a service a queued task imports and
  the worker keeps running the old snapshot — returning *silently wrong* results. A claim
  verified by editing code and re-queueing, without restarting the worker, verified the previous
  version.
- **The host's toolchain is not the container's.** A dependency manager at one major version in
  the image and another on the host rewrites the lockfile into a format the image never uses.
- **Configuration baked at build time.** Copying the tree into the image plus loading a dotenv
  means the image carries real values; *"no env file is mounted, therefore empty"* is false.

**So an architecture claim must name where it was verified** — host, container, worker, dev,
isolated test — the way a surface claim names which state was rendered. *"Verified in the backend
container, 2026-07-28"* is a claim; *"verified"* is not.

## §5 — Anchor on symbols, and here is the receipt

The shared canon (`aidex-conventions/references/reference-conventions.md`, § Stable anchors) bans bare line numbers; this module does not fork that rule. One project's architecture
documentation predated that rule and was built on them: **159 `file:line` anchors** across six
documents. A ten-anchor sample resolved against the current tree returned:

```
ok=5  stale=5  missing-file=0
```

**Half were already wrong**, and the failure mode is the one the rule predicts — they do not
error, they land somewhere plausible. One anchor documented as a function resolved to a keyword
argument in an unrelated call. A reader would take that for the function's body and never
suspect anything.

The pattern tells you which anchors to distrust first: **class definitions at the top of a model
file survived; every service-level function had drifted.** Model files grow at the bottom,
service files grow in the middle.

**Do not mass-repair line numbers.** Re-deriving 159 anchors is a day of work whose output is
another set of numbers that start rotting immediately. **Convert a module's anchors when that
module is swept**, and leave the rest declared as unverified. That project reached zero, per
module, over two days.

---

## The sweep, in order

Stages 2, 3 and 5 are unchanged from `01`. Stages 1 and 4 are substituted.

1. **Code — enumerate, don't read.** Not guards: **branches** (§2), declaration/execution splits
   (§1), string-named references, and the settings surface. Output: a list of configurations.
2. **Relations.** Constraints, keys, orderings and missing tiebreakers; a consumer search for
   every negative; reachability for every positive; migration dates where nulls carry meaning.
3. **Data.** Distribution over the branches from stage 1. Say whether you measured dev or prod.
4. **Run it — one pass, planned.** The substitution for the visual pass, in ascending cost:
   a **query** against dev (read-only, free); a **probe** against the isolated test database
   (drives the real code, **counts as `seen`**); a **management command** or real request in the
   isolated stack; or **the existing test suite**, cheapest of all when it already covers the
   claim.

   **Never against production, and never a write against dev.** The reasoning is identical to
   `01` and the blast radius is larger.
5. **Say where.** Every claim from stage 4 records its environment (§4).

**Stage 4 is not optional here either** — it is *easier* than the visual pass. A probe costs no
auth-throttle budget and can be re-run in a loop. The visual sweep's excuse does not exist on
this side, so a module that skips it is choosing to.

---

## Closing a module

Same bar as `01` — every claim `seen` or `traced`-with-limit, the refuter run, never closed on
link integrity. Two additions:

- **Every anchor is a symbol** (§5), or the module says which of its anchors are inherited
  unverified.
- **Every claim names its environment** (§4).

## Imported prose is not swept prose

Migrating a paragraph out of a legacy document does **not** make it `seen`. It was written under
a methodology with no ledger; its provenance is unknown, which is `inferred` until someone
checks.

So imported text lands with an explicit note naming it an unverified import and pointing at what
would verify it — **or it does not land.** The alternative is worse than leaving it where it was:
once inside the swept document it becomes indistinguishable from content that was actually
checked.

---

## Verification

The claim this file rests on is that the two censuses have different blind spots, so a project
running only one is exposed. Check that a real project's axes disagree:

```bash
cd <project> && ~/.claude/skills/aidex-reference/scripts/docs-census.sh --advisory
```

**Real output, 2026-07-29** (this repo, a CLI/toolkit with no routes at all):

```
skills       0/17 covered (0%)  gap=17 phantom=0 contested=0
hooks        0/3 covered (0%)  gap=3 phantom=0 contested=0
```

Two axes, and a route census would have returned **nothing** here — which is the point of §3:
a project whose only axis is routes reports full coverage of an empty set. **A single-axis
project is the finding.**

> **The `hooks` axis was wrong on its first run** and only dogfooding caught it: without
> `grep -v "^test-"` it counted a test file as a shipped hook. Read a surprising count before
> believing it.
