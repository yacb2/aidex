#!/usr/bin/env python3
"""The spec BUILD: kit markup, exact ids, determinism, and the contract.

Four claims, in the order the plan's acceptance names them:

  DETERMINISM — the same spec built twice is byte-identical. Asserted as a byte
  comparison and not trusted, because the output is read as a DIFF between
  rounds: one set iteration, one `id()`-derived value or one clock in there and
  every round looks like a change. (The build STAMP is the deliberate
  exception, and it lives in the wrap, outside `build()` — BL-439.)

  IDS — a `#id` reaches the page byte-exactly, as `id=`, `data-id=`, the radio
  group's `name=` and the `.consult-id` the reader sees. Not lowercased, not
  slugged, not renumbered. Phase 3's corpus conversion asserts exact
  preservation, and §8.1 is why: a reply that says "on Q3 I disagree" has to
  still mean the same claim next round.

  THE VOCABULARY — one case per block type of `04-block-vocabulary.md`, each
  asserting the kit markup the corpus already carries, plus the refusals that
  are the builder's half of the two-layer split (unknown type, unknown attr,
  missing required attr, a block in the wrong parent).

  THE CONTRACT — a built page passes `check-artifact.sh` unmodified, with no
  spec-specific exemption. That is the only claim here that needs the wrap, and
  it is asserted on a page with items, a gallery, a ledger and a notes box —
  the shapes `check_artifact.py` has rules about.

  WHAT THE CONTRACT CANNOT SEE — the three claims a green gate does not imply,
  each added after a page passed `check-artifact` while failing it: no built
  page holds a `\x00` byte (asserted over EVERY page this file builds, not the
  one construct that found it); `build()` raises `SpecSyntaxError` or
  `SpecBuildError` and nothing else, a `SystemExit` out of a library entry being
  uncatchable by any caller; and a refusal, not silence, for the shapes whose
  failure mode is a page missing text the spec had (`::: prose`, a masthead with
  two titles).

  THE PAGE'S LANGUAGE — a `masthead` that declares `lang=` decides `<html lang>`
  and the kit chrome, over `--lang` and over `build(lang=…)`. Added 2026-09-24
  after 2 of the 30 sampled pages — both English — built into `<html lang="es">`
  and failed the contract's `lang` rule on originals that pass it.

Stdlib only, no runner: `python3 test_build.py`, prints OK, exits 0.
"""
import json
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

import spec_build                                 # noqa: E402
from spec_build import SpecBuildError, build      # noqa: E402
from spec_parser import SpecSyntaxError           # noqa: E402

BUILD = os.path.join(SCRIPTS, "spec_build.py")
CHECK = os.path.join(SCRIPTS, "check-artifact.sh")

failures = []
# Every page this file builds, kept so the NUL sweep at the end runs over all of
# them rather than over one case written for the defect. See § no page ever
# ships a NUL byte.
BUILT = []


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


def holds(label, spec, *needles, **kw):
    """Build `spec` and assert every needle appears in the output verbatim."""
    try:
        html = build(spec, **kw)
    except (SpecSyntaxError, SpecBuildError) as exc:
        fail("%s: refused a valid spec (line %d: %s)"
             % (label, exc.line, exc.message))
        return ""
    BUILT.append((label, html))
    missing = [n for n in needles if n not in html]
    check(label, not missing, "missing %r in:\n%s" % (missing, html))
    return html


def rejects(label, spec, line, needle=""):
    """The spec builds to nothing and the refusal names `line`."""
    try:
        build(spec)
    except SpecBuildError as exc:
        if exc.line != line:
            fail("%s: reported line %d, expected %d (%s)"
                 % (label, exc.line, line, exc.message))
        elif needle and needle not in exc.message:
            fail("%s: message %r does not mention %r" % (label, exc.message, needle))
        else:
            ok("%s (line %d: %s)" % (label, exc.line, exc.message))
        return
    except SpecSyntaxError as exc:
        fail("%s: refused at the TOKENIZER (line %d: %s) — an unknown type, an "
             "unknown attr and a missing required attr are the builder's to "
             "refuse" % (label, exc.line, exc.message))
        return
    fail("%s: accepted it" % label)


# The one spec used for determinism, ids and the contract: every block type the
# page contract has a rule about, in the shape 04-block-vocabulary.md writes it.
PAGE = '''::: masthead {eyebrow="Fixture · spec build" byline="Fuente: `tests/test_build.py`" visual="none: la decisión es de formato y no tiene forma que dibujar"}
# La página construida desde un spec

Tres preguntas abiertas y una decisión cerrada.
:::

::: section {#sec-ledger eyebrow="Lo ya decidido · 1" heading="De dónde parte esta ronda"}
::: ledger
- d1 — **Hecho.** La gramática vive en `03-spec-grammar.md`.
:::
:::

::: group {#G1 title="Formato del spec" eyebrow="Bloque G1"}
La consulta de hoy: qué escribe el agente cuando la página cambia.

::: item {#Q1 title="Fences o YAML" decided=yes}
¿Fences de Pandoc o YAML anidado?

- Fences de Pandoc — prosa con marcas mínimas {recommended}
- YAML anidado — estructura explícita
:::

::: note {.warn}
`item` acepta prosa y listas.
:::

::: item {#Q2 title="Marcador de columna"}
¿El marcador va en la fila separadora?

| ruta | KB |
|---|---:|
| consulta A | 37 |

- Sí, `---:` es markdown estándar {recommended}
- No, un atributo nuevo
:::
:::

::: callout
Ocho de nueve revisores coincidieron, con [confianza alta]{.pill .high}
y sin ningún [`refuted`]{.chip .chip-kill}.
:::

::: verdict {win="Ruta A"}
| n | ruta | detalle |
|---|---|---|
| 3 | Ruta A | turnos · 140k |
| 5 | Ruta B | turnos · 300k |
:::

::: notes {title="Notas generales"}
:::
'''

print("== determinism ==")
first = build(PAGE)
second = build(PAGE)
check("two builds of one spec are byte identical", first == second,
      "%d vs %d bytes" % (len(first), len(second)))
