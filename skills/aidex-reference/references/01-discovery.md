# Discovery: finding the claims

How you find what to document, so that describing something does not depend on someone
remembering to mention it.

**Every rule below is stated as the failure it prevents.** That is deliberate and it is
load-bearing: a rule that reads as general advice does not get run. Each one is a false
statement that actually shipped into a reference, survived a full internal-link check, and was
caught only because a reader happened to remember the feature.

The common shape, and the reason this is a mechanical protocol rather than advice to be
careful: **none was an invented fact.** Every one was a correct reading of one file, where the
answer lived in another. Confidence was uniformly high.

> **Subject has no screen?** Read [`02-architecture.md`](./02-architecture.md) instead of rules
> 1, 2 and 4. It is a *substitution*, not an appendix — for a library, a CLI or a service it is
> the default path, not the exception. The ledger and rules 3, 5, 6, 7 apply unchanged either
> way.

---

## The provenance ledger

The single rule that catches most of it. Every claim carries one of three labels while you work:

| Label | Meaning | May it ship? |
|---|---|---|
| `seen` | The branch was observed running, **or** reproduced by a probe/characterization test | Yes |
| `traced` | Followed in code to its conditional, not observed | **Only with the limitation stated inline** |
| `inferred` | Deduced from a pattern, a framework's reputation, a name | **Never** |

`inferred` never ships. Not as a hedge, not as "presumably" — it is either promoted to `traced`
by following the code, or it is cut.

`traced` ships with its limit named in the text: *"verified in code; not exercised"* rather than
*"exercised 2026-07-28"*. This is what makes **"can this module be closed?"** answerable by
reading it, instead of depending on what a reviewer remembers to ask.

---

## Rule 1 — A surface is not a file

**The failure:** a grid's row actions were declared *in the page* as a data prop; the menu
widget lived *in the shared table component*. Grepping the page for the menu component returned
nothing, and that absence was written up as "there is no context menu". **Five real actions —
including delete — were documented out of existence.**

A page that hands data to a shared component **is** describing a surface. The declaration and
the rendering are in different files by design, so searching one and finding nothing proves
nothing.

Search **outward** from the page — find the props it declares and follow each to whoever renders
it — then **reverse the direction**, because a shared component's own file never lists its call
sites.

The same split exists wherever a page delegates: columns, dialogs, cell renderers, toolbars.
Treat *"the page passes X"* as *"X is part of this surface"*.

## Rule 2 — Every guard is a document you have not read

**The failure:** a control was documented as always present. It renders behind a conditional on
optional data. Half the users see a different screen, and that screen was described as the one
with the control.

A conditional is not a detail of a surface; it **is** a second surface. Enumerate them before
writing and give each one a disposition: *observed in state A and B*, or *observed in A, B marked
`traced`*. A guard with no disposition is an unwritten state, and it is exactly where the
reader's reality will diverge from the document.

**The corollary that bit twice: disabled is not absent, and hidden is not disabled.** A button
greyed with an explanatory tooltip, a menu entry that vanishes without permission, and a control
that never renders are three different user experiences. Say which one.

## Rule 3 — A negative requires a consumer search

**The failure risk:** *"this field is something nothing reads."* Read as a declaration it looks
like ordinary configuration — it even had validation. It survived only because someone searched
the whole tree, in both repos, for consumers.

Claims of the form *nothing reads X* / *X is not possible* / *there is no Y* cannot be supported
by reading a declaration. They require **the search that comes back empty**, and the document
must record what the search covered. *"No consumer in either repo outside tests and migrations"*
is a claim; *"nothing uses it"* is a guess wearing a claim's clothes.

Budget accordingly: **a positive costs one file read, a negative costs a tree search.** Most
documents are mostly negatives, because the useful sentence is usually *"this does less than it
looks like"*.

## Rule 3′ — A positive requires a reachability proof

**The failure:** the symmetric one, and the one that goes unnoticed longest, because it is
*cheap* to commit. Something is found in the code, read correctly, and written up as a feature.
Nobody asks whether a user or a caller can reach it. The document now advertises dead code, and
every reader who trusts it goes looking for a thing that is not there.

