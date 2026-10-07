#!/usr/bin/env python3
"""The per-operation VERBS: spec-only edits, atomic refusals, and the rebuild.

Six claims, in the order the plan's acceptance names them:

  THE SPEC IS WHAT MOVES — one case per verb, asserting both halves: what the
  SPEC text became, and what the REBUILT page then carries. A verb asserted on
  the spec alone would pass while building nothing, and a verb asserted on the
  page alone would pass while the spec and the page had drifted apart, which is
  the one failure the spec route exists to remove.

  THE ROUND TRIP — verb call, then `check-artifact.sh` on the rebuilt page. No
  exemption, no WARN. This is the test Task 1.3 names.

  ATOMICITY — a verb pointed at a missing id, at the wrong kind of block, or at
  an edit whose result would not build, writes NOTHING: the spec file is
  compared BYTE for BYTE afterwards, and so is the page. A half-edited spec is
  worse than a refused edit; a refusal that leaves half a fence behind is worse
  than both.

  NO VERB WRITES HTML — asserted twice, because each half is weak alone. Behind:
  the page a verb produced is byte-identical to the page `spec_build.py -o`
  produces from the same spec text (modulo the build STAMP, which is a clock).
  In front: the module holds no markup and calls no emitter, so there is no
  second renderer to drift from the kit.

  THE AUTHOR'S FORMATTING SURVIVES — a diff of the whole spec before and after,
  asserting that `add-item` and `new-round` only ever ADD lines and `decide`
  changes exactly ONE. No reflow, no re-indent, no attr reordering, no re-quoted
  title, no normalised trailing newline.

  IDEMPOTENCY, PER VERB — `decide` on an already-decided item and `new-round` on
  an already-synced ledger come back byte-identical; `add-item` with a used id
  refuses. Each is the choice `spec_verbs.py` documents, asserted so the
  docstring and the behaviour cannot part ways.

Stdlib only, no runner: `python3 test_verbs.py`, prints OK, exits 0.
"""
import ast
import difflib
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
SCRIPTS = os.path.join(SKILL, "scripts")
sys.path.insert(0, SCRIPTS)
sys.path.insert(0, os.path.join(SCRIPTS, "dash"))

import check_artifact                                        # noqa: E402
import spec_verbs                                            # noqa: E402
from spec_verbs import VerbError, add_item, decide, new_round  # noqa: E402

VERBS = os.path.join(SCRIPTS, "spec_verbs.py")
BUILD = os.path.join(SCRIPTS, "spec_build.py")
CHECK = os.path.join(SCRIPTS, "check-artifact.sh")

failures = []


def fail(msg):
    failures.append(msg)
    print("FAIL: " + msg)


def ok(msg):
    print("  ok: " + msg)


def check(label, cond, detail=""):
    if cond:
        ok(label)
    else:
        fail("%s%s" % (label, (": " + detail) if detail else ""))


def refuses(label, fn, needle):
    """The verb refuses with a `VerbError` that names `needle`."""
    try:
        fn()
    except VerbError as exc:
        if needle not in str(exc):
            fail("%s: message %r does not mention %r" % (label, str(exc), needle))
        else:
            ok("%s (%s)" % (label, exc))
        return
    except Exception as exc:                        # noqa: BLE001
        fail("%s: raised %s instead of VerbError (%s)"
             % (label, type(exc).__name__, exc))
        return
    fail("%s: accepted it" % label)


def diff_shape(before, after):
    """`(added, removed)` line counts between two spec texts.

    Line-level and not token-level on purpose: the claim is that the bytes of
    every line the verb did not edit are where the author left them, and a
    line-level diff that reports zero removals proves exactly that for an
    insert.
    """
    a, b = before.split("\n"), after.split("\n")
    added = removed = 0
    for row in difflib.ndiff(a, b):
        if row.startswith("+ "):
            added += 1
        elif row.startswith("- "):
            removed += 1
    return added, removed


# The fixture: every shape the verbs address and `check_artifact.py` has a rule
# about — a masthead with its visual declaration, a group, a decided item, an
# open item, and the general-notes item the contract requires.
PAGE = '''::: masthead {eyebrow="Fixture · spec verbs" byline="Fuente: `tests/test_verbs.py`" visual="none: la decisión es de formato y no tiene forma que dibujar"}
# La página editada por verbos

Dos preguntas abiertas y una decisión cerrada.
:::

::: group {#G1 title="Formato del spec" eyebrow="Bloque G1"}
La consulta de hoy: qué escribe el agente cuando la página cambia.

::: item {#Q1   title="Fences o YAML"    }
¿Fences de Pandoc o YAML anidado?

- Fences de Pandoc — prosa con marcas mínimas {recommended}
- YAML anidado — estructura explícita
:::

::: item {#Q2 title="Marcador de columna" decided=yes}
¿El marcador va en la fila separadora?

- Sí, `---:` es markdown estándar {recommended}
- No, un atributo nuevo
:::
:::

::: notes {title="Notas generales"}
:::
'''

# The verdict a verb records on an item WITH options: the chosen option's label.
# `yes` there would ship the author's {recommended} option as the verdict
# whatever the reader chose, so the verb refuses it (below).
V = "Fences de Pandoc"

LEDGERED = PAGE.replace(
    "::: group {#G1",
    "::: ledger\n- d1 — **Hecho.** La gramática vive en `03-spec-grammar.md`.\n"
    ":::\n\n::: group {#G1", 1)


print("== add-item: the spec, then the page ==")
after = add_item(PAGE, "G1", "Q3", "Ruta de figuras",
                 body="¿Qué renderizador dibuja las barras?",
                 options=["El de la librería — una rueda binaria",
                          "Uno propio de stdlib — SVG contra los tokens del kit "
                          "{recommended}"])
check("the new fence lands INSIDE the group, after the last item",
      after.index('#Q3') > after.index('#Q2')
      and after.index('#Q3') < after.index("::: notes"), after)
check("the item is written with the id, the title and its options",
      '::: item {#Q3 title="Ruta de figuras"}' in after
      and "¿Qué renderizador dibuja las barras?" in after
      and "- El de la librería — una rueda binaria" in after, after)
added, removed = diff_shape(PAGE, after)
check("add-item only ADDS lines — nothing the author wrote is moved or "
      "re-indented", removed == 0 and added == 7, "%d added, %d removed"
      % (added, removed))
check("the oddly spaced fence of #Q1 is copied through, space for space",
      '::: item {#Q1   title="Fences o YAML"    }' in after)

refuses("add-item refuses an id the spec already uses",
        lambda: add_item(PAGE, "G1", "Q2", "otra"), "#Q2 is already used")
refuses("...and names the group it cannot find",
        lambda: add_item(PAGE, "G9", "Q3", "x"), "#G9")
refuses("...and lists the groups the spec does have",
        lambda: add_item(PAGE, "G9", "Q3", "x"), "#G1")
refuses("...and refuses an id the grammar cannot spell",
        lambda: add_item(PAGE, "G1", "3-Q", "x"), "not a usable id")
quoted = add_item(PAGE, "G1", "Q3", 'con "comillas"')
check("a title carrying a double quote is WRITTEN, not refused — the attr "
      "grammar escapes one since the corpus conversion",
      '::: item {#Q3 title="con \\"comillas\\""}' in quoted, quoted)
check("...and it parses back to the title the caller gave, character for "
      "character",
      [n.attrs.get("title") for n in spec_verbs._walk(spec_verbs.spec_parser.parse(quoted))
       if n.id == "Q3"] == ['con "comillas"'], quoted)
refuses("add-item refuses a group id that is an ITEM's",
        lambda: add_item(PAGE, "Q1", "Q3", "x"), "no `group` with id #Q1")

print()
print("== decide: the attr, and only the attr ==")
one = decide(PAGE, "Q1", V)
check("the verdict lands as `decided=` on the item's own fence, and the "
      "author's spacing inside the braces is left where it was",
      '::: item {#Q1   title="Fences o YAML"    decided="Fences de Pandoc"}' in one, one)
added, removed = diff_shape(PAGE, one)
check("decide changes exactly one line", (added, removed) == (1, 1),
      "%d added, %d removed" % (added, removed))
check("no other fence gains a verdict",
      one.replace('decided="Fences de Pandoc"', "", 1).count("decided") == 1)
check("decide is idempotent for the same verdict — byte-identical spec",
      decide(one, "Q1", V) == one)
two = decide(one, "Q1", "YAML anidado")
check("a DIFFERENT verdict overwrites (the `owner-changed` case)",
      'decided="YAML anidado"' in two and 'decided="Fences de Pandoc"' not in two, two)
check("...and still changes exactly one line", diff_shape(one, two) == (1, 1))
check("an existing bare verdict is replaced in place, not appended",
      decide(PAGE, "Q2", "No, un atributo nuevo").count("decided") == 1
      and 'decided="No, un atributo nuevo"' in decide(PAGE, "Q2", "No, un atributo nuevo"))
refuses("decide refuses an id the spec does not carry",
        lambda: decide(PAGE, "Q9", V), "#Q9")
refuses("...and lists the items it does carry",
        lambda: decide(PAGE, "Q9", V), "#Q1")
refuses("decide refuses a block that is not an item",
        lambda: decide(PAGE, "G1", V), "is a `group` block")
refuses("...and an empty verdict", lambda: decide(PAGE, "Q1", "  "),
        "empty verdict")
# `decided=yes` makes the builder check the {recommended} option, which is the
# author's advice, not the reader's answer: recorded by a verb after a round,
# it would ship the recommendation as the verdict whatever the reader chose.
for flag in ("yes", "TRUE", "1", " yes "):
    refuses("decide refuses %r on an item with options" % flag,
            lambda flag=flag: decide(PAGE, "Q1", flag),
            "pass the chosen option's label")
check("...and records a label verdict on the same item",
      'decided="Fences de Pandoc"' in decide(PAGE, "Q1", "Fences de Pandoc"))
# An option LABELLED `Yes` (mutations_gate's English `Sí`): the builder reads
# decided=Yes as the settled flag and checks the {chosen} option, else the
# {recommended} one. When the {chosen} one is labelled Yes, the verdict is the
# reader's own choice and is recorded; otherwise the page could check another
# option, so the refusal must say what to do, not ask for the label it was
# given (u5-verbs B-c18).
YES_OPTS = "- Fences de Pandoc — prosa con marcas mínimas {recommended}\n" \
           "- YAML anidado — estructura explícita"
try:
    got = decide(PAGE.replace(YES_OPTS, "- Yes {chosen}\n- No"), "Q1", "Yes")
except VerbError as exc:
    got = str(exc)
check("decide records 'Yes' when it is the label of the {chosen} option",
      'decided="Yes"' in got, got)
refuses("decide refuses 'Yes' when the builder would check another option",
        lambda: decide(PAGE.replace(YES_OPTS, "- Yes\n- No {recommended}"),
                       "Q1", "Yes"),
        "mark the 'Yes' option {chosen} first")
refuses("...and reads the verdict in its plain form, as the builder does",
        lambda: decide(PAGE.replace(YES_OPTS, "- Yes\n- No {recommended}"),
                       "Q1", "**Yes**"),
        "mark the 'Yes' option {chosen} first")

