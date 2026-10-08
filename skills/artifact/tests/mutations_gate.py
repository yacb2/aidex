#!/usr/bin/env python3
"""The LOOP-008 mutation gate: agent-like mistakes, refused loudly OR built valid, never silent.

    python3 mutations_gate.py [--verbose] [--only N]     prints ONE stdout line:  mutations: X/Y

Y = the cases below (one per row of the loop's grammar-table.md section 5, "Plausible agent
mistakes", plus the Phase B list: duplicate ids, case-only collisions, an item's first list
becoming options, missing/second masthead, mixed languages, very long tokens, empty sections,
nested groups, 0/1/40 items, hand-edited built HTML). A row with variants has one case per
variant (`17`, `17b`, ...); `--only 17` runs the row's cases. X = the cases that PASS. Exit 0 iff
X == Y and Y >= 1. A probe that gave no verdict prints `mutations: 0/unknown` and exits 1.

A case is DATA: a spec (or raw bytes), a command sequence (steps), and what the LAST step must do:

    refuse   the tool refuses loudly: non-zero exit, a message (naming what is wrong when the case
             says `names`), no Python traceback, nothing half-written (the spec and the page are
             byte-identical to before the step, or the page was never created).
    valid    the tool succeeds, `render-probe.sh --invariants` reports 0 violations for the page
             (ONE browser call for all pages), and the case's meaning predicates hold on the page
             (`has` / `lacks` regexes, `count` of a regex, `files_has` on a side file).
    either   a loud refusal OR a valid page, per the two rules above.

"Built without error" alone is never a pass: a silent acceptance whose page differs from the intent
fails on its meaning predicate. A traceback, a timeout, or a setup step that does not do its job
(a harness fault, reported as such) is a FAIL.

SKIPPED (a row or variant that cannot be expressed as an input; listed here, never silent):

    59 (variant)  save-reply.sh "during a build lock": needs a live concurrent build to hold the lock
                  (save_reply.py:282-306); the missing-page and empty-reply variants are cases 59/59b.
    16 (variant)  "a lone context list with no real options is silently taken AS the options"
                  is case x-ctxlist, relaxed to `either` with no meaning predicate (owner Q6,
                  2026-10-07): which list was meant is not machine-decidable.
    46 (variant)  the CLI `--lang fr` is argparse's own refusal; only the masthead `lang=` is a case.
    63/65/66      one case per named variant of the row; the row's remaining words are the same code path.

Test seams (the gate's own test drives them; nothing else should):
    AIDEX_ARTIFACT_SCRIPTS  a directory replacing skills/artifact/scripts for spec_build.py,
                            spec_verbs.py, save-reply.sh and check-artifact.sh (fakes, no real build)
    AIDEX_RENDER_PROBE      replaces render-probe.sh (a fake probe, no browser)

Expectations chosen LENIENT on purpose (the gate is a measure, not a taste test): 22, 23(free=YES/1),
34, 39, 41, 45, 50, 61, 68, 71 accept the page when it is valid and the meaning predicate holds; see
the comment above each case. Strict on purpose: 11 (case-only ids), 28, 47, 52.
"""
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.environ.get("AIDEX_ARTIFACT_SCRIPTS") or os.path.join(os.path.dirname(HERE), "scripts")
PROBE = os.environ.get("AIDEX_RENDER_PROBE") or os.path.join(SCRIPTS, "render-probe.sh")
STEP_TIMEOUT = 120
TRACEBACK = "Traceback (most recent call last)"

SKIPPED = {}   # row -> reason, for a row with NO case at all (every row 1..75 has one today)

# --- spec building blocks ------------------------------------------------------------------------
# The base is the §2 "valid by construction" skeleton, except that the question paragraphs do not
# close on "?": a question-headed item makes NAV-4 fire (the rail lists data-title, which is not
# visible text; STATE.md "rail-label-invisible"), and that class is the invariant gate's, not this
# one's. Revert the wording when the kicker fix lands.
MAST = '::: masthead {title="Informe de prueba" visual="none: texto"}\nUna frase de apertura.\n:::\n\n'
NOTES = '::: notes {title="Notas"}\n:::\n'


def item(i, title, q, opts, attrs="", ident=None):
    return '::: item {#%s title="%s"%s}\n%s\n\n%s\n:::\n\n' % (ident or i, title, attrs, q, opts)


OPTS1 = "- Sí {recommended} — pista uno\n- No — pista dos"
OPTS2 = "- Alfa — pista a\n- Beta — pista b"
Q1 = item("Q1", "Tema uno", "Primera pregunta sin signo final.", OPTS1)
Q2 = item("Q2", "Tema dos", "Segunda pregunta sin signo final.", OPTS2)
Q3 = item("Q3", "Tema tres", "Tercera pregunta sin signo final.", OPTS2)


def group(inner, gid="G1", title="Bloque uno"):
    return '::: group {#%s title="%s"}\n%s:::\n\n' % (gid, title, inner)


def sec(inner, sid="S1", heading="Datos"):
    return '::: section {#%s heading="%s"}\n%s\n:::\n\n' % (sid, heading, inner)


def doc(*parts, mast=MAST, notes=NOTES):
    return mast + "".join(parts) + notes


BASE = doc(group(Q1 + Q2))
EN = {"Informe de prueba": "Test report", "Una frase de apertura.": "One opening sentence.",
      "Bloque uno": "Block one", "Tema uno": "Topic one", "Tema dos": "Topic two",
      "Primera pregunta sin signo final.": "First question without a closing mark.",
      "Segunda pregunta sin signo final.": "Second question without a closing mark.",
      "Sí": "Yes", "No — pista dos": "No — hint two", "pista uno": "hint one",
      "Alfa — pista a": "Alpha — hint a", "Beta — pista b": "Beta — hint b",
      "visual=\"none: texto\"": "visual=\"none: text\"", "Notas": "Notes"}
BASE_EN = BASE
for _k, _v in EN.items():
    BASE_EN = BASE_EN.replace(_k, _v)
BASE_EN = BASE_EN.replace('title="Test report"', 'title="Test report" lang=en')

