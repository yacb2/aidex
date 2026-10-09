#!/usr/bin/env python3
"""gallery_items.py — a rows JSON becomes one consult-group of review rows.

A review row is ONE screen state in ONE variant (`light-desktop`, …), shown as
the pair the owner rules on: "before" (the committed baseline) and "after" (the
run's proposed render). A state whose screen is new has no baseline, so its row
shows the one capture, labelled as new. The project owns which rows exist and
emits them as rows JSON (for example a `gallery_board.py --rows-json` script):
the variants the owner chose to review, plus every cell that changed without
being asked for (`kind: "unrequested"`). This script turns that document into
markup the kit already understands — `consult-item consult-gallery` sections
with an `.opts one` verdict group and a notes textarea, so `composer.js` pastes
them like any other item and every rule in check_artifact.py keeps applying.

Nothing about the gate is written on the page: no summary, no check output.
An unrequested change reaches the owner as a row, and when there is none the
page says nothing about checks at all.

The output is DETERMINISTIC: row order is the document's, and nothing here
reads the clock or the environment. The one filesystem read is each capture's
PNG header: a capture with no file behind it is refused, and its width and
height go on the <img>, so a lazy image reserves its box before it loads.

Images are copied, never inlined (BL-474). `--root` is the absolute checkout
the paths are relative to, and `--page` the page the block is for: every capture
is copied to `<page-stem>-assets/gallery/<sha256[:16]>.png` beside it and the
<img> links that copy by relative path. The captures live where the project's
runner wipes them (Playwright empties `test-results/` at the start of every
run), so a page that linked them by `file://` showed broken images the day
after it was built. The name is the content's hash: a rebuild of the same rows
is byte-identical, and a re-capture is a new file, hence a new `src`, hence a
new question. Nothing is copied until every row has passed, and a rebuild after
the sources are gone is refused by the same "has no file" line as any missing
capture — the page already built, and its copies, are left as they were.

Usage:
  gallery-items.sh <rows.json> --root <abs repo root> --page <out.html> \
      --group-id <id> --group-title <title> [--lang es|en]
"""

import argparse
import hashlib
import html
import json
import math
import os
import re
import shutil
import struct
import sys
import urllib.parse

import md_body
from _usage import UsageParser
import png_pixels

LANGS = ("es", "en")

# The two tiles of a row, in reading order. English tokens on purpose: they are
# the `data-tile` the checker, the composer's arrows and compare, and a pasted
# mark (`[mark after …]`) all key on, whatever the page's language. What the
# reader sees is the caption below.
TILES = ("before", "after")
TILE_WORDS = {"es": {"before": "antes", "after": "propuesto",
                     "new": "pantalla nueva", "none": "sin antes"},
              "en": {"before": "before", "after": "proposed",
                     "new": "new screen", "none": "no before"}}

# What a variant name says, in the page's language (see `variant_label`).
VIEW_WORDS = {"es": {"desktop": "escritorio", "mobile": "móvil",
                     "tablet": "tableta"},
              "en": {"desktop": "desktop", "mobile": "mobile",
                     "tablet": "tablet"}}
# The variant line under a capture (BL-594): said once, in the page's language,
# `<view>, <theme>`; a variant that does not split is shown as its own name.
VARIANT_LINE = {"es": "Vista: %s", "en": "View: %s"}
THEME_WORDS = {"es": {"light": "tema claro", "dark": "tema oscuro"},
               "en": {"light": "light theme", "dark": "dark theme"}}

# `review` is a row the owner chose (a declared change in a chosen variant);
# `unrequested` is a cell that moved without being in the change set; `sample`
# illustrates and asks nothing, so it carries no verdict (BL-466).
# `alternatives` is N labelled variants of one cell (a skeleton review): the
# labels come from the rows document, so nothing says "before" of a state that
# has no before (BL-516).
# `states` is N locator-scoped captures of ONE component, each ticked or not:
# one item, one checkbox per state (BL-659).
KINDS = ("review", "unrequested", "sample", "alternatives", "states")

VERDICTS = {
    "es": [("Aprobada", "Aprobada: lo propuesto queda como referencia"),
           ("Necesita cambios", "Necesita cambios (di cuáles en las notas)"),
           ("No puedo juzgarla así", "No puedo juzgarla con esta captura")],
    "en": [("Approved", "Approved: the proposed capture becomes the baseline"),
           ("Needs changes", "Needs changes (say which in the notes)"),
           ("Cannot judge", "Cannot judge it from this capture")],
}

# The narrow-screen hint (BL-615): the button word is the composer's zoomLabel.
NARROW_HINT = {"es": "En el móvil, toca Ampliar para leer cada captura.",
               "en": "On a phone, tap Enlarge to read each capture."}

# The ONE instruction of a gallery (BL-595), written under the block's heading
# and assembled from the kinds of row it holds, so a row repeats nothing.
INTRO = {
    "es": {"ask": "Marca tu respuesta en cada fila y, si necesita cambios, di "
                  "cuáles en las notas de esa fila.",
           "new": "Donde hay una sola captura, la pantalla es nueva y no hay "
                  "antes.",
           "new_mixed": "Donde hay una sola captura, la pantalla es nueva y no "
                        "hay antes, salvo donde la fila dice por qué no hay "
                        "antes.",
           "sample": "Las muestras no piden respuesta.",
           "waits": "Las filas que esperan una decisión abierta son solo "
                    "contexto y no piden respuesta.",
           "alt": "Elige una variante en cada fila y, si quieres matizar, di "
                  "por qué en las notas de esa fila.",
           "na": "Un estado que no se puede mostrar explica el motivo en su "
                 "fila; marca tu respuesta igual.",
           "states": "Marca cada estado que apruebas y, para el resto, di qué "
                     "cambiar en las notas."},
    "en": {"ask": "Mark your answer on each row and, if it needs changes, say "
                  "which in that row's notes.",
           "new": "Where there is a single capture, the screen is new and "
                  "there is no before.",
           "new_mixed": "Where there is a single capture, the screen is new "
                        "and there is no before, except where the row says "
                        "why there is no before.",
           "sample": "Samples ask for no answer.",
           "waits": "Rows that wait on an open decision are context only and "
                    "ask for no answer.",
           "alt": "Pick a variant on each row and, if you want to qualify it, "
                  "say why in that row's notes.",
           "na": "A state that cannot be shown gives the reason on its row; "
                 "mark your answer anyway.",
           "states": "Tick each state you approve and, for the rest, say what "
                     "to change in the notes."},
}

# What a sample row says where its answer options would be (BL-693).
ASKS_NOTHING = {"es": "Solo ilustra: no necesita respuesta",
                "en": "Illustration only: no answer needed"}

# What a row says while the consult item it depends on is still open (BL-690).
WAITS_ON = {"es": "Solo contexto: espera la decisión de %s",
            "en": "Context only: waits for the decision on %s"}

# Verdicts past this many stay behind a <summary>: the row asks verdict + note.
VISIBLE_VERDICTS = 2
MORE = {"es": "Más opciones", "en": "More options"}
NONE_OF_THEM = {"es": ("Ninguna", "Ninguna me convence (di qué falta en las notas)"),
                "en": ("None of them", "None of them works (say what is missing in the notes)")}
# The kit's injected "Other" option (L.other in composer.js, both languages):
# a copy, because the source is JavaScript. A label that equals it, or the
# none-of-them label, would make two radios paste the same line.
OTHER = ("Other — see my notes", "Otra — lo explico en las notas")
MARKER_LABEL = re.compile(r"^\[[a-z-]+\]$")
# On a not-applicable row of an alternatives document nothing is "proposed".
NA_AGREE = {"es": "De acuerdo: la celda no aplica",
            "en": "Agreed: the cell does not apply"}
LOOK_LABEL = {"es": "Qué mirar", "en": "What to look at"}
DROPPED_WORD = {"es": "Descartada", "en": "Dropped"}

FLAG = {"es": "cambió sin que lo pidieras", "en": "changed without you asking"}
ALSO = {"es": "también en: ", "en": "also in: "}

NOTES_LABEL = {"es": "Notas sobre esta fila", "en": "Notes on this row"}
NOTES_PLACEHOLDER = {"es": "Qué cambiar…", "en": "What to change…"}
# The block's own free text (BL-701): the gallery group closes with the same
# box spec_build.emit_group writes for every other group; the strings are the
# kit's own (md_body.CHROME groupNotes / groupNotesPh).