PREFIXED = ('::: masthead {title="T" visual="none: x"}\nUna.\n:::\n\n'
            '::: group {#G1 title="G"}\n'
            '::: item {#Q1 title="Q1 · ¿Seguimos?" decided=yes}\n?\n\n- A {recommended}\n- B\n:::\n'
            ':::\n')
check("new-round writes the ledger row from the title the page shows (id prefix stripped)",
      "- Q1 — ¿Seguimos?\n" in new_round(PREFIXED), new_round(PREFIXED))
_rowed = ('::: masthead {title="T" visual="none: x"}\nUna.\n:::\n\n'
          '::: ledger\n- Q1 — ¿Seguimos?\n:::\n\n'
          '::: group {#G1 title="G"}\n'
          '::: item {#Q1 title="Q1 · ¿Seguimos?"}\n?\n\n- A\n- B\n:::\n:::\n')
check("decide rewrites an existing row built from the stripped title",
      "- Q1 — ¿Seguimos? (B)\n" in decide(_rowed, "Q1", "B"), decide(_rowed, "Q1", "B"))

print()
print("== new-round: the ledger, keyed by id ==")
rnd = new_round(PAGE)
check("a spec with no ledger gets one, right after the masthead",
      "::: ledger\n- Q2 — Marcador de columna\n:::" in rnd
      and rnd.index("::: ledger") < rnd.index("::: group"), rnd)
added, removed = diff_shape(PAGE, rnd)
check("new-round only ADDS lines", removed == 0 and added == 4,
      "%d added, %d removed" % (added, removed))
check("new-round is idempotent — a key already in the ledger is not written "
      "twice", new_round(rnd) == rnd)
check("a spec with nothing decided comes back byte-identical",
      new_round(decide(PAGE, "Q2", "Sí, `---:` es markdown estándar").replace(' decided="Sí, ---: es markdown estándar"', ""))
      == PAGE.replace(" decided=yes", ""))
# BL-692: a proposal lasts one round, and expires only if the reader SAW it: it carried
# data-proposal on the saved answered snapshot. One written this turn (absent from it)
# keeps proposal=yes whichever order the verbs run in; no snapshot expires nothing.
two = PAGE.replace(" decided=yes", " decided=yes proposal=yes").replace(
    'title="Fences o YAML"    }', 'title="Fences o YAML" decided=Fences proposal=yes}', 1)
SNAP = ('<section class="consult-item" data-id="Q2" data-title="x" data-decided data-proposal>'
        '</section><section class="consult-item" data-id="Q1" data-title="y"></section>')
check("fixture: both Q1 and Q2 carry proposal=yes", two.count("proposal=yes") == 2, two)
opened = new_round(two, answered_html=SNAP)
check("a proposal on the answered snapshot (Q2, P_old) expires: it is settled in round 2",
      "proposal=yes" in opened and opened.count("proposal=yes") == 1
      and "- Q2 — Marcador de columna" in opened, opened)
check("...and one absent from it (Q1, P_new, written this turn) keeps proposal=yes and gets no ledger row",
      'title="Fences o YAML" decided=Fences proposal=yes}' in opened
      and "- Q1" not in opened, opened)
check("with no snapshot nothing expires (a mid-round --drop/--retitle)",
      new_round(two) == new_round(two, answered_html=None)
      and new_round(two).count("proposal=yes") == 2, new_round(two))
check("...whether or not a retitle rides along",
      new_round(two, retitled=["Q1"]).count("proposal=yes") == 2)
# BL-711: a proposal now carries the ask chips and [not-now], so the reader can answer it
# with something other than "fine". A reply block for it that holds an ask or [not-now]
# means it was NOT accepted: it stays a proposal (open), with no ledger row.
for mark in ("[not-now]", "[show-me]"):
    reply = "### Q2 \u00b7 Marcador de columna\n\n- %s\n" % mark
    kept = new_round(two, answered_html=SNAP, reply=reply)
    check("a proposal the reply marks %s does not expire: it stays proposal=yes with no ledger row" % mark,
          kept.count("proposal=yes") == 2 and "- Q2" not in kept, kept)
H2 = "### Q2 \u00b7 Marcador de columna\n\n"
PICK = H2 + "- No, un atributo nuevo\n"
OTHER = H2 + "- Otra \u2014 lo explico en las notas\n\nusa una tercera\n"
NOTE = H2 + "vale, pero cambia el texto\n"
# A proposal the reader answered with a real pick, Other or a note is NOT accepted: it takes the
# open-item path (the 225f968e guard names the pick, new-round keeps it a proposal).
for what, rep_ in (("a changed pick", PICK), ("Other + note", OTHER), ("a note", NOTE)):
    kept = new_round(two, answered_html=SNAP, reply=rep_)
    check("a proposal the reader answered with %s stays proposal=yes with no ledger row" % what,
          kept.count("proposal=yes") == 2 and "- Q2" not in kept, kept)
check("_bare_picks names a proposal's changed pick like an open item's (the guard that refuses new-round)",
      spec_verbs._bare_picks(two, PICK, {"Q2"}) == [("Q2", "No, un atributo nuevo")]
      and spec_verbs._bare_picks(two, PICK) == [], spec_verbs._bare_picks(two, PICK, {"Q2"}))
settled_pick = new_round(decide(two, "Q2", "No, un atributo nuevo", PICK), answered_html=SNAP, reply=PICK)
check("...and once the writer decides it, the item is no longer a proposal and new-round files it",
      "- Q2 \u2014 Marcador de columna (No, un atributo nuevo)" in settled_pick
      and settled_pick.count("proposal=yes") == 1, settled_pick)
# One reader for "asked about": the duty check reads the union of every saved paste, so a show-me in an
# earlier paste keeps the proposal open even when the last paste holds only a note (and they agree).
TWO_SAVES = ("## G1 \u00b7 Formato del spec\n\n" + H2 + "- [show-me]\n\n<!-- reply saved 2026-10-07 page:abc same-round -->\n\n"
             "## G1 \u00b7 Formato del spec\n\n" + H2 + "vale\n")
check("a show-me in an earlier saved paste keeps the proposal open and the duty is owed (both agree)",
      new_round(two, answered_html=SNAP, reply=TWO_SAVES).count("proposal=yes") == 2
      and any(i == "Q2" for i, _ in check_artifact.marker_duties_of(TWO_SAVES)))
check("a page-defect sub-block alone (the composer's shape) is no reason to keep a proposal open",
      new_round(two, answered_html=SNAP,
                reply="## G1 \u00b7 Formato del spec\n\n" + H2 + "#### Fallo de la p\u00e1gina\n\nel texto se corta\n").count("proposal=yes") == 1)
# A reply the parsers cannot classify is still the reader answering: any content but defect text keeps it open.
for what, rep_ in (("a chat-form note", "Q2: vale pero cambia el texto\n"),
                   ("a line that matches no option (reworded since)", H2 + "- No, un atributo distinto\n")):
    kept = new_round(two, answered_html=SNAP, reply=rep_)
    check("a proposal answered with %s stays proposal=yes with no ledger row" % what,
          kept.count("proposal=yes") == 2 and "- Q2" not in kept, kept)
# Same round, the reader went back to the proposal: the later FULL paste has no Q2 block and supersedes
# the earlier one, as check_artifact reads it (BL-598). Neither the guard nor the expiry may read paste 1.
REVERT = ("## G1 \u00b7 Formato del spec\n\n" + H2 + "- No, un atributo nuevo\n"
          "\n<!-- reply saved 2026-10-07 page:abc same-round -->\n\n"
          "## G2 \u00b7 Otro\n\n### Q1 \u00b7 Fences o YAML\n\n- Fences de Pandoc\n")
check("a same-round full paste without the proposal supersedes the earlier pick: no guard, and it expires",
      spec_verbs._bare_picks(two, REVERT, {"Q2"}) == []
      and new_round(two, answered_html=SNAP, reply=REVERT).count("proposal=yes") == 1)
# decide after new-round must move the ledger row's verdict as well.
settled = new_round(decide(PAGE, "Q1", "Fences de Pandoc"))
redecided = decide(settled, "Q1", "YAML anidado")
check("decide updates the item's ledger row, not only its decided= attr",
      "- Q1 — Fences o YAML (YAML anidado)" in redecided
      and "(Fences de Pandoc)" not in redecided, redecided)
# ...but a hand-written row is left byte-identical, and the caller is told.
import contextlib
import io
hand = new_round(decide(PAGE, "Q1", "Fences de Pandoc")).replace(
    "- Q1 — Fences o YAML (Fences de Pandoc)", "- Q1 — **Fences**, cerrado por el dueño")
err = io.StringIO()
with contextlib.redirect_stderr(err):
    hand2 = decide(hand, "Q1", "YAML anidado")
check("decide leaves a hand-written ledger row byte-identical",
      "- Q1 — **Fences**, cerrado por el dueño" in hand2 and "(YAML anidado)" not in hand2.split("::: group")[0],
      hand2)
check("...and prints that the row is hand-written",
      "ledger row for Q1 is hand-written; update it yourself" in err.getvalue(), err.getvalue())
with tempfile.TemporaryDirectory() as _d:
    _spec = os.path.join(_d, "pg.spec.md")
    check("no .aidex-artifact-prev snapshot: the file wrapper reads None",
          spec_verbs._answered_snapshot(_spec, None) is None)
    os.makedirs(os.path.join(_d, ".aidex-artifact-prev"))
    with open(os.path.join(_d, ".aidex-artifact-prev", "pg.answered.html"), "w") as _fh:
        _fh.write(SNAP)
    check("the snapshot save-reply.sh wrote beside the page is what the file wrapper reads",
          spec_verbs._answered_snapshot(_spec, None) == SNAP)
existing = new_round(LEDGERED)
check("an existing ledger is APPENDED to, its own rows untouched",
      "- d1 — **Hecho.** La gramática vive en `03-spec-grammar.md`." in existing
      and "- Q2 — Marcador de columna" in existing
      and diff_shape(LEDGERED, existing) == (1, 0), existing)
verdicted = new_round(decide(PAGE, "Q1", "Fences de Pandoc"))
check("an option-label verdict travels into the row beside the title",
      "- Q1 — Fences o YAML (Fences de Pandoc)" in verdicted, verdicted)
check("...and `yes` does not, because it says nothing a row should repeat",
      "- Q2 — Marcador de columna\n" in verdicted)
check("an author's rewritten row is left alone — the KEY is what is compared",
      new_round(rnd.replace("- Q2 — Marcador de columna",
                            "- Q2 — Reescrito a mano"))
      == rnd.replace("- Q2 — Marcador de columna", "- Q2 — Reescrito a mano"))

print()
print("== the ledger keyspace is the item keyspace ==")
# A key is a COMPOUND in the field — `c35 · T-265`, `c1 + c12` — and
# `check_artifact.ledger_ids` harvests the TOKENS inside it. Whole-string
# equality on either side of that is a silent bug: the contract reads an id the
# verb cannot see. The fixture ledger below is the field shape; the one the
# suite already had (`- d1 — …`) is a bare single-token key, which is exactly
# the case where whole-string equality happens to be right.
COMPOUND = PAGE.replace(
    "::: group {#G1",
    "::: ledger\n- Q2 · T-265 — **Hecho.** La fecha va en la columna "
    "izquierda.\n:::\n\n::: group {#G1", 1)
