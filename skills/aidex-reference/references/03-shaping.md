# What belongs, and what shape it takes

[`01-discovery.md`](./01-discovery.md) finds the claims. This decides **which of them belong,
where they go, and what shape the document takes.**

> Filenames, front-matter, numbering and the `## Verification` contract live in the shared canon
> (`aidex-conventions/references/reference-conventions.md`) and are not forked here. This file
> carries the **judgment** the canon does not: topic boundaries, what to leave out, and when a
> module has become two.

---

## The axis: surfaces versus mechanisms

Everything else depends on this, and getting it wrong is what causes repeated reorganization.

**The boundary test:** if a user can see it on a screen, it is a **surface**. If it is only
observable by reading code or logs, it is a **mechanism**. A mechanism spanning modules is
architecture; one about how a layer is built is a layer document. Something that is *both* gets
written twice for two different purposes with a link between them — **never the same paragraph
in both places.**

**Cut feature topics by screen or flow. Cut architecture topics by subsystem.** Do not cut
feature topics along code-module boundaries: that works while the documents describe mechanism,
because mechanism does live inside one module. **It breaks the moment they describe what a user
does, because a journey crosses modules constantly.** A single screen touching four modules has
no home in a module-shaped taxonomy, and the instinct is to move walls rather than question the
plan.

The cost of getting it wrong, measured: two documents — one in features, one in architecture —
both documenting the same two models, because the boundary was never defined by an axis. The old
criterion, *"if in doubt, put it in features"*, is **a coin flip, not a rule.**

**Domain models are not architecture.** Putting them there recreates the same error one level
over: architecture is cross-cutting subsystem, not a table inventory.

### An area with no screen of its own is not a feature area

If every place a user touches something lives on someone else's screen, that thing is a
**subsystem wearing a feature costume** — a symptom of having cut along code boundaries. Media is
the worked example: uploads happen on one hub, waveforms appear in an editor, and there is no
"media" screen anywhere.

Such a module is **dissolved, not converted** — and only once every destination exists.
Dissolving earlier produces orphaned content with nowhere to land. Do the surfaces first and it
empties itself: by the time each screen has been written in its own area, what remains is
exactly the mechanism, and that moves in one clean step.

### Apply the axis as each module is touched

Renumbering and relocating everything at once is not worth it: inbound references break, and
modules still frozen from an earlier pass would only be *moved*, not corrected. A module already
rewritten under the axis stays; one not yet reached keeps its place until its turn comes.

---

## Where a present-tense claim may come from

A reference describes the system **as it is now**. Only three sources support that:

| Source | Use it for |
|---|---|
| The code | Behaviour, contracts, guards, why a branch exists |
| The database | Whether something is actually exercised, and how |
| Another reference | Mechanism owned by a different module — **link, don't restate** |

**A plan and an audit are never sources of present state.** They are event documents: they
record what was true on the day they were written, with that day's numbers. A plan's headline
figure was carried into a document as current fact and was false; the one real measured pair was
a different number entirely.

If a claim cannot be traced to code, the database or another reference, **it does not go in.**

---

## Enumerate versus orient

The distinction that governs everything else. A reference must never **enumerate** what the code
declares — it must **orient** a reader toward it.

**The test: if a command returns it in seconds, it does not go in prose.** A reference that
restates the code becomes a second copy that desynchronizes silently, and the reader has no way
to tell which one is lying.

**Leave out — re-derive instead:**

- Field lists, enum members, constraint names.
- Endpoint tables, route tables.
- Code snippets showing how something works. Point at the symbol; the code is the code.
- **Any count.** Not fields, not endpoints, not rows. A count is stale the moment someone adds
  one, and nothing fails when it goes stale. Name what matters or point at the command; never
  tally.

**Keep — nothing else records it:**

- **Decisions and their rejected alternatives.** The code shows a self-referencing key; it cannot
  show that a child relation was considered and rejected.
- **Invariants with no constraint behind them.** Exactly what a refactor breaks, because nothing
  turns red when they break.