ROW_ID = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)+$")
SLUG = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
# The block's id becomes an HTML `id`, a `data-id` and the anchor the rail links
# to. Anything else is either unaddressable or, quoted into the attribute, the
# author's own markup.
GROUP_ID = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*$")


def die(msg):
    """Exit 2 with a plain line. A malformed document is the caller's bug, and
    a traceback tells them about this file instead of about their JSON."""
    sys.stderr.write("gallery-items: " + msg + "\n")
    raise SystemExit(2)


def e(s):
    return html.escape(str(s), quote=True)


def variant_label(variant, lang):
    """`escritorio, tema claro`: a variant is `<mode>-<viewport>`, said in the
    page's language; one that does not split is shown as its own name."""
    parts = variant.split("-")
    if len(parts) == 2:
        mode = THEME_WORDS[lang].get(parts[0])
        view = VIEW_WORDS[lang].get(parts[1])
        if mode and view:
            return view + ", " + mode
    return variant


def variant_line(variant, lang):
    """`Vista: escritorio, tema claro` — the variant once, under the capture."""
    return VARIANT_LINE[lang] % variant_label(variant, lang)


def row_heading(row_title, cell, variant=None, lang="es"):
    """What the reader sees as the row's heading and in the rail: the row's own
    `title`, else the cell's name read as words (`users-list-menu` -> `Users
    list menu`) — never the `<gallery> · <cell> · <variant>` key, which stays
    the reply's `data-title` (gallery_reply.py reads rows by it). A `variant`
    is passed only when the cell has several in the block and the row is folded
    (decided or dropped; an open row says its variant under the capture): it is then added, so
    two untitled rows of one cell do not fold to the same label."""
    if row_title:
        return plain_text(row_title)
    words = cell.replace("-", " ")
    words = words[:1].upper() + words[1:]
    return words + " · " + variant_label(variant, lang) if variant else words


def plain_text(text):
    """Visible text of inline markup (markers and tags dropped): what an attribute
    or an alt text carries, since it cannot show a rendered span."""
    return html.unescape(re.sub(r"<[^>]+>", "", md_body._inline(text)))


def heading_html(row_title, heading):
    """The `<h3>` content: a row's own title renders its inline markers (the
    `title=` rules), a name derived from the cell is plain text."""
    return md_body._inline(row_title) if row_title else e(heading)


def row_id(gallery, cell, variant, kind):
    """`<gallery>-<cell>-<variant>`, plus `-<kind>` for a row that is not a
    review. Derived from names only, so a row keeps its id across rounds and
    an answer stays attached to the question it was given for; an unrequested
    change is a different question from a requested one, so it is a different
    id."""
    ident = "%s-%s-%s" % (gallery, cell, variant)
    return ident if kind == "review" else ident + "-" + kind


def check_path(value, cell, tile):
    """A row path is relative to the repo root, because `--root` is what turns
    it into a URL. An absolute one silently ignores --root and pins the page to
    one machine; a `..` climbs out of the checkout, and the page then shows
    whatever is up there."""
    if not isinstance(value, str):
        die("row '%s': the '%s' path must be a string, not %s"
            % (cell, tile, type(value).__name__))
    if not value.strip():
        die("row '%s' has an empty '%s' path" % (cell, tile))
    if value.startswith("/") or os.path.isabs(value) \
            or ".." in value.replace("\\", "/").split("/"):
        die("row '%s': the '%s' path (%r) must be relative to the repo root "
            "— --root is what makes it a URL, and a path that ignores it pins "
            "the page to one machine or points outside the checkout"
            % (cell, tile, value))


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def capture_path(root, rel):
    """A capture's file under `root`. `render` strips the root's trailing slash,
    so `--root /` arrives as "": `or "/"` keeps it from reading relative to the
    working directory. A gallery row's `rel` has passed check_path, so it is
    relative; spec_build's figure highlight passes an absolute path, which
    os.path.join keeps as is — do not rewrite this as string concatenation."""
    return os.path.join(root or "/", rel)


def png_size(root, value, cell, tile):
    """(width, height) of the capture, read from its IHDR chunk."""
    full = capture_path(root, value)
    try:
        with open(full, "rb") as fh:
            head = fh.read(24)
    except OSError:
        die("row '%s': '%s' has no file at %s — a missing capture shows the "
            "reader a broken image where the screenshot should be"
            % (cell, tile, full))
    if len(head) < 24 or head[:8] != PNG_SIGNATURE or head[12:16] != b"IHDR":
        die("row '%s': '%s' (%s) is not a PNG — its width and height are "
            "read from the PNG header" % (cell, tile, full))
    width, height = struct.unpack(">II", head[16:24])
    if not width or not height:
        die("row '%s': '%s' (%s) declares a %dx%d image — there is no capture "
            "to show" % (cell, tile, full, width, height))
    return width, height


def load(path):
    try:
        with open(path, encoding="utf-8") as fh:
            doc = json.load(fh)
    except FileNotFoundError:
        die("no such rows file: %s" % path)
    except OSError as exc:     # a directory, no permission: refused, never a traceback
        die("cannot read the rows file %s (%s)" % (path, exc.strerror or exc))
    except ValueError as exc:
        die("%s is not valid JSON (%s)" % (path, exc))
    if not isinstance(doc, dict):
        die("the rows document must be a JSON object, not %s"
            % type(doc).__name__)
    for key in ("gallery", "variants", "rows"):
        if key not in doc:
            die("the rows document has no '%s' key" % key)
    if not isinstance(doc["gallery"], str) or not SLUG.match(doc["gallery"]):
        die("'gallery' must be a lowercase slug, not %r" % (doc["gallery"],))
    v = doc["variants"]
    if not isinstance(v, list) or not v \
            or not all(isinstance(x, str) and SLUG.match(x) for x in v):
        die("'variants' must be a non-empty list of variant names "
            "(lowercase slugs), not %r" % (v,))
    if len(set(v)) != len(v):
        die("'variants' names the same variant twice: %s" % " ".join(v))
    # An empty list is D2's "everything matches": render() prints nothing.
    if not isinstance(doc["rows"], list):
        die("'rows' must be a list")
    if "alternatives" in doc:
        alts = doc["alternatives"]
        if not isinstance(alts, list) or len(alts) < 2:
            die("'alternatives' must list at least two variants, each "
                "{\"id\": slug, \"label\": text}, not %r" % (alts,))
        for a in alts:
            if not isinstance(a, dict) or not isinstance(a.get("id"), str) \
                    or not SLUG.match(a["id"]) \
                    or not isinstance(a.get("label"), str) \
                    or not a["label"].strip():
                die("every alternative is {\"id\": slug, \"label\": text}, "
                    "not %r" % (a,))
            a["label"] = a["label"].strip()
            if a["id"] in TILES:
                die("alternative id '%s' is a before/after tile name — the "
                    "composer's compare keys on it, so name the variant "
                    "something else" % a["id"])
        reserved = {x.casefold() for pair in NONE_OF_THEM.values()
                    for x in pair[:1]} | {x.casefold() for x in OTHER}
        seen_labels = set()
        for a in alts:
            if len(a["label"].splitlines()) > 1:
                die("alternative label %r has a line break — it pastes as "
                    "two lines and the reply parser reads the second as "
                    "notes" % a["label"])
            if a["label"].endswith(" [provisional]"):
                die("alternative label %r ends in ' [provisional]' — the "
                    "reply reader strips that suffix as the composer's mark"
                    % a["label"])
            low = a["label"].casefold()
            if low in reserved:
                die("alternative label %r is reserved (the none-of-them and "
                    "Other choices paste under it)" % a["label"])
            if MARKER_LABEL.match(a["label"]):
                die("alternative label %r looks like a marker ([question], "
                    "[not-now]…): the reply parser reads those as asks"
                    % a["label"])
            if low in seen_labels:
                die("the same label twice: %r (labels are compared "
                    "case-insensitively)" % a["label"])
            seen_labels.add(low)
        ids = [a["id"] for a in alts]
        if len(set(ids)) != len(ids):
            die("'alternatives' names the same id twice: %s" % " ".join(ids))
    return doc


LAYOUTS = ("stacked", "side")


# BL-691: an alternatives row may give each option several captures (its
# with-data and its empty state): `"captures": {"a": {"with-data": path,
# "empty": path}, ...}`. The page shows them adjacent per option, still under
# the row's one which-one radio. The caption word of a state, by language; a
# state id with no entry here is shown as written.
OPTION_STATE_WORDS = {"es": {"with-data": "con datos", "empty": "vacío"},
                      "en": {"with-data": "with data", "empty": "empty"}}
