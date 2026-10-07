#!/usr/bin/env python3
"""The spec TOKENIZER, judged against `references/03-spec-grammar.md`.

Two halves, and they are deliberately not the same test:

  the SHAPE it accepts — one fence per block type of
  `04-block-vocabulary.md`, nesting, attrs, prose runs, and the three cases the
  grammar says are NOT tokenizer errors (an unknown type, an unknown attr key,
  a missing required attr). Those three are the two-layer split: if any of them
  raised here, the builder could never say "`chrt` is not a block type — did
  you mean `chart`?".

  the LINE NUMBER it refuses at — every row of the grammar's malformed table,
  each asserting the exact 1-based line reported. The line number is the whole
  value of the error: a tokenizer that raises "malformed spec" with no line is
  the raw-HTML-passthrough failure wearing an exception.

Stdlib only, no runner: `python3 test_parser.py`, prints OK, exits 0.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.join(os.path.dirname(HERE), "scripts")
sys.path.insert(0, SCRIPTS)
sys.path.insert(0, os.path.join(SCRIPTS, "dash"))

import md_body                                   # noqa: E402
import spec_parser                               # noqa: E402
from spec_parser import SpecSyntaxError, parse    # noqa: E402

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


def parses(label, text, expect):
    """`expect` is a callable taking the tree; a truthy return passes."""
    try:
        tree = parse(text)
    except SpecSyntaxError as exc:
        fail("%s: refused a well-formed spec (line %d: %s)"
             % (label, exc.line, exc.message))
        return None
    try:
        verdict = expect(tree)
    except Exception as exc:                      # noqa: BLE001 — the assertion
        fail("%s: the assertion raised %r" % (label, exc))
        return tree
    check(label, verdict, repr(tree))
    return tree


def kinds(nodes):
    """The block types of `nodes`, minus the BLANK prose runs.

    A blank line is a content line, so `:::` / blank / `:::` yields a prose node
    holding one empty string. That is the grammar (a prose run ends at the next
    fence, blank lines included), and `spec_build.py` drops the empty ones —
    asserting against a shape that pretends they are not there would hide the
    day one of them stops being dropped.
    """
    return [n.block_type for n in nodes
            if n.block_type != "prose" or n.text.strip()]


def refuses(label, text, line):
    """The spec is malformed AND the reported line is exactly `line`."""
    try:
        parse(text)
    except SpecSyntaxError as exc:
        if exc.line == line:
            ok("%s (line %d: %s)" % (label, exc.line, exc.message))
        else:
            fail("%s: reported line %d, expected %d (%s)"
                 % (label, exc.line, line, exc.message))
        return
    fail("%s: accepted a malformed spec" % label)


print("== the code-fence marker rule is md_body's, not a second copy ==")
check("CODE_FENCE is md_body.FENCE", spec_parser.CODE_FENCE is md_body.FENCE)

print()
print("== one fence per block type of 04-block-vocabulary.md ==")

# Every type of the closed vocabulary, written the way that file writes it. The
# tokenizer treats them all alike — that is the point of the case: it knows
# SHAPE, so `masthead` and `chrt` cost it the same, and only the builder knows
# which of the two exists.
VOCAB = {
    "masthead": '::: masthead {eyebrow="Source review" byline="1,200 lines"}\n'
                "# A talk on building tools\n\nA 20-minute talk.\n:::",
    "group": '::: group {#G1 title="Formato del spec" eyebrow="Bloque G1"}\nLa consulta de hoy.\n:::',
    "item": '::: item {#Q1 title="T-100" decided=yes}\n¿Es lo mismo?\n\n- Sí {recommended}\n- No\n:::',
    "notes": '::: notes {title="Notas generales"}\n:::',
    "gallery": '::: gallery {#G2 title="Estados" rows=".context/gallery/rows.json" lang=es}\n:::',
    "ledger": "::: ledger\n- d4 — **Hecho.** T-100.\n:::",
    "verdict": '::: verdict {win="Ruta A"}\n| n | ruta |\n|---|---|\n| 3 | Ruta A |\n:::',
    "callout": "::: callout\nEight of nine reviewers.\n:::",
    "note": "::: note\nLas tres categorías.\n:::",
    # `num`, `pill` and `chip` are the three INLINE entries. The vocabulary
    # leaves their form to the builder, and the builder's answer is that they
    # are not fences — but a fence spelled with their name still TOKENIZES,
    # which is what keeps the refusal a vocabulary message instead of a syntax
    # error with no advice in it.
    "num": "::: num\n| n |\n:::",
    "pill": "::: pill {tone=high}\nconfianza alta\n:::",
    "chip": "::: chip {tone=kill}\ndeferred\n:::",
    # Phases 2 and 6. They are not registered anywhere yet and they tokenize
    # today — which is exactly the claim this row makes.
    "chart": '::: chart {#c1 kind=bar title="Bytes" unit=KB}\n| Página | KB |\n|---|---|\n| A | 37 |\n:::',
    "diagram": '::: diagram {#d1 kind=flow}\nA -> B\n:::',
}
for name, text in sorted(VOCAB.items()):
    parses("`%s` tokenizes" % name, text,
           lambda t, n=name: len(t) == 1 and t[0].block_type == n)

# `prose` is the fence-less default every other type is an exception to.
parses("`prose` is the fence-less default",
       "Sesión del 23 de septiembre.\nTres preguntas abiertas.",
       lambda t: len(t) == 1 and t[0].block_type == "prose"
       and t[0].raw_body == ["Sesión del 23 de septiembre.",
                             "Tres preguntas abiertas."])

print()
print("== attrs ==")
parses("classes accumulate in written order, the id is the id, values are strings",
       '::: note {.warn .big #n1 n=3 title="two words" empty=""}\nx\n:::',
       lambda t: t[0].classes == ["warn", "big"] and t[0].id == "n1"
       and t[0].attrs == {"n": "3", "title": "two words", "empty": ""})
parses("a quoted value carries spaces, quotes-of-the-other-kind, braces, '.', '#' and '='",
       '::: note {title="a \'b\' {c} .d #e f=g"}\nx\n:::',
       lambda t: t[0].attrs["title"] == "a 'b' {c} .d #e f=g")
parses("attr text is RAW — escaping happens at build time",
       '::: note {title="a < b & c"}\nx\n:::',
       lambda t: t[0].attrs["title"] == "a < b & c")
parses("the colon count is cosmetic and need not match",
       ":::::: note\nx\n:::\n",
       lambda t: len(t) == 1 and t[0].block_type == "note")

print()
print("== nesting, prose runs and order ==")
NESTED = """Sesión del 23 de septiembre.