HINT_OK = [r'data-label="Sí"', r'class="hint">pista uno']          # the label and the hint both landed apart
ITEM = r'<section class="consult-item"[^>]*'          # an attr on an item element, not in the composer script
LONG = "A" * 4000
SVG = b'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 20"><path d="M0 0h40v20z"/></svg>'


def mut(*pairs, base=BASE):
    """The base with each (old, new) applied; an `old` that is not there is a case-authoring error."""
    t = base
    for old, new in pairs:
        if old not in t:
            raise SystemExit("mutations_gate: case authoring error, %r is not in the base spec" % old)
        t = t.replace(old, new, 1)
    return t


def in_section(block):
    """The block under test, as the last child of the group (a section ahead of the first group is
    refused by the consult-shape contract, which would mask every case that uses it)."""
    return mut(("%s:::\n\n::: notes" % Q2, "%s%s\n\n:::\n\n::: notes" % (Q2, block)))


def deep_notes(n):
    return sec(":::: note\n" * n + "texto\n" + "::::\n" * n)


# --- the cases -----------------------------------------------------------------------------------
CASES = []
B = ("build",)


def case(id, name, spec=BASE, steps=(B,), expect="refuse", names=None, has=(), lacks=(), count=(),
         files=None, files_has=(), geometry=False, profile=None, git=False):
    CASES.append(dict(id=id, name=name, spec=spec, steps=list(steps), expect=expect, names=names,
                      has=list(has), lacks=list(lacks), count=list(count), files=files or {},
                      files_has=list(files_has), geometry=geometry, profile=profile, git=git))


REPLY = ("save", "Q1: No\n")        # a decided item needs the reader's saved answer (consult-decided-trace)


def decide(i="Q1", v="No"):
    return ("verb", "decide", "--id", i, "--verdict", v)


# controls: the unmutated base and the legal verbs must be valid, else every other verdict is moot
case("ctl-base", "the unmutated base builds and probes clean", expect="valid",
     count=[(r'<section class="consult-item"', 2), (r'<header class="masthead"', 1)])
case("ctl-decide", "decide with an exact option label lands on that option", steps=(B, REPLY, decide()),
     expect="valid", has=[r'data-decided="No"'])
case("ctl-add", "add-item with two options builds an item with two options",
     steps=(B, ("verb", "add-item", "--group", "G1", "--id", "Q3", "--title", "Tema tres", "--body",
                "Tercera pregunta sin signo final.", "--option", "Uno", "--option", "Dos")),
     expect="valid", count=[(r'<input type="radio" name="Q3"', 2)])

# 1-13: tokenizer and attribute vocabulary
case("1", "wrong attr name (name= for title=)", mut(('#Q1 title="Tema uno"', '#Q1 name="Tema uno"')),
     names=r"no attr 'name'")
case("2", "attr valid elsewhere on the wrong block (decided on notes)", BASE.replace(
     '::: notes {title="Notas"}', '::: notes {title="Notas" decided=yes}'), names=r"no attr 'decided'")
case("3", "empty title", mut(('title="Tema uno"', 'title=" "')), names=r"non-empty title")
case("4", "item without #id", mut(('{#Q1 title="Tema uno"}', '{title="Tema uno"}')), names=r"needs an #id")
case("5", "bare flag {decided}", mut(('title="Tema uno"}', 'title="Tema uno" decided}')), names=r"attr item 'decided'")
case("6", "unquoted value with a space", mut(('title="Tema uno"', "title=Tema uno")), names=r"attr item 'uno'")
case("6b", "single-quoted value", mut(('title="Tema uno"', "title='Tema uno'")), names=r"single-quoted")
case("6c", "key= with no value", mut(('title="Tema uno"', "title= ")), names=r"has no value")
case("6d", "unescaped inner quote", mut(('title="Tema uno"', 'title="Tema "uno""')), names=r"after the quoted value")
case("7", "uppercase block type", mut(("::: item {#Q1", "::: Item {#Q1")), names=r"block type 'Item'")
case("7b", "typo block type", mut(("::: group {#G1", "::: grup {#G1")), names=r"unknown block type 'grup'")
case("7c", "pill used as a fence", in_section("::: pill\ntexto\n:::"), names=r"`pill` is not a block")
case("8", "::: prose wrapper", in_section("::: prose\ntexto\n:::"), names=r"`prose` is not a fence")
case("9", "duplicate item ids", mut(("{#Q2 ", "{#Q1 ")), names=r"#Q1 is taken")
# 10: builder or wrap may refuse; a built page must still carry both groups with one id each
case("10", "duplicate group ids", doc(group(Q1, "G1"), group(Q2, "G1", "Bloque dos")), expect="either",
     names=r"G1", count=[(r'<section class="consult-group"', 2)])
case("10b", "two sections sharing an id", MAST + sec("Texto uno.") + sec("Texto dos.", "S1", "Otra"),
     expect="either", names=r"S1", count=[(r'id="S1"', 1)], has=[r"<h2>Datos", r"<h2>Otra"])
# 11 strict on purpose: the generator rule is ids unique case-insensitively (grammar-table §6), and
# the reply/composer behaviour with case-folded keys is unknown (§5 row 11 "U")
case("11", "ids differing only by case (Q1, q1)", mut(("{#Q2 ", "{#q1 ")), names=r"\bq1\b|\bQ1\b")
case("12", "unicode id", mut(("#Q1 ", "#Bloqué ")), names=r"starts with a letter")
case("12b", "id starting with a digit", mut(("#Q1 ", "#1a ")), names=r"starts with a letter")
case("12c", "spaced id", mut(("#Q1 ", "#Q 1 ")), names=r"attr item '1'")
case("12d", "add-item with a unicode id",
     steps=(B, ("verb", "add-item", "--group", "G1", "--id", "Bloqué", "--title", "X", "--option", "Uno",
                "--option", "Dos")), names=r"not a usable id")
case("13", "#id on a callout", in_section("::: callout {#c1}\ntexto\n:::"), names=r"takes no #id")
case("13b", "#id on a ledger", in_section("::: ledger {#l1}\n- clave — valor\n:::"), names=r"takes no #id")

# 14-25: options and item attributes
NOOPT = '1. Sí {recommended} — pista uno\n2. No — pista dos'
case("14", "options as a numbered list", mut((OPTS1, NOOPT)), expect="either", names=r"Q1.*option|option.*Q1",
     count=[(r'<input type="radio" name="Q1"', 2)])
