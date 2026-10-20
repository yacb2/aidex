# Spec grammar — `:::` fences and `{...}` attrs

The exact grammar a page spec is written in and Phase 1's tokenizer reads. This file
is the contract: the tokenizer implements *this*, it does not re-derive a grammar from
the prior art, and a disagreement between the two is a bug in the tokenizer.

## Contents

- [Provenance, and what is NOT installed](#provenance-and-what-is-not-installed)
- [The shape](#the-shape)
- [Lexical rules](#lexical-rules)
- [Attrs](#attrs)
- [Nesting](#nesting)
- [`section`: a page section that is not a `group`](#section-a-page-section-that-is-not-a-group)
- [The page's language](#the-pages-language)
- [Prose outside any fence](#prose-outside-any-fence)
- [Fenced code blocks](#fenced-code-blocks)
- [`gallery` rows and `item dropped=`](#gallery-rows-and-item-dropped)
- [An `item`'s heading: `heading=` over `title=` (BL-652)](#an-items-heading-heading-over-title-bl-652)
- [An `item`'s option list: one choice or a set](#an-items-option-list-one-choice-or-a-set)
- [What counts as malformed](#what-counts-as-malformed)
- [Two layers, and why](#two-layers-and-why)
- [Related](#related)

## Provenance, and what is NOT installed

The syntax is Pandoc's fenced-div grammar (`:::` fences, curly-brace attrs, nesting) as a
hand-written stdlib tokenizer over a stricter subset: everything Pandoc leaves optional,
this grammar requires or forbids, so each construct has one spelling and every rejection
has a line number. Nothing shells out to `pandoc`; no markdown library is installed.

Prose inside a block is rendered by the existing `scripts/dash/md_body.py` subset
(headings, paragraphs, `-`/`1.` lists, pipe tables, fenced code, `` ` ``, `**`, `_`).
This grammar adds fences *around* that; it does not change it.

**A list nests by indentation.** A `-` or `1.` line indented deeper than the first
marker of its list opens a sub-list inside the item above it, of its own kind, to any
depth; a marker at the list's own indent or shallower is a sibling. An indented ordered
marker opens a sub-list only when it counts from `1`; `   25. text` is a wrapped line.
An `item`'s options list is the exception: it is read by `spec_build`, not this
renderer, and an indented line under an option folds into the option's label. A blank line ends
the list, so a sub-list is written with no blank line before it. Before BL-568 every
marker line was a sibling, and a point's `a`/`b`/`c` shipped renumbered as the points
after it. (This is the prose renderer's rule; the indentation of a `:::` fence still
carries no meaning, below.)

### Backslash escapes, for this renderer's own markers only

`\\`, `` \` ``, `\*`, `\_` and `\[` put the character itself in the page. Nothing
else is escapable, and the backslash before anything else is a backslash.

- **Inside a code span the backslash is literal.** `` `a\_b` `` shows `a\_b`.
  CommonMark's rule, and the reason is that a path in backticks is the one place
  an author means the backslash they typed.
- **A literal backtick in prose is a builder refusal, not an escape.** `` \` `` is
  accepted by the renderer, but the page would show a raw backtick (invariant
  CNT-2), so `spec_build` refuses it with the spec line, and refuses a backtick
  with no partner the same way (the renderer leaves it raw too). Write `` `x` ``
  for code; a literal backtick belongs inside a code span. Code spans are paired over the whole wrapped paragraph or list item, so a span
  may wrap. Fenced code blocks and real code spans are code and are not checked; a
  fence opens with exactly three backticks or tildes at the start of the line (a
  four-backtick fence or a BOM before it is prose). A double-backtick span is not
  supported, so ``` ``a`b`` ``` is refused as unmatched.
- **Block markers are not escapable.** `#`, `-`, `|`, `:::` are read a layer
  above this one, by `_blocks` and by the tokenizer, and an escape here would
  arrive after they had already decided. A paragraph that must open with `- ` has
  no spelling in this grammar; see `$AIDEX_SPEC_CORPUS/corpus-specs/CONVERSION-NOTES.md`.

### Inline links

`[text](target)` becomes `<a href="target">text</a>` wherever prose is rendered, in
a body or in an attr such as `heading=`. The label may carry `` ` ``, `**` and `_`;
the target may hold one level of balanced parentheses and no whitespace.

- **Allowed targets:** a relative path (`R1.html`, `../research/nota.html#s2`), a
  `#fragment`, `https:`, `http:` and `mailto:` (none of them carries script;
  `http:` and `mailto:` are what the markdown notes the same renderer wraps use).
- **Refused, with the spec line:** every other scheme (`javascript:`, `data:`,
  `vbscript:`, `file:`), a protocol-relative `//host`, a backslash or a backslash
  escape in the target (`a\_b.html`; write `a_b.html`, a target is never read as
  emphasis) and any control character. The builder stops on the first one:
  `line 3: link target 'javascript:alert(1)' is refused: ...`. The markdown route
  (`wrap-report.sh --in x.md`) does not stop: it renders a refused link as plain
  text, `label (target)`, with no href.
- **Id in `title=`:** an item title starting with its own id and a separator (`Q1 · `, `Q1: `,
  `Q1 - `, `Q1 — `, `Q1. `) is stripped by the builder with a stderr note naming the line;
  `Q1 seguimos` (no separator) is refused with `repeats its id`. A `section` written with
  `title=` and no `heading=` is read as `heading=` the same way (both given: refused).
- **Not in `title=`:** the title is also the rail entry and a decided item's
  summary, where it shows as raw text. A link there is refused with the fence's line.
- **Not a link:** inside a code span or a code fence, or after `\[` (which reaches
  the page as `&#91;`, a bracket the reader sees and the contract does not take for
  a link).

`check-artifact` fails a page (`raw-link`) whose visible text still shows a
`[text](target)`, outside `<code>`, `<pre>` and `<textarea>`: the shape the
blind-review page shipped before this existed.

## The shape

```
::: <block-type> {.class #id key="value"}
<body — markdown prose, or nested ::: blocks>
:::
```

## Lexical rules

A spec file is UTF-8 text, read **line by line**. A line is classified as an open
fence, a close fence, or content — in that order — and nothing else. Line endings are
`\n`; a trailing `\r` is stripped before classification. Line numbers in errors are
1-based and count the file's physical lines.

### Open fence

```
^:::+[ \t]+<block-type>([ \t]+\{<attrs>\})?[ \t]*$
```

- **Starts at column 0.** A fence line with any leading whitespace is content, not a
  fence. This is the rule that keeps a `:::` typed inside an indented list item from
  silently opening a block; it also means a nested fence is written flush left, with
  indentation carrying no meaning anywhere in this grammar.
- **Three or more colons**, run together. The count is *not* significant: it is not
  matched against the closing fence and it does not encode nesting depth. Nesting is
  tracked by a stack (below). Writing `::::` around a block that contains `:::` blocks
  is allowed and is purely cosmetic.
- **The block type is required** and is the first token after the colons. Pandoc allows
  a bare `::: {.class}` div; this grammar does not — the vocabulary is closed
  (`04-block-vocabulary.md`) and an untyped block has nothing to build.
  Type syntax: `[a-z][a-z0-9-]*` (lowercase ASCII, digits, single hyphens, no trailing
  hyphen). An unknown *but well-formed* type tokenizes fine and is rejected by the
  builder, not by the tokenizer — see "Two layers" below.
- **At most one attr group**, in curly braces, after the type. Nothing may follow the
  closing `}` but whitespace.
- **Separator is one or more spaces or tabs.** `:::item` (no space) is content, not a
  fence: requiring the space is what keeps a prose line beginning with colons from
  being read as markup.

### Close fence

```
^:::+[ \t]*$
```

A line of three or more colons and nothing else. It closes the **innermost open block**.
Its colon count need not match the opening fence's. A close fence with no block open is
malformed (see below).

### Content

Every other line. Content belongs to the innermost open block, or — if no block is open
— to the document's top level.

## Attrs

Inside `{` … `}`, a whitespace-separated list of three kinds of item, in any order and
any number:

| Written | Means | Repeats? |
|---|---|---|
| `.name` | a class | yes — classes accumulate, in written order |
| `#name` | the id | **no** — a second `#id` on one fence is malformed |
| `key=value` | a keyed attribute | a repeated **key** is malformed |

- `name` for a class or an id is `[A-Za-z][A-Za-z0-9_-]*`. This is the same shape
  `gallery_items.py` already enforces on a group id (`GROUP_ID`), for the same reason:
  the id becomes an HTML `id`, a `data-id` and the rail's anchor, so anything else is
  either unaddressable or the author's own markup arriving inside an attribute.
- `key` is `[a-z][a-z0-9-]*`.

### Values and quoting

- **Quoted:** `key="value"`. Double quotes only. The value is every character up to the
  next **unescaped** `"`. A value may contain spaces, single quotes, `{`, `}`, `.`, `#`
  and `=`; all are literal.
  Single-quoted values (`key='v'`) are **not** a form of quoting: the quotes would be
  part of an unquoted value, and since `'` is not allowed there, the fence is malformed.
- **Two escapes inside a quoted value, and only two:** `\"` is a double quote and `\\`
  is a backslash. **A backslash before anything else is a backslash** — `title="a\_b"`
  hands `a\_b` to `md_body._inline`, whose own escape pass (§ Backslash escapes) then
  decides what the `\_` means. That is the same layering rule as everywhere else here:
  each layer consumes its own escapes and passes the rest down untouched.

  Refusals keep their line: a quote that never closes (`key="abc\"` is that case) and
  text running straight on after the closing quote. `spec_verbs.py` writes this syntax
  through `spec_parser.quote_value()`.
- **Unquoted:** `key=value` where value matches `[^\s"'{}]+`. Use it for slugs, numbers
  and booleans. Anything with a space must be quoted.
- **Empty is quoted only:** `key=""` is a valid empty value; `key=` is malformed.
- A value is always a **string** to the tokenizer. `n=3` yields `"3"`. Any coercion to
  int/bool is the builder's, per block type.
- Text is carried **raw**. Escaping for HTML happens at build time (`_shell.esc`), once,
  as it already does everywhere else in this skill. A `<` in an attr value is data.
- **No HTML entities, in attrs or prose.** `&quot;`, `&amp;`, `&lt;`, `&gt;`, `&apos;`,
  `&#NN;` and `&#xHH;` are refused by the builder with the spec line, the entity and what
  to write instead: `\"` inside a quoted attr, the character itself in prose. Escaping
  happens once, so an entity would reach the reader as its own letters (echo_lab_ws,
  2026-09-29: a group heading showed `&quot;es-419&quot;`). A bare `&` (`R&D`, `Q&A`) is
  text, and an entity inside a code span or a code fence is code.

## Nesting

A fence may contain fences. The tokenizer keeps a stack:

- an open fence pushes a block;
- a close fence pops the innermost one;
- content appends to the top of the stack, or to the document when the stack is empty.

The result is a tree. Depth is not limited by the grammar; the builder may refuse a
nesting a given block type does not accept (an `item` inside an `item`, say) — again,
builder, not tokenizer.

A `group` needs no child for its own free text: the build closes every group with
its notes box (BL-701; `04-block-vocabulary.md`), so a spec never writes one.

- **A decided-but-correctable point is an `item decided=yes proposal=yes` in its consult group** (BL-687, BL-692: `proposal=yes` keeps it in place instead of folding it as settled), with its round's other items: not a top-level `callout`, not a `ledger` row (the ledger holds what EARLIER rounds settled). Shape: `04-block-vocabulary.md` § `item`; built example: `tests/fixtures/decided-items.spec.md`. A proposal with no option lines is refused (`proposal=yes needs options`), `free=yes` or not: the reader corrects by re-picking, so the proposed option is `{recommended}` or `{chosen}` and pre-selected whether `decided=` is the flag or the verdict text (a `dropped=` item cannot be a proposal).
- **`item` at the document's top level builds**, but `check_artifact`'s `check_shape` fails
  the built page (an item outside a block, § 8.4), so an ungrouped item cannot ship.
- **`item`, `masthead` and `note` accept a nested `note` or `callout`**, in the position
  written (an aside between the question and the options stays there). Everything else
  they could nest is refused by the `PARENTS` table.
- **An `item` also accepts a nested figure block** (`figure`, `chart`, `graph`, `video`,
  `diagram`), in written order; `masthead` and `note` do not (`spec_build.FIGURE_BLOCKS`).
  Two or more ADJACENT `figure`s (`.png`/`.jpg`/`.jpeg`/`.svg`) in an item render as one
  thumbnail grid (`.gal.shots`, `data-cols` = min(n, 4)); any other block, a sentence or
  the option list ends the run, so write a sentence between two figures to keep them
  apart. Every `figure` of an item opens the "Ampliar" viewer (Left/Right or buttons to
  page, an svg at its viewBox width); `chart`, `diagram` and `graph` get none.
- A `masthead`'s **standfirst** is the first paragraph of its own prose; an aside written
  above it stays above it.

## `section`: a page section that is not a `group`

An id'd `<section>` with a `.sec-head` (eyebrow and `h2`): the visual section, the ledger
section or a reference section. Without it the head's strings become loose prose, which
`check_artifact`'s `consult-shape` reads as "prose before the first block" and its `rail`
rule reads as a heading missing from the index.

```
::: section {#sec-ledger eyebrow="Lo ya decidido · 3" heading="Dónde quedó la ronda anterior"}
::: ledger
- d1 — **Hecho.** La migración 2 está cerrada.
:::
:::
```

The `#id` is REQUIRED, for the rail and for nothing else: it is not a `data-id`, no
reply names it and the composer reads only one: a section whose `#id` is `sec-ledger` is where it places the Decided section when no question is still open (after it; with none, after the header), so name the ledger section anything else and the Decided section lands before it. While a question is open the Decided section goes after the last open block instead (BL-860). `heading` is required, `eyebrow` is
optional, and a `section` may only appear at the document's top level — a section
inside a section has no rail entry and no meaning. What it may contain is what the
`PARENTS` table already allows anywhere: prose, `ledger`, `note`, `callout`,
`chart`, `diagram`, `figure`, `verdict`. `masthead`, `group`, `notes` and `item` stay top-level, so they
are refused inside it by the table that already says so.

`group` emits the same `.sec-head` and keeps its own attrs: a group's head also
carries the block's NAME (`data-title`) and its id is a paste key. A `section` names
nothing and is answered by nobody.

## The page's language

A `masthead` may declare `lang="es"` or `lang="en"`: the page's language. It becomes
`<html lang>` through `wrap-report.sh` and selects the kit chrome's strings; a body in the
other language fails `check_artifact`'s `lang` rule (BL-279).

- A second `masthead` is refused ("second masthead"): a page has exactly one.
- A page built from a spec with a `masthead` carries `<meta name="spec-built">`, and check-artifact fails it if a hand edit leaves zero or two mastheads. No `masthead` (a fragment, or `--title`), no stamp. An answerable spec with neither is refused ("no document title").
- A `lang=` that contradicts the body is refused as a mixed-language page: 3 or more stopwords of the other language and at least 3 times the declared language's, counted over rendered prose only (code, attribute keys, URLs and data blocks are left out).

The declaration WINS over `--lang` and over `build(lang=…)`, which are the default
for a spec that stays silent. One owner per fact: the language belongs to the page,
not to the command that builds it.

## Prose outside any fence

A run of content lines while the stack is **empty** is a top-level **prose block**: it
carries no type, no attrs and no id, and it is rendered by passing the run verbatim to
`md_body.py`. Consecutive content lines, blank lines included, form **one** prose block;
a prose block ends at the next open fence, the next close fence, or end of file. Blank
lines around a fence are optional and carry no meaning — the tokenizer neither requires
nor inserts them.

The same rule applies *inside* a block: a run of content lines inside a fence is that
block's prose body, and a block may mix prose runs and nested fences in any order. The
body's parts stay in written order.

## Fenced code blocks

Inside a ```` ``` ```` or `~~~` code fence, `:::` lines are **literal content**, never
fences. The tokenizer tracks the code fence with the same marker rule `md_body.py`
already uses (`FENCE` there): a code block opens on a bare ```` ``` ```` / `~~~` line
and closes only on a bare line of **its own** marker. This is not a nicety — it is what
lets a spec document this grammar, or paste a shell run that echoes `:::`, without the
example opening a block. A code fence left unclosed at end of file takes the rest of its
enclosing block as code (degrade, never drop) and is **not** a malformed-spec error.
At top level the build still names it: one `WARN [unclosed-code-fence]` line on stderr
carrying the fence's opening line, and when the swallowed lines hold a `:::` open the
check is `unclosed-code-fence-swallows-blocks` and `spec_build.py --check` fails before
writing the page, which stays as it was (BL-848).

## `gallery` rows and `item dropped=`

`::: gallery {#id title=… rows=<rows.json>}` reads its rows from a JSON document (shape:
`04-block-vocabulary.md` § `gallery`, and § Gallery rows of `gallery-rows.md`).
These things of the grammar are worth stating here:

- **Prose body** (BL-625): the block may carry one or more paragraphs between its fences. They
  render inside the gallery's group as an author lead, above the generated intro and the first
  row, so context the brief placed before the tiles does not need a group of its own. Prose
  only: a nested block is refused. The lead goes with the block: an empty `rows` (D2) drops
  both, silently.
- **`kind`** of a row is `review`, `unrequested`, `sample` (no radios), `states` (N captures of one
  component, a checkbox each; `04-block-vocabulary.md`) or `alternatives`
  (labelled variants declared once in the document's `alternatives`, one which-one radio). An option's capture may be `{"with-data": path, "empty": path}`: the page shows each option's states adjacent, still one radio per row (`04-block-vocabulary.md`, BL-691).
- **`look`** is required on every shown row by this route: a row without it fails the build
  (and `--check`), with a message naming the cell. Not-applicable and dropped rows are exempt.
- **`answer`** (BL-629) on a `decided` row is the reply to the owner's note on it: the row folds,
  keeps its id, has no radios, and the fold's summary shows the text. Refused on a row without
  `decided`, blank, or on a dropped, not-applicable, alternatives or states row.
- **`dropped="<reason>"`** on an `item` (and `"dropped"` on a row) takes it out of the question
  set: its id stays, it folds like a decided item and reads `Descartada: <reason>` /
  `Dropped: <reason>`. An empty reason, or `dropped` together with `decided`, is refused.

**Dropping items in a new round** (BL-533). A round that removes an item from the spec
is refused by the id-stability check (`consult-ids`, BL-396) unless the page declares the
drop. `spec_verbs.py new-round --drop <#id>` (repeatable) records the ids on the
masthead as `dropped-ids="Q6 Q7"`, which builds `<meta name="consult-dropped">`; the
check then notes those ids instead of failing. Every drop must be declared: an id left
out still fails. An id that stays in the spec is an error there (use `dropped="reason"`
on the item instead). Any id the page no longer carries qualifies (BL-612): an item, a
`group` (`--drop G1`), and a gallery row id (`--drop audit-with-data-light-desktop`, a
row is never a spec node). The verb only refuses ids still in the spec; it does NOT check a
row id against the rows document, so drop only rows really gone from it.
The verb only records and rebuilds; it never opens a round.

Relabelling: a `group` or gallery block whose id stays and whose `title` changes only
produces a note in `consult-ids` (a block title is a label, not a claim a reply points
at). An `item` whose title changes still fails unless declared with `--retitle`.

**Rewording an item's title** (BL-611). Changing the title of a kept id fails `consult-ids`
("id reused for a different claim"). `spec_verbs.py new-round --retitle <#id>` (repeatable)
records the ids on the masthead as `retitled-ids="Q1 Q3"`, which builds
`<meta name="consult-retitled">`; the check then notes each id with its old and new title
instead of failing. The id never changes, and an id left out still fails. Unlike `--drop`,
the declaration lasts ONE round: every `new-round` replaces `retitled-ids` with its own
`--retitle` list and removes it when the call names none, so a later reword of the same id
must be declared again. The id must still be in the spec. Start every round with
`new-round`; a rebuild by other means keeps the previous declaration. (`new-round` also settles
the `proposal=yes` items the reader saw on the saved answered page, BL-692, the ones the reply lists as accepted under `## Decidido sin corrección` included, except one the saved
reply answered (an ask, `[not-now]` or a page defect in any saved paste, a re-pick, Other or a note), which stays an
open proposal until the writer `decide`s it, BL-711; it changes nothing
about ones written this turn.)

## An `item`'s heading: `heading=` over `title=` (BL-652)

The `<h3>` of an item is its first paragraph when that paragraph closes on a question,
else its `title=` (BL-576). When the sentence over the item is not a question and the
rail entry and the reply heading must stay a short name, write `heading="…"` beside
`title="…"`: the h3 is the heading whole, `data-title` stays the title, and the first paragraph
becomes the situation lead (`.consult-lead`) under the h3, as for a title-headed item. It is the same attr `group` and
`section` already take, with the same meaning (`title` the NAME, `heading` the sentence).
Without `heading=` nothing changes. Adding `heading=` to an item on a live page changes its h3, so its `questionHash` changes once and typed-but-unsent text reads blank once (as BL-576). `heading=` follows the `title=` quoting rules and is
not a retitle: `consult-ids` and `check_prev` read `data-title` only.

**The title is shown, never hidden.** When the h3 is a question or a `heading=` that differs
from the title, the builder prints the title above it as a kicker (`eyebrow consult-kicker`),
because the rail lists the item by `data-title`.

## An `item`'s option list: one choice or a set

The first markdown list in an `item` body is its option list, and the `item` builder
reads it (the tokenizer only sees prose). A second `-` list is refused at its line:
number an explanation list (`1.`) or move it into a `note`. One option per `- ` line; ` — ` splits the
label from its hint; `{recommended}` anywhere on the line marks it, except inside a
backtick span (there it is the syntax quoted, and stays literal). `{chosen}` is the same
marker for a decided item's winning option: checked, not recommended, at most one on a
`select=one` item (several on `select=many`), refused on an undecided item (`04-block-vocabulary.md` § item).
`{provisional}` is its mirror on an OPEN item: the option the reader picked beside an ask
last round, drawn checked while the item stays asked; refused on a decided or dropped item
and twice on a `select=one` item. The keyed attr
`select=` decides what kind of list it is:

| `select=` | Renders | Reply | Use it for |
|---|---|---|---|
| `one` (default, or absent) | radios, `.opts one` | the one ticked option | one decision among alternatives |
| `many` | checkboxes, `.opts` | every ticked option, in page order | one question whose answer is a set |

Any other value is a builder error with the fence's line
(`` line 3: `item` select='several' is not a value (it takes: one, many) ``). Several
independent decisions are several items, never one `select=many` item — see
`04-block-vocabulary.md` § item.

`select=many` with no options to tick is refused too (an open answer is `free=yes` alone).

Closed vocabularies the builder refuses outside of (M1):

- `free=` and `proposal=` take `yes` or `true`; anything else (`YES`, `1`, `maybe`) is refused.
- `decided=` is `yes`/`true`/`1` (the flag) or the verdict as text. `no`, `false` and `0` are refused as a verdict (they read as "not decided"): leave `decided` off. Exception: the text is, to the letter, one of the item's option labels (`decide --verdict No` on an option `No`), or the item has no options.
- The flag is read case-insensitively and without markdown marks (`YES`, `**True**`, `1`), by the builder and by `spec_verbs.py`: `new-round` files such an item in the ledger as the bare title, not `Title (YES)`.
- `spec_verbs.py decide` on a `select=many` item records the labels in the options' own order, whatever order the verdict named them in; the same set in another order is already recorded (byte-identical, no new round stamp).
- A `verdict` block holding a header and a separator but no cell row is refused (`one row per cell`), not built as an empty box.
- `spec_build.py --new-round` needs `-o <out.html>`, like `--check`; without it the flag is refused instead of ignored.
- `spec_build.py --no-reply` needs `--new-round`: it opens a round the reader sent no reply to, and is refused when the round has a saved reply (BL-824).
- Item ids that differ only by case (`Q1`, `q1`) are refused; other blocks only collide on the exact id.
- An option's hint is separated by ` — `; a spaced ` - ` or ` -- ` is refused.
- A `pill`/`chip` tone is one of `md_body.SPAN_TONES`; a malformed or unknown tone is refused.
- A block class is `.warn` or `.wide` (`spec_build.BLOCK_CLASSES`); any other is refused.

## What counts as malformed

Every case below is a hard error: the tokenizer raises with the **1-based line number**,
the offending line, and what was expected. It never guesses, never repairs, and never
silently drops input.

| Case | Example |
|---|---|
| Close fence with no block open | a `:::` line at top level |
| End of file with a block still open | missing `:::` |
| Open fence with no block type | `::: {.big}` |
| Block type not `[a-z][a-z0-9-]*` | `::: Item`, `::: my_item`, `::: item-` |
| Text after the attr group | `::: item {.x} trailing` |
| Unclosed or unopened attr brace | `::: item {.x`, `::: item .x}` |
| Two `#id`s on one fence | `::: item {#a #b}` |
| A repeated attr key | `::: item {n=1 n=2}` |
| `key=` with no value | `::: item {title=}` |
| Unquoted value containing a quote, brace or space | `::: item {title=two words}` |
| A quoted value whose closing `"` never arrives | `::: item {title="abc}`, `::: item {title="abc\"}` |
| Text running straight on after a quoted value | `::: item {title="abc\\"x}` |
| An attr item that is none of the three kinds | `::: item {big}` |
| A fence opened more than 100 deep (`spec_parser.MAX_DEPTH`) | the 101st `::: note` inside 100 open ones |
| A markdown list nested more than 50 deep (`md_body.MAX_LIST_DEPTH`; the builder's refusal, at the block's line) | a 51st `- x` indented under 50 others |
| An HTML entity in an attr value or in prose (the builder's refusal, not the tokenizer's; code spans and fences exempt) | `heading="&quot;x&quot;"` (write `\"x\"`), `a &lt; b` (write `a < b`) |
| Raw syntax in prose (the builder's refusal, CNT-1/2/3; code spans and fences exempt), a markdown heading in an item body, a `section` with no body | an indented `:::` line, a literal `{#x}`, a `**` that closes nothing, `# Titulo` in an item, `::: section` with nothing inside |

Not malformed, on purpose: an **unknown block type**, an **unknown attr key**, and a
**missing required attr**. They tokenize; the builder rejects them.

## Two layers, and why

**Tokenizer** = shape only: fences, nesting, attr syntax. It knows nothing about
`item`, `chart` or `masthead`.

**Builder** = meaning: which types exist, which attrs each one takes, which are
required, what may nest inside what.

A shape error names a line and a character; a vocabulary error names a block type and an
attribute and lists the alternatives.

## Related

- `06-block-bodies.md` — the body and shape rules of `chart`, `diagram` (with `tree` and `compare`), `figure`, `video` and `graph`.
- `04-block-vocabulary.md` — the closed set of block types, their attrs and corpus counts.
- `01-dash-conventions.md` — the GENERATED header contract of rendered board pages and spec-built pages.
- `02-local-first-artifacts.md` — the Route S how-to; the page contract `check-artifact` enforces on the
  HTML the build emits is in `consultation.md` and `route-b.md`.