- **Anomalies and exceptions.** Two sibling routes behaving differently is worth a sentence; that
  both exist is not.
- **Cross-boundary contracts** — the shape a caller needs without reading the implementation.
  One line, never a schema.
- **The command that re-derives everything above.**

### Four things that look like code and are not duplication

Going "no code at all" is a step too far. Removing these makes the document prettier and less
trustworthy:

| Kept | Why it is not a copy |
|---|---|
| Symbol anchors | An address, not a copy. Without them, exploration starts with blind greps |
| Verification commands | They do not *describe* the system, they **measure** it |
| Measured output with a date | Evidence for a claim, not a restatement of code |
| A cross-boundary contract line | Serves a reader who will not open the implementation at all |

**A document with no anchors and no commands is unfalsifiable** — nothing in it can be checked,
so nothing in it can be known to be stale. That is a worse failure than being slightly long.

### Grep every symbol you name

An anchor is only an address if it resolves. **A symbol that does not exist fails silently and
completely**: the validator passes, the census reads `covered`, no link is broken, and the reader
greps for a name that is nowhere in the tree.

It happened on the first production run, in a *correction* written to fix an earlier refutation:
the module named `multipart_upload.py::complete_upload` as the caller. The reachability was right;
the function is `complete_multipart`, and `complete_upload` appears nowhere in the repo. Invented
from the shape of the surrounding names, and it took a second close-gate pass to catch.

So before the module ships, grep the symbols back — one pass over what you wrote, not per claim:

```bash
# every `file.py::symbol` and every `backtick_symbol` you introduced
grep -rn "def <symbol>\|class <symbol>\|<symbol> =" <src>
```

Nothing you can automate fully — a symbol may be a settings key, a column, a CLI flag — but the
question is mechanical and it is the last cheap check before an expensive one. **A wrong symbol is
as unfollowable as a stale line number, and unlike a stale line number nothing about it looks
wrong.**

---

## Lead with the journey, not the layer

**A module opens with what the user does and sees. The mechanism comes after.**

Organising a module as data model → backend → frontend describes the order it was *built*, not
the order it is *understood*, and it buries the product. There is no "Frontend" section: the
user-facing journey **is** the spine, and where the code lives is a short pointer near the end.

A journey is legitimate reference content, not duplication — **it does not live in any single
file.** It is spread across a router, several pages and their components, and reconstructing it
is expensive and error-prone. **Aggregation no single file provides is exactly what earns a
document its place.**

### Define once where it is born; document behaviour where it happens

A concept spanning several areas is **not** written as one cross-area document. It is defined
once, in the area where the thing comes into existence, and each area then documents **what you
do with it there**.

**Why locality wins:** a single cross-area document describing another area's screens goes stale
whenever that area changes — but it sits in a folder nobody opens when changing it. The change
and the documentation end up in different places, which is the definition of documentation that
rots. **Locality puts the document next to the thing that would invalidate it.**

**The guardrail that keeps this from becoming N drifting copies:** an area document says *what
you do here*; it never redefines *what the thing is*. It links to the definition. The moment an
area document explains the data model of something defined elsewhere, the rule has been broken.

### "What a healthy X looks like"

Close the journey with a short list of what should be true when nothing is wrong. **This is the
section that earns the document its keep**, because it is what makes a deviation *visible*. A
reader comparing the list against reality either confirms the system or finds a question — and
finding the question is the point.

Write each entry as an observable state, not an instruction, and say what a mismatch would mean.
This is also where a known rough edge belongs, stated plainly. **A reference that only describes
the happy path cannot be used to tell healthy from broken**, which is most of what a reader needs
it for.

---

## Shape

### Flat file or folder

**An area is a flat file while it fits in one document. It becomes a folder when it needs three
or more. Never nest preemptively.** A folder for a single document buys nothing; a flat list of
twenty files with no grouping is just as bad in the other direction.

**Count the surfaces, not the files you happen to have written.** Merging four surfaces into one
file and then observing "this area is only two documents" is circular — it was the merge that
produced the number.