case("15", "options indented under the question", mut((OPTS1, "  - Sí {recommended} — pista uno\n  - No — pista dos")),
     expect="either", names=r"Q1.*option|option.*Q1", count=[(r'<input type="radio" name="Q1"', 2)])
case("16", "a context list before the real options",
     mut((OPTS1, "- contexto uno\n- contexto dos\n\nTexto entre listas.\n\n" + OPTS1)), names=r"second `-` list")
# x-ctxlist: a list of evidence and no options. "- dato uno / - dato dos" is shape-identical to a
# bare options list, so the bullets becoming the options is accepted (owner, LOOP-008 Q6,
# 2026-10-07): a refusal or a valid page both pass; no grammar marker separates the two.
case("x-ctxlist", "an item whose only list is evidence (first list becoming options)",
     mut((OPTS1, "- dato uno\n- dato dos")), expect="either", names=r"Q1.*option|option.*Q1")
case("17", "hint separated by ' - ' instead of ' — '", mut(("{recommended} — pista uno", "{recommended} - pista uno")),
     expect="either", names=r"hint|separator|dash", lacks=[r'data-label="[^"]* - '], has=HINT_OK)
case("17b", "hint separated by '--'", mut(("{recommended} — pista uno", "{recommended} -- pista uno")),
     expect="either", names=r"hint|separator|dash", lacks=[r'data-label="[^"]*--'], has=HINT_OK)
case("18", "parenthetical in a label", mut(("- Sí {recommended}", "- Sí (recomendado) {recommended}")),
     names=r"parenthetical")
case("18b", "an Otra option", mut(("- No — pista dos", "- Otra opción — pista dos")), names=r"already adds")
case("18c", "an option that names notes", mut(("- No — pista dos", "- Ver notas — pista dos")), names=r"already adds")
case("19", "{recommended} on the question line", mut(("Primera pregunta sin signo final.", "Primera pregunta {recommended}.")),
     expect="either", names=r"\{recommended\}", lacks=[r"\{recommended\}"])
case("19b", "(recommended) typed in a label", mut(("- Sí {recommended}", "- Sí (recommended) {recommended}")),
     names=r"parenthetical")
case("20", "decided=yes with no recommended option", mut(('{#Q2 title="Tema dos"', '{#Q2 title="Tema dos" decided=yes')),
     names=r"no option marked")
case("21", "decided=no meaning not decided", mut(('title="Tema uno"', 'title="Tema uno" decided=no')),
     expect="either", names=r"decided=", lacks=[ITEM + r'data-decided="no"'])
case("21b", "decided=false", mut(('title="Tema uno"', 'title="Tema uno" decided=false')),
     expect="either", names=r"decided=", lacks=[ITEM + r'data-decided="false"'])
case("21c", "decided=0", mut(('title="Tema uno"', 'title="Tema uno" decided=0')),
     expect="either", names=r"decided=", lacks=[ITEM + r'data-decided="0"'])
# 22, 23(free=YES/1): the build treats these as "not decided" / "not free" with no word; lenient
# because the attribute is simply absent, which is what a plain reading of an empty value gives
case("22", 'decided="" is not decided', mut(('title="Tema uno"', 'title="Tema uno" decided=""')),
     expect="either", names=r"decided=", lacks=[ITEM + r"data-decided"])
case("22b", 'decided="**" is not decided', mut(('title="Tema uno"', 'title="Tema uno" decided="**"')),
     expect="either", names=r"decided=", lacks=[ITEM + r"data-decided"])
case("23", "free=YES meaning free", mut(('title="Tema uno"', 'title="Tema uno" free=YES')),
     expect="either", names=r"free='?(YES|maybe|1)", has=[ITEM + r"data-free"])
case("23b", "free=maybe", mut(('title="Tema uno"', 'title="Tema uno" free=maybe')), names=r"free='?(YES|maybe|1)")
case("23c", "free=1", mut(('title="Tema uno"', 'title="Tema uno" free=1')),
     expect="either", names=r"free='?(YES|maybe|1)", has=[ITEM + r"data-free"])
case("24", "select=multi", mut(('title="Tema uno"', 'title="Tema uno" select=multi')), names=r"select='?multi")
case("25", "proposal=YES", mut(('title="Tema uno"', 'title="Tema uno" decided=yes proposal=YES')), names=r"proposal='?YES")

# 26-27: nesting
case("26", "nested group", doc(group(Q1 + group(Q2, "G2", "Otro"))), names=r"`group` may only")
case("26b", "item inside an item", doc(group(Q1.replace("\n:::\n\n", "\n\n" + Q2 + ":::\n\n", 1))), names=r"`item` may only")
case("26c", "masthead inside a group", doc(group(Q1 + MAST)), names=r"`masthead` may only")
case("26d", "section inside a section", MAST + sec(sec("texto", "S2", "Dentro")), names=r"`section` may only")
case("26e", "notes inside a group", doc(group(Q1 + NOTES), notes=""), names=r"`notes` may only")
case("27", "item inside a callout", in_section("::: callout\n" + Q3 + ":::"), names=r"`item`.*callout|callout.*`item`")
case("27b", "chart inside the masthead",
     mut(("Una frase de apertura.\n", "Una frase de apertura.\n::: chart {type=bar}\nA,1\nB,2\n:::\n")), names=r"cannot contain a `chart`")
case("27c", "note inside a ledger", in_section("::: ledger\n::: note\ntexto\n:::\n:::"), names=r"cannot contain a `note`")

# 28-38: page-level and structure
# 28 and 47 strict: a page carries one masthead / its language; "valid" needs exactly one masthead
case("28", "two mastheads", MAST + BASE, expect="either", names=r"two mastheads|second masthead|more than one masthead", count=[(r'<header class="masthead"', 1)])
case("28b", "a masthead after content", mut(("::: notes", MAST + "::: notes")), expect="either", names=r"two mastheads|second masthead|more than one masthead",
     count=[(r'<header class="masthead"', 1)])