MAX_OPTION_STATES = 4


def check_option_states(caps, alts, cell):
    """The state ids of a per-state alternatives row, or None for the plain
    one-capture-per-option row. Every option carries the same SET of states
    (the first option's order is the row's order), because the block's
    `data-tiles` is one matrix for all rows."""
    shapes = {isinstance(caps[a["id"]], dict) for a in alts}
    if shapes == {False}:
        return None
    if shapes == {True, False}:
        die("row '%s': some alternatives have one capture and others a "
            "{state: path} object — every option of a row shows the same "
            "states" % cell)
    first = list(caps[alts[0]["id"]])
    if not 2 <= len(first) <= MAX_OPTION_STATES \
            or not all(SLUG.match(k) for k in first):
        die("row '%s': per-option states are 2 to %d lowercase slugs "
            "(\"with-data\", \"empty\"), not %r"
            % (cell, MAX_OPTION_STATES, first))
    for a in alts:
        got = list(caps[a["id"]])
        if set(got) != set(first):
            die("row '%s': option '%s' has the states %r, but '%s' has %r — "
                "every option shows the same states (the first option's order "
                "is the row's)"
                % (cell, a["id"], got, alts[0]["id"], first))
        for st in first:
            check_path(caps[a["id"]][st], cell, "%s/%s" % (a["id"], st))
    ids = [a["id"] + "-" + st for a in alts for st in first]
    if len(set(ids)) != len(ids):
        die("row '%s': the option and state ids make the same tile name "
            "twice (%s); rename an option or a state" % (cell, " ".join(ids)))
    return first


def check_title(row, cell):
    """The row's optional human heading (BL-577): one line of plain text in the
    page's language. It is shown, never parsed, so it may say anything."""
    title = row.get("title")
    if title is None:
        return None
    if not isinstance(title, str) or not title.strip() \
            or "\n" in title or "\r" in title:
        die("row '%s': 'title' must be a non-empty single line of text"
            % cell)
    if md_body.LINK.search(md_body.CODE.sub(" ", title)):
        die("row '%s': 'title' takes no link (raw-link): a title is a heading "
            "and a rail label, so put the link in the row's 'look' or 'note'"
            % cell)
    return title.strip()


NAMED = re.compile(r"^@[A-Za-z0-9][A-Za-z0-9_.-]*$")


def named_region(root, path, name, cell, tile):
    """BL-607: the {x, y, w, h} of "@name", read from `<capture>.regions.json`
    (the capture's path with `.png` swapped), a {"name": {x, y, w, h}} map in
    the capture's own pixels written by the harness's capture step."""
    side = capture_path(root, re.sub(r"\.png$", "", path, flags=re.I)
                        + ".regions.json")
    try:
        with open(side, encoding="utf-8") as fh:
            table = json.load(fh)
    except OSError:
        die("row '%s': highlight '%s' on the %s capture needs %s, which is "
            "missing — the capture step writes it" % (cell, name, tile, side))
    except ValueError:
        die("row '%s': %s is not valid JSON" % (cell, side))
    if not isinstance(table, dict) or name[1:] not in table:
        die("row '%s': highlight '%s' is not in %s (it has: %s)"
            % (cell, name, side,
               ", ".join(sorted(table)) if isinstance(table, dict) else "none"))
    entry = table[name[1:]]
    if not isinstance(entry, dict):
        die("row '%s': highlight '%s' in %s must be one {\"x\", \"y\", \"w\", "
            "\"h\"} object, not %r" % (cell, name, side, entry))
    return check_highlight(entry, cell, "%s in %s" % (name, side))[0]


def check_highlight(value, cell, key="highlight"):
    """`highlight`: one region {x, y, w, h} in the capture's own pixels, or a
    non-empty list of them (BL-596). Returns a list of 4-tuples; whether it
    fits the capture is checked against its size in `render`."""
    regions = value if isinstance(value, list) else [value]
    if not regions:
        die("row '%s': '%s' is an empty list — leave it out, or give "
            "at least one {x, y, w, h}" % (cell, key))
    out = []
    for r in regions:
        if isinstance(r, str):
            # BL-607: "@name" is resolved from the capture's regions.json
            # sidecar in `figure`, where the capture path is known.
            if not NAMED.match(r):
                die("row '%s': a named highlight is \"@name\" (letters, "
                    "digits, - _ .), not %r (%s)" % (cell, r, key))
            out.append(r)
            continue
        if not isinstance(r, dict) or set(r) != {"x", "y", "w", "h"}:
            die("row '%s': a highlight is {\"x\", \"y\", \"w\", \"h\"} in "
                "capture pixels, not %r (%s)" % (cell, r, key))
        for k, v in r.items():
            if isinstance(v, bool) or not isinstance(v, (int, float)) \
                    or v != v or v in (float("inf"), float("-inf")):
                die("row '%s': highlight '%s' must be a number, not %r"
                    % (cell, k, v))
        if r["x"] < 0 or r["y"] < 0 or r["w"] <= 0 or r["h"] <= 0:
            die("row '%s': a highlight needs x, y >= 0 and w, h > 0 (got %r)"
                % (cell, r))
        out.append((r["x"], r["y"], r["w"], r["h"]))
    return out


def check_dropped(row, cell):
    """The stripped `dropped` reason of a row that left the question set."""
    reason = row["dropped"]
    if not isinstance(reason, str) or not reason.strip():
        die("row '%s': 'dropped' must be a non-empty string (why it left "
            "the question set)" % cell)
    if "decided" in row:
        die("row '%s' is both dropped and decided — it left the "
            "question set or it was settled, not both" % cell)
    return reason.strip()


def check_decided(row, cell):
    """The stripped `decided` verdict. Blank in the plain form the fold shows
    (BL-545): "**" is no verdict."""
    if not isinstance(row["decided"], str) \
            or not md_body.PLAIN.sub("", row["decided"]).strip():
        die("row '%s': 'decided' must be a non-empty string (the "
            "verdict)" % cell)
    return row["decided"].strip()