**Areas are named, never numbered.** A named folder never has to be renumbered when the topic
grows, which removes the single largest source of churn: every renumbering breaks inbound
references, and the fear of breaking them is what makes a reorganization keep getting deferred.

> A named **flat** area (`voices.md`) composes the two rules into something the shared validator
> rejects, since it wants `NN-<slug>.md`. Numbering it reintroduces the churn the naming rule
> exists to remove; wrapping it in a folder is the thing this section rejects. **Record a waiver**
> in `.context/.aidex-waivers` with `-` as the anchor — the finding is about the *name*, which
> content edits do not change, so a content hash would resurface it forever.

### One summary, and only one

| Level | Its job | What it must never do |
|---|---|---|
| Topic index | **Describe** — one line per module or area | Explain how anything works, or link into a document's sections |
| Area index | **Summarize** — what the area is, how its documents relate | Restate what its documents say |
| A module | **Explain** | — |

A fact lives at exactly one level, so nothing is written twice and nothing can drift out of sync.

**Deep links into a document's sections do not belong in an index.** They resolve today and rot
silently tomorrow, and nothing detects it — a checker would have to reimplement the renderer's
slug rules to even find out. One project's index pointed at a section anchor that **kept
resolving perfectly while the claim named in it became false.**

### Where `covers:` goes in a folder area

**On the module that explains. Never on an index.**

This falls straight out of one-summary-per-level: the module is the only level that *explains*,
so it is the only level that can own. An area index that also declares `covers:` makes the
census report `contested` between an index and its own children — a false positive that trains
readers to ignore the one class that means real drift.

So for a modular area:

```
features/editor/00-index.md      no covers:  — it summarizes
features/editor/01-shell.md      covers: "routes:/productions/:id/editor"
features/editor/04-timeline.md   covers: "routes:/productions/:id/editor"   ← also legitimate
```

Two modules in the **same area** declaring the same route is normal and not drift: one screen
can need several documents, and the area is the unit a reader opens. `contested` earns its keep
across **different areas or topics**, which is where the boundary was never decided —
a features module and an architecture module both claiming the same subsystem.

### The size trigger

**Above roughly 2,500 words, review the module. Do not split reflexively.** Measured with
`wc -w`; it is a tripwire that makes you ask two questions, not a limit:

1. **Is there re-derivable content?** Usually yes, and removing it is the whole fix.
2. **Is there a second workflow in here?** Only if yes does the module split.

A long but coherent module is navigated with sections. A module mixing two workflows navigates
badly at any size, including well under the trigger.

**Count words, never lines.** Line counts measure text-wrapping style: an unwrapped module looks
less than half the size of a wrapped one with comparable content.

> **This threshold is not `CLAUDE.md`'s, and the economics are opposite.** `CLAUDE.md` is loaded
> on *every* request, so every token is a permanent tax. A reference module is read **on demand,
> once, when it is relevant** — making it too small does not reduce cost, it raises it, because
> the reader pays an index read, a guess, and then exploration anyway. **The binding constraint
> here is duplication, not length.**

---

## Verification

This file sets a size trigger, so the check is that it and its siblings respect it:

```bash
wc -w ~/.claude/skills/aidex-reference/references/*.md ~/.claude/skills/aidex-reference/SKILL.md
```

**Real output, 2026-09-02 — stated as the invariant, not the numbers:** every reference module is
**either under the ~2,500-word trigger or carries the note that answers it** (see the block inside
`01-discovery.md`'s Rule 3′ for the shape), and `SKILL.md` is under the skill-conventions budget
(~4k tokens ideal, 5k max).

**No count is pinned here.** Every number this command returns is about a file that changes on
every edit, and this block is itself one of the files it measures — a pinned value is stale the
moment it is written. A module the command reports over the trigger is **the tripwire firing, not
a violation**: answer its two questions — is there re-derivable content, is there a second
workflow — in a note beside the rule, and leave the count to the command.