case("29", "no masthead", BASE.replace(MAST, ""), names=r"no document title")
case("30", "empty spec", "", names=r"no document title")
case("30b", "whitespace-only spec", "  \n\n\n", names=r"no document title")
case("30c", "prose-only spec", "Solo un párrafo de texto, sin bloques.\n", names=r"no document title")
case("31", "empty group", doc(group("")), expect="refuse", names=r"carries no decision")
case("32", "empty item body", doc(group(Q1 + '::: item {#Q2 title="Tema dos"}\n:::\n\n')), expect="refuse",
     names=r"'Q2' offers")
case("33", "empty note", in_section("::: note\n:::"), names=r"`note` is empty")
case("33b", "empty callout", in_section("::: callout\n:::"), names=r"`callout` is empty")
case("33c", "empty chart", in_section("::: chart {type=bar}\n:::"), names=r"`chart` has no data")
case("33d", "empty diagram", in_section("::: diagram {shape=row}\n:::"), names=r"`diagram` has no body")
case("33e", "empty graph", in_section("::: graph\n:::"), names=r"`graph` has no body")
case("34", "empty ledger", in_section("::: ledger\n:::"), expect="either", names=r"`ledger`.*empty|empty.*ledger")
case("35", "unclosed fence", BASE.rstrip("\n").rsplit(":::", 1)[0], names=r"never closed")
case("35b", "extra close fence", BASE + ":::\n", names=r"close fence with no block open")
# 36: an indented fence is a literal paragraph; valid only if the literal `:::` is not on the page (CNT-1)
case("36", "indented fence lines", in_section("  ::: callout\n  texto\n  :::"),
     expect="either", names=r"indent", lacks=[r":::"])
case("36b", "fence glued to its type", mut(("::: group {#G1", ":::group {#G1")), names=r"close fence with no block open")
case("37", "code fence never closed in an item", mut(("Primera pregunta sin signo final.", "Primera pregunta sin signo final.\n\n```\ncodigo")),
     names=r"code fence")
# 38 lenient on the message: the builder reports the first close fence, not the BOM
case("38", "BOM at the start of the spec", b"\xef\xbb\xbf" + BASE.encode("utf-8"), expect="either",
     names=r"close fence with no block open|BOM|byte order", has=[r"<h1>Informe de prueba"])
case("39", "CRLF spec", BASE.replace("\n", "\r\n").encode("utf-8"), expect="valid",
     count=[(r'<section class="consult-item"', 2)])
case("40", "HTML entity in prose", mut(("Primera pregunta sin signo final.", "Primera &amp; pregunta.")),
     names=r"HTML entity")
# 41 lenient: raw HTML is escaped and shown literally; valid means no live tag reached the page
case("41", "raw HTML in prose", mut(("Primera pregunta sin signo final.", "Primera <script>alert(1)</script> y <b>negrita</b>.")),
     expect="either", names=r"raw HTML|HTML tag|<script>", lacks=[r"<script>alert", r"<b>negrita"])
case("42", "javascript: link", mut(("Primera pregunta sin signo final.", "Mira [esto](javascript:alert(1)).")),
     names=r"link target 'javascript")
case("42b", "data: link", mut(("Primera pregunta sin signo final.", "Mira [esto](data:text/html,x).")),
     names=r"link target 'data")
case("42c", "link inside title=", mut(('title="Tema uno"', 'title="Ver [esto](https://x.org)"')), names=r"title= holds a link")
case("43", "bad pill tone", mut(("Primera pregunta sin signo final.", "Es [raro]{.pill .1x} aquí.")),
     expect="either", names=r"pill|tone", lacks=[r"\{\.pill"])
case("43b", "unknown chip tone", mut(("Primera pregunta sin signo final.", "Es [raro]{.chip .zz} aquí.")),
     expect="either", names=r"chip|tone", lacks=[r"chip zz"])
case("44", "invented class on a block", in_section("::: callout {.evil}\ntexto\n:::"),
     expect="either", names=r"evil|unknown class", lacks=[r'class="[^"]*\bevil\b'])
# 45 lenient: only the geometry probe sees overflow, so these pages also go through the default mode
case("45", "very long token in the masthead title", mut(('title="Informe de prueba"', 'title="%s"' % LONG)),
     expect="either", names=r"long", geometry=True)
case("45b", "very long token in body", mut(("Primera pregunta sin signo final.", "Primera " + "B" * 6000 + " final.")),
     expect="either", names=r"long", geometry=True)
case("45c", "very long chart label", in_section("::: chart {type=bar}\n%s,1\nB,2\n:::" % ("C" * 3000)),
     expect="either", names=r"long", geometry=True)
case("46", "masthead lang outside es/en", mut(('title="Informe de prueba"', 'title="Informe de prueba" lang=fr')),
     names=r"lang='fr'")
case("46b", "masthead lang in capitals", mut(('title="Informe de prueba"', 'title="Informe de prueba" lang=ES')),
     names=r"lang='ES'")
# 47 strict: an English masthead over a Spanish body is a mixed-language page
case("47", "masthead lang=en over a Spanish body", mut(('title="Informe de prueba"', 'title="Informe de prueba" lang=en')),
     expect="either", names=r"mixed|body", has=[r'<html lang="es"'])
case("48", "markdown heading inside an item body", mut(("Primera pregunta sin signo final.", "# Titulo\n\nPrimera pregunta sin signo final.")),
     expect="either", names=r"markdown heading|heading in an item|`# `", lacks=[r"<h3[^>]*>\s*Titulo"])
case("49", "{chosen} on an undecided item", mut(("- No — pista dos", "- No {chosen} — pista dos")), names=r"chosen")
case("49b", "two {chosen} on select=one",
     mut(('title="Tema uno"', 'title="Tema uno" decided=yes'), ("- Sí {recommended}", "- Sí {chosen}"),
         ("- No — pista dos", "- No {chosen} — pista dos")), names=r"chosen")
case("49c", "dropped and decided together", mut(('title="Tema uno"', 'title="Tema uno" dropped="ya no" decided=yes')),
     names=r"dropped and decided")
case("50", "NUL byte in prose", mut(("Primera pregunta", "Primera\x00 pregunta")), expect="either",
     names=r"NUL|control character", lacks=[r"\x00"])