# Run in a SEPARATE interpreter too: `PYTHONHASHSEED` changes per process, and
# a dict or set iteration this file happened to freeze inside one process is
# exactly the shape that survives an in-process comparison.
env = dict(os.environ, PYTHONHASHSEED="0")
tmp = tempfile.mkdtemp(prefix="spec-build-test-")
try:
    spec_path = os.path.join(tmp, "page.spec.md")
    with open(spec_path, "w", encoding="utf-8") as fh:
        fh.write(PAGE)
    runs = []
    for seed in ("0", "1", "12345"):
        env["PYTHONHASHSEED"] = seed
        runs.append(subprocess.run([sys.executable, BUILD, spec_path],
                                   capture_output=True, env=env).stdout)
    check("three processes with different PYTHONHASHSEED agree, byte for byte",
          len(set(runs)) == 1 and runs[0].decode("utf-8") == first)

    print()
    print("== ids reach the page byte-exactly ==")
    # Ids whose spelling a slugger, a lowercaser or a counter would change.
    ID_SPEC = ('::: group {#G1_Mixed-Case title="t"}\n'
               '::: item {#Q10_a-B title="t"}\n?\n\n- Sí\n- No\n:::\n'
               '::: item {#Q2 title="t"}\n?\n:::\n:::\n'
               '::: notes {title="n"}\n:::\n')
    html = build(ID_SPEC)
    BUILT.append(("ids", html))

    def attr_id(page, ident):
        """A real `id="X"` attribute, not the tail of `data-id="X"`.

        The plain substring test that used to stand here could not fail: every
        emitter that writes `data-id="G1"` satisfies `'id="G1"' in html` on the
        same bytes. Deleting `id=` from `emit_group` — which breaks every rail
        anchor and every `#G1` deep link — left all three id checks green.
        """
        return re.search(r'(?<![-\w])id="%s"' % re.escape(ident), page)

    check("the group's #id lands as a REAL id= attribute, not only data-id=",
          bool(attr_id(html, "G1_Mixed-Case")), html)
    for ident in ("G1_Mixed-Case", "Q10_a-B", "Q2"):
        check("id %r survives verbatim, everywhere it lands" % ident,
              ('data-id="%s"' % ident) in html)
    for ident in ("Q10_a-B", "Q2"):
        check("id %r is the one the READER sees on the item" % ident,
              ('<span class="consult-id">%s</span>' % ident) in html)
    # An item emits no `id=` of its own: composer.js sets it at runtime from
    # data-id. Asserted so the docstring's claim and the page agree.
    check("an item's id travels as data-id only — the runtime sets id=",
          not attr_id(html, "Q10_a-B") and not attr_id(html, "Q2"), html)
    check("the item's radio group and its visible id are the SAME string",
          'name="Q10_a-B"' in html
          and '<span class="consult-id">Q10_a-B</span>' in html)
    check("no id is invented, lowercased or renumbered",
          "g1_mixed-case" not in html and "q10" not in html, html)

    print()
    print("== the block vocabulary ==")
    holds("masthead: eyebrow, h1, standfirst, byline",
          '::: masthead {eyebrow="E" byline="B"}\n# T\n\nS\n\nMás.\n:::',
          '<header class="masthead">', '<p class="eyebrow">E</p>', "<h1>T</h1>",
          '<p class="standfirst">S</p>', "<p>Más.</p>",
          '<div class="byline">B</div>')
    holds("masthead: title= alone is the h1, and the body keeps its standfirst",
          '::: masthead {title="Attr"}\nS\n\nMás.\n:::',
          "<h1>Attr</h1>", '<p class="standfirst">S</p>', "<p>Más.</p>")
    holds("section: an id'd <section> with a .sec-head, and its body inside it",
          '::: section {#sec-ledger eyebrow="E" heading="H"}\n'
          '::: ledger\n- k — v\n:::\n:::',
          '<section id="sec-ledger">', '<div class="sec-head">',
          '<p class="eyebrow">E</p>', "<h2>H</h2>", '<div class="ledger">')
    holds("section: eyebrow is optional and a plain body is prose",
          '::: section {#s1 heading="H"}\nTexto.\n:::',
          '<section id="s1">', "<h2>H</h2>", "<p>Texto.</p>")
    holds("section: a .class lands on the section, never on the sec-head",
          '::: section {.wide #s1 heading="H"}\n:::',
          '<section class="wide" id="s1">', '<div class="sec-head">')
    holds("group: the kit's consult-group, sec-head and h2",
          '::: group {#G1 title="T" eyebrow="E"}\nx\n::: item {#Q1 title="i"}\n?\n:::\n:::',
          '<section class="consult-group" id="G1" data-id="G1" data-title="T">',
          '<div class="sec-head">', '<p class="eyebrow">E</p>', "<h2>T</h2>")
    ITEM = ('::: group {#G1 title="T"}\n'
            '::: item {#Q1 title="Short name" decided=yes}\n'
            "¿La pregunta, preguntada?\n\n"
            "- Sí, cerrar — los doce ajustes son menores {recommended}\n"
            "- No, uno cambia el resultado\n"
            ":::\n:::\n")
    holds("item: data-title is the short name, the h3 is the QUESTION",
          ITEM,
          '<section class="consult-item" data-id="Q1" data-title="Short name" data-decided>',
          '<h3><span class="consult-id">Q1</span>¿La pregunta, preguntada?</h3>')
    holds("item: the option list becomes `.opts one` with data-label and a hint",
          ITEM,
          '<div class="opts one">',
          '<input type="radio" name="Q1" data-label="Sí, cerrar" data-recommended>',
          '<span>Sí, cerrar <span class="hint">los doce ajustes son menores</span></span>',
          '<input type="radio" name="Q1" data-label="No, uno cambia el resultado">')
    holds("item: the notes box is injected on every item, never optional",
          ITEM, '<p class="fieldlabel">Notas sobre esto</p>', "<textarea ")
    # The marker is `{recommended}` and the emitted flag is `data-recommended`,
    # so the old needle `"recommended)"` was punctuation the grammar cannot
    # produce: it held for every spec an author could write. The needle is the
    # marker itself, on an option with NO ` — ` hint, which is the shape that
    # leaks it with nothing else failing (the hint assertion above is what
    # caught the leak on the other shape, and only by accident).
    ITEM_NO_HINT = ('::: group {#G1 title="T"}\n'
                    '::: item {#Q1 title="t"}\n?\n\n'
                    "- Sí, cerrar {recommended}\n- No\n:::\n:::\n")
    no_hint = build(ITEM_NO_HINT)
    BUILT.append(("item with a hint-less recommended option", no_hint))
    check("item: the `{recommended}` marker never reaches the page — it is the attr",
          "{recommended}" not in no_hint, no_hint)
    check("item: ...and it did become data-recommended",
          'data-label="Sí, cerrar" data-recommended' in no_hint, no_hint)
    # `data-label` is what the composer pastes into the reply, so the markup
    # punctuation an author wrote for the PAGE is stripped from it (PLAIN).
    # Nothing asserted this: every other data-label case here is
    # punctuation-free, so `esc(PLAIN.sub("", label))` could be replaced by
    # `esc(label)` with the whole suite green and backticks travelling into the
    # reader's paste.
    MARKUP_OPT = ('::: group {#G1 title="T"}\n'
                  '::: item {#Q1 title="t"}\n?\n\n'
                  "- Sí, `---:` es **markdown** estándar\n- No\n:::\n:::\n")
    holds("item: markup punctuation is stripped from data-label, kept in the span",
          MARKUP_OPT,
          'data-label="Sí, ---: es markdown estándar"',
          "<span>Sí, <code>---:</code> es <strong>markdown</strong> estándar</span>")
    holds("notes: the general-notes item",
          '::: notes {title="Notas generales"}\n:::',
          '<section class="consult-item consult-notes" data-id="notes" '
          'data-title="Notas generales">',
          '<h3><span class="consult-id">notes</span>Notas generales</h3>')
    holds("ledger: a grid of .k/.v rows and nothing else",
          "::: ledger\n- d4 — **Hecho.** T-100.\n- d12 — Plantilla.\n:::",
          '<div class="ledger">',
          '<div><span class="k">d4</span><span class="v"><strong>Hecho.</strong> T-100.</span></div>',
          '<div><span class="k">d12</span><span class="v">Plantilla.</span></div>')
    h = holds("ledger: a row with no ` — ` is a row with no KEY, not a refusal",
              "::: ledger\n- d4 — con clave\n- sin separador ninguno\n:::",
              '<div><span class="v">sin separador ninguno</span></div>')
    check("...and the key-less row carries no `.k`, so `ledger_ids` harvests "
          "no item id out of a row that names no decision",
          h.count('class="k"') == 1, h)
    holds("verdict: win= flags the winning cell, by its label",
          '::: verdict {win="Ruta A"}\n| n | ruta | detalle |\n|---|---|---|\n'
          "| 3 | Ruta A | 140k |\n| 5 | Ruta B | 300k |\n:::",
          '<div class="verdict">',
          '<div class="win"><b>3</b>Ruta A<br><small>140k</small></div>',
          "<div><b>5</b>Ruta B<br><small>300k</small></div>")
    holds("callout: the framed aside keeps its paragraph",
          "::: callout\nOcho de nueve.\n:::",
          '<div class="callout">', "<p>Ocho de nueve.</p>")
    holds("note: one paragraph sits bare in the div, as the corpus writes it",
          "::: note\nLas tres categorías.\n:::",
          '<div class="note">Las tres categorías.</div>')
    holds("note: `.warn` is the one class components.css styles on it",
          "::: note {.warn}\nOjo.\n:::", '<div class="note warn">')
    holds("num: a right-aligned separator cell marks the column",
          "| ruta | KB |\n|---|---:|\n| A | 37 |",
          '<th class="num">KB</th>', '<td class="num">37</td>')
    holds("pill and chip are INLINE spans, not fences",
          "Con [confianza alta]{.pill .high} y un [deferred]{.chip .chip-kill}.",
          '<span class="pill high">confianza alta</span>',
          '<span class="chip chip-kill">deferred</span>')
    holds("pill: tone= is the second class, as the vocabulary spells it",
          "Con [info]{.pill tone=info}.", '<span class="pill info">info</span>')
    check("a bracketed span of any OTHER class is left exactly as written",
          "[x]{.foo}" in build("Texto [x]{.foo} literal."))
    # A code span or an emphasis INSIDE a pill/chip label. Both shapes shipped
    # broken: the code span's text was replaced by two literal NUL bytes and the
    # stash index (data loss, past a green check-artifact), and `**bold**` leaked
    # its asterisks as text. One root cause — the stash was restored by a single
    # non-recursive pass and stashed content was never re-processed.
    holds("pill: a code span inside the label survives, as code",
          "La tarea [`T-12`]{.chip .chip-kill} queda diferida.",
          '<span class="chip chip-kill"><code>T-12</code></span>')
    holds("pill: emphasis inside the label is rendered, not leaked as asterisks",
          "Con [**alta**]{.pill .high} y [_baja_]{.pill .info}.",
          '<span class="pill high"><strong>alta</strong></span>',
          '<span class="pill info"><em>baja</em></span>')
    holds("pill: a mixed label keeps the words AROUND the code span too",
          "Estado [a `x` b]{.chip tone=kill} aquí.",
          '<span class="chip kill">a <code>x</code> b</span>')

    print()
    print("== an item's options are read with the code fences tracked ==")
    # `_split_options` was the third line-scanner over one text and the only one
    # blind to ``` fences: a bullet-shaped line inside a code block BEFORE the
    # option list became a radio button, the real options degraded into a <pre>,
    # and check-artifact passed the page. The reader answered a question that
    # was never asked.
    FENCED = ('::: group {#G1 title="T"}\n'
              '::: item {#Q1 title="t"}\n'
              "¿Qué comando corro?\n\n"
              "```bash\n$ git log --oneline\n- rm -rf /tmp/x\n- ls\n```\n\n"
              "- Sí, correrlo {recommended}\n- No\n:::\n:::\n")
    fenced = holds("item: a bullet inside a ``` fence is CODE, not an option",
                   FENCED,
                   '<pre><code class="lang-bash">$ git log --oneline\n'
                   "- rm -rf /tmp/x\n- ls</code></pre>",
                   '<input type="radio" name="Q1" data-label="Sí, correrlo" '
                   "data-recommended>",
                   '<input type="radio" name="Q1" data-label="No">')
    check("item: the code lines reach no data-label and no radio",
          'data-label="rm -rf /tmp/x"' not in fenced
          and 'data-label="ls"' not in fenced, fenced)
    check("item: the real options are not degraded into a <pre>",
          "- Sí, correrlo" not in fenced, fenced)
    holds("item: a ``` fence AFTER the options still renders as code",
          '::: group {#G1 title="T"}\n::: item {#Q1 title="t"}\n?\n\n'
          "- A\n- B\n\n```diff\n- old\n+ new\n```\n:::\n:::\n",
          '<input type="radio" name="Q1" data-label="A">',
          '<pre><code class="lang-diff">- old\n+ new</code></pre>')
    holds("item: a ~~~ fence is tracked by its own marker, like md_body's",
          '::: group {#G1 title="T"}\n::: item {#Q1 title="t"}\n?\n\n'
          "~~~\n- no es opción\n~~~\n\n- A\n- B\n:::\n:::\n",
          '<input type="radio" name="Q1" data-label="A">',
          "<pre><code>- no es opción</code></pre>")

    print()
    print("== the gallery unit, generated by gallery_items.py and not re-implemented ==")
    rows = {"gallery": "audit",
            "tiles": ["light-desktop", "dark-mobile"],
            "rows": [{"cell": "with-data",
                      "tiles": {"light-desktop": "shots/ld/audit-with-data.png",
                                "dark-mobile": "shots/dm/audit-with-data.png"}},
                     {"cell": "no-permission",
                      "notApplicable": "El rol siempre tiene el permiso."}]}
    with open(os.path.join(tmp, "rows.json"), "w", encoding="utf-8") as fh:
        json.dump(rows, fh)

    # gallery_items opens every tile (a missing capture is refused, the PNG
    # header gives the <img> its width and height), so each root is real.
    def captures(root):
        for rel in ("shots/ld/audit-with-data.png", "shots/dm/audit-with-data.png"):
            os.makedirs(os.path.dirname(os.path.join(root, rel)), exist_ok=True)
            subprocess.run([sys.executable, os.path.join(HERE, "png_fixture.py"),
                            os.path.join(root, rel), "16", "9"], check=True)
    checkout = os.path.realpath(os.path.join(tmp, "checkout"))
    captures(checkout)
    gal = holds("gallery: one consult-item per row, the matrix on the block",
                '::: gallery {#E title="Galería audit" rows="rows.json" '
                'root="%s"}\n:::' % checkout,
                '<section class="consult-group" id="E" data-id="E" '
                'data-title="Galería audit" data-tiles="light-desktop dark-mobile">',
                '<section class="consult-item consult-gallery" '
                'data-id="audit-with-data" data-title="audit · with-data">',
                '<figure data-tile="light-desktop"><img '
                'src="file://%s/shots/ld/audit-with-data.png"' % checkout,
                '<p class="gal-na">El rol siempre tiene el permiso.</p>',
                base_dir=tmp)
    check("gallery: rows= is relative to the SPEC, not to the cwd", bool(gal))

    # `root` defaults to the CHECKOUT ROOT, not to the spec's directory. The
    # rows document's tile paths are relative to the checkout (gallery_items
    # refuses an absolute one), so the old default made every tile of every spec
    # outside the checkout root — including `.context/decisions/`, where the one
    # shipped gallery page lives — a file:// URL to nothing, with the gate green
    # because no checker stats a linked image.
    repo = os.path.join(tmp, "repo")
    specdir = os.path.join(repo, ".context", "specs")
    os.makedirs(specdir)
    with open(os.path.join(specdir, "rows.json"), "w", encoding="utf-8") as fh:
        json.dump(rows, fh)
    gitrc = subprocess.run(["git", "init", "-q", repo],
                           capture_output=True, text=True).returncode
    captures(repo)
    GAL_SPEC = ('::: gallery {#E title="Galería audit" rows="rows.json"}\n:::')
    if gitrc == 0:
        real = os.path.realpath(repo)
        html = holds("gallery: root defaults to the CHECKOUT root, not the "
                     "spec's directory", GAL_SPEC,
                     'src="file://%s/shots/ld/audit-with-data.png"' % real,
                     base_dir=specdir)
        check("gallery: no tile is resolved against the spec's own directory",
              ".context/specs/shots" not in html, html)
        holds("gallery: an explicit root= still overrides the default",
              '::: gallery {#E title="G" rows="rows.json" root="%s"}\n:::' % checkout,
              'src="file://%s/shots/ld/audit-with-data.png"' % checkout,
              base_dir=specdir)
    else:
        fail("gallery: `git init` failed in the temp dir, so the checkout-root "
             "default could not be exercised")
    outside = os.path.join(tmp, "outside")
    os.makedirs(outside)

    print()
    print("== build() raises the documented exceptions and nothing else ==")
    # `gallery_items` is a CLI module: its refusals call `die()`, which raises
    # SystemExit — a BaseException that escaped `build()` uncatchably, so no
    # caller could report a bad rows file and no gallery refusal was testable
    # (this file's own `rejects` catches SpecBuildError). The claim is the
    # library contract, asserted over every bad shape that reaches a
    # non-SpecBuildError path.
    with open(os.path.join(tmp, "broken.json"), "w", encoding="utf-8") as fh:
        fh.write("{not json")
    with open(os.path.join(tmp, "noroot.json"), "w", encoding="utf-8") as fh:
        json.dump({"gallery": "a", "tiles": ["t"],
                   "rows": [{"cell": "c", "tiles": {"t": "/abs/x.png"}}]}, fh)
    BAD = [
        ("an NBSP-only attr group (a paste out of a rendered page)",
         "::: note {\xa0}\nhola\n:::\n", tmp),
        ("a form feed in the attr group", "::: note {\x0c}\n:::\n", tmp),
        ("a gallery whose rows= file is missing",
         '::: gallery {#E title="G" rows="gone.json"}\n:::', tmp),
        ("a gallery whose rows= JSON is malformed",
         '::: gallery {#E title="G" rows="broken.json"}\n:::', tmp),
        ("a gallery whose rows JSON breaks gallery_items' own rules",
         '::: gallery {#E title="G" rows="noroot.json"}\n:::', tmp),
        ("a gallery with no rows= at all", '::: gallery {#E title="G"}\n:::', tmp),
        ("a gallery outside any checkout, with no root=",
         '::: gallery {#E title="G" rows="rows.json"}\n:::', outside),
        ("an unknown block type", "::: chrt\nx\n:::\n", tmp),
        ("a `::: prose` fence", "::: prose\nx\n:::\n", tmp),
        ("an unclosed block", "::: note\nx\n", tmp),
    ]
    for label, spec, where in BAD:
        try:
            build(spec, base_dir=where)
        except (SpecSyntaxError, SpecBuildError) as exc:
            check("%s is refused as %s, with line %d"
                  % (label, type(exc).__name__, exc.line), exc.line >= 1,
                  exc.message)
        except BaseException as exc:              # noqa: BLE001 — the claim
            fail("%s: raised %s(%s) — build() promises SpecSyntaxError or "
                 "SpecBuildError, and a SystemExit cannot even be caught by a "
                 "caller's `except Exception`"
                 % (label, type(exc).__name__, exc))
        else:
            fail("%s: built without a word" % label)

    print()
    print("== the builder's half of the two-layer split ==")
    rejects("an unknown block type names the alternatives",
            "::: chrt {#c1}\nx\n:::", 1, "unknown block type")
    # `chart` WAS this case in Phase 1 and is registered since Phase 2, so the
    # absence claim moved to `diagram`, the next type through the same seam
    # (Phase 6). A registered `chart` still refuses this spec — with its own
    # message, from the other side of the split — and that is asserted in
    # test_chart.py, not here.
    # The escape the corpus conversion had to add. Both markers were EATEN on a
    # page `check-artifact` passes: `.context/worklists/_archive/*-report.md`
    # shipped as `.context/worklists/archive/-report.md` with an `<em>` in the
    # middle. Backticks were the workaround, and they are a monospace font the
    # author did not ask for.
    holds("a backslash escapes `_` and `*` in prose",
          "::: note\n.context/worklists/\\_archive/\\*-report.md\n:::",
          ".context/worklists/_archive/*-report.md")
    check("…and the escaped text carries no <em>",
          "<em>" not in BUILT[-1][1], BUILT[-1][1])
    holds("a backslash escapes a backtick, so no code span opens",
          "::: note\nejecutó \\`0013\\`.\n:::", "ejecutó `0013`.")
    check("…and no <code> was opened by the escaped pair",
          "<code>" not in BUILT[-1][1], BUILT[-1][1])
    holds("inside a code span the backslash is literal (CommonMark)",
          "::: note\n`a\\_b`\n:::", "<code>a\\_b</code>")
    holds("an UNescaped backtick pair still makes a code span",
          "::: note\nel `0013` de siempre\n:::", "<code>0013</code>")
    holds("`\\[` keeps a bracket out of the pill/chip span syntax",
          "::: note\n\\[x]{.pill .high}\n:::", "&#91;x]{.pill .high}")
    check("…and no <span class=\"pill\"> was emitted",
          'class="pill' not in BUILT[-1][1], BUILT[-1][1])

    # Phase 6 registered `diagram`, so the line that used to read "not
    # registered yet" now asserts the opposite: the dispatch KNOWS it, and what
    # it refuses is the missing `shape`, at the fence's line. Everything about
    # its body is `test_diagram.py`'s; what belongs here is that the seam took.
    check("`diagram` is registered in the dispatch (Phase 6)",
          "diagram" in spec_build.EMITTERS, str(sorted(spec_build.EMITTERS)))
    rejects("...and a `diagram` with no shape is refused at the fence's line",
            "::: diagram {#d1}\na: x\n:::", 1, "there is no default")
    rejects("an unknown attr key names what the type does take",
            '::: note {wat="x"}\ny\n:::', 1, "takes no attr")
    rejects("a missing required attr", "::: group {#G1}\nx\n:::", 1, "title")
    rejects("a missing #id", '::: group {title="T"}\nx\n:::', 1, "#id")
    # `title` and `heading` are two strings with two audiences: `data-title` is
    # the rail entry and the head of the composed reply, the `<h2>` is the
    # sentence this round found. Most corpus blocks write both, and they differ.
    holds("`group` heading= is the h2 and title= stays the data-title",
          '::: group {#G1 title="Corto" heading="La frase larga que encontró '
          'esta ronda"}\nx\n:::',
          'data-title="Corto"', '<h2>La frase larga que encontró esta ronda</h2>')
    holds("`group` without heading= puts the title in the h2",
          '::: group {#G1 title="Corto"}\nx\n:::',
          'data-title="Corto"', '<h2>Corto</h2>')
    # NOT a refusal since Phase 3, and the reason is one owner per rule.
    # 4 of the 30 sampled corpus pages write a decision outside any block, so a
    # spec that cannot say it cannot convert them. The rule itself is
    # check_artifact.py's `check_shape`, which fails the built page by name and
    # cites § 8.4, and `wrap-report.sh --out` runs it before the page lands —
    # so this builds, and it still cannot SHIP. If this ever starts refusing
    # again, the corpus conversion of those four pages is what breaks.
    holds("an item outside any block BUILDS — consult-shape owns that rule",
          '::: item {#Q1 title="T"}\n?\n:::',
          '<section class="consult-item" data-id="Q1"')
    # 3 of the 30 sampled pages put a framed aside inside a decision, and the
    # aside keeps the POSITION it was written in: between the question and the
    # options, not pushed below them.
    h = holds("`item` carries a nested note where it was written",
              '::: item {#Q1 title="T"}\n?\n\n::: note\nOjo\n:::\n\n'
              '- a\n- b\n:::',
              '<div class="note">Ojo</div>', '<div class="opts one">')
    check("the nested note comes BEFORE the options it qualifies",
          h.find('class="note"') < h.find('class="opts'),
          "the aside was pushed below the options")
    # G3. A sampled page closes an aside with a quieter one inside it.
    h = holds("a `note` carries a nested `note`, in the position it was written",
              "::: note\nEl env\u00edo qued\u00f3 confirmado.\n\n::: note {.warn}\n"
              "Salvo una cosa.\n:::\n:::",
              '<div class="note warn">Salvo una cosa.</div>')
    check("...and the outer note keeps its own prose ABOVE the nested one",
          h.index("El env\u00edo") < h.index("Salvo una cosa"), h)
    check("...and an outer note holding a nested one is not unwrapped into "
          "bare text: `_unwrap_p` cannot match a body ending in `</div>`",
          '<div class="note"><p>El env\u00edo qued\u00f3 confirmado.</p>' in h, h)
    # G4. A sampled page's masthead opens with two.
    h = holds("a `masthead` carries a framed aside, after its standfirst",
              '::: masthead {eyebrow="E"}\n# T\n\nEl resumen.\n\n'
              "::: note\nDos avisos ya resueltos.\n:::\n:::",
              '<p class="standfirst">El resumen.</p>',
              '<div class="note">Dos avisos ya resueltos.</div>')
    check("...and the aside sits BELOW the standfirst it followed, not above",
          h.index('class="standfirst"') < h.index('class="note"'), h)
    h = holds("...and an aside written FIRST does not steal the standfirst",
              '::: masthead\n# T\n\n::: note\nAviso.\n:::\n\nEl resumen.\n:::',
              '<div class="note">Aviso.</div>',
              '<p class="standfirst">El resumen.</p>')
    check("...the aside still comes first, where it was written",
          h.index('class="note"') < h.index('class="standfirst"'), h)
    # The CLI reads the masthead a SECOND time, for `<title>`, and it used to
    # read it with `_prose_lines` — which refuses an aside. `spec_build.py
    # <spec>` then died with "`masthead` cannot contain a `note` block" on a
    # page `build()` had just produced without complaint, and no in-process
    # test saw it because none of them goes through `page_title`.
    check("page_title reads a masthead that carries an aside",
          spec_build.page_title(
              '::: masthead\n\n::: note\nAviso.\n:::\n\n# T\n\nEl resumen.\n:::\n')
          == "T")
    rejects("a masthead still refuses a block that is not an aside",
            '::: masthead\n# T\n\n::: ledger\n- k — v\n:::\n:::',
            4, "cannot contain")
    rejects("a note still refuses a block that is not an aside",
            "::: note\nx\n\n::: ledger\n- k — v\n:::\n:::",
            4, "cannot contain")
    rejects("an item still refuses a block that is not an aside",
            '::: item {#Q1 title="T"}\n?\n\n::: ledger\n- k — v\n:::\n:::',
            4, "cannot contain")
    # A figure block qualifies THIS decision the way an aside does, so an item
    # nests one in written order. Only the item: a masthead or a note that
    # carried a drawing would be a page-level figure in the wrong place.
    h = holds("an item nests a figure block where it was written",
              '::: item {#Q1 title="T"}\n¿Cuál?\n\n'
              '::: diagram {shape=row}\na: uno\nb: dos\n:::\n\n'
              '- A — uno\n- B — dos\n:::',
              '<svg viewBox=', 'data-id="Q1"')
    check("...the drawing sits between the question and the options",
          h.index("¿Cuál?") < h.index("<svg") < h.index('type="radio"'), h)
    holds("an item nests a chart the same way",
          '::: item {#Q1 title="T"}\n¿Cuál?\n\n'
          '::: chart {type=bar}\nuno,1\ndos,2\n:::\n\n- A — uno\n:::',
          '<svg', 'data-id="Q1"')
    # Same rule as an aside written first: an item that opens with something
    # other than a paragraph asks its title, and keeps the paragraph below.
    h = holds("a figure written FIRST: the h3 asks the title, as an aside does",
              '::: item {#Q1 title="T"}\n::: diagram {shape=row}\na: uno\n:::\n\n'
              '¿Cuál?\n\n- A — uno\n:::',
              '<h3><span class="consult-id">Q1</span>T</h3>', '<p>¿Cuál?</p>')
    check("...and the figure stays above the paragraph it was written above",
          h.index("<svg") < h.index("<p>¿Cuál?</p>"), h)
    rejects("a masthead still refuses a figure block",
            '::: masthead\n# T\n\n::: diagram {shape=row}\na: uno\n:::\n:::',
            4, "cannot contain")
    rejects("a note still refuses a figure block",
            "::: note\nx\n\n::: diagram {shape=row}\na: uno\n:::\n:::",
            4, "cannot contain")
    rejects("an item inside an item",
            '::: group {#G1 title="T"}\n::: item {#Q1 title="T"}\n'
            '::: item {#Q2 title="T"}\n?\n:::\n:::\n:::', 3, "may only appear in")
    rejects("a section with no #id — the rail indexes `.main > section[id]`",
            '::: section {heading="H"}\nx\n:::', 1, "needs an #id")
    rejects("a section with no heading — a sec-head with no h2 is not one",
            "::: section {#s1}\nx\n:::", 1, "heading")
    rejects("a section inside a section",
            '::: section {#s1 heading="H"}\n'
            '::: section {#s2 heading="H"}\nx\n:::\n:::', 2,
            "may only appear in")
    rejects("a group inside a section — a group is the page's own child",
            '::: section {#s1 heading="H"}\n::: group {#G1 title="T"}\n'
            '::: item {#Q1 title="T"}\n?\n:::\n:::\n:::', 2,
            "may only appear in")
    rejects("a group inside a group",
            '::: group {#G1 title="T"}\n::: group {#G2 title="T"}\n'
            '::: item {#Q1 title="T"}\n?\n:::\n:::\n:::', 2, "may only appear in")
    rejects("`pill` as a fence says where a pill really goes",
            "::: pill {tone=high}\nalta\n:::", 1, "inline")
    rejects("`num` as a fence says it is a column marker",
            "::: num\n| n |\n:::", 1, "separator row")
    # G2. It used to be refused. `check_artifact.ledger_ids` names the key-less
    # grid a legitimate `.ledger` in its own docstring, so the refusal made a
    # page the CONTRACT accepts unbuildable — and 3 of the 30 sampled pages
    # write one.
    rejects("a ledger body that is not a list",
            "::: ledger\nprosa suelta\n:::", 1, "list of")
    rejects("win= naming no cell of the verdict",
            '::: verdict {win="Nadie"}\n| n | ruta |\n|---|---|\n| 3 | DOT |\n:::',
            1, "names no cell")
    rejects("a body on a block that takes none",
            '::: notes {title="N"}\ntexto\n:::', 1, "takes no body")
    # The line number a REFUSAL carries is the spec's, not the rendered page's:
    # the author edits the spec.
    # `prose` is the type the tokenizer gives a fence-less run, which also made
    # it a spellable fence name — and a fence node holds its body in a prose
    # CHILD, so `emit_prose` rendered `node.text` ("") and the whole body left
    # the page with no error and no line number, on a page check-artifact then
    # passed. 04-block-vocabulary.md says prose is "Not a fence."; the builder
    # now says it too, in all four places a fence can sit.
    rejects("`::: prose` is refused at the top level, never silently emptied",
            "::: prose\nEsto se pierde entero.\n\n- y la lista\n:::\n",
            1, "not a fence")
    rejects("`::: prose` inside a group is refused at ITS line",
            '::: group {#G1 title="T"}\n::: item {#Q1 title="t"}\n?\n:::\n'
            "::: prose\nx\n:::\n:::\n", 5, "not a fence")
    rejects("`::: prose` inside a prose-bodied block is refused",
            "::: note\n::: prose\nx\n:::\n:::\n", 2, "not a fence")
    rejects("`::: prose` inside a block that takes no body is refused",
            '::: notes {title="N"}\n::: prose\nx\n:::\n:::\n', 2, "not a fence")
    rejects("a masthead that writes its title twice",
            '::: masthead {title="Attr"}\n# Body\n\nS\n:::', 1, "ONCE")
    rejects("a gallery whose rows= file does not exist",
            '::: gallery {#E title="G" rows="no-such.json" root="/abs"}\n:::',
            1, "no such rows file")

    rejects("the refusal carries the line of the offending FENCE, deep in a page",
            "prosa\n\n::: callout\nx\n:::\n\n::: note\ny\n:::\n\n"
            '::: group {#G1}\nz\n:::\n', 11, "title")

    print()
    print("== inline links: [text](target) ==")
    # The blind-review page (experiments/2026-09-24-artifact-route-ab/review/
    # gen_review.py) had to patch its HTML after the build because the grammar
    # had no link: a spec could not point at a sibling page.
    holds("a link to a sibling page renders as <a href>",
          "Abre [R1](R1.html) y puntúala.", '<a href="R1.html">R1</a>')
    holds("a #fragment link", "Ver [el bloque](#G1).",
          '<a href="#G1">el bloque</a>')
    holds("an https: link, its & escaped in the attribute",
          "La [fuente](https://example.com/a?b=1&c=2).",
          '<a href="https://example.com/a?b=1&amp;c=2">fuente</a>')
    holds("a relative path with directories",
          "Ver [la nota](../research/nota.html#s2).",
          '<a href="../research/nota.html#s2">la nota</a>')
    holds("an underscore in the target is not read as emphasis",
          "Ver [by_model](by_model_v2.html) y _esto_.",
          '<a href="by_model_v2.html">by_model</a>', "<em>esto</em>")
    holds("a code span as the label is still code",
          "Ver [`R1`](R1.html).", '<a href="R1.html"><code>R1</code></a>')
    holds("emphasis in the label is rendered",
          "Ver [**R1**](R1.html).", '<a href="R1.html"><strong>R1</strong></a>')
    holds("one level of parentheses in an https: target is kept",
          "La [página](https://en.wikipedia.org/wiki/Ley_(física)).",
          '<a href="https://en.wikipedia.org/wiki/Ley_(física)">página</a>')
    holds("a link inside backticks stays literal code",
          "Escribe `[R1](R1.html)` así.", "<code>[R1](R1.html)</code>")
    check("…and no <a> was emitted for it", "<a " not in BUILT[-1][1],
          BUILT[-1][1])
    holds("an escaped bracket is not a link",
          "Literal \\[R1](R1.html) aquí.", "&#91;R1](R1.html)")
    check("…and no <a> was emitted for it", "<a " not in BUILT[-1][1],
          BUILT[-1][1])
    holds("a link in an item body, the blind-review shape",
          '::: group {#G1 title="T"}\n::: item {#R1 title="R1"}\n'
          "Abre [R1](R1.html) y puntúala.\n\n- 1\n- 2\n:::\n:::\n",
          '<a href="R1.html">R1</a>')
    holds("a refused scheme inside a code fence is code, not a refusal",
          "```\n[x](javascript:alert(1))\n```\n", "[x](javascript:alert(1))")
    rejects("javascript: is refused, with the line it is on",
            "prosa\n\nVer [x](javascript:alert(1)).\n", 3, "javascript:")
    rejects("JavaScript: in any case is refused",
            "Ver [x](JavaScript:alert(1)).", 1, "refused")
    rejects("data: is refused", "prosa\n[x](data:text/html,hola)\n", 2, "data:")
    holds("http: is allowed (Phase 5 review: it carries no script)",
          "[x](http://example.com)", '<a href="http://example.com">x</a>')
    holds("mailto: is allowed", "[yo](mailto:a@b.c)", '<a href="mailto:a@b.c">yo</a>')
    rejects("file: is refused", "[x](file:///etc/passwd)", 1, "file:")
    rejects("a backslash escape in a target is refused by the builder, as "
            "_inline refuses it (same tokenisation)", "[x](a\\_b.html)", 1,
            "refused")
    rejects("a backslash-backslash target is refused by the builder",
            "[a](\\\\evil.com)", 1, "refused")
    rejects("a link in title= is refused: the rail and the decided summary "
            "show the title raw",
            '::: group {#G1 title="T"}\n::: item {#Q1 title="Ver [R1](R1.html)"}\n'
            "?\n:::\n:::\n", 2, "title=")
    rejects("a protocol-relative //host is refused",
            "[x](//example.com/a)", 1, "refused")
    rejects("a refused link deep in a block names its own line, not the fence's",
            '::: group {#G1 title="T"}\n::: item {#Q1 title="T"}\nuno\n'
            "dos [x](javascript:void(0))\n:::\n:::\n", 4, "javascript:")
    rejects("a refused link in an attr is refused at the fence line",
            '::: section {#s1 heading="Ver [x](data:,a)"}\nx\n:::\n', 1,
            "data:")
    import md_body                                  # noqa: E402
    for bad in ("javascript:alert(1)", "\x01javascript:alert(1)",
                "java\tscript:x", "data:text/html,x", "vbscript:x",
                "\\\\evil.example/x", "//evil.example/x", "file:///x"):
        check("_inline never emits an href for %r" % bad,
              "href" not in md_body._inline("[x](%s)" % bad),
              md_body._inline("[x](%s)" % bad))

    print()
    print("== check-artifact fails a raw [x](y) left in the visible text ==")
    wrap = os.path.join(SCRIPTS, "wrap-report.sh")

    def contract(label, body):
        src = os.path.join(tmp, label + ".body")
        with open(src, "w", encoding="utf-8") as fh:
            fh.write(body)
        r = subprocess.run(["bash", wrap, "--title", "t", "--lang", "es",
                            "--in", src], capture_output=True, text=True,
                           cwd=tmp)
        page = os.path.join(tmp, label + ".html")
        with open(page, "w", encoding="utf-8") as fh:
            fh.write(r.stdout)
        return subprocess.run(["bash", CHECK, page], capture_output=True,
                              text=True)

    review = ('::: masthead {eyebrow="Revisión ciega" lang="es" visual="none: '
              'solo enlaza"}\n# Revisión ciega de páginas\n\nPuntúa cada '
              'página que se abre desde su bloque, según lo útil que es para '
              'lo que se pidió.\n:::\n\n'
              '::: group {#GR title="Informe" heading="R1: informe"}\n'
              "**Lo que se pidió:** un informe de la nota.\n\n"
              '::: item {#R1 title="R1"}\nAbre [R1](R1.html) y puntúala.\n\n'
              "- 1 — no sirve\n- 5 — excelente\n:::\n:::\n\n"
              '::: notes {title="Comentario general"}\n:::\n')
    linked = build(review)
    r = contract("linked", linked)
    check("the built review page passes check-artifact",
          r.returncode == 0, r.stdout + r.stderr)
    # The pre-fix shape: the same page as the builder emitted it before inline
    # links existed, the markdown shipped to the reader as text.
    raw = linked.replace('<a href="R1.html">R1</a>', "[R1](R1.html)")
    check("(the pre-fix shape carries the literal link)",
          "[R1](R1.html)" in raw and raw != linked)
    r = contract("raw", raw)
    check("check-artifact FAILS the pre-fix shape with [raw-link]",
          r.returncode != 0 and "[raw-link]" in r.stdout + r.stderr,
          r.stdout + r.stderr)
    check("…and names the raw link it saw", "[R1](R1.html)" in r.stdout + r.stderr,
          r.stdout + r.stderr)
    escaped = build(review.replace("Abre [R1](R1.html)", "Abre \\[R1](R1.html)"))
    check("(the escaped bracket builds no <a>)", '<a href="R1.html"' not in escaped)
    r = contract("escaped", escaped)
    check("a documented `\\[` escape passes check-artifact (no raw-link)",
          r.returncode == 0, r.stdout + r.stderr)
    r = contract("coded", linked.replace('<a href="R1.html">R1</a>',
                                         "<code>[R1](R1.html)</code>"))
    check("a raw link shown as <code> is not flagged — that is the author "
          "quoting the syntax", r.returncode == 0, r.stdout + r.stderr)

    print()
    print("== the built page passes check-artifact.sh, unmodified ==")
    out = os.path.join(tmp, "page.html")
    r = subprocess.run([sys.executable, BUILD, spec_path, "-o", out, "--check"],
                       capture_output=True, text=True)
    check("spec_build.py -o --check exits 0", r.returncode == 0,
          r.stdout + r.stderr)
    check("the page exists and carries the kit", os.path.isfile(out)
          and "artifact-kit" in open(out, encoding="utf-8").read())
    r = subprocess.run(["bash", CHECK, out], capture_output=True, text=True)
    check("check-artifact.sh passes it on its own, with no exemption",
          r.returncode == 0, r.stdout + r.stderr)
    check("...and prints no WARN either", "WARN" not in (r.stdout + r.stderr),
          r.stdout + r.stderr)
    page = open(out, encoding="utf-8").read()
    for ident in ("G1", "Q1", "Q2", "notes"):
        check("the WRAPPED page still carries id %r byte-exactly" % ident,
              ('data-id="%s"' % ident) in page)

    print()
    print("== no built page ever ships a NUL byte ==")
    # U+0000 is `md_body._inline`'s stash sentinel and it is invalid in HTML.
    # It reached a DELIVERED page — `<span class="chip chip-kill">\x000\x00</span>`,
    # the author's identifier gone — and check-artifact.sh passed it. The
    # assertion is general on purpose: over every page this file built, not a
    # case written for the pill that found it. A NUL in the OUTPUT means the
    # restore did not finish, whatever the construct was.
    BUILT.append(("the wrapped page on disk",
                  open(out, "rb").read().decode("utf-8", "surrogateescape")))
    BUILT.append(("a NUL written by the AUTHOR is dropped, not carried",
                  build("Un \x00 suelto y [`x`]{.pill} al lado.")))
    dirty = [label for label, html in BUILT if "\x00" in html]
    check("every page built here holds zero \\x00 bytes (%d pages)" % len(BUILT),
          not dirty, "NUL in: %r" % dirty)

    print()
    print("== the CLI ==")
    r = subprocess.run([sys.executable, BUILD, spec_path], capture_output=True,
                       text=True)
    check("no -o writes the BODY to stdout", r.returncode == 0
          and r.stdout.startswith('<meta name="consult-visual"')
          and "<!doctype" not in r.stdout.lower())
    bad = os.path.join(tmp, "bad.spec.md")
    with open(bad, "w", encoding="utf-8") as fh:
        fh.write("prosa\n\n::: item {#a #b}\n:::\n")
    r = subprocess.run([sys.executable, BUILD, bad], capture_output=True, text=True)
    check("a malformed spec exits 1 and names <file>:<line>",
          r.returncode == 1 and ":3:" in r.stderr, r.stderr)
    r = subprocess.run([sys.executable, BUILD, spec_path, "--check"],
                       capture_output=True, text=True)
    check("--check without -o is a usage error (exit 2)", r.returncode == 2,
          r.stderr)

    print()
    print("== the page's language is the page's, not the command's ==")
    # 2 of the 30 sampled pages are English. With the language fixed at the
    # CLI's `es` default they built into `<html lang="es">` over an English
    # body, which check_artifact's `lang` rule fails (BL-279) — on pages whose
    # ORIGINALS pass it. `corpus:` cannot see it: the judge compares ids and
    # visible text, and <html lang> is neither.
    check("spec_lang reads the masthead's declaration",
          spec_build.spec_lang('::: masthead {lang="en"}\n# T\n\nS\n:::\n')
          == "en")
    check("spec_lang is \"\" when no masthead declares one",
          spec_build.spec_lang("::: masthead\n# T\n\nS\n:::\n") == "")
    check("the declaration wins over the lang= argument",
          "Copy" in build('::: masthead {lang="en"}\n# T\n\nS\n:::\n'
                          '::: notes {title="n"}\n:::\n', lang="es"))
    check("...and the argument still decides when the spec is silent",
          "Copiar" in build("::: masthead\n# T\n\nS\n:::\n"
                            '::: notes {title="n"}\n:::\n', lang="es"))
    rejects("a masthead lang= outside the known set",
            '::: masthead {lang="fr"}\n# T\n\nS\n:::\n', 1, "is not one of")
    en_spec = os.path.join(tmp, "en.spec.md")
    with open(en_spec, "w", encoding="utf-8") as fh:
        fh.write('::: masthead {lang="en" visual="none: a format decision has '
                 'no shape to draw"}\n# An English page\n\nThe body is in '
                 "English, and so is the page.\n:::\n\n"
                 '::: notes {title="General notes"}\n:::\n')
    en_out = os.path.join(tmp, "reports", "en.html")
    r = subprocess.run([sys.executable, BUILD, en_spec, "-o", en_out],
                       capture_output=True, text=True)
    check("an English spec wraps into <html lang=\"en\"> and passes the "
          "contract", r.returncode == 0
          and os.path.exists(en_out)
          and '<html lang="en">' in open(en_out, encoding="utf-8").read(),
          r.stdout + r.stderr)

    print()
    print("== the registration seam Phases 2 and 6 plug into ==")
    # The probe type is a NAME NOBODY OWNS, not `chart`: Phase 2 registered
    # `chart` through this very seam, so asserting its absence would now assert
    # that the seam went unused. `diagram` (Phase 6) is the next one through and
    # is not borrowed here for the same reason.
    check("register() adds a type without reshaping anything",
          "zz-probe" not in spec_build.EMITTERS)
    spec_build.register("zz-probe", lambda node, ctx: "<div>PROBE</div>")
    try:
        check("a registered type builds through the same dispatch",
              "<div>PROBE</div>" in build("::: zz-probe {#c1 kind=bar}\n| a |\n:::"))
    finally:
        del spec_build.EMITTERS["zz-probe"]
    check("`chart` arrived through that same seam (Phase 2)",
          "chart" in spec_build.EMITTERS)
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print()
if failures:
    print("%d failure(s)" % len(failures))
    raise SystemExit(1)
print("OK — the build: determinism across processes, exact id preservation, "
      "every block type's kit markup, options read with the code fences "
      "tracked, the builder's refusals with their spec line, build()'s two "
      "exception types and nothing else, zero NUL bytes in every page built "
      "here, the gallery unit and its checkout root, the CLI, and a built page "
      "through check-artifact.sh unmodified")