def check_row(row, variants, n, alts=None, require_look=False):
    """Every refusal a row can earn, named by cell rather than by index.
    Returns a dict: `cell` and `kind` always; `variant`, `before`, `after`,
    `captures` (alternatives), `look`, `decided`, `dropped` as the row has
    them. A not-applicable row has kind None and its reason in `after`."""
    if not isinstance(row, dict):
        die("row %d is not an object" % n)
    cell = row.get("cell")
    if not isinstance(cell, str) or not SLUG.match(cell):
        die("row %d: 'cell' must be a lowercase slug, not %r" % (n, cell))
    # `depends_on` (BL-690): the id of the consult item this row's content is
    # built on. While that item is open the row is context only (see
    # `pending_on`); it is meaningless on a row that is its own question.
    if "depends_on" in row:
        dep = row["depends_on"]
        if not isinstance(dep, str) or not GROUP_ID.match(dep):
            die("row '%s': 'depends_on' must be a consult item id, not %r"
                % (cell, dep))
        if "notApplicable" in row or row.get("kind") in ("alternatives",
                                                         "states"):
            die("row '%s': 'depends_on' goes on a review, unrequested or "
                "sample row — a notApplicable, alternatives or states row is "
                "a question of its own" % cell)
    # `answer` (BL-629): the reply to the owner's note on a row that is decided.
    # The fold shows it in its summary; an open row carries its own text, and a
    # notApplicable or dropped row has no slot for it, so it is refused there.
    if "answer" in row:
        ans = row["answer"]
        if not isinstance(ans, str) or not ans.strip():
            die("row '%s': 'answer' must be a non-empty string, not %r"
                % (cell, ans))
        if "decided" not in row:
            die("row '%s': 'answer' goes on a decided row — an open row "
                "carries its own text" % cell)
        if "dropped" in row or "notApplicable" in row:
            die("row '%s': 'answer' goes on a decided review row — a dropped "
                "or notApplicable row has nowhere to show it" % cell)
        if row.get("kind") in ("alternatives", "states"):
            die("row '%s': 'answer' does not go on an alternatives or states "
                "row — its choice controls stay visible, so the fold would "
                "not hide them and the row would still ask" % cell)
    # `noBefore` (BL-610) is a reason on the one shape that shows a single
    # capture. Anywhere else it would be dropped silently on a live question
    # (notApplicable, alternatives), so it is refused there; a dropped row
    # does not read it, like `note`.
    if "noBefore" in row and "dropped" not in row and (
            "notApplicable" in row or row.get("kind") == "alternatives"):
        die("row '%s': 'noBefore' only goes on a row that shows a single "
            "'after' capture, not a notApplicable or alternatives row"
            % cell)
    # A declared cell the screen cannot reach: the emitter sends its reason
    # instead of captures, and the row asks the owner to accept that.
    if "notApplicable" in row:
        reason = row["notApplicable"]
        if not isinstance(reason, str) or not reason.strip():
            die("row '%s': 'notApplicable' must be a non-empty string (the "
                "reason)" % cell)
        if "note" in row:
            die("row '%s': a 'notApplicable' row takes no 'note' — it is "
                "still a live question, so put the explanation in the "
                "reason" % cell)
        if "decided_note" in row and "dropped" not in row:
            die("row '%s': a 'notApplicable' row takes no 'decided_note' — "
                "it shows no captures to put it under, so it would be "
                "dropped silently" % cell)
        if "before" in row or "after" in row:
            die("row '%s' carries both captures and 'notApplicable' — a row "
                "is either shown or not applicable, never both" % cell)
        out = {"cell": cell, "kind": None, "after": reason.strip(),
               "title": check_title(row, cell)}
        if "dropped" in row:
            out["dropped"] = check_dropped(row, cell)
        elif "decided" in row:
            out["decided"] = check_decided(row, cell)
        return out
    variant = row.get("variant")
    if not isinstance(variant, str) or not SLUG.match(variant):
        die("row '%s': 'variant' must be a lowercase slug, not %r"
            % (cell, variant))
    kind = row.get("kind")
    if kind not in KINDS:
        die("row '%s': 'kind' is %r, not one of %s"
            % (cell, kind, ", ".join(KINDS)))
    # A dropped row left the question set: its id, title and kind stay so the
    # answer history keeps a home, and the reason takes the place of the
    # captures (which are often gone by then).
    if "dropped" in row:
        return {"cell": cell, "variant": variant, "kind": kind,
                "dropped": check_dropped(row, cell),
                "title": check_title(row, cell)}
    # A review row is a variant the owner chose; an unrequested one may be any
    # variant the harness captured — that is the point of it.
    if kind == "review" and variant not in variants:
        die("row '%s' is a review row in variant '%s', which is not one of "
            "the chosen variants (%s)" % (cell, variant, " ".join(variants)))
    out = {"cell": cell, "variant": variant, "kind": kind,
           "title": check_title(row, cell)}
    if "depends_on" in row:
        out["depends_on"] = row["depends_on"]
    if "highlight" in row:
        out["highlight"] = check_highlight(row["highlight"], cell, "highlight")
    if "highlight_before" in row:
        if "before" not in row:
            die("row '%s': 'highlight_before' needs a 'before' capture" % cell)
        out["highlight_before"] = check_highlight(row["highlight_before"],
                                                  cell, "highlight_before")
    layout = row.get("layout")
    if layout is not None:
        if layout not in LAYOUTS:
            die("row '%s': 'layout' is %r, not one of %s"
                % (cell, layout, ", ".join(LAYOUTS)))
        out["layout"] = layout
    if "decided" in row:
        out["decided"] = check_decided(row, cell)
    if "answer" in row:
        out["answer"] = row["answer"].strip()
    # What the owner should look at on THIS row (BL-516: a cell with no stated
    # reason could not be judged). The spec route requires it; the CLI, which
    # existing project emitters feed, only shows it when present.
    look = row.get("look")
    if look is not None and (not isinstance(look, str) or not look.strip()):
        die("row '%s': 'look' must be a non-empty string" % cell)
    if look is None and require_look:
        die("row '%s' has no 'look' line — say in one sentence what the "
            "reader should look at in this cell (rows JSON key \"look\")"
            % cell)
    if look is not None:
        out["look"] = look.strip()
    # `note` (BL-609): the explain-why / reframe / example lines a row used to
    # cram into `look`. A list, one <li> each, shown under the look line; it is
    # not a paragraph, so the one-line look limits do not apply to it.
    if "note" in row:
        note = row["note"]
        if not isinstance(note, list) or not note \
                or not all(isinstance(x, str) and x.strip() for x in note):
            die("row '%s': 'note' must be a non-empty list of non-empty "
                "strings, not %r" % (cell, note))
        out["note"] = [x.strip() for x in note]
    # `decided_note` (BL-613): the "decidido, corrígeme si no" text of a row,
    # shown as the kit's callout under the captures, never in the look line.
    if "decided_note" in row:
        dn = row["decided_note"]
        if not isinstance(dn, str) or not dn.strip():
            die("row '%s': 'decided_note' must be a non-empty string, not %r"
                % (cell, dn))
        if "decided" in row:
            die("row '%s': 'decided_note' goes on a row still open — a "
                "'decided' row folds away and seals its notes, so the "
                "correction offer would vanish" % cell)
        out["decided_note"] = dn.strip()
    if alts is not None and kind != "alternatives":
        die("row '%s' is a %s row in a document that declares 'alternatives' "
            "— every row of that document is an alternatives row (or dropped "
            "or not applicable), because the block's tiles are the "
            "alternatives" % (cell, kind))
    if kind == "alternatives":
        if alts is None:
            die("row '%s' is an alternatives row but the document declares no "
                "'alternatives' (the labels are declared once, at the top)"
                % cell)
        for k in ("before", "after"):
            if k in row:
                die("row '%s': an alternatives row takes no '%s' — its "
                    "captures are the 'captures' object" % (cell, k))
        caps = row.get("captures")
        if not isinstance(caps, dict):
            die("row '%s': an alternatives row needs 'captures', an object "
                "{alternative id: path}" % cell)
        for a in alts:
            if a["id"] not in caps:
                die("row '%s' has no capture for '%s' — every alternative is "
                    "shown in every row" % (cell, a["id"]))
            if isinstance(caps[a["id"]], dict):
                continue    # per-state captures: checked below (BL-691)
            check_path(caps[a["id"]], cell, a["id"])
        extra = sorted(set(caps) - {a["id"] for a in alts})
        if extra:
            die("row '%s' has a capture for '%s', which is not a declared "
                "alternative" % (cell, extra[0]))
        out["captures"] = caps
        out["option_states"] = check_option_states(caps, alts, cell)
        return out
    if kind == "states":
        for k in ("before", "after", "highlight", "highlight_before", "layout",
                  "noBefore", "also", "captures"):
            if k in row:
                die("row '%s': a states row takes no '%s' — its captures are "
                    "the 'states' list" % (cell, k))
        sts = row.get("states")
        if not isinstance(sts, list) or len(sts) < 2:
            die("row '%s': a states row needs 'states', a list of at least two "
                "{\"id\": slug, \"label\": text, \"capture\": path}" % cell)
        reserved = {x.casefold() for x in OTHER}
        ids, labels = set(), set()
        for st in sts:
            if not isinstance(st, dict) or not isinstance(st.get("id"), str) \
                    or not SLUG.match(st["id"]) \
                    or not isinstance(st.get("label"), str) \
                    or not st["label"].strip() or "capture" not in st:
                die("row '%s': every state is {\"id\": slug, \"label\": text, "
                    "\"capture\": path}, not %r" % (cell, st))
            label = st["label"].strip()
            if len(label.splitlines()) > 1:
                die("row '%s': state label %r has a line break — it pastes "
                    "as two lines and the reply parser reads the second as "
                    "notes" % (cell, label))
            if st["id"] in ids:
                die("row '%s' names the state id '%s' twice" % (cell, st["id"]))
            if label.endswith(" [provisional]"):
                die("row '%s': state label %r ends in ' [provisional]' — the "
                    "reply reader strips that suffix as the composer's mark"
                    % (cell, label))
            if label.casefold() in labels:
                die("row '%s': the label %r is used by two states (labels are "
                    "compared case-insensitively)" % (cell, label))
            if label.casefold() in reserved or MARKER_LABEL.match(label):
                die("row '%s': state label %r is reserved (the Other choice "
                    "or a [marker] the reply parser reads as an ask)"
                    % (cell, label))
            if st["id"] in TILES:
                die("row '%s': state id '%s' is a before/after tile name — "
                    "the composer's compare keys on it, so name the state "
                    "something else" % (cell, st["id"]))
            check_path(st["capture"], cell, st["id"])
            ids.add(st["id"])
            labels.add(label.casefold())
        out["states"] = [{"id": st["id"], "label": st["label"].strip(),
                          "capture": st["capture"]} for st in sts]
        return out
    # `also`: the other variants where an unrequested cell changed too. One
    # row per unrequested change, so the owner answers it once.
    if "also" in row:
        also = row["also"]
        if kind != "unrequested":
            die("row '%s': 'also' is only for an unrequested row, not a %s "
                "row" % (cell, kind))
        if not isinstance(also, list) or not also \
                or not all(isinstance(x, str) and SLUG.match(x) for x in also):
            die("row '%s': 'also' must be a non-empty list of variant names "
                "(lowercase slugs), not %r" % (cell, also))
        if variant in also:
            die("row '%s': 'also' names the row's own variant '%s'"
                % (cell, variant))
        twice = sorted({x for x in also if also.count(x) > 1})
        if twice:
            die("row '%s': 'also' names %s twice" % (cell, " ".join(twice)))
    if "after" not in row:
        die("row '%s' (%s) has no 'after' capture" % (cell, variant))
    check_path(row["after"], cell, "after")
    if "noBefore" in row:
        why = row["noBefore"]
        if "before" in row:
            die("row '%s' carries both 'before' and 'noBefore' — a row has a "
                "before or says why it has none" % cell)
        if not isinstance(why, str) or not why.strip():
            die("row '%s': 'noBefore' must be a non-empty string (why there "
                "is no before), not %r" % (cell, why))
        out["noBefore"] = why.strip()
    # Absent is the one way to say "new screen". A present-but-empty `before`
    # is a baseline the emitter lost, and showing it as new would hide that.
    if "before" in row:
        check_path(row["before"], cell, "before")
    out["before"] = row.get("before")
    out["after"] = row["after"]
    return out