case("51", "hand-editing the built page, then rebuilding",
     steps=(B, ("edit_html", "<h1>Informe de prueba</h1>", "<h1>Informe de prueba</h1><!--HAND-EDIT-->"), B),
     expect="either", names=r"hand[- ]edit|diverg|overwrit", has=[r"HAND-EDIT"])
case("52", "decide before the first build", steps=(decide(),), names=r"before.*build|no page|not built|first build")
case("52b", "new-round before any build", steps=(("verb", "new-round"),), names=r"before.*build|no page|not built|first build")
case("53", "decide an unknown id", steps=(B, REPLY, decide("Q9", "No")), names=r"#Q9")
case("53b", "decide a group", steps=(B, REPLY, decide("G1", "No")), names=r"#G1 is a `group`")
case("53c", "decide with an empty verdict", steps=(B, REPLY, decide("Q1", "")), names=r"empty verdict")
case("53d", "decide yes on an item with options", steps=(B, REPLY, decide("Q1", "yes")), names=r"'yes' would record")
case("54", "decide with a verdict that is no option", steps=(B, ("save", "Q1: Opción inventada que no existe\n"), decide("Q1", "Opción inventada que no existe")),
     expect="either", names=r"verdict.*option|option.*verdict", lacks=[r"Opción inventada"])
# 54b (owner, LOOP-008 Q7): the reply carries a real option AND an extra line with no words, so
# the invented verdict cannot hide behind a one-line reply (case 54 passed while "option + any
# line" let it through). A worded note ("Gracias") is the documented free-text route and passes.
case("54b", "decide with an invented verdict beside a real option and a wordless extra line",
     steps=(B, ("save", "Q1: No\n\n---\n"), decide("Q1", "Opción inventada que no existe")),
     expect="either", names=r"verdict.*option|option.*verdict", lacks=[r"Opción inventada"])
# 55: a question added to the spec after the reply was saved, then decided through the verb
case("55", "decide a question added after the saved reply",
     steps=(B, REPLY, ("edit_spec", Q2, Q2 + Q3), B, decide("Q3", "Alfa")), names=r"#Q3|Q3 is shown as Decided")
case("56", "multi-line verdict", steps=(B, REPLY, decide("Q1", "uno\ndos")), names=r"verdict|quoted value|newline")
case("57", "add-item with a duplicate id",
     steps=(B, ("verb", "add-item", "--group", "G1", "--id", "Q1", "--title", "X", "--option", "Uno", "--option", "Dos")),
     names=r"already used")
case("57b", "add-item into a missing group",
     steps=(B, ("verb", "add-item", "--group", "GX", "--id", "Q3", "--title", "X", "--option", "Uno", "--option", "Dos")),
     names=r"no `group` with id #GX")
case("57c", "add-item with a bare ::: in the body",
     steps=(B, ("verb", "add-item", "--group", "G1", "--id", "Q3", "--title", "X", "--body", "uno\n:::\ndos",
                "--option", "Uno", "--option", "Dos")), names=r"--body|bare|close fence")
case("57d", "add-item with a parenthetical option",
     steps=(B, ("verb", "add-item", "--group", "G1", "--id", "Q3", "--title", "X", "--option", "Uno (rec)",
                "--option", "Dos")), names=r"parenthetical")
case("58", "--new-round with no saved reply", steps=(B, ("build", "--new-round")), names=r"no saved reply")
case("58b", "--new-round again after a verb rebuild",
     steps=(B, REPLY, decide(), ("build", "--new-round")), names=r"no saved reply")
case("59", "save-reply on a missing page", steps=(("save", "Q1: No\n"),),
     names=r"(?m)^usage: save-reply\.sh .*is not a file")
case("59b", "save-reply with an empty reply", steps=(B, ("save", "  \n")), names=r"reply is empty")
case("60", "save-reply with a reply path that does not exist", steps=(B, ("savefile", "nope.reply.txt")),
     names=r"cannot read the reply")
# 61 by design: a second save appends under a separator; both replies must be on disk
case("61", "second save-reply before a rebuild",
     steps=(B, ("save", "Q1: primera respuesta\n"), ("save", "Q1: segunda respuesta\n")), expect="valid",
     files_has=[(".aidex-artifact-prev/m61.reply.md", r"primera respuesta"),
                (".aidex-artifact-prev/m61.reply.md", r"segunda respuesta")])
case("62", "spec file that is not UTF-8", BASE.replace("Una frase", "Una fr\x00ase").encode("utf-8").replace(b"\x00", b"\xff"),
     names=r"not UTF-8")

CHART = "::: chart {%s}\n%s\n:::"
case("63", "chart with a decimal comma", in_section(CHART % ("type=bar", "A,1,5\nB,2")), names=r"3 comma-separated")
case("63b", "chart value 1e3", in_section(CHART % ("type=bar", "A,1e3\nB,2")), names=r"'1e3'")
case("63c", "chart value NaN", in_section(CHART % ("type=bar", "A,NaN\nB,2")), names=r"'NaN'")
case("63d", "chart table with a ragged row", in_section(CHART % ("type=bar", "| k | a | b |\n|---|---|---|\n| x | 1 | 2 |\n| y | 3 |")),
     names=r"2 cells and the header has 3")
case("63e", "chart with nine series",
     in_section(CHART % ("type=bar", "| k | " + " | ".join("s%d" % i for i in range(10)) + " |\n|---|" + "---|" * 10 +
                         "\n| x | " + " | ".join("1" for _ in range(10)) + " |")), names=r"10 series")
case("63f", "chart without a type", in_section("::: chart\nA,1\nB,2\n:::"), names=r"needs type=")
case("64", "chart value with 400 digits", in_section(CHART % ("type=bar", "A,%s\nB,2" % ("9" * 400))), names=r"out of a chart's range")
DIA = "::: diagram {%s}\n%s\n:::"
case("65", "diagram with nine boxes", in_section(DIA % ("shape=row", "\n".join("a%d: Caja %d" % (i, i) for i in range(9)))),
     names=r"9 boxes")