check("new-round adds NO second row for an id a COMPOUND key already names",
      new_round(COMPOUND) == COMPOUND, new_round(COMPOUND))

SETTLED = PAGE.replace(
    "::: group {#G1",
    "::: ledger\n- Q7 · T-300 — **Hecho.** El filtro de estado es propio.\n"
    ":::\n\n::: group {#G1", 1)
refuses("add-item refuses an id the LEDGER owns, with no block of that id",
        lambda: add_item(SETTLED, "G1", "Q7", "Filtro de estado"),
        "already used by a ledger row")
refuses("...and reads the compound key by TOKEN, not whole-string",
        lambda: add_item(SETTLED, "G1", "T-300", "Filtro de estado"),
        "already used by a ledger row")
check("...while an id no ledger token names is still accepted",
      '::: item {#Q8 title="Otra"}' in add_item(SETTLED, "G1", "Q8", "Otra"))

# A row with no ` — ` has no KEY: `emit_ledger` ships it as a `.v` cell alone
# and `check_artifact.ledger_ids` reads no id out of it. Its words are prose,
# so they name no settled item (u5-verbs B-c17).
FREE_ROW = PAGE.replace(
    "::: notes",
    "::: ledger\n- Se cerró Q2 en la reunión general\n:::\n\n::: notes", 1)
check("new-round still files a decided item a KEY-LESS row mentions in prose",
      "- Q2 — Marcador de columna\n" in new_round(FREE_ROW), new_round(FREE_ROW))
try:
    free_add = add_item(FREE_ROW, "G1", "general", "Otra")
except VerbError as exc:
    free_add = str(exc)
check("...and add-item accepts an id that is only a word of a key-less row",
      '::: item {#general title="Otra"}' in free_add, free_add)
BARE_ROW = PAGE.replace("::: notes", "::: ledger\n- Q2\n:::\n\n::: notes", 1)
bare_rows = [ln for ln in decide(new_round(BARE_ROW), "Q2",
                                 "No, un atributo nuevo").split("\n")
             if ln.startswith("- Q2 — ")]
check("...and decide moves the row new-round wrote, not a key-less `- Q2` row",
      len(bare_rows) == 1 and bare_rows[0].endswith("(No, un atributo nuevo)"),
      str(bare_rows))

NESTED_LEDGER = PAGE.replace(
    "::: item {#Q1",
    "::: ledger\n- Q2 — Marcador de columna\n:::\n\n::: item {#Q1", 1)
refuses("new-round refuses a ledger nested inside a block — settled rows do "
        "not go in the middle of the question set",
        lambda: new_round(NESTED_LEDGER), "nested inside")
refuses("...and refuses a spec carrying two ledgers rather than guessing",
        lambda: new_round(NESTED_LEDGER.replace(
            "::: group {#G1", "::: ledger\n- z1 — Otra cosa\n:::\n\n"
            "::: group {#G1", 1)), "2 `ledger` blocks")

print()
print("== --body is spec text, so it is read as spec text ==")
refuses("add-item refuses a body that closes the item's own fence",
        lambda: add_item(PAGE, "G1", "Q3", "Ruta",
                         body="una línea\n:::\n\n::: item {#Q1 title=\"otra\"}"),
        "closes the item's own fence")
refuses("...including one that only opens a block it never closes",
        lambda: add_item(PAGE, "G1", "Q3", "Ruta",
                         body="::: figure {src=\"x.svg\"}"),
        "is not usable spec text")
refuses("...and a nested block whose id the spec already carries",
        lambda: add_item(PAGE, "G1", "Q3", "Ruta",
                         body="::: figure {#Q2 src=\"x.svg\"}\n:::"),
        "already uses")
check("a body that only indents its fence is prose and is accepted",
      "    ::: no es una marca" in add_item(PAGE, "G1", "Q3", "Ruta",
                                            body="    ::: no es una marca"))
check("...and the accepted item is still exactly one fence",
      add_item(PAGE, "G1", "Q3", "Ruta", body="prosa").count("::: item") == 3)

print()
print("== the general-notes item stays last ==")
# The same page with the general-notes item INSIDE the group. The contract
# ("always last", 02-local-first-artifacts.md §7.3) is not checked by
# check_artifact.py, so an item appended after it would ship silently.
NOTES_TAIL = ':::\n:::\n\n::: notes {title="Notas generales"}\n:::\n'
INNER_NOTES = PAGE.replace(
    NOTES_TAIL, ':::\n\n::: notes {title="Notas generales"}\n:::\n:::\n', 1)
check("the fixture really moved the notes item inside the group",
      INNER_NOTES != PAGE and INNER_NOTES.rstrip().endswith(":::\n:::"),
      INNER_NOTES[-200:])
moved = add_item(INNER_NOTES, "G1", "Q3", "Ruta de figuras")
check("an item added to a group whose last child is the notes item lands "
      "BEFORE it", moved.index("#Q3") < moved.index("::: notes"), moved)
check("...and the notes item is still the last block of the spec",
      moved.rstrip().endswith(":::") and moved.count("::: notes") == 1)

print()
print("== CRLF: the line ending is the author's too ==")
CRLF = PAGE.replace("\n", "\r\n")


def lf_only(text):
    """Lines terminated by a bare LF in a text whose other lines are CRLF."""
    rows = text.split("\n")[:-1]                 # the last is after the final \n
    return [r for r in rows if not r.endswith("\r")]


check("add-item injects no LF-only line into a CRLF spec",
      not lf_only(add_item(CRLF, "G1", "Q3", "Ruta",
                           body="¿Qué renderizador?", options=["Uno propio"])),
      str(lf_only(add_item(CRLF, "G1", "Q3", "Ruta"))))
check("new-round injects none either, ledger or no ledger",
      not lf_only(new_round(CRLF))
      and not lf_only(new_round(LEDGERED.replace("\n", "\r\n"))),
      str(lf_only(new_round(CRLF))))
check("...and decide still changes exactly one line on a CRLF spec",
      diff_shape(CRLF, decide(CRLF, "Q1", V)) == (1, 1))

print()
print("== decide, with `decided` anywhere in the attr group ==")
POSITIONS = ('::: item {#Qa decided="no" title="Primera"}\ncuerpo\n:::\n\n'
             '::: item {#Qb decided="no"}\ncuerpo\n:::\n\n'
             '::: item {#Qc decided="" title="Vacía"}\ncuerpo\n:::\n')
first = decide(POSITIONS, "Qa", "sí, cerrado")
check("`decided` FIRST in the group is rewritten in place, the title untouched",
      '::: item {#Qa decided="sí, cerrado" title="Primera"}' in first, first)
only = decide(POSITIONS, "Qb", "sí")
check("`decided` as the ONLY attr beside the id is rewritten, not appended",
      '::: item {#Qb decided="sí"}' in only
      and only.count("decided") == 3, only)
empty = decide(POSITIONS, "Qc", "sí")
check("an EMPTY `decided=\"\"` is filled in place",
      '::: item {#Qc decided="sí" title="Vacía"}' in empty, empty)
check("...and each of the three changes exactly one line",
      diff_shape(POSITIONS, first) == (1, 1)
      and diff_shape(POSITIONS, only) == (1, 1)
      and diff_shape(POSITIONS, empty) == (1, 1))

print()
print("== the trailing newline is the author's too ==")
check("a spec with no final newline keeps none",
      not decide(PAGE.rstrip("\n"), "Q1", V).endswith("\n"))
check("a spec with one keeps exactly one",
      decide(PAGE, "Q1", V).endswith(":::\n")
      and not decide(PAGE, "Q1", V).endswith(":::\n\n"))