::: group {#g1 title="Formato"}
La consulta de hoy.

::: item {#q1 title="Fences"}
Los dos se parsean igual.

- Fences {recommended}
:::

::: note
`item` acepta prosa.
:::
:::

::: chart {#c1 kind=bar}
| Página | KB |
:::
"""
parses("the worked example reads as prose, group(prose,item,note), chart",
       NESTED,
       lambda t: kinds(t) == ["prose", "group", "chart"]
       and kinds(t[1].children) == ["prose", "item", "note"]
       and t[1].children[1].id == "q1")
parses("a block may mix prose runs and nested fences, in written order",
       "::: group {#g title=\"t\"}\nantes\n::: note\nx\n:::\ndespués\n:::",
       lambda t: kinds(t[0].children) == ["prose", "note", "prose"]
       and t[0].children[2].raw_body == ["después"])
parses("blank lines inside a prose run keep it ONE block",
       "uno\n\ndos\n\n::: note\nx\n:::",
       lambda t: len(t) == 2 and t[0].raw_body == ["uno", "", "dos", ""])
parses("line numbers are 1-based physical lines",
       "a\n\n::: note\nx\n:::\n\n::: callout\ny\n:::",
       lambda t: [n.line for n in t] == [1, 3, 6, 7])
parses("a blank line between two fences is its own (blank) prose run",
       "::: note\nx\n:::\n\n::: callout\ny\n:::",
       lambda t: [n.block_type for n in t] == ["note", "prose", "callout"]
       and t[1].raw_body == [""])
parses("a trailing \\r is stripped before classification",
       "::: note\r\nx\r\n:::\r\n",
       lambda t: len(t) == 1 and t[0].block_type == "note"
       and t[0].children[0].raw_body == ["x"])

print()
print("== what is NOT a fence ==")
parses("an INDENTED ::: is content — indentation carries no meaning anywhere",
       "- un item de lista:\n  ::: note\n  sigue siendo prosa",
       lambda t: len(t) == 1 and t[0].block_type == "prose"
       and len(t[0].raw_body) == 3)
parses("`:::item` with no separator is content",
       ":::item\n:::nota",
       lambda t: len(t) == 1 and t[0].block_type == "prose")
parses("`:::` inside a ``` code fence is literal content",
       "::: note\n```\n::: item {#q1}\n:::\n```\n:::",
       lambda t: len(t) == 1 and t[0].block_type == "note"
       and t[0].children[0].raw_body[2] == ":::")
parses("a `~~~` block is closed only by its OWN marker",
       "::: note\n~~~\n```\n::: item\n~~~\n:::",
       lambda t: len(t) == 1 and t[0].block_type == "note")
parses("an unclosed code fence at top level takes the rest as prose, and is NOT an error",
       "texto\n```sh\necho hi\n::: item {#q1}\n",
       lambda t: len(t) == 1 and t[0].block_type == "prose"
       and t[0].raw_body[-1] == "::: item {#q1}")

print()
print("== NOT malformed, on purpose: the builder's three ==")
parses("an unknown block type tokenizes",
       "::: chrt {#c1}\nx\n:::",
       lambda t: t[0].block_type == "chrt")
parses("an unknown attr key tokenizes",
       '::: item {#q1 wat="x"}\ny\n:::',
       lambda t: t[0].attrs == {"wat": "x"})
parses("a missing required attr tokenizes",
       "::: group\nsin title ni id\n:::",
       lambda t: t[0].block_type == "group" and t[0].id is None
       and t[0].attrs == {})

print()
print("== `\\\"` and `\\\\` inside a quoted attr value (03-spec-grammar.md) ==")
# The gap this closed: `dynamic_sites_ws/.context/reports/2026-09-03-cierre-del-
# proyecto.html` writes an `<h2>` with a phrase in straight double quotes, and a
# `group` heading is VISIBLE text. With no escape the only conversions were a
# character the author never typed or a page dropped from the sample.
parses("a double quote inside a quoted value, written `\\\"`",
       '::: group {#G1 title="T" heading="El caso \\"raro\\" de hoy"}\nx\n:::\n',
       lambda t: t[0].attrs == {"title": "T",
                                "heading": 'El caso "raro" de hoy'})
parses("`\\\\` is one backslash, and the value after it still ends where it ends",
       '::: item {#q1 title="C:\\\\" decided=yes}\nx\n:::\n',
       lambda t: t[0].attrs == {"title": "C:\\", "decided": "yes"})
parses("a backslash before anything else is a backslash — md_body reads it a "
       "layer down",
       '::: item {#q1 title="a\\_b"}\nx\n:::\n',
       lambda t: t[0].attrs == {"title": "a\\_b"})
check("quote_value is the inverse: every value round-trips through a fence line",
      all(parse('::: item {#q1 title=%s}\nx\n:::\n'
                % spec_parser.quote_value(v))[0].attrs["title"] == v
          for v in ['con "comillas"', 'C:\\', 'a\\"b', '\\', '"', 'llano']))

print()
print("== every row of the grammar's malformed table, with its line number ==")
refuses("close fence with no block open",
        "una línea\n\n:::\n", 3)
refuses("close fence with no block open, after a balanced block",
        "::: note\nx\n:::\n:::\n", 4)
refuses("end of file with a block still open",
        "texto\n\n::: group {#g1 title=\"t\"}\nsin cerrar\n", 3)
# The `:::` on line 4 closes the INNERMOST block (the item), so what is left
# open is the group — and the line reported is the line of the fence that is
# still open, never the end of the file. That is the only line the author can
# act on: EOF is where the tokenizer noticed, not where the mistake is.
refuses("end of file with the OUTER block still open, the inner one closed",
        "::: group {#g1 title=\"t\"}\n::: item {#q1 title=\"t\"}\nx\n:::\n", 1)
refuses("an unclosed ``` fence swallows the close and the block is unclosed",
        "::: note\n```\necho hi\n:::\n", 1)
refuses("open fence with no block type",
        "x\n::: {.big}\n:::\n", 2)
refuses("block type not [a-z][a-z0-9-]* — capital",
        "::: Item\n:::\n", 1)
refuses("block type not [a-z][a-z0-9-]* — underscore",
        "x\n\n::: my_item\n:::\n", 3)
refuses("block type not [a-z][a-z0-9-]* — trailing hyphen",
        "::: note\n::: item-\n:::\n:::\n", 2)
refuses("text after the attr group",
        "::: item {.x} trailing\n:::\n", 1)
refuses("unclosed attr brace",
        "x\n::: item {.x\n:::\n", 2)
refuses("unopened attr brace",
        "x\n\n::: item .x}\n:::\n", 3)
refuses("two #ids on one fence",
        "::: note\n::: item {#a #b}\n:::\n:::\n", 2)
refuses("a repeated attr key",
        "::: item {n=1 n=2}\n:::\n", 1)
refuses("`key=` with no value",
        "x\n::: item {title=}\n:::\n", 2)
refuses("unquoted value containing a space",
        "::: item {title=two words}\n:::\n", 1)
refuses("unquoted value containing a quote",
        "::: item {title=two\"words}\n:::\n", 1)
refuses("a single-quoted value is not a form of quoting",
        "x\n::: item {title='dos palabras'}\n:::\n", 2)
refuses("unquoted value containing a brace",
        "::: item {title=a{b}\n:::\n", 1)
refuses("an attr item that is none of the three kinds",
        "x\n\n::: item {big}\n:::\n", 3)
refuses("a fence opened one past MAX_DEPTH, at its own line",
        "::: note\n" * (spec_parser.MAX_DEPTH + 1) + "x\n"
        + ":::\n" * (spec_parser.MAX_DEPTH + 1), spec_parser.MAX_DEPTH + 1)
refuses("a class whose name is not [A-Za-z][A-Za-z0-9_-]*",
        "::: item {.1big}\n:::\n", 1)
refuses("an id whose name is not [A-Za-z][A-Za-z0-9_-]*",
        "::: item {#1q}\n:::\n", 1)
refuses("an escaped quote does NOT close the value, so the value is unclosed",
        '::: item {title="abc\\"}\n:::\n', 1)
refuses("a trailing `\\\\` closes the value and the text then runs straight on",
        '::: item {title="abc\\\\"x}\n:::\n', 1)

print()
print("== SpecSyntaxError is the ONLY error surface, non-ASCII whitespace included ==")


def only_syntax(label, text, line):
    """Malformed, refused at `line`, and refused as `SpecSyntaxError`.

    `refuses` above lets any other exception escape the harness; this one names
    it. The module docstring promises one error surface carrying a line number,
    and both CLIs catch that class alone — anything else reaches the author as a
    traceback about this file, with no line to act on.
    """
    try:
        parse(text)
    except SpecSyntaxError as exc:
        check("%s (line %d: %s)" % (label, exc.line, exc.message),
              exc.line == line,
              "reported line %d, expected %d" % (exc.line, line))
        return
    except BaseException as exc:                  # noqa: BLE001 — the claim
        fail("%s: raised %s(%s) — the module promises SpecSyntaxError and "
             "nothing else" % (label, type(exc).__name__, exc))
        return
    fail("%s: accepted a malformed spec" % label)


# `\xa0` (a pasted NBSP, or Option+Space on macOS), `\x0b` and `\x0c` are
# whitespace to `str.split()` and NOT to the attr scanner's ASCII skip loop.
# An attr group made of nothing else therefore reached the "name the bad item"
# branch with no token to name, and `.split()[0]` raised a bare IndexError out
# of `parse()` — the only uncaught-exception class a 400k-case fuzz over the
# fence alphabet found.
for name, ws in (("an NBSP", "\xa0"), ("a vertical tab", "\x0b"),
                 ("a form feed", "\x0c")):
    only_syntax("an attr group holding only %s" % name,
                "::: note {%s}\nhola\n:::\n" % ws, 1)
    only_syntax("an attr group holding only %s, then a token" % name,
                "x\n::: note {%sA}\n:::\n" % ws, 2)
    only_syntax("%s BEFORE a valid attr" % name,
                "::: note {%s.big}\n:::\n" % ws, 1)

print()
print("== a `:::` fence node is marked authored; a prose RUN is not ==")
parses("an implicit prose run carries authored=False",
       "Sesión del 23.\n",
       lambda t: t[0].block_type == "prose" and t[0].authored is False)
parses("`::: prose` tokenizes as an AUTHORED node of the same type",
       "::: prose\nEsto.\n:::\n",
       lambda t: len(t) == 1 and t[0].block_type == "prose"
       and t[0].authored is True and t[0].raw_body == []
       and [c.raw_body for c in t[0].children] == [["Esto."]])
parses("every other fence is authored too",
       "::: note\nx\n:::\n",
       lambda t: t[0].authored is True and t[0].children[0].authored is False)

print()
if failures:
    print("%d failure(s)" % len(failures))
    raise SystemExit(1)
print("OK — the tokenizer: every vocabulary type, prose runs, nesting, attrs, "
      "code fences, the builder's three non-errors, every malformed row of "
      "03-spec-grammar.md at its exact line, SpecSyntaxError as the only error "
      "surface, and the authored flag that tells a `::: prose` fence from a "
      "prose run")