case("65b", "diagram box with a unicode name", in_section(DIA % ("shape=row", "ñ: Caja\nb: Otra")), names=r"neither a box nor an arrow")
case("65c", "diagram arrow to an unknown box", in_section(DIA % ("shape=row", "a: A\nb: B\na -> zz")), names=r"`zz`")
case("65d", "diagram cycle of one box", in_section(DIA % ("shape=cycle", "a: A")), names=r"has one box")
case("65e", "diagram dir on a cycle", in_section(DIA % ("shape=cycle dir=lr", "a: A\nb: B\nc: C\na -> b\nb -> c\nc -> a")),
     names=r"dir= is a `row`")
case("66", "graph with bad DOT", in_section("::: graph\nthis is not dot {{{\n:::"), names=r"Graphviz refused")
case("66b", "graph with a colour", in_section("::: graph\ndigraph { a [color=red]; a -> b }\n:::"), names=r"colour")
FIG = "::: figure {src=\"%s\" title=\"Figura\"}\n:::"
case("67", "figure with a missing file", in_section(FIG % "nope.svg"), names=r"no such file")
case("67b", "figure with an absolute path", in_section(FIG % "/etc/hosts.svg"), files={"hosts.svg": SVG}, names=r"absolute")
case("67c", "figure with a bad file type", in_section(FIG % "x.gif"), files={"x.gif": b"GIF89a"}, names=r"type|extension")
# 68 lenient: `..` is legitimate (assets beside the reports folder); valid means the figure got in
case("68", "figure src escaping the spec folder", in_section(FIG % "../out.svg"), expect="either",
     names=r"outside|escap|\.\./out\.svg", files={"../out.svg": SVG}, has=[r"<svg"])
case("69", "gallery without rows",
     mut(("::: group {#G1", '::: gallery {#GAL title="Galería"}\n:::\n\n::: group {#G1')), names=r"non-empty rows")
case("69b", "gallery with a missing rows file",
     mut(("::: group {#G1", '::: gallery {#GAL title="Galería" rows="nope.json"}\n:::\n\n::: group {#G1')), names=r"nope|no such rows", git=True)
case("70", "nesting 1500 deep", mut(("::: group {#G1", deep_notes(1500) + "::: group {#G1")),
     names=r"fences nest at most|depth")
# 71 lenient: a ragged pipe table in prose renders as is
case("71", "ragged pipe table in prose", in_section("| a | b |\n|---|---|\n| 1 |\n| 1 | 2 | 3 |"),
     expect="either", names=r"table|cell|column", has=[r"<table"])
case("72", "item with exactly one option", mut((OPTS2, "- Alfa — pista a")), expect="refuse",
     names=r"'Q2' offers")
case("73", "verdict that is not a table", in_section("::: verdict\nsolo texto\n:::"), names=r"pipe table")
case("73b", "verdict with a win that names no cell",
     in_section('::: verdict {win="zzz"}\n| 1 | Uno |\n| 2 | Dos |\n:::'), names=r"win='zzz'")
case("74", "dropped-ids naming a live item", mut(('title="Informe de prueba"', 'title="Informe de prueba" dropped-ids="Q1"')),
     names=r"dropped-ids")
case("74b", "retitled-ids naming an absent item", mut(('title="Informe de prueba"', 'title="Informe de prueba" retitled-ids="Q9"')),
     names=r"retitled-ids")
PROFILE_EN = "## Language\n\n- language: en\n"
case("75", "verbs in an en-profile project with a silent masthead", steps=(B, REPLY, decide()), expect="either",
     names=r"masthead[^\n]*lang=|lang=[^\n]*masthead", profile=PROFILE_EN, has=[r'<html lang="en"', r'data-decided="No"'])
case("75b", "verbs on a page whose masthead declares lang=en", BASE_EN, steps=(B, REPLY, decide("Q1", "No")), expect="valid",
     has=[r'<html lang="en"', r'data-decided="No"'])

# Phase B shapes that are not a §5 row
case("x-0items", "a consultation with no item at all (refused, or a page with zero items)", doc(), expect="either", count=[(r'<section class="consult-item"', 0)], names=r"carries no decision|no item|nothing to answer")
case("x-1item", "one item", doc(group(Q1)), expect="valid", count=[(r'<section class="consult-item"', 1)])
case("x-40items", "forty items in one group",
     doc(group("".join(item("Q%d" % i, "Tema %d" % i, "Pregunta %d sin signo final." % i, OPTS2) for i in range(1, 41)))),
     expect="valid", count=[(r'<section class="consult-item"', 40)])
case("x-emptysection", "a section with a heading and no body", MAST + sec(""), expect="either",
     names=r"`section`.*empty|empty section|no body")

# hand-edited built HTML: the page is built, edited, and the consumer pipeline (check-artifact, then
# the probe) must refuse the damage or the page must still be valid with its meaning intact
H = ('<section class="consult-item" data-id="Q1"')
case("h1", "hand edit: an id carried twice", steps=(B, ("edit_html", H, H.replace("data-id", 'id="G1" data-id')), ("check",)),
     expect="either", names=r'"G1"|id G1', count=[(r'id="G1"', 1)])
HM = '<header class="masthead">\n<h1>Informe de prueba</h1>\n<p class="standfirst">Una frase de apertura.</p>\n</header>\n'
case("h2", "hand edit: masthead removed", steps=(B, ("edit_html", HM, ""), ("check",)),
     expect="either", names=r"no masthead|missing masthead|\bh1\b", count=[(r'<header class="masthead"', 1)])
case("h3", "hand edit: second masthead", steps=(B, ("edit_html", HM, HM + HM), ("check",)),
     expect="either", names=r"second masthead|two mastheads|more than one masthead|\bh1\b", count=[(r'<header class="masthead"', 1)])
LAB = '  <div class="opts one">\n    <label><input type="radio" name="Q1" data-label="Sí" data-recommended><span>Sí <span class="hint">pista uno</span></span></label>\n    <label><input type="radio" name="Q1" data-label="No"><span>No <span class="hint">pista dos</span></span></label>\n  </div>\n'
case("h4", "hand edit: an item's options removed", steps=(B, ("edit_html", LAB, ""), ("check",)),
     expect="either", names=r"offers 0 option", count=[(r'<input type="radio" name="Q1"', 2)])