# BL-688: a capture this big is a whole-screen overview, not a locator-scoped
# component shot. The rows JSON carries no scope key, so the size decides:
# height separates the two (component crops are short, screens are tall); width
# only excludes slivers.
OVERVIEW_MIN = (320, 600)


def changed_overview(root, r):
    """True when a live open row shows an overview capture whose cell changed:
    a before that differs from the after, or a new screen (no before)."""
    if r["kind"] not in ("review", "unrequested") or "decided" in r:
        return False
    w, h = png_size(root, r["after"], r["cell"], "after")
    if w < OVERVIEW_MIN[0] or h < OVERVIEW_MIN[1]:
        return False
    if r.get("before") is None:
        return True
    png_size(root, r["before"], r["cell"], "before")
    with open(capture_path(root, r["before"]), "rb") as fb, \
            open(capture_path(root, r["after"]), "rb") as fa:
        return fb.read() != fa.read()


# BL-693: two rows whose highlighted regions hold the same pixels show the
# reader the same thing twice. A channel value counts as different only past
# REDUNDANT_TOLERANCE of 255 (two renders of one region differ by 1-3 in
# gradients and anti-aliasing: the round-5 pair did); ONE value past it, a
# changed glyph, makes the regions different.
REDUNDANT_TOLERANCE = 4
# Which row of a redundant pair is the one to drop: the one that illustrates
# least, never decided by position.
DROP_ORDER = {"sample": 0, "unrequested": 1, "review": 2}


def row_regions(root, r):
    """The AFTER-capture regions a row highlights, resolved to (x, y, w, h)."""
    out = []
    for reg in r["highlight"]:
        out.append(named_region(root, r["after"], reg, r["cell"],
                                "after") if isinstance(reg, str) else reg)
    return out


def region_pixels(root, r, regions):
    try:
        with open(capture_path(root, r["after"]), "rb") as fh:
            data = fh.read()
    except OSError:
        return None          # the render loop refuses the missing capture itself
    # Floats: the origin floors and the size rounds up, so boxes of one
    # declared size stay one size (a sub-pixel offset of one @name is the same
    # place). The cost: when frac(x)+frac(w) > 1 the trailing partial pixel
    # line is left out of the crop.
    crops = [png_pixels.crop(data, math.floor(x), math.floor(y),
                             math.ceil(w), math.ceil(h))
             for x, y, w, h in regions]
    return None if any(c is None for c in crops) else crops


def row_name(r):
    """cell · variant · kind: two rows of one cell (a review and a sample) differ."""
    return " · ".join(x for x in (r["cell"], r.get("variant"), r["kind"]) if x)


def same_places(a, b, root):
    """Whether each highlight of row a names the same place as the one of row b:
    two names by name, a name and a raw rectangle by the rectangle the name
    resolves to, two raw rectangles by their {x, y, w, h}."""
    for ha, hb in zip(a["highlight"], b["highlight"]):
        if isinstance(ha, str) and isinstance(hb, str):
            if ha != hb:
                return False
            continue
        ra = named_region(root, a["after"], ha, a["cell"], "after") \
            if isinstance(ha, str) else ha
        rb = named_region(root, b["after"], hb, b["cell"], "after") \
            if isinstance(hb, str) else hb
        if tuple(ra) != tuple(rb):
            return False
    return True


def same_pixels(a, b):
    """True when every channel value of the two crops is within the tolerance.
    Crops of a different channel count (RGB beside RGBA) are not comparable."""
    for ca, cb in zip(a, b):
        for ra, rb in zip(ca, cb):
            if len(ra) != len(rb):
                return False
            if ra != rb and any(abs(x - y) > REDUNDANT_TOLERANCE
                                for x, y in zip(ra, rb)):
                return False
    return True


def check_redundant_regions(root, doc, variants, alts, require_look):
    """Refuse a row whose highlighted region repeats another row's (same size,
    every channel value within REDUNDANT_TOLERANCE), naming both rows. The row
    named for dropping is the least illustrative of the pair (DROP_ORDER, then
    the later one); when exactly one of the pair is decided the live one is
    named; two decided rows are never refused. A
    capture this reader cannot decode keeps its row."""
    seen = []
    for n, row in enumerate(doc["rows"], 1):
        r = check_row(row, variants, n, alts, require_look)
        if r["kind"] not in DROP_ORDER or "dropped" in r \
                or "highlight" not in r:
            continue
        regions = row_regions(root, r)
        shape = [(w, h) for _, _, w, h in regions]
        crops = None
        for prior, pshape, pcrops in seen:
            if pshape != shape or not same_places(prior, r, root):
                continue
            if crops is None:
                crops = region_pixels(root, r, regions)
            if pcrops[0] is None:
                pcrops[0] = region_pixels(root, prior, row_regions(root, prior))
            if crops is None or pcrops[0] is None \
                    or not same_pixels(crops, pcrops[0]):
                continue
            if ("decided" in prior) == ("decided" in r):
                if "decided" in r:
                    continue      # both settled: nothing live to refuse
                drop, keep = (prior, r) if DROP_ORDER[prior["kind"]] \
                    < DROP_ORDER[r["kind"]] else (r, prior)
            else:                 # exactly one decided: the live one goes
                drop, keep = (r, prior) if "decided" in prior else (prior, r)
            die("rows '%s' and '%s': the highlighted region of '%s' is "
                "pixel-identical to the one of '%s', so it shows the "
                "reader nothing new. Drop the row '%s' and say its "
                "knock-on in one line of the look text of '%s'"
                % (row_name(prior), row_name(r), row_name(drop),
                   row_name(keep), row_name(drop), row_name(keep)))
        seen.append((r, shape, [None]))


def full_pixels(root, path, w, h):
    with open(capture_path(root, path), "rb") as fh:
        return png_pixels.crop(fh.read(), 0, 0, w, h)


def check_identical_pairs(root, doc, variants, alts, require_look):
    """Refuse a live row whose before and after hold the same pixels (owner,
    LOOP-008 Q8): its look line says something changed and the pair shows
    nothing. Same tolerance as the redundant-region check; a decided or dropped
    row is settled and kept, and a capture this reader cannot decode keeps its row."""
    for n, row in enumerate(doc["rows"], 1):
        r = check_row(row, variants, n, alts, require_look)
        if r["kind"] not in ("review", "unrequested") or "decided" in r or "dropped" in r \
                or not r.get("before"):
            continue
        same = r["before"] == r["after"]
        if not same:
            size = png_size(root, r["after"], r["cell"], "after")
            if png_size(root, r["before"], r["cell"], "before") != size:
                continue
            a = full_pixels(root, r["after"], *size)
            b = full_pixels(root, r["before"], *size)
            same = a is not None and b is not None and same_pixels([a], [b])
        if same:
            die("row '%s': its before and after are pixel-identical, so the pair "
                "shows the reader no change while the row asks them to review one. "
                "Re-capture the before from the code without the change, or show "
                "the screen as kind: sample (one capture, nothing to answer)"
                % row_name(r))


