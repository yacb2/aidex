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
import struct
import subprocess
import sys
import tempfile
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
SCRIPTS = os.path.join(SKILL, "scripts")
sys.path.insert(0, SCRIPTS)
sys.path.insert(0, os.path.join(SCRIPTS, "dash"))

import contract_defects                          # noqa: E402
import spec_build                                 # noqa: E402
from spec_build import SpecBuildError, build      # noqa: E402
from spec_parser import SpecSyntaxError           # noqa: E402

BUILD = os.path.join(SCRIPTS, "spec_build.py")
CONTRACT = os.path.join(SCRIPTS, "dash", "contract_defects.py")
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


def rejects(label, spec, line, needle="", **kw):
    """The spec builds to nothing and the refusal names `line`."""
    try:
        build(spec, **kw)
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

::: item {#Q3 title="Bloques a documentar" select=many}
¿Qué bloques entran en la referencia?

- Tabla {recommended}
- Figura {recommended}
- Galería — solo si hay capturas
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
    # BL-477: a `# ` comment inside a fenced command is not the masthead title.
    holds("masthead: a `# ` line inside a fence is code, not a second title",
          '::: masthead {title="T"}\nS\n\n```bash\n# install\nls\n```\n:::',
          "<h1>T</h1>", '<pre><code class="lang-bash"># install\nls</code></pre>')
    check("page_title skips a `# ` line inside a fence",
          spec_build.page_title('::: masthead\n```bash\n# install\n```\n\n'
                                '# Real\n\nS\n:::\n') == "Real")
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
    # BL-514: the consult contract makes the first paragraph a situation lead
    # that ENDS in the question, and the whole lead used to become the bold h3.
    # The h3 keeps only the closing question; the situation is body text.
    h = holds("item: a situation lead leaves only its closing question in the h3",
              ITEM.replace("¿La pregunta, preguntada?",
                           "Ana, observadora, silencia una pista. Hoy recibe un "
                           "error. ¿Debe poder hacerlo?"),
              '<h3><span class="consult-id">Q1</span>¿Debe poder hacerlo?</h3>',
              '<p class="consult-lead">Ana, observadora, silencia una pista. '
              'Hoy recibe un error.</p>')
    check("...and the situation reads between the question and the options",
          -1 < h.find("</h3>") < h.find("consult-lead") < h.find('type="radio"'), h)
    holds("item: a one-sentence lead stays whole in the h3",
          ITEM.replace("¿La pregunta, preguntada?", "El Sr. López lo pidió."),
          '<h3><span class="consult-id">Q1</span>El Sr. López lo pidió.</h3>')
    holds("item: a situation with no closing question asks the title",
          ITEM.replace("¿La pregunta, preguntada?",
                       "Ana silencia una pista. Hoy recibe un error."),
          '<h3><span class="consult-id">Q1</span>Short name</h3>',
          '<p class="consult-lead">Ana silencia una pista. Hoy recibe un error.</p>')
    holds("item: an abbreviation does not split the question",
          ITEM.replace("¿La pregunta, preguntada?",
                       "Hoy falla. ¿Lo cierra el Sr. López?"),
          '<h3><span class="consult-id">Q1</span>¿Lo cierra el Sr. López?</h3>',
          '<p class="consult-lead">Hoy falla.</p>')
    holds("item: a run of closing questions stays together in the h3",
          ITEM.replace("¿La pregunta, preguntada?",
                       "Hoy falla. ¿Lo cerramos? ¿O esperamos?"),
          '<h3><span class="consult-id">Q1</span>¿Lo cerramos? ¿O esperamos?</h3>',
          '<p class="consult-lead">Hoy falla.</p>')
    holds("item: the option list becomes `.opts one` with data-label and a hint",
          ITEM.replace(" decided=yes", ""),
          '<div class="opts one">',
          '<input type="radio" name="Q1" data-label="Sí, cerrar" data-recommended>',
          '<span>Sí, cerrar <span class="hint">los doce ajustes son menores</span></span>',
          '<input type="radio" name="Q1" data-label="No, uno cambia el resultado">')
    holds("item: the notes box is injected on every item, never optional",
          ITEM, '<p class="fieldlabel">Notas sobre esto</p>', "<textarea ")
    # LOOP-006 decided-item-without-verdict: `decided=yes` shipped a bare
    # `data-decided` with nothing checked, and the composer's fold showed the
    # title alone. "yes" is a flag, not a verdict: the option that won is the
    # one the author recommended, and it carries `checked`.
    decided_item = holds("item: decided=yes checks the recommended option",
                         ITEM, 'data-label="Sí, cerrar" data-recommended checked>')
    check("item: ...and only that one",
          decided_item.count(" checked") == 1, decided_item)
    for flag in ("YES", "true", "1"):
        holds("item: decided=%s is the same flag, never a data-decided=\"%s\" "
              "verdict" % (flag, flag), ITEM.replace("decided=yes", 'decided="%s"' % flag),
              'data-title="Short name" data-decided>',
              'data-recommended checked>')
    rejects("item: decided=yes with no {recommended} option is refused",
            ITEM.replace(" {recommended}", ""), 2,
            "no option marked {recommended}")
    # Two checked radios in one name group: the parser keeps the last, and the
    # fold shows that one as the verdict with nothing on the page saying so.
    rejects("item: decided=yes on a select=one item with two {recommended} "
            "options is refused",
            ITEM.replace("- No, uno cambia el resultado",
                         "- No, uno cambia el resultado {recommended}"), 2,
            "more than one")
    holds("item: ...while select=many checks every recommended option",
          ITEM.replace("decided=yes", "decided=yes select=many").replace(
              "- No, uno cambia el resultado",
              "- No, uno cambia el resultado {recommended}"),
          'data-label="Sí, cerrar" data-recommended checked>',
          'data-label="No, uno cambia el resultado" data-recommended checked>')
    holds("item: a decided=\"<verdict>\" keeps its value and checks nothing",
          ITEM.replace("decided=yes", 'decided="Sí, en dos pasos"'),
          'data-decided="Sí, en dos pasos"')
    check("item: ...no option is pre-checked by a written verdict",
          " checked" not in build(ITEM.replace("decided=yes",
                                               'decided="Sí, en dos pasos"')))
    # BL-468: an item with no option list points at options that do not
    # exist when it gets the options placeholder, and one marked `free=yes`
    # carries the flag check-artifact reads to leave it unwarned.
    OPEN_ITEM = ('::: group {#G1 title="T"}\n'
                 '::: item {#H1 title="t" free=yes}\n¿Qué opinas?\n:::\n:::\n')
    open_item = holds("item: an optionless item gets the free-answer placeholder",
                      OPEN_ITEM, 'data-free>', '<textarea placeholder="Tu respuesta…">')
    check("item: ...and never the one that names options",
          "opciones" not in open_item, open_item)
    holds("item: an item WITH options keeps the options placeholder",
          ITEM, '<textarea placeholder="Lo que las opciones no cubren…">')
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
    # BL-481: the marker BEFORE the hint, and on a wrapped option whose last
    # line is not the marker's. Only the end-of-line shape was read, so both of
    # these shipped `{recommended}` as text with no data-recommended, past a
    # green --check (8 options on a real page, 2026-09-27).
    ITEM_MID = ('::: group {#G1 title="T"}\n'
                '::: item {#Q1 title="t"}\n?\n\n'
                "- Cerrar {recommended} — los ajustes son menores\n"
                "- Seguir {recommended}\n  — con un salto de línea\n"
                "- No\n:::\n:::\n")
    holds("item: {recommended} before the hint is still the recommendation",
          ITEM_MID,
          '<input type="radio" name="Q1" data-label="Cerrar" data-recommended>'
          '<span>Cerrar <span class="hint">los ajustes son menores</span></span>',
          '<input type="radio" name="Q1" data-label="Seguir" data-recommended>'
          '<span>Seguir <span class="hint">con un salto de línea</span></span>',
          '<input type="radio" name="Q1" data-label="No"><span>')
    check("item: ...and the marker never reaches the page",
          "{recommended}" not in BUILT[-1][1], BUILT[-1][1])
    # BL-454: a question whose answer is a SET. Only radios could be built, so
    # "which of these four go to the queue" let the reader tick one.
    MANY = ('::: group {#G1 title="T"}\n'
            '::: item {#Q1 title="t" select=many}\n?\n\n'
            "- Uno {recommended}\n- Dos {recommended} — con pista\n- Tres\n"
            ":::\n:::\n")
    many = holds("item: select=many builds a checkbox group in `.opts`",
                 MANY, '<div class="opts">',
                 '<input type="checkbox" name="Q1" data-label="Uno" '
                 'data-recommended><span>Uno</span>',
                 '<input type="checkbox" name="Q1" data-label="Dos" '
                 'data-recommended><span>Dos <span class="hint">con pista',
                 '<input type="checkbox" name="Q1" data-label="Tres"><span>')
    check("item: ...and no radio and no `.opts one` in a many item",
          'type="radio"' not in many and "opts one" not in many, many)
    holds("item: select=one is the default spelled out: radios",
          MANY.replace("select=many", "select=one"),
          '<div class="opts one">', '<input type="radio" name="Q1" data-label="Uno"')
    rejects("item: an unknown select= value is refused, naming the line",
            '::: group {#G1 title="T"}\n\n'
            '::: item {#Q1 title="t" select=several}\n?\n\n- A\n:::\n:::\n',
            3, "select")
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
    # BL-476: a fence glued to the bold-label line before it (no blank line) is
    # the shape a consultation item writes; md_body's paragraph loop swallowed it.
    glued = holds("item: a fence glued to a bold-label line is still a code block",
                  '::: group {#G1 title="T"}\n::: item {#Q1 title="t"}\n?\n\n'
                  "**Qué pasa hoy.**\n```python\nx = 1  # **no**\n```\n\n"
                  "- A\n- B\n:::\n:::\n",
                  "<p><strong>Qué pasa hoy.</strong></p>",
                  '<pre><code class="lang-python">x = 1  # **no**</code></pre>')
    check("item: no fence backticks leak out of the glued block",
          "``" not in glued, glued)
    # BL-477: an option cannot carry a code block. Folding an indented fence into
    # the option put backticks in its data-label; splitting there instead left
    # every later option as a plain <li>, unselectable, and check-artifact
    # passed both. The author is told where the code goes.
    rejects("item: an indented fence under an option is refused",
            '::: group {#G1 title="T"}\n::: item {#Q1 title="t"}\n?\n\n'
            "- A\n  ```\n  code\n  ```\n- B\n:::\n:::\n",
            2, "an option cannot carry a code block")
    # A title that repeats the id built, and only the wrap's check-artifact
    # (item-title-repeats-id) caught it afterwards. Refused at the fence with
    # contract_defects' own predicate: "X10 …" under X1 is another token.
    rejects("item: a title that repeats its id is refused at the fence line",
            '::: group {#G1 title="T"}\n::: item {#X1 title="X1 — foo"}\n?\n\n'
            "- A\n- B\n:::\n:::\n", 2, "repeats its id")
    holds("item: ...while a title that starts with ANOTHER token still builds",
          '::: group {#G1 title="T"}\n::: item {#X1 title="X10 foo"}\n?\n\n'
          "- A\n- B\n:::\n:::\n", 'data-title="X10 foo"')
    # The first `-` list is the options: an explanation list written before
    # the real ones became the radio buttons and the real options became prose,
    # their {recommended} shipped as literal text. Refused at the second list.
    EXPLAINED = ('::: group {#G1 title="T"}\n::: item {#Q1 title="t"}\n?\n\n'
                 "- why one\n- why two\n\nSo the options are:\n\n"
                 "- A {recommended}\n- B\n:::\n:::\n")
    rejects("item: a {recommended} on a list that is not the options is refused",
            EXPLAINED, 10, "number the explanation list")
    rejects("item: a second `-` list in an item is refused, marker or not",
            EXPLAINED.replace(" {recommended}", ""), 10,
            "only the first is its options")
    holds("item: ...while a numbered explanation list before the options builds",
          EXPLAINED.replace("- why one\n- why two", "1. why one\n2. why two"),
          '<input type="radio" name="Q1" data-label="A" data-recommended>',
          "<ol>")

    print()
    print("== the gallery unit, generated by gallery_items.py and not re-implemented ==")
    rows = {"gallery": "audit", "variants": ["light-desktop"],
            "rows": [{"cell": "with-data", "variant": "light-desktop",
                      "kind": "review",
                      "before": "shots/ld/audit-with-data.png",
                      "after": "actual/ld/audit-with-data.png"},
                     {"cell": "loaded", "variant": "dark-mobile",
                      "kind": "unrequested",
                      "before": "shots/dm/audit-loaded.png",
                      "after": "actual/dm/audit-loaded.png"}]}
    with open(os.path.join(tmp, "rows.json"), "w", encoding="utf-8") as fh:
        json.dump(rows, fh)

    # gallery_items opens every tile (a missing capture is refused, the PNG
    # header gives the <img> its width and height), so each root is real.
    def captures(root, width):
        for rel in ("shots/ld/audit-with-data.png", "actual/ld/audit-with-data.png",
                    "shots/dm/audit-loaded.png", "actual/dm/audit-loaded.png"):
            os.makedirs(os.path.dirname(os.path.join(root, rel)), exist_ok=True)
            subprocess.run([sys.executable, os.path.join(HERE, "png_fixture.py"),
                            os.path.join(root, rel), str(width), "9"], check=True)
    # Each root's captures have their own width, so the <img width> says which
    # root a tile was read from: the src names a content-addressed copy.
    checkout = os.path.realpath(os.path.join(tmp, "checkout"))
    captures(checkout, 16)
    galpage = os.path.join(tmp, "galpages", "gal.html")
    FIRST_TILE = ('<figure data-tile="before"><img '
                  'src="gal-assets/gallery/')
    gal = holds("gallery: one consult-item per row, the pair on the block",
                '::: gallery {#E title="Galería audit" rows="rows.json" '
                'root="%s"}\n:::' % checkout,
                '<section class="consult-group" id="E" data-id="E" '
                'data-title="Galería audit" data-tiles="before after">',
                '<section class="consult-item consult-gallery" '
                'data-id="audit-with-data-light-desktop" '
                'data-title="audit · with-data · light-desktop"',
                FIRST_TILE, 'width="16"',
                'data-id="audit-loaded-dark-mobile-unrequested"',
                '<p class="gal-flag">cambió sin que lo pidieras</p>',
                base_dir=tmp, page=galpage)
    check("gallery: rows= is relative to the SPEC, not to the cwd", bool(gal))
    # LOOP-006 img-src-portable: a body built with no page to land beside
    # linked every capture by file://, which pins the page to this machine and
    # to captures Playwright wipes. There is nowhere to copy them, so the
    # gallery is refused and the author is told to build with -o.
    rejects("gallery: a body with no page to copy the captures beside is refused",
            '::: gallery {#E title="G" rows="rows.json" root="%s"}\n:::'
            % checkout, 1, "build with -o", base_dir=tmp)

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
    captures(repo, 17)
    GAL_SPEC = ('::: gallery {#E title="Galería audit" rows="rows.json"}\n:::')
    if gitrc == 0:
        html = holds("gallery: root defaults to the CHECKOUT root, not the "
                     "spec's directory", GAL_SPEC, FIRST_TILE, 'width="17"',
                     base_dir=specdir, page=galpage)
        check("gallery: no tile is resolved against the spec's own directory",
              ".context/specs/shots" not in html, html)
        holds("gallery: an explicit root= still overrides the default",
              '::: gallery {#E title="G" rows="rows.json" root="%s"}\n:::' % checkout,
              FIRST_TILE, 'width="16"', base_dir=specdir, page=galpage)
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
        json.dump({"gallery": "a", "variants": ["light-desktop"],
                   "rows": [{"cell": "c", "variant": "light-desktop",
                             "kind": "review", "after": "/abs/x.png"}]}, fh)
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
    print("== an item's id is unique in the spec (group-item-id-collision) ==")
    # composer.js gives every item `id = data-id` at run time; a group or block
    # carrying the same id leaves two elements with it, and the rail link lands
    # on the group. Invisible on the source, so the builder refuses it.
    W1_ITEM = '::: item {#W1 title="t"}\n?\n\n- A {recommended}\n- B\n:::\n'
    rejects("a group whose id is its item's id is refused, naming both lines",
            '::: group {#W1 title="T"}\n%s:::\n' % W1_ITEM, 2, "line 1")
    rejects("a section whose id is an item's id is refused",
            '::: section {#W1 heading="H"}\n:::\n\n::: group {#G1 title="T"}\n'
            '%s:::\n' % W1_ITEM, 5, "line 1")
    rejects("two items sharing an id are refused",
            '::: group {#G1 title="T"}\n%s\n%s:::\n' % (W1_ITEM, W1_ITEM), 9,
            "line 2")
    holds("distinct ids build", '::: group {#G1 title="T"}\n%s:::\n' % W1_ITEM,
          'data-id="W1"')

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
    # An aside is a framed box: with no body it rendered as an empty bordered
    # bar (`<div class="note"></div>`) above the options of every item that
    # carried one, and the build still exited 0.
    rejects("an empty `note` inside an item is refused at ITS line",
            '::: item {#D2 title="X"}\nQuestion text?\n\n::: note\n:::\n\n'
            "- A {recommended}\n- B\n:::\n", 4, "empty")
    rejects("an empty `callout` is refused, blank lines are not a body",
            "::: callout\n\n:::\n", 1, "empty")
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
          '::: group {#G1 title="T"}\n::: item {#R1 title="Utilidad del informe"}\n'
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

    print()
    print("== an HTML entity in a spec is refused, with its line (03 § Attrs) ==")
    # echo_lab_ws 84edd64: `heading="¿&quot;es-419&quot; o …?"` built, and the
    # reader saw a literal `&quot;` — text is escaped once, so an entity is data.
    rejects("the echo_lab heading: &quot; in an attr names `\\\"`",
            '::: group {#G5 title="d6 · Etiquetas" '
            'heading="¿&quot;es-419&quot; o el nombre completo?"}\n'
            '::: item {#D6 title="T"}\n?\n\n- a\n- b\n:::\n:::\n', 1, '\\"')
    rejects("&quot; in title= is refused", '::: group {#G1 title="a &quot;b&quot;"}\n'
            '::: item {#Q1 title="T"}\n?\n\n- a\n- b\n:::\n:::\n', 1, "&quot;")
    rejects("&amp; in eyebrow= is refused, naming the literal character",
            '::: masthead {eyebrow="R &amp; D"}\n# T\n:::\n', 1, "`&`")
    rejects("an entity in prose names its own line and the literal character",
            "uno\n\nBody &quot;es-419&quot; y más.\n", 3, '`"`')
    for ent, char in (("&lt;", "<"), ("&gt;", ">"), ("&apos;", "'"),
                      ("&#34;", '"'), ("&#x22;", '"'), ("&#X27;", "'")):
        rejects("%s in prose is refused" % ent, "a %s b\n" % ent, 1,
                "`%s`" % char)
    rejects("the paragraph the `;` lint miscounted is an entity refusal now",
            "Body &quot;es-419&quot; &amp; &lt;b&gt;\n", 1, "entity")
    for ent, char in (("&nbsp;", "\u00a0"), ("&mdash;", "\u2014")):
        rejects("named entity %s beyond the markup five is refused" % ent,
                "a %s b\n" % ent, 1, "entity")
    holds("&word; that decodes to nothing stays legal", "AT&T; ok",
          "AT&amp;T; ok")
    holds("a bare & stays legal (R&D, Q&A)", "R&D y Q&A, & más.",
          "R&amp;D y Q&amp;A, &amp; más.")
    holds("an entity inside a code span is code",
          "Escribe `&quot;` así.", "<code>&amp;quot;</code>")
    holds("an entity inside a code fence is code",
          "```\na &amp; b\n```\n", "a &amp;amp; b")
    holds("`\\\"` is the spelling: the heading shows a quote",
          '::: section {#s1 heading="¿\\"es-419\\" o no?"}\nx\n:::\n',
          "¿&quot;es-419&quot; o no?")
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
              '::: item {#R1 title="Utilidad del informe"}\nAbre [R1](R1.html) y puntúala.\n\n'
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
    # BL-481: the net for the option marker (contract_defects owns it now,
    # under decision-item-without-options, LOOP-006). The pre-fix shape is what the
    # builder emitted for `- 5 {recommended} — excelente`: the marker as text
    # in the label, no data-recommended.
    leaked = linked.replace(
        '<input type="radio" name="R1" data-label="5"><span>5 ',
        '<input type="radio" name="R1" data-label="5 {recommended}">'
        '<span>5 {recommended} ')
    check("(the leaked shape carries the literal marker)",
          "{recommended}" in leaked and leaked != linked)
    r = contract("leaked", leaked)
    check("check-artifact FAILS a page that shows a literal {recommended}",
          r.returncode != 0 and "[decision-item-without-options]" in r.stdout
          and "literal {recommended}" in r.stdout + r.stderr,
          r.stdout + r.stderr)
    r = contract("rec-coded", linked.replace(
        "Abre <a", "Escribe <code>{recommended}</code> y abre <a"))
    check("a {recommended} shown as <code> is not flagged — the author "
          "quoting the marker", r.returncode == 0, r.stdout + r.stderr)

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
    for ident in ("G1", "Q1", "Q2", "Q3", "notes"):
        check("the WRAPPED page still carries id %r byte-exactly" % ident,
              ('data-id="%s"' % ident) in page)

    print()
    print("== a gallery page outlives its captures (BL-474) ==")
    # The captures a rows document points at live in the project's
    # `test-results/`, which Playwright wipes at the start of every run. A page
    # that linked them by `file://<root>/<path>` showed broken images on both
    # halves the day after it was built, with the contract green, because no
    # checker stats a linked image. Asserted the way the reader meets it: build,
    # wipe the sources, and every <img> must still resolve to a file.
    galroot = os.path.join(tmp, "galroot")
    # Four DIFFERENT captures (sizes), so four copies: identical fixtures would
    # let every <img> point at one file and still "resolve".
    for n, rel in enumerate(("shots/ld/audit-with-data.png",
                             "actual/ld/audit-with-data.png",
                             "shots/dm/audit-loaded.png",
                             "actual/dm/audit-loaded.png"), 1):
        os.makedirs(os.path.dirname(os.path.join(galroot, rel)), exist_ok=True)
        subprocess.run([sys.executable, os.path.join(HERE, "png_fixture.py"),
                        os.path.join(galroot, rel), str(10 + n), "9"], check=True)
    gspec = os.path.join(tmp, "gal.spec.md")
    with open(gspec, "w", encoding="utf-8") as fh:
        fh.write('::: masthead {visual="none: the screenshots are the '
                 'evidence"}\n# Revisión audit\n\nDos filas.\n:::\n\n'
                 '::: gallery {#E title="Galería audit" rows="rows.json" '
                 'root="%s"}\n:::\n\n::: notes {title="Notas"}\n:::\n'
                 % galroot)
    gout = os.path.join(tmp, "reports", "gal.html")

    def imgs(path):
        return re.findall(r'<img src="([^"]*)"[^>]* width="(\d+)"',
                          open(path, encoding="utf-8").read())

    def target(src):
        if src.startswith("file://"):
            return src[len("file://"):]
        return os.path.join(os.path.dirname(gout), urllib.parse.unquote(src))

    def gbuild():
        return subprocess.run([sys.executable, BUILD, gspec, "-o", gout,
                               "--check"], capture_output=True, text=True)
    r = gbuild()
    check("a gallery page builds and passes the contract", r.returncode == 0,
          r.stdout + r.stderr)
    first = imgs(gout)
    r = gbuild()
    check("a rebuild of the same rows links the same copies (content names)",
          r.returncode == 0 and imgs(gout) == first, r.stdout + r.stderr)
    shutil.rmtree(galroot)
    gone = [s for s, _ in first if not os.path.isfile(target(s))]
    check("every <img> still resolves after the source captures are wiped",
          len(first) == 4 and not gone, "broken: %r" % gone)
    wrong = [s for s, w in first if os.path.isfile(target(s))
             and struct.unpack(">I", open(target(s), "rb").read()[16:20])[0]
             != int(w)]
    check("...each to the copy of ITS capture (four tiles, four files)",
          not wrong and len({s for s, _ in first}) == 4, "wrong: %r" % wrong)
    before = open(gout, "rb").read()
    r = gbuild()
    check("a rebuild after the sources are gone is refused, naming the "
          "missing file", r.returncode == 1 and "has no file at %s" % galroot
          in r.stderr, r.stdout + r.stderr)
    check("...and leaves the page it would have replaced untouched",
          open(gout, "rb").read() == before
          and all(os.path.isfile(target(s)) for s, _ in first))

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
    # A spec with no masthead lang= and no --lang follows the project's
    # profile, the same reader the wrap and lang-follows-profile use: a hard
    # "es" default built an en-profile page as lang="es" and failed --check.
    enproj = os.path.join(tmp, "enproj")
    os.makedirs(os.path.join(enproj, ".context"))
    with open(os.path.join(enproj, ".context", "artifact-style.md"), "w",
              encoding="utf-8") as fh:
        fh.write("# Style\n\n## Language\n\n- language: en\n")
    silent_spec = os.path.join(enproj, "silent.spec.md")
    with open(silent_spec, "w", encoding="utf-8") as fh:
        fh.write('::: masthead {visual="none: a format decision has no shape '
                 'to draw"}\n# An English page\n\nThe body is in English, and '
                 "so is the page.\n:::\n\n"
                 '::: notes {title="General notes"}\n:::\n')
    silent_out = os.path.join(enproj, "silent.html")
    r = subprocess.run([sys.executable, BUILD, silent_spec, "-o", silent_out,
                        "--check"], capture_output=True, text=True)
    check("a spec silent on lang follows the en profile and passes --check",
          r.returncode == 0 and os.path.exists(silent_out)
          and '<html lang="en">' in open(silent_out, encoding="utf-8").read(),
          r.stdout + r.stderr)

    print()
    print("== the rail and the prose follow the page contract (LOOP-006) ==")
    # ui-string-language: the railhead was "Contents" on every page, so a
    # Spanish page read without JS (a static snapshot) showed English chrome.
    NOTES_ONLY = "::: masthead\n# T\n\nS\n:::\n::: notes {title=\"n\"}\n:::\n"
    holds("an es page's rail is headed \"Contenido\"", NOTES_ONLY,
          '<p class="railhead">Contenido</p>', lang="es")
    holds("an en page's rail is headed \"Contents\"", NOTES_ONLY,
          '<p class="railhead">Contents</p>', lang="en")
    # mixed-content-types: a paragraph carrying FACTS_MIN <code> tokens is a
    # list or a table written as a sentence. The threshold is contract_defects',
    # read from there, so the builder and the check cannot drift apart.
    dense = "Toca " + ", ".join("`v%d`" % i
                                for i in range(contract_defects.FACTS_MIN)) + "."
    rejects("a paragraph with FACTS_MIN code tokens is refused",
            "Intro.\n\n%s\n" % dense, 3, "a list or a table")
    rejects("...inside an item too, naming the paragraph's own line",
            '::: group {#G1 title="T"}\n::: item {#Q1 title="t"}\n?\n\n%s\n\n'
            "- A {recommended}\n- B\n:::\n:::\n" % dense, 5, "a list or a table")
    rejects("...and inside a note, below an intro paragraph",
            "Antes.\n\n::: note\nIntro.\n\n%s\n:::\n" % dense, 6,
            "a list or a table")
    # Two code blocks opening on the same line: the refusal names the one that
    # holds the prose, not the first whose opening line matches.
    PROSE_PRE = ("```\nls -la\nThis is the first long sentence. Here comes "
                 "the second long sentence. And this is the third long "
                 "sentence.\n```\n")
    rejects("a code block of prose after a look-alike one names its own line",
            "Intro.\n\n```\nls -la\necho ok\n```\n\n" + PROSE_PRE, 8,
            "prose sentences")
    holds("a paragraph with one token fewer builds",
          "Toca %s.\n" % ", ".join(
              "`v%d`" % i for i in range(contract_defects.FACTS_MIN - 1)),
          "<code>v0</code>")
    holds("the same tokens as a list build", "::: note\n%s\n:::\n"
          % "\n".join("- `v%d`" % i for i in range(contract_defects.FACTS_MIN)),
          "<li><code>v0</code></li>")

    # No drift between the builder and the check: for each shape, the builder
    # refuses exactly when contract_defects fails the page it would have
    # built. The page is built with the builder's refusal switched off, so the
    # comparison is against what the author would really have shipped —
    # including the promotions (a one-paragraph note is unwrapped into the
    # div, an item's first paragraph becomes its <h3>).
    DRIFT = [
        ("a dense paragraph", "Intro.\n\n%s\n" % dense),
        ("a dense one-paragraph note", "::: note\n%s\n:::\n" % dense),
        ("a dense two-paragraph note", "::: note\nIntro.\n\n%s\n:::\n" % dense),
        ("a dense item question", '::: group {#G1 title="T"}\n'
         '::: item {#Q1 title="t"}\n%s\n\n- A {recommended}\n- B\n:::\n:::\n'
         % dense),
        ("a dense masthead standfirst", "::: masthead\n# T\n\n%s\n:::\n" % dense),
        ("a code block of prose", "Intro.\n\n" + PROSE_PRE),
        ("a dense paragraph after an item's options", '::: group {#G1 title="T"}\n'
         '::: item {#Q1 title="t"}\n?\n\n- A {recommended}\n- B\n\n%s\n:::\n:::\n'
         % dense),
    ]
    real_check = spec_build.contract_defects.check_mixed_content_types
    for label, spec in DRIFT:
        # Only the mixed-content refusal counts: a spec refused for any other
        # reason would read as agreement with a page that fails.
        try:
            build(spec)
            refused = False
        except SpecBuildError as exc:
            if not exc.message.startswith("mixed-content-types:"):
                fail("%s: refused for another reason (%s)" % (label, exc.message))
                continue
            refused = True
        spec_build.contract_defects.check_mixed_content_types = \
            lambda path, html: []
        try:
            page = build(spec)
        except SpecBuildError as exc:
            fail("%s: the page cannot be built even without the refusal (%s)"
                 % (label, exc.message))
            continue
        finally:
            spec_build.contract_defects.check_mixed_content_types = real_check
        fails_page = bool(real_check("", page))
        check("builder and check agree on %s (refused=%s, page fails=%s)"
              % (label, refused, fails_page), refused == fails_page)
    # The boundary: the built page itself, read by the contract checks.
    r = subprocess.run([sys.executable, CONTRACT, out], capture_output=True,
                       text=True)
    check("the wrapped fixture page (PAGE, built to page.html) passes every "
          "contract_defects source check",
          r.returncode == 0, r.stdout + r.stderr)

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