# Y is pinned: a case dropped from the table must not read as green. The wiring in invariant_gate.py
# sets MIN["mutations"] to this number (`python3 mutations_gate.py --expected` prints it).
EXPECTED_CASES = 155
if len(CASES) != EXPECTED_CASES:
    raise SystemExit("mutations_gate: %d cases, EXPECTED_CASES is %d" % (len(CASES), EXPECTED_CASES))


# --- the runner ----------------------------------------------------------------------------------
class Result:
    def __init__(self, cmd, rc, out, label, stdin=None):
        self.cmd, self.rc, self.out, self.label, self.stdin = cmd, rc, out, label, stdin


def read(path):
    try:
        with open(path, "rb") as fh:
            return fh.read()
    except OSError:
        return None


def run(cmd, cwd, stdin=None):
    try:
        r = subprocess.run(cmd, cwd=cwd, input=stdin, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           timeout=STEP_TIMEOUT)
        return r.returncode, r.stdout.decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        return None, "timeout after %ds" % STEP_TIMEOUT


def prepare(c, root):
    """The case's tree <root>/r<id>/.context/reports with its spec, files and profile."""
    safe = re.sub(r"[^A-Za-z0-9]", "", c["id"])
    top = os.path.join(root, "r" + safe)
    reports = os.path.join(top, ".context", "reports")
    os.makedirs(reports)
    stem = "m" + safe
    spec = os.path.join(reports, stem + ".spec.md")
    data = c["spec"] if isinstance(c["spec"], bytes) else c["spec"].encode("utf-8")
    with open(spec, "wb") as fh:
        fh.write(data)
    for rel, blob in c["files"].items():
        p = os.path.normpath(os.path.join(reports, rel))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as fh:
            fh.write(blob)
    if c["git"]:      # `gallery rows=` is relative to the checkout root; without one the refusal is about that
        subprocess.run(["git", "init", "-q", top], check=True)
    if c["profile"]:
        os.makedirs(os.path.join(top, ".context", "profiles"))
        with open(os.path.join(top, ".context", "profiles", "artifact.md"), "w") as fh:
            fh.write(c["profile"])
    return reports, spec, os.path.join(reports, stem + ".html")


def step_cmd(st, spec, page, reports):
    kind = st[0]
    if kind == "build":
        return [sys.executable, os.path.join(SCRIPTS, "spec_build.py"), spec, "-o", page] + list(st[1:]), None
    if kind == "verb":
        return [sys.executable, os.path.join(SCRIPTS, "spec_verbs.py"), st[1], spec, "--out", page] + list(st[2:]), None
    if kind == "save":
        return ["bash", os.path.join(SCRIPTS, "save-reply.sh"), page if len(st) < 3 else st[2], "-"], st[1].encode()
    if kind == "savefile":
        return ["bash", os.path.join(SCRIPTS, "save-reply.sh"), page, os.path.join(reports, st[1])], None
    if kind == "check":
        return ["bash", os.path.join(SCRIPTS, "check-artifact.sh"), page], None
    raise SystemExit("mutations_gate: unknown step %r" % (kind,))


def execute(c, root):
    """Run the steps. -> dict(page, spec, results, before, setup_fault, final)"""
    reports, spec, page = prepare(c, root)
    results, fault = [], None
    before = {}
    for n, st in enumerate(c["steps"]):
        last = n == len(c["steps"]) - 1
        if last:
            before = {"spec": read(spec), "page": read(page)}
        if st[0] in ("edit_spec", "edit_html"):
            path = spec if st[0] == "edit_spec" else page
            text = (read(path) or b"").decode("utf-8", "replace")
            if st[1] not in text:
                fault = "setup step %d (%s): %r is not in the file" % (n + 1, st[0], st[1][:60])
                break
            with open(path, "wb") as fh:
                fh.write(text.replace(st[1], st[2], 1).encode("utf-8"))
            results.append(Result(None, 0, "", "%s %r" % (st[0], st[1][:40])))
            continue
        cmd, stdin = step_cmd(st, spec, page, reports)
        rc, out = run(cmd, reports, stdin)
        results.append(Result(cmd, rc, out, " ".join(str(x) for x in st), stdin))
        if not last and (rc != 0 or TRACEBACK in out):
            fault = "setup step %d (%s) did not succeed (rc=%s): %s" % (n + 1, st[0], rc, out.strip()[:160])
            break
    return dict(page=page, spec=spec, reports=reports, results=results, before=before, fault=fault,
                after={"spec": read(spec), "page": read(page)})


def without_notices(out):
    """The output minus WARN and NOTE lines: a page-level warning is never what refused the build."""
    return "\n".join(ln for ln in out.splitlines() if not re.match(r"\s*(WARN|NOTE)\b", ln))


def headline(out):
    """The line of a tool's output that says why it failed (a FAIL/ERROR/spec-* line), else the first."""
    lines = [ln.strip() for ln in out.splitlines() if ln.strip()]
    return next((ln for ln in lines if re.match(r"(FAIL|ERROR|spec-)", ln)), lines[0] if lines else "no output")[:200]


def judge_refusal(c, x):
    """None when the last step refused as the contract demands, else the reason."""
    r = x["results"][-1]
    if r.rc is None:
        return "hang: " + r.out
    if TRACEBACK in r.out:
        return "refused with a Python traceback"
    if c["names"] and not re.search(c["names"], without_notices(r.out), re.I):
        return "refusal does not name the problem (expected /%s/): %s" % (c["names"], r.out.strip()[:160])
    if x["after"]["spec"] != x["before"]["spec"]:
        return "refused but the spec was changed (half-written)"
    if x["after"]["page"] != x["before"]["page"]:
        return "refused but the page was %s (half-written)" % ("created" if x["before"]["page"] is None else "changed")
    return None


def judge_meaning(c, x):
    page = (x["after"]["page"] or b"").decode("utf-8", "replace")
    for rx in c["has"]:
        if not re.search(rx, page):
            return "built page lacks /%s/ (the intended meaning did not land)" % rx
    for rx in c["lacks"]:
        m = re.search(rx, page)
        if m:
            return "built page carries /%s/ (%r): the mistake took effect silently" % (rx, m.group(0)[:60])
    for rx, n in c["count"]:
        k = len(re.findall(rx, page))
        if k != n:
            return "built page has %d x /%s/, intent is %d" % (k, rx, n)
    for rel, rx in c["files_has"]:
        txt = (read(os.path.join(x["reports"], rel)) or b"").decode("utf-8", "replace")
        if not re.search(rx, txt):
            return "%s lacks /%s/" % (rel, rx)
    return None