def pct(v):
    return ("%.3f" % v).rstrip("0").rstrip(".") + "%"


def highlight_layer(regions, width, height, cell, tile):
    """The outline layer of a tile (BL-596): a CSS overlay in percentages of
    THIS capture, so it scales with the image and edits no pixel. A region that
    leaves the capture it was measured on is refused. `highlight` is the AFTER's
    (a before has a different layout); a before gets one only from
    `highlight_before`, measured on the before capture."""
    boxes = []
    for x, y, w, h in regions:
        if x + w > width or y + h > height:
            die("row '%s': highlight %dx%d at %s,%s runs outside the %s "
                "capture (%dx%d px) — the region is in that capture's own "
                "pixels" % (cell, w, h, x, y, tile, width, height))
        boxes.append('<span class="gal-hl" style="left:%s;top:%s;width:%s;'
                     'height:%s"></span>'
                     % (pct(100.0 * x / width), pct(100.0 * y / height),
                        pct(100.0 * w / width), pct(100.0 * h / height)))
    return ('<span class="gal-hl-layer" aria-hidden="true" '
            'style="aspect-ratio:%d / %d">%s</span>'
            % (width, height, "".join(boxes)))


def figure(root, path, tile, caption, cell, alt, assets, copies,
           regions=None):
    """One tile. `assets` is the page-relative dir of the copies and the src is
    the capture's copy there; the copy is only recorded in `copies` (name ->
    source), and `render` makes it once every row has passed. Without a page
    (`assets` None) there is nowhere to copy to, and a `file://` src pins the
    page to this machine and to captures the next run wipes (LOOP-006
    img-src-portable), so the tile is refused."""
    width, height = png_size(root, path, cell, tile)
    full = capture_path(root, path)
    if assets is None:
        die("row '%s': a gallery needs the page it goes into, to copy its "
            "captures beside it: build with -o <out.html> (gallery-items.sh "
            "--page)" % cell)
    with open(full, "rb") as fh:
        name = hashlib.sha256(fh.read()).hexdigest()[:16] + ".png"
    copies[name] = full
    src = urllib.parse.quote("%s/%s" % (assets, name))
    if regions:
        regions = [named_region(root, path, r, cell, tile)
                   if isinstance(r, str) else r for r in regions]
    layer = highlight_layer(regions, width, height, cell, tile) \
        if regions else ""
    return ('      <figure data-tile="%s"><img src="%s" alt="%s" width="%d"'
            ' height="%d" loading="lazy">%s<figcaption>%s</figcaption></figure>'
            % (e(tile), e(src), e(alt), width, height, layer, e(caption)))


def radio(ident, label, text):
    return ('<label><input type="radio" name="%s" data-label="%s">'
            '<span>%s</span></label>' % (e(ident), e(label), e(text)))


def options(ident, lang, choices, visible=VISIBLE_VERDICTS):
    """One which-one group. Only the first VISIBLE_VERDICTS choices show; the
    rest sit inside a closed <details> in the same `.opts` group, so the row
    asks verdict + note by default (BL-516) and the radios still share one
    name and paste like any other."""
    out = ['    <div class="opts one">']
    for label, text in choices[:visible]:
        out.append('      ' + radio(ident, label, text))
    rest = choices[visible:]
    if rest:
        out.append('      <details class="opts-more"><summary>%s</summary>'
                   % e(MORE[lang]))
        for label, text in rest:
            out.append('        ' + radio(ident, label, text))
        out.append('      </details>')
    out.append('    </div>')
    return out


def verdicts(ident, lang):
    return options(ident, lang, VERDICTS[lang])


def notes(lang):
    return ['    <p class="fieldlabel">%s</p>' % e(NOTES_LABEL[lang]),
            '    <textarea placeholder="%s"></textarea>'
            % e(NOTES_PLACEHOLDER[lang])]


def na_row_id(gallery, cell):
    """The id of a not-applicable cell, which has no variant (the writer's and
    the reply parser's one spelling)."""
    return "%s-%s-not-applicable" % (gallery, cell)


def dropped_section(ident, title, heading, title_src, reason, lang,
                    variant=None):
    """The lines of a dropped row: the reason where the tiles were, and a
    decided mark so the composer folds it and counts it nowhere."""
    attrs = ' data-id="%s" data-title="%s" data-heading="%s"' \
        % (e(ident), e(title), e(heading))
    if variant is not None:
        attrs += ' data-variant="%s"' % e(variant)
    return (['  <section class="consult-item consult-gallery"%s'
             ' data-decided="%s" data-dropped="%s">'
             % (attrs, e(DROPPED_WORD[lang] + ": " + reason), e(reason)),
             '    <h3>%s</h3>' % heading_html(title_src, heading),
             '    <p class="gal-na">%s</p>' % e(reason)]
            + notes(lang) + ['  </section>'])


def na_row(gallery, cell, reason, lang, alts=False, dropped=None,
           decided=None, heading=None):
    """`<gallery>-<cell>-not-applicable`, titled `<gallery> · <cell>`: a
    not-applicable cell has no variant. The suffix keeps the id apart from the
    old light/dark matrix's `<gallery>-<cell>`, whose verdicts were given on
    four captures, not on a reason."""
    ident = na_row_id(gallery, cell)
    title = "%s · %s" % (gallery, cell)
    title_src, heading = heading, row_heading(heading, cell)
    if dropped is not None:
        return "\n".join(dropped_section(ident, title, heading, title_src,
                                         dropped, lang))
    choices = list(VERDICTS[lang])
    if alts:
        choices[0] = (choices[0][0], NA_AGREE[lang])
    settled = ' data-decided="%s"' % e(decided) if decided else ''
    return "\n".join(
        ['  <section class="consult-item consult-gallery" data-id="%s"'
         ' data-title="%s" data-heading="%s"%s>'
         % (e(ident), e(title), e(heading), settled),
         '    <h3>%s</h3>' % heading_html(title_src, heading),
         '    <p class="gal-na">%s</p>' % e(reason)]
        + options(ident, lang, choices) + notes(lang) + ['  </section>'])


def pending_on(r, items):
    """The consult item id a checked row `r` waits on, or None (BL-690).

    `items` maps item id -> (settled, before_the_gallery) for every item of the
    page; None (the CLI, which sees no page) reads every dependency as open. A
    decided row and a sample never wait: the first is settled, the second asks
    nothing already. A dependency on an item the page lacks, or one placed
    after the gallery, is refused: the open decision goes first."""
    dep = r.get("depends_on")
    if dep is None:
        return None
    settled, before = (False, True) if items is None else items.get(dep, (None, None))
    if settled is None:
        die("row '%s': depends_on '%s' is not an item of this page"
            % (r["cell"], dep))
    if settled or "decided" in r or r["kind"] == "sample":
        return None
    if not before:
        die("row '%s' waits on item '%s', which comes after the gallery: the "
            "open decision goes first, the rows that depend on it after"
            % (r["cell"], dep))
    return dep


def alternatives_states(doc, variants, alts, require_look):
    """The state ids every alternatives row of the block shows (BL-691), or
    None when none has per-option states. The block's `data-tiles` is one
    matrix for all rows, so a row with other states than its neighbours is
    refused."""
    seen = None
    for n, row in enumerate(doc["rows"], 1):
        r = check_row(row, variants, n, alts, require_look)
        if r.get("kind") != "alternatives" or "option_states" not in r:
            continue
        if seen is None:
            seen = (r["cell"], r["option_states"])
        elif (set(r["option_states"] or ()) != set(seen[1] or ())):
            def said(st):
                return "plain (one capture per option)" if st is None \
                    else repr(st)
            die("rows '%s' and '%s' show different states per option (%s vs "
                "%s) — one document, one set of states; the first row's "
                "order is the page's"
                % (seen[0], r["cell"], said(seen[1]), said(r["option_states"])))
    return seen[1] if seen else None


def group_intro(doc, variants, alts, require_look, lang, items=None):
    """The block's one instruction (BL-595): which sentences apply depends on
    the kinds of row the block holds. Rows are only classified here; `render`
    still checks every one."""
    shapes = set()
    for n, row in enumerate(doc["rows"], 1):
        r = check_row(row, variants, n, alts, require_look)
        if "dropped" in r or "decided" in r:
            continue    # folded rows ask nothing
        if r["kind"] is None:
            shapes.add("na")
        elif r["kind"] == "alternatives":
            shapes.add("alt")
        elif r["kind"] == "sample":
            shapes.add("sample")
        elif pending_on(r, items):
            shapes.add("waits")
        elif r["kind"] == "states":
            shapes.add("states")
        else:
            shapes.add("ask")
            if r.get("before") is None:
                shapes.add("new_why" if "noBefore" in r else "new")
    # Plain single captures say "new"; qualified when a noBefore row sits
    # beside them so the intro never contradicts that row's caption.
    if "new" in shapes and "new_why" in shapes:
        shapes.add("new_mixed")
        shapes.discard("new")
    return " ".join(INTRO[lang][k]
                    for k in ("ask", "new", "new_mixed", "alt", "states",
                              "sample", "waits", "na")
                    if k in shapes)