Before a thing is documented as a capability, **name its entry point and the chain from that
entry point to the code.** The kinds of entry point that exist are project-specific and are
declared in `.context/references/00-profile.md` — route, endpoint, scheduled job, queue
consumer, management command, signal handler, webhook, public export.

A capability reachable from none of them is **either dead code, or a capability whose entry
point you have not found** — and which of the two it is *is the finding*, not a detail to
resolve quietly.

**The inverse error is real too, so do not read grep as truth.** Anything named by a *string*
rather than a symbol — a scheduler row naming a dotted path, a provider registry key — is
invisible to grep and to the type-checker. It looks dead and is live, and a rename that an IDE
blesses breaks it with nothing going red.

**Cost note:** run per claim this rule is expensive, which is why it does not get followed.
Run once as a census (`scripts/docs-census.sh`) it is a diff, and the whole sweep amortizes it.
Use the census.

## Rule 4 — A framework's limits get checked, not recalled

**The failure:** *"the context menu is an Enterprise feature, so this Community-licensed grid has
none."* The widget is Enterprise. The **event** is not. The app listened to the event and rendered
its own menu — which is why the menu existed all along.

A recalled limitation is `inferred`, and `inferred` never ships. Check the library, or check what
the codebase actually does with it. A project constraint bounding which *widgets* may be used
tells you nothing about which capabilities the app built for itself.

**The same applies to code comments.** A comment beside the row actions warned that two icon
names were unmapped and rendered nothing; both were mapped. A comment is a claim by a past
author, with the same provenance problem as anything else — it ages in place, and nothing turns
red when it goes stale.

## Rule 5 — A release note proves shipping, never current state

The changelog is the case the source rules do not cover, and it cuts both ways in one session:

- **It corrected a wrong conclusion.** A missing prompt was about to be documented as an
  oversight. The changelog showed it was withdrawn on purpose, with the reason.
- **It caused one.** An entry saying an action "is rejected" was read as current. The screen
  shows the button *disabled with a tooltip* — a later change the earlier entry cannot know
  about.

Entries accumulate and later ones reverse earlier ones, so **a single matching entry is not the
answer.** A release note establishes that a change shipped and preserves the *why*, which is
often recorded nowhere else and is worth mining. It never establishes that the change is still
in force.

## Rule 6 — Separate field age from row age

**The failure:** a column was null on most rows, and that was written up as meaning the default
path had been taken. The field had been added six weeks earlier. Every row before that date is
null because **nothing recorded it** — a completely different meaning sharing one representation.

Before reading a column's nulls or defaults as semantics, ask **when the column was added** and
how much data predates it. If rows predate the field, the null has two meanings and the document
must say both.

## Rule 7 — Ask the data which branches are real

Code shows what *can* happen; only the data shows what *does*. A capability was documented from
the code, then queried: zero rows used it, which retired two enum values as unused in the same
stroke.

Run the distribution query for anything the document treats as a live variation, and pin the
**command** in the Verification block so the next reader re-derives instead of trusting.

Two cautions, both earned:

- **Dev is not production.** Say which you measured.
- **Ordering without a tiebreaker is not an order.** Two selection paths picked "the same" row by
  two different rules, and neither the model's ordering nor the query's `order_by` reached a
  unique column. They agreed on the day they were checked. **A single observation of a
  non-deterministic ordering is not evidence of a rule.**

---

## The sweep, in order

Cheapest first; each stage narrows the next.

1. **Code — enumerate, don't read.** Guards (Rule 2), delegated props (Rule 1), permission calls,
   and the user-facing copy the surface uses. Output: a list of states, not prose. A locale file
   is the fastest inventory of *candidate* copy — and it is not evidence that any of it renders.
2. **Relations.** Constraints, foreign keys, orderings and their missing tiebreakers; consumer
   searches for every negative (Rule 3); reachability for every positive (Rule 3′); migration
   dates for every field whose nulls carry meaning (Rule 6).