def probe(pages, flags):
    """(rc, stdout, stderr) of one probe call; the fake or the real script."""
    r = subprocess.run(["bash", PROBE] + flags + pages, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return r.returncode, r.stdout, r.stderr


def invariants(pages):
    """({basename: [violation lines]}, set(pages with no verdict)). Unknown -> None."""
    def one_call(batch):
        rc, out, err = probe(batch, ["--invariants"])
        m = re.search(r"^INVARIANTS pages=(\d+) violations=(\d+)$", out, re.M)
        if rc not in (0, 1) or not m or int(m.group(1)) != len(batch):
            return None
        fired = {}
        for ln in out.splitlines():
            mm = re.match(r"^INV (\S+) (\S+) (.*)$", ln)
            if mm:
                fired.setdefault(mm.group(2), []).append("%s %s" % (mm.group(1), mm.group(3)))
        return fired
    got = one_call(pages)
    if got is not None:
        return got, set()
    fired, nope = {}, set()                      # the batch had no verdict: isolate the page that did it
    for p in pages:
        g = one_call([p])
        if g is None:
            nope.add(os.path.basename(p))
        else:
            fired.update(g)
    if len(nope) == len(pages):
        return None, nope
    return fired, nope


def geometry(pages):
    rc, out, err = probe(pages, [])
    if rc not in (0, 1):
        return None
    fired = {}
    for ln in out.splitlines():
        m = re.match(r"^DEFECT (\S+) (.*)$", ln)
        if m:
            fired.setdefault(m.group(1), []).append(m.group(2))
    return fired


def repro(c, x, root):
    lines = ["    spec (%s):" % os.path.basename(x["spec"])]
    spec = (c["spec"] if isinstance(c["spec"], str) else repr(c["spec"][:200]))
    sl = spec.splitlines()
    lines += ["      " + ln[:140] for ln in sl[:40]] + (["      ... (%d more lines)" % (len(sl) - 40)] if len(sl) > 40 else [])
    lines.append("    commands, in a directory laid out as .context/reports/ (the spec above saved as m.spec.md):")
    for r in x["results"]:
        sh = " ".join(shlex.quote(a) for a in r.cmd).replace(x["reports"] + os.sep, "") if r.cmd else r.label
        lines.append("      " + (("printf %s | " % shlex.quote(r.stdin.decode())) if r.stdin else "") + sh)
    return "\n".join(lines)


def main(argv):
    if "--expected" in argv:
        print(EXPECTED_CASES)
        return 0
    verbose = "--verbose" in argv
    only = None
    if "--only" in argv:
        only = argv[argv.index("--only") + 1] if argv.index("--only") + 1 < len(argv) else ""
    cases = [c for c in CASES if only is None or re.fullmatch(re.escape(only) + r"[a-z]?", c["id"])]
    root = tempfile.mkdtemp(prefix="mutations-gate-")
    fails = {}                                       # id -> (reason, case, exec)
    try:
        pending = []                                 # (case, exec): valid path, waits for the probe
        for c in cases:
            x = execute(c, root)
            if x["fault"]:
                fails[c["id"]] = ("HARNESS FAULT " + x["fault"], c, x)
                continue
            r = x["results"][-1]
            if any(TRACEBACK in q.out for q in x["results"]):
                fails[c["id"]] = ("a Python traceback came out of %s" % r.label.split()[0], c, x)
            elif r.rc is None:
                fails[c["id"]] = ("hang: " + r.out, c, x)
            elif c["expect"] == "refuse" or (c["expect"] == "either" and r.rc != 0):
                if r.rc == 0:
                    fails[c["id"]] = ("silently accepted: rc=0 where a refusal is the only right answer", c, x)
                else:
                    why = judge_refusal(c, x)
                    if why:
                        fails[c["id"]] = (why, c, x)
            else:                                    # valid path: rc must be 0 and the page must exist
                if r.rc != 0:
                    fails[c["id"]] = ("rc=%d where a valid page was expected: %s" % (r.rc, headline(r.out)), c, x)
                elif x["after"]["page"] is None:
                    fails[c["id"]] = ("rc=0 but no page was written", c, x)
                else:
                    why = judge_meaning(c, x)
                    if why:
                        fails[c["id"]] = (why, c, x)
                    else:
                        pending.append((c, x))
        if pending:
            pages = [x["page"] for _, x in pending]
            got, nope = invariants(pages)
            if got is None:
                sys.stderr.write("mutations-gate: the probe gave no verdict on %d page(s): is Playwright installed "
                                 "(AIDEX_PLAYWRIGHT_DIR)?\n" % len(pages))
                print("mutations: 0/unknown")
                return 1
            for c, x in pending:
                b = os.path.basename(x["page"])
                if b in nope:
                    fails[c["id"]] = ("the probe crashed on this page (no verdict)", c, x)
                elif got.get(b):
                    fails[c["id"]] = ("built page violates %d invariant(s): %s" % (len(got[b]), "; ".join(got[b])[:300]), c, x)
            geo = [(c, x) for c, x in pending if c["geometry"] and c["id"] not in fails]
            if geo:
                g = geometry([x["page"] for _, x in geo])
                for c, x in geo:
                    if g is None:
                        fails[c["id"]] = ("the geometry probe gave no verdict", c, x)
                    elif g.get(os.path.basename(x["page"])):
                        fails[c["id"]] = ("built page has geometry defects: %s" % "; ".join(g[os.path.basename(x["page"])])[:300], c, x)
        total = len(cases)
        if verbose:
            for cid, (why, c, x) in sorted(fails.items(), key=lambda kv: [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", kv[0])]):
                sys.stderr.write("FAIL %s %s\n    %s\n    reproduce: python3 %s --only %s --verbose\n%s\n"
                                 % (cid, c["name"], why, os.path.relpath(os.path.abspath(__file__)), cid, repro(c, x, root)))
        print("mutations: %d/%d" % (total - len(fails), total))
        return 0 if total >= 1 and not fails else 1
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