print()
print("== the file half: refuse without writing, or write and rebuild ==")
tmp = tempfile.mkdtemp(prefix="spec-verbs-test-")
try:
    def first_build(path, page=None, reply=b"Q1: Fences de Pandoc\n\na note, so new-round may carry it\n"):
        """The first build of `path`, plus the reader's saved reply (a decision
        needs it, BL-569). Fails loudly when either step fails: a spec that does
        not build is made with `fresh(..., build=False)`."""
        page = page or os.path.join(os.path.dirname(path), "page.html")
        done = subprocess.run([sys.executable, BUILD, path, "-o", page],
                              capture_output=True, text=True)
        if done.returncode != 0:
            fail("first_build: %s did not build: %s" % (path, done.stderr))
            return page
        saved = subprocess.run(["bash", os.path.join(SCRIPTS, "save-reply.sh"),
                                page, "-"], input=reply, capture_output=True)
        if saved.returncode != 0:
            fail("first_build: save-reply failed: %r" % saved.stderr)
        return page

    def fresh(name, text=PAGE, build=True):
        """A spec in its own dir. `decide` and `new-round` need a built page
        (M3 52), so by default the first build is done here, the way a real
        project has one; a spec that does not build simply has no page."""
        d = os.path.join(tmp, name)
        os.makedirs(d)
        path = os.path.join(d, "page.spec.md")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        if build:
            first_build(path)
        return path

    def run(*argv):
        return subprocess.run([sys.executable, VERBS] + list(argv),
                              capture_output=True, text=True)

    def read(path, mode="r"):
        with open(path, mode, **({} if "b" in mode else
                                 {"encoding": "utf-8"})) as fh:
            return fh.read()

    # --- the CLI, one case per verb, spec AND page ---------------------------
    spec = fresh("cli-add")
    page = os.path.join(os.path.dirname(spec), "page.html")
    r = run("add-item", spec, "--group", "G1", "--id", "Q3",
            "--title", "Ruta de figuras", "--body", "¿Qué renderizador?",
            "--option", "Uno propio de stdlib {recommended}",
            "--option", "El de la librería")
    check("add-item exits 0 and prints the page it rebuilt",
          r.returncode == 0 and r.stdout.strip().endswith("page.html"),
          r.stdout + r.stderr)
    check("...the SPEC carries the new item",
          '::: item {#Q3 title="Ruta de figuras"}' in read(spec))
    built = read(page)
    check("...and the PAGE carries it, with the id the spec wrote",
          'data-id="Q3"' in built
          and '<span class="consult-id">Q3</span>' in built
          and 'name="Q3"' in built
          and 'data-label="Uno propio de stdlib"' in built, built[:400])
    check("...and the option marked {recommended} is the recommended one",
          "data-recommended" in built)

    spec = fresh("cli-decide")
    page = os.path.join(os.path.dirname(spec), "page.html")
    r = run("decide", spec, "--id", "Q1", "--verdict", V)
    check("decide exits 0", r.returncode == 0, r.stdout + r.stderr)
    check("...the SPEC records the verdict", 'decided="Fences de Pandoc"' in read(spec))
    built = read(page)
    check("...and the PAGE marks the item decided, bare as the kit reads it",
          re.search(r'<section class="consult-item" data-id="Q1"[^>]*'
                    r'\sdata-decided\b', built) is not None, built[:2000])
    r = run("decide", spec, "--id", "Q1", "--verdict", "YAML anidado")
    check("a label verdict reaches the page as the value of data-decided",
          r.returncode == 0
          and 'data-decided="YAML anidado"' in read(page),
          r.stdout + r.stderr)

    spec = fresh("cli-round")
    page = os.path.join(os.path.dirname(spec), "page.html")
    r = run("new-round", spec)
    check("new-round exits 0", r.returncode == 0, r.stdout + r.stderr)
    check("...the SPEC grew a ledger", "::: ledger" in read(spec))
    built = read(page)
    check("...and the PAGE carries the ledger row as a `.k`/`.v` pair",
          '<span class="k">Q2</span><span class="v">Marcador de columna</span>'
          in built, built[:2000])

    # --- the round trip the phase names -------------------------------------
    print()
    print("== the rebuilt page passes check-artifact.sh, unmodified ==")
    spec = fresh("roundtrip")
    page = os.path.join(os.path.dirname(spec), "page.html")
    for argv, label in (
            (("add-item", spec, "--group", "G1", "--id", "Q3",
              "--title", "Ruta de figuras", "--body", "¿Qué renderizador?",
              "--option", "Uno propio de stdlib {recommended}",
              "--option", "El de la librería"), "add-item"),
            (("decide", spec, "--id", "Q1", "--verdict", V), "decide"),
            (("new-round", spec), "new-round")):
        if label == "decide":      # BL-569: a decision needs the reply that made it
            sr = subprocess.run(["bash", os.path.join(SCRIPTS, "save-reply.sh"),
                                 page, "-"], input="Q1: Fences\n", text=True,
                                capture_output=True)
            check("(setup) the reply for the decision is saved",
                  sr.returncode == 0, sr.stdout + sr.stderr)
        r = run(*argv)
        check("%s rebuilds the page" % label, r.returncode == 0,
              r.stdout + r.stderr)
        c = subprocess.run(["bash", CHECK, page], capture_output=True,
                           text=True)
        check("...and check-artifact.sh passes it with no exemption (%s)"
              % label, c.returncode == 0, c.stdout + c.stderr)
        # The fixture's round-1 Q2 is "decided" without proposal=yes, so the BL-692 round-1
        # advisory is expected on the add-item step only (pinned in test-consult-spec-trace.sh).
        # decide and new-round run in round 2: their own output (the verb's trial build
        # included) must carry no WARN at all.
        mine = r.stdout + r.stderr + c.stdout + c.stderr
        other = [ln for ln in mine.splitlines() if "WARN" in ln
                 and (label != "add-item" or "consult-round1-decided" not in ln)]
        check("...and prints no WARN%s (%s)" % (" other than the round-1 advisory"
              if label == "add-item" else "", label), not other, "\n".join(other))

    # --- atomicity ----------------------------------------------------------
    print()
    print("== a refused verb writes nothing ==")
    spec = fresh("atomic")
    page = os.path.join(os.path.dirname(spec), "page.html")
    r = subprocess.run([sys.executable, BUILD, spec, "-o", page],
                       capture_output=True, text=True)
    check("the page builds once before the refusals", r.returncode == 0,
          r.stdout + r.stderr)
    spec_bytes, page_bytes = read(spec, "rb"), read(page, "rb")
    for argv, label, needle in (
            (("decide", spec, "--id", "Q9", "--verdict", V),
             "decide on a missing id", "#Q9"),
            (("add-item", spec, "--group", "G9", "--id", "Q3",
              "--title", "x"), "add-item into a missing group", "#G9"),
            (("add-item", spec, "--group", "G1", "--id", "Q2",
              "--title", "x"), "add-item with an id already used", "#Q2"),
            (("decide", spec, "--id", "G1", "--verdict", V),
             "decide on a block that is not an item", "#G1"),
            # The one refusal that comes from the BUILD and not from the id
            # lookup: the spec parses, and `emit_item` then refuses an option
            # with no label. It is the case the in-memory build gate exists for.
            (("add-item", spec, "--group", "G1", "--id", "Q4",
              "--title", "x", "--option", "   "),
             "add-item whose result would not build", "unbuildable")):
        r = run(*argv)
        check("%s exits non-zero" % label, r.returncode != 0,
              r.stdout + r.stderr)
        check("...and says so, naming the target (%s)" % label,
              needle in r.stderr, r.stderr)
        check("...and the SPEC is byte-identical (%s)" % label,
              read(spec, "rb") == spec_bytes)
        check("...and the PAGE is byte-identical (%s)" % label,
              read(page, "rb") == page_bytes)

    # --- the gate is the REBUILD's, not a weaker one -------------------------
    print()
    print("== an edit that builds but fails the CONTRACT is refused ==")
    # The gap this covers: `build()` + a title is a WEAKER gate than the rebuild,
    # which also runs check_artifact.py. An edit that passes the weak gate and
    # fails the strong one used to be WRITTEN, the rebuild then failed, and every
    # later verb call wrote and failed the same way — the spec wedged with no
    # verb able to recover it. Fixture: a ledger that records Q2 as settled while
    # Q2 is still open (`decided but still asked`), so ANY edit's result parses,
    # builds, and fails the contract.
    WEDGE = PAGE.replace(' decided=yes', '').replace(
        "::: group {#G1",
        "::: ledger\n- Q2 — Marcador de columna\n:::\n\n::: group {#G1", 1)
    # A never-built wedged spec: decide refuses for the missing page, not the wedge.
    nb = fresh("contract-gate-never-built", WEDGE, build=False)
    nb_bytes = read(nb, "rb")
    r = run("decide", nb, "--id", "Q2", "--verdict", "No, un atributo nuevo")
    check("decide on a never-built wedged spec refuses: not been built",
          r.returncode == 1 and "not been built" in r.stderr
          and read(nb, "rb") == nb_bytes, r.stdout + r.stderr)
    # A page that was built from a valid spec, then the spec wedged by hand.
    spec = fresh("contract-gate", PAGE.replace(" decided=yes", ""))
    first_build(spec, reply=b"Q1: Fences de Pandoc\nQ2: No, un atributo nuevo\n")
    with open(spec, "w", encoding="utf-8") as fh:
        fh.write(WEDGE)
    page = os.path.join(os.path.dirname(spec), "page.html")
    spec_bytes, page_bytes = read(spec, "rb"), read(page, "rb")
    r = run("add-item", spec, "--group", "G1", "--id", "Q3", "--title", "Ruta")
    check("an edit whose result fails the contract exits non-zero",
          r.returncode == 1, r.stdout + r.stderr)
    check("...and says the edit was refused, not that the spec was written",
          "unbuildable" in r.stderr
          and "the spec was written" not in r.stderr, r.stderr)
    check("...and the SPEC is byte-identical afterwards",
          read(spec, "rb") == spec_bytes, read(spec))
    check("...and the PAGE is byte-identical afterwards",
          read(page, "rb") == page_bytes)
    check("...and no trial file was left beside the spec",
          not [f for f in os.listdir(os.path.dirname(spec))
               if "trial" in f or f.endswith(".tmp")],
          str(os.listdir(os.path.dirname(spec))))
    # ...and the spec is not wedged: the edit that REPAIRS the contract passes
    # the same gate and is written. A gate that refused this too would have
    # traded a wedge for a dead end.
    r = run("decide", spec, "--id", "Q2", "--verdict", "No, un atributo nuevo")
    check("the repairing edit is accepted — the spec is refused, not frozen",
          r.returncode == 0 and 'decided="No, un atributo nuevo"' in read(spec),
          r.stdout + r.stderr)

    print()
    print("== a spec that is already unbuildable is named as it stands ==")
    # BL-522.4 (asset_lab BL-011, round 2): `new-round` on a spec the author
    # had hand-edited into an unbuildable state said "the edit would leave ...
    # unbuildable (line N ...)", N counted on the CANDIDATE, which carries the
    # ledger rows the verb inserted above. The author opened line N of the file
    # and found nothing there; the edit was never the cause. Both rules are the
    # grammar's (03-spec-grammar.md: a `section` is top-level only; a png needs
    # `alt`), so the verb still refuses, naming the file's own line and the fix.
    UNIT = PAGE.replace(
        "- YAML anidado — estructura explícita\n",
        "- YAML anidado — estructura explícita\n\n%s\n", 1)
    for name, fence, needle in (
            ("section-in-item",
             '::: section {#sec-x heading="Ejemplos"}\nTexto.\n:::',
             "`section` may only appear in the document"),
            ("png-no-alt", '::: figure {src="shot.png" title="Pantalla"}\n:::',
             'needs alt="')):
        spec = fresh("as-it-stands-" + name, UNIT % fence, build=False)
        subprocess.run([sys.executable, os.path.join(HERE, "png_fixture.py"),
                        os.path.join(os.path.dirname(spec), "shot.png"),
                        "40", "30"], check=True)
        at = read(spec).split("\n").index(fence.split("\n")[0]) + 1
        spec_bytes = read(spec, "rb")
        r = run("new-round", spec)
        check("new-round on a spec that does not build exits 1 (%s)" % name,
              r.returncode == 1, r.stdout + r.stderr)
        check("...says the spec is unbuildable as it stands, not that the "
              "edit made it so (%s)" % name,
              "as it stands" in r.stderr
              and "the edit would leave" not in r.stderr, r.stderr)
        check("...names line %d of the file on disk and the rule (%s)"
              % (at, name),
              "line %d:" % at in r.stderr and needle in r.stderr, r.stderr)
        check("...and the SPEC is byte-identical (%s)" % name,
              read(spec, "rb") == spec_bytes)

    print()
    print("== the write path refuses like the read path ==")
    ro = fresh("readonly")
    subprocess.run([sys.executable, BUILD, ro, "-o",
                    os.path.join(os.path.dirname(ro), "page.html")],
                   capture_output=True, text=True)
    ro_bytes = read(ro, "rb")
    os.chmod(os.path.dirname(ro), 0o555)
    try:
        r = run("decide", ro, "--id", "Q1", "--verdict", V)
        check("a spec in a read-only directory is a refusal, not a traceback",
              r.returncode == 1 and "Traceback" not in r.stderr, r.stderr)
        check("...and the refusal names the file it could not write",
              "cannot write" in r.stderr, r.stderr)
        check("...and the spec is byte-identical", read(ro, "rb") == ro_bytes)
    finally:
        os.chmod(os.path.dirname(ro), 0o755)

    print()
    print("== a symlinked spec is edited through the link, never replaced ==")
    real = fresh("symlink-real")
    link_dir = os.path.join(tmp, "symlink-link")
    os.makedirs(link_dir)
    link = os.path.join(link_dir, "page.spec.md")
    os.symlink(real, link)
    first_build(link)
    r = run("decide", link, "--id", "Q1", "--verdict", V)
    check("the verb edits a symlinked spec", r.returncode == 0,
          r.stdout + r.stderr)
    check("...the path is still a symlink — `os.replace` did not fork the file",
          os.path.islink(link), str(os.listdir(link_dir)))
    check("...and what changed is the file the link names",
          'decided="Fences de Pandoc"' in read(real))

    # --- no verb writes HTML -------------------------------------------------
    print()
    print("== the page comes out of build(), never out of a verb ==")
    # Both runs start from a page that does not exist, so both are round 1 and
    # the only difference left is the clock in the build stamp.
    a_spec = fresh("nohtml-verb")
    r = run("decide", a_spec, "--id", "Q1", "--verdict", V)
    check("the verb rebuilt its page", r.returncode == 0, r.stdout + r.stderr)
    b_spec = fresh("nohtml-plain")
    shutil.copyfile(a_spec, b_spec)
    b_page = os.path.join(os.path.dirname(b_spec), "page.html")
    r = subprocess.run([sys.executable, BUILD, b_spec, "-o", b_page],
                       capture_output=True, text=True)
    check("spec_build.py built the same spec on its own", r.returncode == 0,
          r.stdout + r.stderr)

    STAMP = re.compile(r'(<meta name="artifact-built" content=")[^"]*'
                       r'|(<p class="railbuilt"[^>]*>).*?(</p>)', re.S)

    def normalised(path):
        text = read(path).replace(os.path.dirname(path), "<dir>")
        return STAMP.sub("<stamp>", text)

    a_page = os.path.join(os.path.dirname(a_spec), "page.html")
    check("the verb's page is byte-identical to the plain build's, once the "
          "clock is normalised", normalised(a_page) == normalised(b_page),
          "\n".join(list(difflib.unified_diff(
              normalised(a_page).splitlines(),
              normalised(b_page).splitlines(), "verb", "build", lineterm=""))
              [:40]))

    source = read(VERBS)
    # Read as a SYNTAX TREE, not grepped. The module's own docstring quotes
    # `<meta name="consult-round">` and names `spec_build.py`, so a regex over
    # the text answers for the prose and not for the code — the first version of
    # both assertions failed on exactly that, which is the shape they exist to
    # catch elsewhere.
    tree = ast.parse(source)
    docstrings = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef,
                             ast.ClassDef)):
            doc = ast.get_docstring(node, clean=False)
            if doc is not None:
                docstrings.add(doc)
    literals = [n.value for n in ast.walk(tree)
                if isinstance(n, ast.Constant) and isinstance(n.value, str)
                and n.value not in docstrings]
    markup = [s for s in literals
              if re.search(r"<(?:div|section|p|span|input|header|aside|meta)\b",
                           s)]
    check("spec_verbs.py holds no markup of its own — no tag, no kit class",
          not markup, str(markup))
    touched = sorted({n.attr for n in ast.walk(tree)
                      if isinstance(n, ast.Attribute)
                      and isinstance(n.value, ast.Name)
                      and n.value.id == "spec_build"})
    check("...and calls no emitter: the only spec_build names it touches are "
          "the ones a caller may",
          touched == ["HINT_SEP", "LANGS", "PLAIN", "build", "chosen_labels",
                     "clean_item_title", "hand_edit_defect", "has_options",
                     "main", "option_labels", "page_title",
                     "refuse_missing_visual", "resolve_lang"],
          str(touched))
    writes = re.findall(r'open\(([^,]+), "w"', source)
    check("...and the only file it opens for writing is the spec's own temp",
          writes == ["tmp"], str(writes))

    print()
    print("== a verb on a spec with a gallery ==")
    # A gallery copies its captures beside the page it goes into and refuses a
    # body with no page (img-src-portable). The verb's pre-check built with no
    # page, so every verb on a gallery spec died before writing anything.
    gspec = fresh("gallery", build=False, text=PAGE.replace(
        '::: notes {title="Notas generales"}',
        '::: gallery {#E title="Galería" rows="rows.json" root="caps"}\n:::\n\n'
        '::: notes {title="Notas generales"}', 1))
    gdir = os.path.dirname(gspec)
    rel = "shots/ld/audit-with-data.png"
    os.makedirs(os.path.join(gdir, "caps", "shots", "ld"))
    subprocess.run([sys.executable, os.path.join(HERE, "png_fixture.py"),
                    os.path.join(gdir, "caps", rel), "16", "9"], check=True)
    with open(os.path.join(gdir, "rows.json"), "w", encoding="utf-8") as fh:
        fh.write('{"gallery": "audit", "variants": ["light-desktop"], "rows": '
                 '[{"cell": "with-data", "variant": "light-desktop", '
                 '"kind": "review", "look": "the table", "after": "%s"}]}' % rel)
    try:
        first_build(gspec)
        gout = spec_verbs.decide_file(gspec, "Q1", V)
        check("decide on a gallery spec returns the page it rebuilt",
              gout == os.path.join(gdir, "page.html"), gout)
        check("...whose tiles link the copies beside it",
              'src="page-assets/gallery/' in read(gout))
    except (VerbError, spec_verbs.BuildFailed) as exc:
        fail("decide on a gallery spec was refused: %s" % exc)

    print()
    print("== a verb on a spec the builder refuses for its visual ==")
    # The verb's pre-check must see the CLI's own visual refusal, and name the
    # spec as unbuildable as it stands rather than blame the edit.
    novis = fresh("novisual", build=False, text=PAGE.replace(
        ' visual="none: la decisión es de formato y no tiene forma que dibujar"', "", 1))
    try:
        spec_verbs.decide_file(novis, "Q1", V)
        fail("decide on a spec with no visual= was not refused")
    except VerbError as exc:
        check("decide on a spec with no visual= names the masthead rule and the spec as it stands",
              "needs visual=" in str(exc) and "unbuildable as it stands" in str(exc),
              str(exc))

    print()
    print("== the CLI's own edges ==")
    r = run("decide", os.path.join(tmp, "missing.spec.md"), "--id", "Q1",
            "--verdict", V)
    check("a spec that is not there is a refusal, not a traceback",
          r.returncode == 1 and "cannot read the spec" in r.stderr, r.stderr)
    latin = fresh("latin1", "", build=False)
    with open(latin, "wb") as fh:
        fh.write(b"::: masthead\n# T\n\nS \xff\xfe\n:::\n")
    r = run("new-round", latin)
    check("a spec that is not UTF-8 is a refusal naming the byte offset, not a "
          "traceback (LOOP-008 D3)", r.returncode == 1
          and "Traceback" not in r.stderr and "cannot read the spec" in r.stderr
          and "not UTF-8" in r.stderr and "offset 20" in r.stderr, r.stderr)
    bad = fresh("unparseable", "prosa\n\n::: item {#a #b}\n:::\n", build=False)
    r = run("decide", bad, "--id", "Q1", "--verdict", V)
    check("a spec that does not parse is refused with its line",
          r.returncode == 1 and "line 3" in r.stderr, r.stderr)
    r = run()
    check("no verb prints the usage and exits 2", r.returncode == 2)
    spec = fresh("outflag")
    elsewhere = os.path.join(tmp, "outflag", "otra.html")
    first_build(spec, elsewhere)
    r = run("decide", spec, "--id", "Q1", "--verdict", V,
            "--out", elsewhere)
    check("--out chooses the page", r.returncode == 0
          and os.path.isfile(elsewhere), r.stdout + r.stderr)
    r = run("decide", spec, "--id", "Q1", "--verdict", V, "--out", spec)
    check("--out pointed at the spec itself is refused",
          r.returncode == 1 and "is the spec itself" in r.stderr, r.stderr)
    check("...and the spec was not written first",
          'decided="Fences de Pandoc"' in read(spec))
    # M1: a verdict equal to a bold or numeric option label must survive the rebuild
    # (decided=No / decided=0 read as "not decided" when compared with the raw label).
    for label, verdict in (("**No**", "No"), ("0", "0")):
        sp = fresh("negword-" + verdict, PAGE.replace(
            "- YAML anidado — estructura explícita", "- %s — estructura explícita" % label))
        r = run("decide", sp, "--id", "Q1", "--verdict", verdict)
        check("decide --verdict %s on an option %s rebuilds (exit 0)" % (verdict, label),
              r.returncode == 0 and 'decided="%s"' % verdict in read(sp), r.stdout + r.stderr)

    print()
    print("== decide: several --id/--verdict pairs in one call (BL-497) ==")
    # One reader reply decides several items; one call records them all and
    # rebuilds once, so the page moves one round and every item carries it.
    more = "".join(
        '\n::: item {#Q%d title="Item %d"}\n¿Pregunta %d?\n\n'
        "- A {recommended}\n- B\n:::\n" % (n, n, n) for n in (3, 4))
    multi_text = PAGE.replace(" decided=yes", "").replace(
        "- No, un atributo nuevo\n:::\n:::",
        "- No, un atributo nuevo\n:::\n" + more + ":::", 1)
    mspec = fresh("multi", multi_text)
    mdir = os.path.dirname(mspec)
    mpage = os.path.join(mdir, "page.html")

    def rounds(path):
        html = read(path)
        return (re.findall(r'<meta name="consult-round" content="(\d+)">', html),
                re.findall(r'data-id="(Q\d)"[^>]*data-decided="[^"]*"'
                           r'[^>]*data-decided-round="(\d+)"', html))

    check("(setup) the first build is at round 1", rounds(mpage)[0] == ["1"])
    saved = subprocess.run(["bash", os.path.join(SCRIPTS, "save-reply.sh"),
                            mpage, "-"], input="Q1: Fences de Pandoc\nQ2: No, un atributo nuevo\nQ3: A\nQ4: B\n", text=True,
                           capture_output=True)
    check("(setup) the reader's reply is saved", saved.returncode == 0,
          saved.stdout + saved.stderr)
    r = run("decide", mspec, "--id", "Q2", "--verdict", "No, un atributo nuevo",
            "--id", "Q3", "--verdict", "A", "--id", "Q4", "--verdict", "B")
    check("decide with three pairs exits 0", r.returncode == 0, r.stderr)
    text = read(mspec)
    check("...all three verdicts are in the spec, each on its own item",
          'decided="No, un atributo nuevo"' in text
          and re.search(r'#Q3[^}]*decided="A"', text)
          and re.search(r'#Q4[^}]*decided="B"', text), text)
    # The next two cells are GUARDS, not regressions: BL-507 gates the round on
    # a saved reply, so separate calls would also read 2. They pin it stays so.
    meta, stamps = rounds(mpage)
    check("...the page moved exactly one round, to 2", meta == ["2"], str(meta))
    check("...and Q2, Q3 and Q4 all carry data-decided-round=2",
          sorted(q for q, n in stamps if n == "2") == ["Q2", "Q3", "Q4"],
          str(stamps))
    before = read(mspec)
    r = run("decide", mspec, "--id", "Q1", "--id", "Q2", "--verdict", V)
    check("a --id with no matching --verdict is refused, spec untouched",
          r.returncode == 2 and "one --verdict per --id" in r.stderr
          and read(mspec) == before, r.stdout + r.stderr)
    r = run("decide", mspec, "--id", "Q1", "--verdict", V,
            "--id", "Q9", "--verdict", "A")
    check("one unknown id refuses the whole call, nothing written (Q1 is not "
          "left at B)",
          r.returncode == 1 and "#Q9" in r.stderr and read(mspec) == before,
          r.stdout + r.stderr)
    r = run("decide", mspec, "--id", "Q1", "--verdict", V,
            "--id", "Q1", "--verdict", "YAML anidado")
    check("a repeated --id in one call is refused, spec untouched",
          r.returncode == 2 and "repeats" in r.stderr and read(mspec) == before,
          r.stdout + r.stderr)
    r = run("decide", mspec, "--id", "Q1", "--verdict", V,
            "--id", "#Q1", "--verdict", "YAML anidado")
    check("...and so is the same id written once with its `#`, spec untouched "
          "(the guard compares ids, not argv spellings)",
          r.returncode == 2 and "repeats" in r.stderr and read(mspec) == before,
          r.stdout + r.stderr)
    # --- a {chosen} option is the verdict: decide may not contradict it --------
    CHOSEN_PAGE = PAGE.replace(
        "- Fences de Pandoc — prosa con marcas mínimas {recommended}\n"
        "- YAML anidado — estructura explícita",
        "- Uno {recommended}\n- **Dos** {chosen}\n- Tres").replace(
        '{#Q1   title="Fences o YAML"    }', '{#Q1 title="F" decided="Dos"}')
    cspec = fresh("chosen-decide", CHOSEN_PAGE)
    cbytes = read(cspec, "rb")
    r = run("decide", cspec, "--id", "Q1", "--verdict", "Tres")
    check("decide a verdict other than the {chosen} option is refused, spec "
          "byte-identical",
          r.returncode != 0 and "{chosen}" in r.stderr
          and read(cspec, "rb") == cbytes, r.stdout + r.stderr)
    # The option is `**Dos**` in the spec, but the page's data-label (and so the
    # reader's reply) carries it as plain `Dos`: the plain form is the same option.
    r = run("decide", cspec, "--id", "Q1", "--verdict", "Dos")
    check("...and the same label as the {chosen} option is accepted, in the "
          "plain form the page's data-label carries",
          r.returncode == 0, r.stdout + r.stderr)
    # Same option, same verdict: decided="Dos" already records it, so the
    # markdown spelling is a no-op, not a rewrite (idempotence, and the round
    # stamp, which compares the same plain form).
    r = run("decide", cspec, "--id", "Q1", "--verdict", "**Dos**")
    check("...and in the spec's own markdown form, spec byte-identical",
          r.returncode == 0 and read(cspec, "rb") == cbytes,
          r.stdout + r.stderr)
    # BL-545: spaces inside the markers fold away too (strip AFTER the markup goes).
    r = run("decide", cspec, "--id", "Q1", "--verdict", "** Dos **")
    check("...and with spaces inside the markers (** Dos **), spec byte-identical",
          r.returncode == 0 and read(cspec, "rb") == cbytes,
          r.stdout + r.stderr)
    mspec2 = fresh("chosen-decide-md", CHOSEN_PAGE.replace(
        'decided="Dos"', 'decided="**Dos**"'))
    mbytes = read(mspec2, "rb")
    r = run("decide", mspec2, "--id", "Q1", "--verdict", "Dos")
    check("...and the mirror: decided=\"**Dos**\" with the plain verdict Dos, "
          "spec byte-identical",
          r.returncode == 0 and read(mspec2, "rb") == mbytes,
          r.stdout + r.stderr)

    # --- BL-533: a new round may DROP items, and the drop is recorded ----------
    print()
    print("== new-round --drop: an item leaves the page, its id is recorded ==")
    dspec = fresh("drop")
    dpage = os.path.join(os.path.dirname(dspec), "page.html")
    r = run("new-round", dspec)
    check("the page exists before the drop (baseline taken)", r.returncode == 0,
          r.stdout + r.stderr)
    Q1_BLOCK = PAGE[PAGE.index("::: item {#Q1"):PAGE.index("::: item {#Q2")]
    without_q1 = read(dspec).replace(Q1_BLOCK, "")
    check("fixture: the edit removed Q1 from the spec", "#Q1" not in without_q1)
    with open(dspec, "w", encoding="utf-8") as fh:
        fh.write(without_q1)
    r = run("new-round", dspec)
    check("a removal nobody declared is still refused (BL-396), spec untouched",
          r.returncode == 1 and "dropped between rounds" in r.stdout + r.stderr
          and read(dspec) == without_q1, r.stdout + r.stderr)
    r = run("new-round", dspec, "--drop", "Q9")
    check("...and declaring a DIFFERENT id does not excuse it",
          r.returncode == 1 and "dropped between rounds" in r.stdout + r.stderr
          and "Q1" in r.stdout + r.stderr and read(dspec) == without_q1,
          r.stdout + r.stderr)
    r = run("new-round", dspec, "--drop", "Q1")
    check("new-round --drop Q1 exits 0 on a spec whose next round removed Q1",
          r.returncode == 0, r.stdout + r.stderr)
    check("...the SPEC records it on the masthead",
          'dropped-ids="Q1"' in read(dspec).split("\n", 1)[0], read(dspec)[:300])
    built = read(dpage)
    check("...and the PAGE carries the record and no longer the item",
          '<meta name="consult-dropped" content="Q1">' in built
          and 'data-id="Q1"' not in built, built[:600])
    r = run("new-round", dspec, "--drop", "Q1")
    check("...and repeating the drop is idempotent (the id is listed once)",
          r.returncode == 0 and read(dspec).split("\n", 1)[0].count("Q1") == 1, r.stdout + r.stderr)
    r = run("new-round", dspec, "--drop", "", "--drop", "#")
    check("empty ids (\"\", \"#\") are ignored, not recorded",
          r.returncode == 0 and 'dropped-ids="Q1"' in read(dspec).split("\n", 1)[0],
          r.stdout + r.stderr)
    before = read(dspec, "rb")
    r = run("add-item", dspec, "--group", "G1", "--id", "Q1", "--title", "Otra")
    check("re-adding a dropped id is refused, spec unchanged",
          r.returncode == 1 and "dropped in an earlier round" in r.stderr
          and read(dspec, "rb") == before, r.stdout + r.stderr)
    # --- BL-611: --retitle records ids whose title changed; the id never moves
    rspec = fresh("retitle")
    r = run("new-round", rspec, "--retitle", "Q1")
    head = read(rspec).split("\n", 1)[0]
    check("new-round --retitle Q1 exits 0 and records it on the masthead",
          r.returncode == 0 and 'retitled-ids="Q1"' in head, r.stdout + r.stderr)
    check("...the item keeps its id (still #Q1 in the spec)",
          "::: item {#Q1" in read(rspec), read(rspec)[:300])
    check("...and the PAGE carries the consult-retitled meta",
          '<meta name="consult-retitled" content="Q1">'
          in read(os.path.join(os.path.dirname(rspec), "page.html")))
    r = run("new-round", rspec, "--retitle", "Q1", "--retitle", "#")
    check("...repeating it is idempotent (listed once)",
          r.returncode == 0 and read(rspec).split("\n", 1)[0].count("Q1") == 1,
          r.stdout + r.stderr)
    r = run("new-round", rspec)
    check("BL-611: a later new-round without --retitle removes retitled-ids "
          "(one round only), spec still parses",
          r.returncode == 0 and "retitled-ids" not in read(rspec)
          and "::: item {#Q1" in read(rspec), r.stdout + r.stderr + read(rspec)[:300])
    check("...and the page no longer carries the consult-retitled meta",
          "consult-retitled" not in read(os.path.join(os.path.dirname(rspec), "page.html")))
    # a retitled id may be dropped in a later round
    r = run("new-round", rspec, "--retitle", "Q1")
    trimmed = read(rspec).replace(Q1_BLOCK, "")
    with open(rspec, "w", encoding="utf-8") as fh:
        fh.write(trimmed)
    r = run("new-round", rspec, "--drop", "Q1")
    head = read(rspec).split("\n", 1)[0]
    check("BL-611: an id retitled earlier can be dropped (rc 0, dropped-ids set, "
          "retitled-ids gone)",
          r.returncode == 0 and 'dropped-ids="Q1"' in head
          and "retitled-ids" not in head, r.stdout + r.stderr + head)
    # --drop X --retitle Y in one call
    xspec = fresh("both")
    trimmed = read(xspec).replace(Q1_BLOCK, "")
    with open(xspec, "w", encoding="utf-8") as fh:
        fh.write(trimmed)
    r = run("new-round", xspec, "--drop", "Q1", "--retitle", "Q2")
    head = read(xspec).split("\n", 1)[0]
    check("BL-611: --drop Q1 --retitle Q2 in one call records both",
          r.returncode == 0 and 'dropped-ids="Q1"' in head
          and 'retitled-ids="Q2"' in head, r.stdout + r.stderr + head)
    r = run("new-round", fresh("retitle-gone"), "--retitle", "Q99")
    check("--retitle of an id not in the spec is refused",
          r.returncode == 1 and "Q99" in r.stderr, r.stdout + r.stderr)
    r = run("new-round", fresh("drop-live"), "--drop", "Q1")
    check("--drop of an id still in the spec is refused: use item dropped=",
          r.returncode == 1 and "still" in r.stderr, r.stdout + r.stderr)

    # --- BL-612: groups and gallery rows drop too; a group relabel is a note ---
    print()
    print("== new-round --drop on groups and gallery rows; a group title is a note ==")
    R1 = "audit-with-data-light-desktop"
    ROUND1 = '''::: masthead {eyebrow="Fixture" byline="x" visual="none: formato"}
# Restructura

Una ronda se reestructura.
:::

::: group {#G1 title="Bloque uno"}
Contexto uno.

::: item {#Q1 title="Fences o YAML"}
¿Fences o YAML?

- Fences {recommended}
- YAML
:::
:::

::: group {#G2 title="Bloque dos"}
Contexto dos.

::: item {#Q3 title="Marcador"}
¿Cuál marcador?

- Este {recommended}
- Ninguno
:::
:::

::: gallery {#E title="Galería" rows="rows.json" root="caps"}
:::

::: notes {title="Notas generales"}
:::
'''
    rspec2 = fresh("restructure", ROUND1, build=False)
    rdir = os.path.dirname(rspec2)
    rpage = os.path.join(rdir, "page.html")
    os.makedirs(os.path.join(rdir, "caps", "shots"))
    for png in ("a.png", "b.png"):
        subprocess.run([sys.executable, os.path.join(HERE, "png_fixture.py"),
                        os.path.join(rdir, "caps", "shots", png), "16", "9"],
                       check=True)

    def rows_json(cell, png):
        with open(os.path.join(rdir, "rows.json"), "w", encoding="utf-8") as fh:
            fh.write('{"gallery": "audit", "variants": ["light-desktop"], '
                     '"rows": [{"cell": "%s", "variant": "light-desktop", '
                     '"kind": "review", "look": "la tabla", "after": '
                     '"shots/%s"}]}' % (cell, png))
    rows_json("with-data", "a.png")
    r = subprocess.run([sys.executable, BUILD, rspec2, "-o", rpage],
                       capture_output=True, text=True)
    check("BL-612 fixture: round 1 builds (G1 with Q1, G2, gallery row)",
          r.returncode == 0 and 'data-id="%s"' % R1 in read(rpage),
          r.stdout + r.stderr)
    # round 2: G1, Q1 and the gallery row leave; G2 is relabelled
    round2 = (read(rspec2).replace(
        read(rspec2)[read(rspec2).index("::: group {#G1"):
                     read(rspec2).index("::: group {#G2")], "")
        .replace('title="Bloque dos"', 'title="Bloque dos, renombrado"'))
    with open(rspec2, "w", encoding="utf-8") as fh:
        fh.write(round2)
    rows_json("loaded", "b.png")
    r = run("new-round", rspec2)
    check("BL-612: the removals nobody declared still FAIL (groups and row too)",
          r.returncode == 1 and "G1" in r.stdout + r.stderr
          and "dropped between rounds" in r.stdout + r.stderr,
          r.stdout + r.stderr)
    round1_page = os.path.join(rdir, "round1-snapshot.html")
    shutil.copy(rpage, round1_page)
    r = run("new-round", rspec2, "--drop", "G1", "--drop", "Q1", "--drop", R1)
    drop_out = r.stdout + r.stderr
    check("BL-612: --drop <group> --drop <item> --drop <gallery row> exits 0 "
          "(the G2 relabel is a note, not a FAIL)",
          r.returncode == 0, r.stdout + r.stderr)
    check("...the masthead gains dropped-ids=\"G1 Q1 %s\"" % R1,
          'dropped-ids="G1 Q1 %s"' % R1 in read(rspec2).split("\n", 1)[0],
          read(rspec2)[:300])
    c = subprocess.run(["bash", CHECK, rpage, "--prev", round1_page],
                       capture_output=True, text=True)
    check("BL-612: check-artifact --prev passes on the old and new pages",
          c.returncode == 0, c.stdout + c.stderr)
    check("...and reports the G2 title change as a NOTE naming both titles",
          re.search(r"NOTE \[consult-ids\][^\n]*G2[^\n]*bloque dos[^\n]*renombrado",
                    drop_out) is not None
          and not re.search(r"FAIL \[consult-ids\][^\n]*G2", drop_out), drop_out)
    # an ITEM retitled in the same shape still FAILs unless declared
    reworded = read(rspec2).replace('title="Marcador"', 'title="Otra cosa"')
    with open(rspec2, "w", encoding="utf-8") as fh:
        fh.write(reworded)
    r = run("new-round", rspec2)
    check("BL-612: a retitled ITEM (Q3) still FAILs consult-ids undeclared",
          r.returncode == 1 and "id reused for a different claim" in r.stdout + r.stderr
          and "Q3" in r.stdout + r.stderr, r.stdout + r.stderr)
    r = run("new-round", rspec2, "--retitle", "Q3")
    check("...and passes when declared with --retitle Q3 (BL-611 intact)",
          r.returncode == 0, r.stdout + r.stderr)
    # an item id that becomes a BLOCK id is not a relabel: still a FAIL
    ispec = fresh("item-to-group")
    run("new-round", ispec)
    swapped = read(ispec)
    q2 = swapped[swapped.index("::: item {#Q2"):swapped.index(":::\n:::\n\n::: notes")]
    swapped = swapped.replace(q2 + ":::\n", "", 1).replace(
        "::: notes", '::: group {#Q2 title="Otro bloque"}\nCtx.\n\n'
        '::: item {#Q9 title="Nueva"}\n¿Nueva?\n\n- A {recommended}\n- B\n:::\n:::\n\n'
        '::: notes', 1)
    with open(ispec, "w", encoding="utf-8") as fh:
        fh.write(swapped)
    r = run("new-round", ispec)
    check("BL-612: an item id (Q2) that becomes a group id is NOT a relabel note: "
          "FAIL consult-ids, no --drop given",
          r.returncode == 1 and "Q2" in r.stdout + r.stderr
          and "id reused for a different claim" in r.stdout + r.stderr,
          r.stdout + r.stderr)

    # --- M3: the verb-layer mistakes the mutation gate catches ---------------
    print()
    print("== M3: no page yet, a verdict that is no option, the page language, "
          "a hand-edited page ==")
    # 52/52b: decide and new-round on a spec whose page was never built refuse,
    # and write nothing (no round-1 page appears from nowhere).
    for verb_args in (("decide", "--id", "Q1", "--verdict", "Fences de Pandoc"),
                      ("new-round",)):
        nb = fresh("nobuild-" + verb_args[0], build=False)
        nb_spec_before = read(nb)
        r = run(verb_args[0], nb, *verb_args[1:])
        check("M3 52: %s before any build refuses naming the missing build"
              % verb_args[0],
              r.returncode == 1 and re.search(
                  r"before.*build|no page|not built|first build",
                  r.stderr) is not None, r.stdout + r.stderr)
        check("...and writes neither the page nor the spec",
              not os.path.exists(os.path.join(os.path.dirname(nb), "page.html"))
              and read(nb) == nb_spec_before)

    zb = fresh("zero-page", build=False)
    open(os.path.join(os.path.dirname(zb), "page.html"), "w").close()
    r = run("decide", zb, "--id", "Q1", "--verdict", "Fences de Pandoc")
    check("M3 52: a zero-byte page.html counts as not built: exit 1, no page",
          r.returncode == 1 and "no page" in r.stderr, r.stdout + r.stderr)

    # 54: a verdict that is none of the item's options is refused, naming both;
    # an option label (any spelling of the markup) and an item without options
    # still take any text.
    refuses("M3 54: decide refuses a verdict that is no option of the item",
            lambda: decide(PAGE, "Q1", "Opción inventada"), "verdict")
    refuses("...and lists the options it does have",
            lambda: decide(PAGE, "Q1", "Opción inventada"), "Fences de Pandoc")
    check("...an option label is still recorded",
          'decided="YAML anidado"' in decide(PAGE, "Q1", "YAML anidado"))
    check("...and so is an item with no options, with free text",
          'decided="se queda así"' in decide(
              PAGE.replace("- Fences de Pandoc — prosa con marcas mínimas "
                           "{recommended}\n- YAML anidado — estructura explícita\n",
                           ""), "Q1", "se queda así"))

    # The documented free-text route: the saved reply answers the id with the
    # kit's Other choice, or with an option plus a note. A bare line is not it.
    OTHER_REPLY = ("### Q1 · Fences o YAML\n\n- Otra — lo explico en las notas"
                   "\n\nMejor usar X\n")
    NOTE_REPLY = "### Q1 · Fences o YAML\n\n- YAML anidado\n\nSolo si es opcional\n"
    CHAT_OTHER = "Q1: Otra — lo explico en las notas\nMejor usar X\n"
    BARE_REPLY = "Q1: Opción inventada que no existe\n"
    NOT_NOW_REPLY = ("### Q1 · Fences o YAML\n\n- Todavía no — lo dejo para otra "
                     "ronda\n\nluego\n")
    OPTION_ONLY = "### Q1 · Fences o YAML\n\n- YAML anidado\n"
    for label, reply in (("Other + note", OTHER_REPLY),
                         ("an option + a note", NOTE_REPLY),
                         ("chat-form Other + note", CHAT_OTHER)):
        check("M3 54: a verdict that is no option is recorded when the saved "
              "reply says %s" % label,
              'decided="Usar X"' in decide(PAGE, "Q1", "Usar X", reply))
    for label, reply in (("a bare reply line", BARE_REPLY),
                         ("Todavía no + a note", NOT_NOW_REPLY),
                         ("an option and no note", OPTION_ONLY),
                         ("no saved reply", None)):
        refuses("M3 54: ...and refused when the saved reply is %s" % label,
                lambda reply=reply: decide(PAGE, "Q1", "Usar X", reply),
                "none of its options")
    # The composer's page-defect sub-block (LOOP-008 Q10) is no note: an option
    # beside it is still a bare pick, so it opens no free-text verdict.
    for label, head in (("es", "Fallo de la p\u00e1gina"), ("en", "Page problem")):
        refuses("M3 54: ...and refused when the saved reply is an option + a "
                "page-defect sub-block (%s)" % label,
                lambda head=head: decide(
                    PAGE, "Q1", "Usar X",
                    "### Q1 \u00b7 T\n\n- YAML anidado\n\n#### %s\n\nel bot\u00f3n no carga\n" % head),
                "none of its options")
    check("M3 54: a real note BEFORE a page-defect sub-block still opens free text",
          'decided="Usar X"' in decide(
              PAGE, "Q1", "Usar X",
              "### Q1 \u00b7 T\n\n- YAML anidado\n\nSolo si es opcional\n\n"
              "#### Fallo de la p\u00e1gina\n\nel bot\u00f3n no carga\n"))
    # An option-shaped line that is no option of the item is an invention too.
    for label, reply in (
            ("a chat-form invented option + a note",
             "Q1: Opción inventada\n\nGracias\n"),
            ("a kit-form invented option + a note",
             "### Q1 · T\n\n- Algo que no es opcion\n\nnota\n"),
            ("a provisional option + a note",
             "### Q1 · T\n\n- YAML anidado [provisional]\n\nnota\n"),
            ):
        refuses("M3 54: ...and refused when the saved reply is %s" % label,
                lambda reply=reply: decide(PAGE, "Q1", "Usar X", reply),
                "none of its options")
    check("M3 54: a chat-form option whose note repeats its text is still option + note",
          'decided="Usar X"' in decide(
              PAGE, "Q1", "Usar X", "Q1:YAML anidado\nYAML anidado\n"))
    # The reply the composer pastes carries the badge suffix on a recommended
    # option (composer.js recSuffix: ' (recomendada)' / ' (recommended)').
    for label, reply in (
            ("a recommended option + a note (es)",
             "### Q1 · T\n\n- Fences de Pandoc (recomendada)\n\nmatiz\n"),
            ("a recommended option + a note (en)",
             "### Q1 · T\n\n- Fences de Pandoc (recommended)\n\nnote\n"),
            ("an English Other + a note",
             "### Q1 · T\n\n- Other \u2014 see my notes\n\nnote\n")):
        check("M3 54: free text is recorded when the saved reply is %s" % label,
              'decided="Usar X"' in decide(PAGE, "Q1", "Usar X", reply))
    NN = PAGE.replace(
        "- Fences de Pandoc \u2014 prosa con marcas m\u00ednimas {recommended}\n"
        "- YAML anidado \u2014 estructura expl\u00edcita",
        "- Todav\u00eda no migrar\n- Migrar ya")
    check("M3 54: an option whose label begins with the Not-now words is an "
          "option, so option + note opens free text",
          NN != PAGE and 'decided="Usar X"' in decide(
              NN, "Q1", "Usar X", "### Q1 \u00b7 T\n\n- Todav\u00eda no migrar\n\nnota\n"))
    check("M3 54: a REAL chat-form option + a note still opens free text",
          'decided="Usar X"' in decide(
              PAGE, "Q1", "Usar X", "Q1: YAML anidado\n\nSolo si es opcional\n"))
    refuses("...an Other for ANOTHER id does not open Q1",
            lambda: decide(PAGE, "Q1", "Usar X",
                           OTHER_REPLY.replace("Q1", "Q2")), "none of its options")
    fs = fresh("free-text", build=False)
    first_build(fs, reply=OTHER_REPLY.encode("utf-8"))
    r = run("decide", fs, "--id", "Q1", "--verdict", "Usar X")
    check("M3 54: the CLI reads the saved reply.md: Other + note, exit 0, "
          "decided=\"Usar X\"", r.returncode == 0 and 'decided="Usar X"'
          in read(fs), r.stdout + r.stderr)
    bare = fresh("free-text-bare", build=False)
    first_build(bare, reply=BARE_REPLY.encode("utf-8"))
    before_bare = read(bare, "rb")
    r = run("decide", bare, "--id", "Q1", "--verdict", "Opción inventada que no existe")
    check("...and the bare invented reply exits 1 'none of its options', spec "
          "untouched", r.returncode == 1 and "none of its options" in r.stderr
          and read(bare, "rb") == before_bare, r.stdout + r.stderr)
    # the verdict is written in the label's own spelling
    check("M3: a verdict matching a label case-insensitively records the label's "
          "own text", 'decided="YAML anidado"' in decide(PAGE, "Q1", "yaml ANIDADO"))
    # select=one has ONE winner: a comma list is two, so refused; select=many
    # reads the set longest-first (a label may hold a comma).
    refuses("M3: select=one refuses two labels joined by a comma",
            lambda: decide(PAGE, "Q1", "Fences de Pandoc, YAML anidado"),
            "none of its options")
    MANY = PAGE.replace('{#Q1   title="Fences o YAML"    }',
                        '{#Q1 title="F" select=many}').replace(
        "- Fences de Pandoc — prosa con marcas mínimas {recommended}\n"
        "- YAML anidado — estructura explícita",
        "- Uno, dos\n- Uno\n- Tres")
    check("M3: select=many records two labels joined by ', '",
          'decided="Uno, Tres"' in decide(MANY, "Q1", "uno, tres"))
    check("...and a label that holds a comma is read whole, longest first",
          'decided="Uno, dos, Tres"' in decide(MANY, "Q1", "Uno, dos, Tres"))
    refuses("...and a part that is no label still refuses",
            lambda: decide(MANY, "Q1", "Uno, Cuatro"), "none of its options")
    AB = MANY.replace("- Uno, dos\n- Uno\n- Tres", "- A, B\n- A\n- B")
    check("M3: select=many finds the partition `A, B` + `A` + `B` past a first "
          "partition that repeats a label",
          AB != MANY and 'decided="A, B, A, B"' in decide(AB, "Q1", "A, B, A, B"))
    refuses("M3: select=many refuses a label named twice",
            lambda: decide(MANY, "Q1", "Uno, Uno"), "none of its options")

    # new-round refuses while the saved reply holds a bare option pick the spec
    # has not decided (owner case 225f968e: the next round started at Q15 and
    # 14 earlier answers were lost). Other, option + note and a provisional pick
    # may be carried open.
    def nr(name, reply, text=PAGE):
        path = fresh(name, text, build=False)
        first_build(path, reply=reply.encode("utf-8"))
        return path
    pg = lambda path: os.path.join(os.path.dirname(path), "page.html")
    bp = nr("nr-bare", "Q1: yaml anidado\n")
    before = (read(bp, "rb"), read(pg(bp), "rb"))
    r = run("new-round", bp)
    check("M3 new-round: a bare pick undecided exits 1 naming the id, the "
          "option and the decide command", r.returncode == 1
          and "#Q1" in r.stderr and "decide --id Q1 --verdict \"YAML anidado\""
          in r.stderr, r.stdout + r.stderr)
    check("...and the spec and the page are byte-identical afterwards",
          (read(bp, "rb"), read(pg(bp), "rb")) == before)
    r = run("decide", bp, "--id", "Q1", "--verdict", "YAML anidado")
    r2 = run("new-round", bp)
    check("M3 new-round: succeeds once the pick is decided",
          r.returncode == 0 and r2.returncode == 0, r.stderr + r2.stderr)
    # BL-711, file route: a proposal the reader re-picked is refused like an open item's pick, and
    # deciding it ends its proposal state, so the next round files exactly one ledger row.
    pr = nr("nr-prop", "## G1 \u00b7 Formato del spec\n\n### Q2 \u00b7 Marcador de columna\n\n- No, un atributo nuevo\n", two)
    r = run("new-round", pr)
    check("M3 new-round: a re-picked proposal exits 1 naming the decide command",
          r.returncode == 1 and "decide --id Q2" in r.stderr, r.stdout + r.stderr)
    r = run("decide", pr, "--id", "Q2", "--verdict", "No, un atributo nuevo")
    r2 = run("new-round", pr)
    check("...and once decided (proposal dropped) new-round files exactly one Q2 ledger row",
          r.returncode == 0 and r2.returncode == 0
          and read(pr).count("- Q2 \u2014") == 1
          and not re.search(r"#Q2[^}]*proposal", read(pr)), r.stderr + r2.stderr + read(pr)[-900:])
    for label, reply in (
            ("an Other answer", OTHER_REPLY),
            ("an option + a note", NOTE_REPLY),
            ("Other alone", "### Q1 \u00b7 T\n\n- Otra \u2014 lo explico en las notas\n"),
            ("a pick + Other", "### Q1 \u00b7 T\n\n- YAML anidado\n- Otra \u2014 lo explico en las notas\n"),
            ("no reply block for the item", "Q9: nada\n")):
        r = run("new-round", nr("nr-" + re.sub(r"\W", "", label), reply))
        check("M3 new-round: %s does not block" % label, r.returncode == 0,
              r.stdout + r.stderr)
    # the contract (marker duties) may still refuse the unchanged item; the
    # guard under test is only that new-round does not demand a decide first
    r = run("new-round", nr("nr-q", "### Q1 \u00b7 T\n\n- YAML anidado\n- [question]\n"))
    check("M3 new-round: a pick + [question] is not a bare pick",
          "decide --id" not in r.stderr, r.stdout + r.stderr)
    r = run("new-round", nr("nr-pd", "### Q1 \u00b7 T\n\n- YAML anidado\n- [page-defect]\n"))
    check("M3 new-round: a pick + [page-defect] still blocks (the answer stands)",
          r.returncode == 1 and "decide --id Q1" in r.stderr, r.stdout + r.stderr)
    r = run("new-round", nr("nr-pd2", "### Q1 \u00b7 T\n\n- YAML anidado\n\n#### Fallo de la p\u00e1gina\n\nse ve roto\n"))
    check("M3 new-round: a pick + a page-defect sub-block still blocks (the sub-block is no note)",
          r.returncode == 1 and "decide --id Q1" in r.stderr, r.stdout + r.stderr)
    # A provisional pick whose label matches as written (the label ends in the
    # suffix) is the only case that reaches the provisional skip.
    PROV = PAGE.replace("- YAML anidado \u2014 estructura expl\u00edcita",
                        "- YAML anidado [provisional]")
    check("M3 new-round fixture: the provisional label replaced", PROV != PAGE)
    r = run("new-round", nr("nr-prov", "### Q1 \u00b7 T\n\n- YAML anidado [provisional]\n", PROV))
    check("M3 new-round: a provisional pick does not block", r.returncode == 0,
          r.stdout + r.stderr)
    MANY2 = PAGE.replace('{#Q1   title="Fences o YAML"    }', '{#Q1 title="F" select=many}'
                         ).replace("- Fences de Pandoc \u2014 prosa con marcas m\u00ednimas {recommended}\n"
                                   "- YAML anidado \u2014 estructura expl\u00edcita", "- Uno\n- Dos\n- Tres")
    r = run("new-round", nr("nr-many", "### Q1 \u00b7 T\n\n- Uno\n- Tres\n", MANY2))
    check("M3 new-round: a select=many reply names the whole set in the command",
          r.returncode == 1 and '--verdict "Uno, Tres"' in r.stderr, r.stdout + r.stderr)
    r = run("new-round", nr("nr-two", "### Q1 \u00b7 T\n\n- Fences de Pandoc\n- YAML anidado\n"))
    check("M3 new-round: select=one with two pick lines suggests the LAST (the "
          "reader's final line)", r.returncode == 1
          and '--verdict "YAML anidado"' in r.stderr, r.stdout + r.stderr)
    r = run("new-round", nr("nr-en", "### Q1 \u00b7 T\n\n- Fences de Pandoc (recommended)\n"))
    check("M3 new-round: an English reply (recommended suffix stripped) blocks "
          "the same way", r.returncode == 1 and "decide --id Q1" in r.stderr,
          r.stdout + r.stderr)

    # 75: the rebuild follows the project profile when the masthead is silent
    # (the builder CLI's rule), instead of a hard-coded --lang es.
    en = fresh("profile-en")
    ctx = os.path.join(os.path.dirname(en), ".context", "profiles")
    os.makedirs(ctx)
    with open(os.path.join(ctx, "artifact.md"), "w", encoding="utf-8") as fh:
        fh.write("## Language\n\n- language: en\n")
    r = run("decide", en, "--id", "Q1", "--verdict", "YAML anidado")
    check("M3 75: decide in an en-profile project with a silent masthead exits "
          "0", r.returncode == 0, r.stdout + r.stderr)
    built_en = read(os.path.join(os.path.dirname(en), "page.html")) \
        if r.returncode == 0 else ""
    check("...and the page is <html lang=\"en\"> with the item decided",
          '<html lang="en"' in built_en and 'data-decided="YAML anidado"'
          in built_en, built_en[:200])

    # 51: a hand edit to the built page survives a rebuild by refusal, from the
    # builder and from a verb, with the hand-edited bytes left in place.
    he = fresh("hand-edit")
    he_page = os.path.join(os.path.dirname(he), "page.html")
    r = subprocess.run([sys.executable, BUILD, he, "-o", he_page],
                       capture_output=True, text=True)
    check("M3 51 setup: the first build lands", r.returncode == 0,
          r.stdout + r.stderr)
    edited = read(he_page).replace("<h1>", "<h1><!--HAND-EDIT-->", 1)
    check("...the edit applied", "HAND-EDIT" in edited)
    with open(he_page, "w", encoding="utf-8") as fh:
        fh.write(edited)
    r = subprocess.run([sys.executable, BUILD, he, "-o", he_page],
                       capture_output=True, text=True)
    check("M3 51: rebuilding over a hand-edited page refuses naming the hand "
          "edit", r.returncode == 1 and re.search(
              r"hand[- ]edit|diverg", r.stderr) is not None, r.stdout + r.stderr)
    check("...and the hand-edited page is left in place", read(he_page) == edited)
    he_spec = read(he)
    r = run("decide", he, "--id", "Q1", "--verdict", "YAML anidado")
    check("M3 51: a verb over the hand-edited page refuses too, naming it",
          r.returncode == 1 and re.search(r"hand[- ]edit|diverg", r.stderr)
          is not None, r.stdout + r.stderr)
    check("...leaving the page and the spec as they were",
          read(he_page) == edited and read(he) == he_spec)

finally:
    shutil.rmtree(tmp, ignore_errors=True)

print()
if failures:
    print("%d failure(s)" % len(failures))
    raise SystemExit(1)
print("OK — the verbs: add-item/decide/new-round on the spec and on the "
      "rebuilt page, the round trip through check-artifact.sh, atomic "
      "refusals compared byte for byte, the page produced only by build(), "
      "the author's formatting and trailing newline preserved, and each "
      "verb's documented idempotency")