3. **Data.** Distribution over the branches from stage 1 (Rule 7). This tells you which states
   are worth the cost of observing.
4. **Observe — one pass, planned.** Pick a real case per state from stage 3 and watch it. The
   instrument is in the profile.

**Stage 4 is not optional, and skipping it is this protocol's own failure mode.** On its first
run the sweep did stages 1–3 and reported findings without it — the labels said `traced` but the
summary read as settled. Two claims flipped from deduced to observed the moment the pass was
actually run, and one gained a nuance no amount of code reading would have produced. If it
cannot be run, **say which states stayed `traced`**; do not let the omission be silent.

### Read-only against dev; anything that writes goes to the isolated environment

Loading a page, snapshotting the accessibility tree, dispatching an event to open a menu that is
already there — safe against dev, and it is what most documenting needs.

Anything that **writes** — creating a row, running CRUD, triggering a pipeline, uploading,
deleting — must not touch dev. The distinction is not caution, it is what a claim is worth: a
write-path claim verified against dev has contaminated the very fixture the next reader will
check it against.

> **Never trust a green run you have not seen fail.** One project's isolated-test template
> database had fallen behind the migrations on disk, and the runner **reported success without
> executing anything**. An empty run and a passing run are the same output. It was settled with
> a deliberately failing canary that reported one failure and propagated a non-zero exit.

### A probe counts as `seen` — but a probe is not a test

Some claims cannot be observed at reasonable cost, and they are exactly the ones worth pinning,
because they describe damage that happens quietly. **A probe written against the isolated test
database drives the real service code rather than asserting a reading of it, and counts as
`seen`.**

The difference from a test is the document's problem, because it changes what the reference may
say:

- **Disposable probe** — lives outside the suite, in scratch space. Use it when the behaviour it
  reproduces is a **defect**. A characterization test that passes *because* a bug exists is a
  trap: when the bug is fixed the test goes red and the reflex is to fix the test. The reference
  must then say plainly that **nothing re-verifies this claim** and point at the item that owns
  it. That sentence is not a weakness; it is the accurate cost of writing down a defect.
- **Kept test** — belongs in the suite and is pinned from the Verification block, so document and
  proof move together. Appropriate when the behaviour is intended and merely non-obvious.

**Documenting is a read activity.** A sweep that starts committing files to a working branch has
quietly changed jobs. Probes go to scratch; anything meant to survive is the user's call.

### When a claim is not falsifiable, pin its preconditions

Non-determinism cannot be made to misbehave on demand, and observing the "right" result proves
nothing twice. Do not chase a reproduction. **Pin the facts that make the divergence possible** —
two selection rules keyed differently, no ordering reaching a unique column — and say plainly
that the failure is *possible* rather than *demonstrated*. A document claiming more will be
contradicted by the next run that happens to agree.

---

## Closing a module

A module may be closed when **every claim in it is `seen` or `traced`-with-limit** — and never
on link integrity:

> 388 internal links resolved, zero broken, across a document with **three false statements in
> it.** Link checks verify the shape of the document. Nothing in this file verifies shape.

Two additions that are not the author's to self-assess:

- **Run the refuter** (`agents/reference-refuter.md`). Closing on your own labels is the failure
  the ledger cannot catch, because you assigned the labels.
- **Re-read your own corrections.** A correct sentence was changed into a false one during one
  sweep, because the correction was *reasoned* rather than *looked up*. A correction is a new
  claim and takes the same ledger label as any other.

---

## Verification

This file states rules, so its check is that the expensive one is actually paid for — Rule 3′
is only followed if the census makes it a diff instead of a per-claim search:

```bash
~/.claude/skills/aidex-reference/scripts/docs-census.sh --dry-run
bash ~/.claude/skills/aidex-reference/tests/test-docs-census.sh | tail -1
```

**Real output, 2026-07-29:** the dry run prints each axis command without executing it; the test
suite reports `25 passed, 0 failed`. **A dry run that prints nothing means the project has no
`00-profile.md`, so Rule 3′ has no entry-point list and reverts to a per-claim search** — which
is the state in which it does not get followed.