# Cell-name words that say a bare row is the CURRENT state of a decision: a
# `before` rendered as a new screen. Words that also name UI states (before-
# submit, today-empty, current-user-menu, now-playing) are deliberately absent.
# Structure alone cannot decide: the frozen manifest holds galleries of 4 to 13
# single-capture state rows (loading, empty, error...) that are right as they are.
DECISION_WORDS = frozenset(("hoy", "baseline"))


def check_not_proposals_as_rows(doc, variants, alts, require_look, items):
    """Refuse a decision shown as independent single-capture rows (asset_lab
    4b192d67: "hoy" plus proposals as review rows gave textareas and nothing
    to choose). Two or more distinct cells that are asked single-capture
    review/unrequested rows (not decided, dropped, waiting) with no `noBefore`,
    one of them named as the current state (DECISION_WORDS, a whole `-` token
    of the slug); one such cell alone is a plain new screen."""
    bare = []
    for n, row in enumerate(doc["rows"], 1):
        r = check_row(row, variants, n, alts, require_look)
        if "dropped" not in r and "decided" not in r \
                and r["kind"] in ("review", "unrequested") \
                and r.get("before") is None and "noBefore" not in r \
                and not pending_on(r, items) and r["cell"] not in bare:
            bare.append(r["cell"])
    named = [c for c in bare if DECISION_WORDS & set(c.split("-"))]
    if len(bare) > 1 and named:
        die("%d cells show a single capture with no before and no 'noBefore' "
            "(%s), and %s is the current state: a bare row named as the "
            "current state is a 'before' shown as a new screen — make it the "
            "'before' of the row it precedes, or use one 'kind': "
            "\"alternatives\" row for the options, or give each new screen a "
            "'noBefore' reason" % (len(bare), ", ".join(bare), ", ".join(named)))


def render(doc, root, group_id, group_title, lang, page=None,
           require_look=False, lead="", items=None, refuse_bare_rows=False):
    """The block, or "" for an empty `rows`: when every capture matches its
    baseline (D2) the owner's page carries no gallery block and no text about
    it — not an empty heading, not a "nothing changed" line.

    `page` is the path of the page the block goes into: every capture is copied
    beside it (see the module docstring). None is refused at the first tile:
    a capture linked where it is breaks on this page's next reader.
    `require_look` refuses a row with no "what to look at" line (the spec
    route sets it). `lead` is the author's own prose as ready HTML, placed
    between the heading and the generated intro. `items` is what the page
    knows of its consult items (see `pending_on`): a row that depends on an
    open one is context only, and an unrequested row that depends on it is
    folded the way a dropped row is, asking nothing (BL-690).
    `refuse_bare_rows` (the spec route sets it) refuses several single-capture
    rows with no `noBefore` (a decision shown as independent rows)."""
    if not doc["rows"]:
        return ""
    assets, copies = None, {}
    if page is not None:
        assets = os.path.splitext(os.path.basename(page))[0] + "-assets/gallery"
    gallery = doc["gallery"]
    variants = list(doc["variants"])
    alts = doc.get("alternatives")
    tiles = [a["id"] for a in alts] if alts else list(TILES)
    option_states = alternatives_states(doc, variants, alts, require_look)
    if option_states:
        tiles = [a["id"] + "-" + st for a in alts for st in option_states]
    words = TILE_WORDS[lang]
    root = root.rstrip("/")
    out = []
    add = out.append
    add('<section class="consult-group" id="%s" data-id="%s" data-title="%s"'
        ' data-tiles="%s">' % (e(group_id), e(group_id), e(group_title),
                               " ".join(tiles)))
    add('  <div class="sec-head">')
    add('    <h2>%s</h2>' % e(group_title))
    add('  </div>')
    if lead:
        add(lead)
    intro = group_intro(doc, variants, alts, require_look, lang, items)
    if intro:
        add('  <p class="gal-intro">%s <span class="gal-intro-narrow">%s</span></p>'
            % (e(intro), e(NARROW_HINT[lang])))
    check_redundant_regions(root, doc, variants, alts, require_look)
    check_identical_pairs(root, doc, variants, alts, require_look)
    if refuse_bare_rows:
        check_not_proposals_as_rows(doc, variants, alts, require_look, items)
    seen, unrequested, ids = {}, {}, {}
    cell_variants = {}
    for row in doc["rows"]:
        if isinstance(row, dict) and "notApplicable" not in row \
                and isinstance(row.get("variant"), str):
            cell_variants.setdefault(row.get("cell"), set()).add(row["variant"])
    for n, row in enumerate(doc["rows"], 1):
        r = check_row(row, variants, n, alts, require_look)
        cell, variant, kind = r["cell"], r.get("variant"), r["kind"]
        before, after = r.get("before"), r.get("after")
        # One cell in one variant is one question: a second row for it (the
        # same cell both requested and unrequested) is two answers to it. A
        # dropped row asks nothing, so it can sit beside the row that replaced
        # it (a review row retired for alternatives of the same cell).
        live = "dropped" not in r
        if live:
            if (cell, variant) in seen:
                die("rows %d and %d are both cell '%s' in variant '%s'"
                    % (seen[(cell, variant)], n, cell, variant))
            seen[(cell, variant)] = n
        if kind == "unrequested" and live:
            if cell in unrequested:
                die("rows %d and %d: cell '%s' has two unrequested rows — one "
                    "row per unrequested change, its other variants in 'also'"
                    % (unrequested[cell], n, cell))
            unrequested[cell] = n
        if kind is None:
            na_id = na_row_id(gallery, cell)
            if na_id in ids:
                die("rows %d and %d are both cell '%s' not applicable — one "
                    "row per cell, dropped or not (they share the id '%s')"
                    % (ids[na_id], n, cell, na_id))
            ids[na_id] = n
            add(na_row(gallery, cell, after, lang, alts=bool(alts),
                       dropped=r.get("dropped"), decided=r.get("decided"),
                       heading=r.get("title")))
            continue
        ident = row_id(gallery, cell, variant, kind)
        if not ROW_ID.match(ident):
            die("row id '%s' is not lowercase slugs joined by hyphens" % ident)
        if ident in ids:
            die("rows %d and %d both produce the row id '%s' — a dropped row "
                "and a live one of the same kind share an id"
                % (ids[ident], n, ident))
        ids[ident] = n
        title = "%s · %s · %s" % (gallery, cell, variant)
        heading = row_heading(
            r.get("title"), cell,
            variant if len(cell_variants.get(cell, ())) > 1
            and ("dropped" in r or "decided" in r
                 or pending_on(r, items)) else None, lang)
        # A dropped row is out of the question set: same id, title and kind as
        # when it was asked, the reason where the tiles were, and a decided
        # mark so the composer folds it and counts it nowhere.
        if "dropped" in r:
            reason = r["dropped"]
            out.extend(dropped_section(ident, title, heading, r.get("title"),
                                       reason, lang, variant))
            continue
        # BL-690: an unrequested row whose only change is a still-open option is
        # not asked this round, but its id stays (a round that loses an id fails
        # the id-stability check). It asks nothing and is NOT decided: no
        # data-decided, so the composer neither folds its block into the decided
        # section nor counts it settled, and a reply duty owed on it stays open.
        # A plain closed <details> keeps it small in place; the waiting line is
        # its summary and doubles as the gal-na reason a figure-less row needs.
        waits = pending_on(r, items)
        if waits and kind == "unrequested":
            line = WAITS_ON[lang] % waits
            add('  <section class="consult-item consult-gallery" data-id="%s"'
                ' data-title="%s" data-heading="%s" data-variant="%s"'
                ' data-asks-nothing data-waits-on="%s">'
                % (e(ident), e(title), e(heading), e(variant), e(waits)))
            add('    <h3>%s</h3>' % heading_html(r.get("title"), heading))
            add('    <details class="gal-waiting">')
            add('      <summary class="gal-na gal-asks-nothing">%s</summary>' % e(line))
            if "look" in r:
                add('      <p class="gal-look"><strong>%s:</strong> %s</p>'
                    % (e(LOOK_LABEL[lang]), md_body._inline(r["look"])))
            add('    </details>')
            add('  </section>')
            continue
        # A new screen shows one capture, so the row narrows the block's
        # matrix to that tile; the checker holds it to exactly that.
        narrow = '' if kind in ("alternatives", "states") \
            or before is not None \
            else ' data-tiles="after"'
        settled = ' data-decided="%s"' % e(r["decided"]) if "decided" in r else ''
        if kind == "states":
            narrow = ' data-states="%s"' % e(" ".join(
                st["id"] for st in r["states"]))
        if "answer" in r:
            settled += ' data-answer="%s"' % e(r["answer"])
        if kind == "sample" or waits:
            settled += " data-asks-nothing"
        if waits:
            settled += ' data-waits-on="%s"' % e(waits)
        add('  <section class="consult-item consult-gallery" data-id="%s"'
            ' data-title="%s" data-heading="%s" data-variant="%s"%s%s>'
            % (e(ident), e(title), e(heading), e(variant), narrow, settled))
        add('    <h3>%s</h3>' % heading_html(r.get("title"), heading))
        if kind == "unrequested":
            flag = FLAG[lang]
            if row.get("also"):
                flag += " · " + ALSO[lang] + "; ".join(
                    variant_label(v, lang) for v in row["also"])
            add('    <p class="gal-flag">%s</p>' % e(flag))
        if "look" in r:
            add('    <p class="gal-look"><strong>%s:</strong> %s</p>'
                % (e(LOOK_LABEL[lang]), md_body._inline(r["look"])))
        if "note" in r:
            add('    <ul class="gal-note">')
            for item in r["note"]:
                add('      <li>%s</li>' % md_body._inline(item))
            add('    </ul>')
        # BL-688: the owner must never hunt for the change on an overview.
        if "highlight" not in r and changed_overview(root, r):
            die("row '%s': a full-page capture (%dx%d or larger) whose cell "
                "changed needs a 'highlight' that says where to look — write "
                "<capture>.regions.json for the changed region and set "
                "highlight: '@name' on the row (harness contract, named "
                "highlights)" % (cell, OVERVIEW_MIN[0], OVERVIEW_MIN[1]))
        # A before/after pair sits side by side: captures scale to the cell and
        # are never cropped, and the owner enlarges them anyway (owner
        # 2026-10-01, reversing BL-589's stacked default); `"layout": "stacked"`
        # puts before above after at the column's full width.
        pair = kind not in ("alternatives", "states") and before is not None
        layout = r.get("layout") or "side"
        per_option = r.get("option_states")
        add('    <div class="gal%s"%s>'
            % (" stacked" if layout == "stacked" and pair else "",
               ' data-per-option="%d"' % len(per_option) if per_option else ""))
        regions = r.get("highlight")
        alt = heading + " · "
        if kind == "states":
            for st in r["states"]:
                add(figure(root, st["capture"], st["id"], st["label"], cell,
                           alt + st["label"], assets, copies))
        elif kind == "alternatives":
            for a in alts:
                if not option_states:
                    add(figure(root, r["captures"][a["id"]], a["id"],
                               a["label"], cell, alt + a["label"], assets,
                               copies, regions))
                    continue
                # BL-691: option-major, so each option's states sit adjacent.
                for k, st in enumerate(option_states):
                    # The highlight outlines the canonical (first, with-data)
                    # state only: a fixed region would overflow a shorter
                    # empty capture, and @name needs a sidecar per capture.
                    cap = "%s · %s" % (a["label"],
                                       OPTION_STATE_WORDS[lang].get(st, st))
                    add(figure(root, r["captures"][a["id"]][st],
                               a["id"] + "-" + st, cap, cell, alt + cap,
                               assets, copies, regions if k == 0 else None))
        elif before is not None:
            add(figure(root, before, "before", words["before"], cell,
                       alt + words["before"], assets, copies,
                       r.get("highlight_before")))
            add(figure(root, after, "after", words["after"], cell,
                       alt + words["after"], assets, copies, regions))
        else:
            # A reason replaces the "new screen" label (BL-610).
            label = "%s: %s" % (words["none"], r["noBefore"]) \
                if "noBefore" in r else words["new"]
            add(figure(root, after, "after", label, cell,
                       alt + label, assets, copies, regions))
        add('    </div>')
        add('    <p class="gal-variant">%s</p>' % e(variant_line(variant, lang)))
        if "decided_note" in r:
            add('    <div class="callout"><p>%s</p></div>'
                % e(r["decided_note"]))
        if "answer" in r:
            add('    <div class="callout"><p>%s</p></div>' % e(r["answer"]))
        if kind == "states":
            add('    <div class="opts">')
            for st in r["states"]:
                add('      <label><input type="checkbox" name="%s-%s" '
                    'data-label="%s"><span>%s</span></label>'
                    % (e(ident), e(st["id"]), e(st["label"]), e(st["label"])))
            add('    </div>')
        elif kind == "alternatives":
            choices = [(a["label"], a["label"]) for a in alts]
            choices.append(NONE_OF_THEM[lang])
            # Peer choices are all visible; only "none of them" collapses.
            out.extend(options(ident, lang, choices, visible=len(alts)))
        elif kind == "sample" or waits:
            # BL-693: a row that asks nothing carries no answer control at all
            # (no verdicts, no notes box) and says so where the options would be.
            # BL-690: a row waiting on an open item is the same shape, and its
            # line names the item.
            add('    <p class="gal-asks-nothing">%s</p>'
                % e(WAITS_ON[lang] % waits if waits else ASKS_NOTHING[lang]))
            add('  </section>')
            continue
        elif "answer" not in r:
            out.extend(verdicts(ident, lang))
        out.extend(notes(lang))
        add('  </section>')
    add('  <div class="group-notes">')
    add('    <p class="fieldlabel">%s</p>' % e(md_body.chrome("groupNotes", lang)))
    add('    <textarea placeholder="%s"></textarea>'
        % e(md_body.chrome("groupNotesPh", lang)))
    add('  </div>')
    add('</section>')
    if assets is not None:
        dest = os.path.join(os.path.dirname(os.path.abspath(page)), assets)
        os.makedirs(dest, exist_ok=True)
        for name, full in sorted(copies.items()):
            # Content-addressed: a file of the same size already holds these
            # bytes; a shorter one is a copy an interrupted build left.
            target = os.path.join(dest, name)
            if not os.path.isfile(target) \
                    or os.path.getsize(target) != os.path.getsize(full):
                shutil.copyfile(full, target)
    return "\n".join(out) + "\n"


def main(argv):
    ap = UsageParser(
        prog="gallery-items.sh",
        form="gallery-items.sh <rows.json> --root <abs repo root> --page <out.html> "
             "--group-id <id> --group-title <title> [--lang es|en]",
        description="Turn a gallery rows JSON into one consult-group of "
                    "before/proposed review rows.")
    ap.add_argument("rows", metavar="<rows.json>",
                    help="the rows document the project emits")
    ap.add_argument("--root", required=True, metavar="<abs repo root>",
                    help="absolute checkout the row paths are relative to")
    ap.add_argument("--page", required=True, metavar="<out.html>",
                    help="the page the block goes into: the captures are "
                         "copied beside it and linked from there")
    ap.add_argument("--group-id", required=True, metavar="<id>",
                    help="the block's id, stable across rounds")
    ap.add_argument("--group-title", required=True, metavar="<title>",
                    help="the block's heading")
    ap.add_argument("--lang", default="es", choices=LANGS,
                    help="the page's language (default: es)")
    args = ap.parse_args(argv)

    if not GROUP_ID.match(args.group_id):
        ap.error("--group-id %r is not an html id — it becomes id=, data-id= and the "
                 "rail's anchor, so it starts with a letter and holds letters, "
                 "digits, '-' and '_' only" % args.group_id)
    if not os.path.isabs(args.root):
        ap.error("--root must be an absolute path (got '%s') — a file:// URL "
                 "built from a relative one resolves nowhere" % args.root)
    # not isfile: a <(...) or /dev/stdin pipe is a valid rows document. load()
    # keeps die() for everything else: spec_build reads its message.
    if not os.path.exists(args.rows) or os.path.isdir(args.rows):
        ap.error("no such rows file: %s" % args.rows)
    doc = load(args.rows)
    sys.stdout.write(render(doc, args.root, args.group_id, args.group_title,
                            args.lang, page=args.page))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
