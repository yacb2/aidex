#!/usr/bin/env python3
"""gallery_items.py — a rows JSON becomes one consult-group of review rows.

A review row is ONE screen state in ONE variant (`light-desktop`, …), shown as
the pair the owner rules on: "before" (the committed baseline) and "after" (the
run's proposed render). A state whose screen is new has no baseline, so its row
shows the one capture, labelled as new. The project owns which rows exist and
emits them as rows JSON (`gallery_board.py --rows-json` in dashboard_template):
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
import os
import re
import shutil
import struct
import sys
import urllib.parse

LANGS = ("es", "en")

# The two tiles of a row, in reading order. English tokens on purpose: they are
# the `data-tile` the checker, the composer's arrows and compare, and a pasted
# mark (`[mark after …]`) all key on, whatever the page's language. What the
# reader sees is the caption below.
TILES = ("before", "after")
TILE_WORDS = {"es": {"before": "antes", "after": "propuesto",
                     "new": "pantalla nueva"},
              "en": {"before": "before", "after": "proposed",
                     "new": "new screen"}}

# What a variant name says, in the page's language. A variant is
# `<mode>-<viewport>`; anything that does not split into two known words is
# shown as its own name rather than guessed at.
MODE_WORDS = {"es": {"light": "claro", "dark": "oscuro"},
              "en": {"light": "light", "dark": "dark"}}
VIEW_WORDS = {"es": {"desktop": "escritorio", "mobile": "móvil"},
              "en": {"desktop": "desktop", "mobile": "mobile"}}

# `review` is a row the owner chose (a declared change in a chosen variant);
# `unrequested` is a cell that moved without being in the change set; `sample`
# illustrates and asks nothing, so it carries no verdict (BL-466).
KINDS = ("review", "unrequested", "sample")

VERDICTS = {
    "es": [("Aprobada", "Aprobada: lo propuesto queda como baseline"),
           ("Necesita cambios", "Necesita cambios (di cuáles en las notas)"),
           ("No puedo juzgarla así", "No puedo juzgarla con esta captura")],
    "en": [("Approved", "Approved: the proposed capture becomes the baseline"),
           ("Needs changes", "Needs changes (say which in the notes)"),
           ("Cannot judge", "Cannot judge it from this capture")],
}

INTRO = {
    "es": {"pair": "%s: antes y propuesto. Marca tu respuesta y, si necesita "
                   "cambios, di cuáles en las notas de esta fila.",
           "new": "%s: la pantalla es nueva, así que no hay antes. Marca tu "
                  "respuesta y, si necesita cambios, di cuáles en las notas "
                  "de esta fila.",
           "sample": "%s: una muestra, no hay nada que aprobar.",
           "na": "Este estado no se puede mostrar, por el motivo de abajo. "
                 "Marca tu respuesta."},
    "en": {"pair": "%s: before and proposed. Mark your answer and, if it "
                   "needs changes, say which in the row's notes.",
           "new": "%s: the screen is new, so there is no before. Mark your "
                  "answer and, if it needs changes, say which in the row's "
                  "notes.",
           "sample": "%s: a sample, nothing to approve.",
           "na": "This state cannot be shown, for the reason below. Mark "
                 "your answer."},
}

FLAG = {"es": "cambió sin que lo pidieras", "en": "changed without you asking"}
ALSO = {"es": "también en: ", "en": "also in: "}

NOTES_LABEL = {"es": "Notas sobre esta fila", "en": "Notes on this row"}
NOTES_PLACEHOLDER = {"es": "Qué cambiar…", "en": "What to change…"}

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
    parts = variant.split("-")
    if len(parts) == 2:
        mode = MODE_WORDS[lang].get(parts[0])
        view = VIEW_WORDS[lang].get(parts[1])
        if mode and view:
            return mode + " · " + view
    return variant


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


def png_size(root, value, cell, tile):
    """(width, height) of the capture, read from its IHDR chunk."""
    # `render` strips the root's trailing slash, so `--root /` arrives as "":
    # joined as is, the capture would be read relative to the working directory.
    full = os.path.join(root or "/", value)
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
    return doc


def check_row(row, variants, n):
    """Every refusal a row can earn, named by cell rather than by index.
    Returns (cell, variant, kind, before|None, after); a not-applicable row
    returns (cell, None, None, None, reason)."""
    if not isinstance(row, dict):
        die("row %d is not an object" % n)
    cell = row.get("cell")
    if not isinstance(cell, str) or not SLUG.match(cell):
        die("row %d: 'cell' must be a lowercase slug, not %r" % (n, cell))
    # A declared cell the screen cannot reach: the emitter sends its reason
    # instead of captures, and the row asks the owner to accept that.
    if "notApplicable" in row:
        reason = row["notApplicable"]
        if not isinstance(reason, str) or not reason.strip():
            die("row '%s': 'notApplicable' must be a non-empty string (the "
                "reason)" % cell)
        if "before" in row or "after" in row:
            die("row '%s' carries both captures and 'notApplicable' — a row "
                "is either shown or not applicable, never both" % cell)
        return cell, None, None, None, reason.strip()
    variant = row.get("variant")
    if not isinstance(variant, str) or not SLUG.match(variant):
        die("row '%s': 'variant' must be a lowercase slug, not %r"
            % (cell, variant))
    kind = row.get("kind")
    if kind not in KINDS:
        die("row '%s': 'kind' is %r, not one of %s"
            % (cell, kind, ", ".join(KINDS)))
    # A review row is a variant the owner chose; an unrequested one may be any
    # variant the harness captured — that is the point of it.
    if kind == "review" and variant not in variants:
        die("row '%s' is a review row in variant '%s', which is not one of "
            "the chosen variants (%s)" % (cell, variant, " ".join(variants)))
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
    # Absent is the one way to say "new screen". A present-but-empty `before`
    # is a baseline the emitter lost, and showing it as new would hide that.
    before = row.get("before")
    if "before" in row:
        check_path(before, cell, "before")
    return cell, variant, kind, before, row["after"]


def figure(root, path, tile, caption, cell, alt, assets, copies):
    """One tile. With a page, `assets` is the page-relative dir of the copies
    and the src is the capture's copy there; the copy is only recorded in
    `copies` (name -> source), and `render` makes it once every row has passed.
    Without one (`assets` None: a body with nowhere to land) the src is the
    capture's own `file://` URL."""
    path = path.lstrip("/")
    width, height = png_size(root, path, cell, tile)
    full = os.path.join(root or "/", path)
    if assets is None:
        src = "file://%s/%s" % (root, path)
    else:
        with open(full, "rb") as fh:
            name = hashlib.sha256(fh.read()).hexdigest()[:16] + ".png"
        copies[name] = full
        src = urllib.parse.quote("%s/%s" % (assets, name))
    return ('      <figure data-tile="%s"><img src="%s" alt="%s" width="%d"'
            ' height="%d" loading="lazy"><figcaption>%s</figcaption></figure>'
            % (e(tile), e(src), e(alt), width, height, e(caption)))


def verdicts(ident, lang):
    out = ['    <div class="opts one">']
    for label, text in VERDICTS[lang]:
        out.append('      <label><input type="radio" name="%s"'
                   ' data-label="%s"><span>%s</span></label>'
                   % (e(ident), e(label), e(text)))
    out.append('    </div>')
    return out


def notes(lang):
    return ['    <p class="fieldlabel">%s</p>' % e(NOTES_LABEL[lang]),
            '    <textarea placeholder="%s"></textarea>'
            % e(NOTES_PLACEHOLDER[lang])]


def na_row(gallery, cell, reason, lang):
    """`<gallery>-<cell>-not-applicable`, titled `<gallery> · <cell>`: a
    not-applicable cell has no variant. The suffix keeps the id apart from the
    old light/dark matrix's `<gallery>-<cell>`, whose verdicts were given on
    four captures, not on a reason."""
    ident = "%s-%s-not-applicable" % (gallery, cell)
    title = "%s · %s" % (gallery, cell)
    return "\n".join(
        ['  <section class="consult-item consult-gallery" data-id="%s"'
         ' data-title="%s">' % (e(ident), e(title)),
         '    <h3><span class="consult-id">%s</span>%s</h3>'
         % (e(ident), e(title)),
         '    <p>%s</p>' % e(INTRO[lang]["na"]),
         '    <p class="gal-na">%s</p>' % e(reason)]
        + verdicts(ident, lang) + notes(lang) + ['  </section>'])


def render(doc, root, group_id, group_title, lang, page=None):
    """The block, or "" for an empty `rows`: when every capture matches its
    baseline (D2) the owner's page carries no gallery block and no text about
    it — not an empty heading, not a "nothing changed" line.

    `page` is the path of the page the block goes into: every capture is copied
    beside it (see the module docstring). None links the captures where they
    are — only for a body that is not written as a page."""
    if not doc["rows"]:
        return ""
    assets, copies = None, {}
    if page is not None:
        assets = os.path.splitext(os.path.basename(page))[0] + "-assets/gallery"
    gallery = doc["gallery"]
    variants = list(doc["variants"])
    words = TILE_WORDS[lang]
    root = root.rstrip("/")
    out = []
    add = out.append
    add('<section class="consult-group" id="%s" data-id="%s" data-title="%s"'
        ' data-tiles="%s">' % (e(group_id), e(group_id), e(group_title),
                               " ".join(TILES)))
    add('  <div class="sec-head">')
    add('    <h2>%s</h2>' % e(group_title))
    add('  </div>')
    seen, unrequested = {}, {}
    for n, row in enumerate(doc["rows"], 1):
        cell, variant, kind, before, after = check_row(row, variants, n)
        # One cell in one variant is one question: a second row for it (the
        # same cell both requested and unrequested) is two answers to it.
        if (cell, variant) in seen:
            die("rows %d and %d are both cell '%s' in variant '%s'"
                % (seen[(cell, variant)], n, cell, variant))
        seen[(cell, variant)] = n
        if kind == "unrequested":
            if cell in unrequested:
                die("rows %d and %d: cell '%s' has two unrequested rows — one "
                    "row per unrequested change, its other variants in 'also'"
                    % (unrequested[cell], n, cell))
            unrequested[cell] = n
        if kind is None:
            add(na_row(gallery, cell, after, lang))
            continue
        ident = row_id(gallery, cell, variant, kind)
        if not ROW_ID.match(ident):
            die("row id '%s' is not lowercase slugs joined by hyphens" % ident)
        title = "%s · %s · %s" % (gallery, cell, variant)
        # A new screen shows one capture, so the row narrows the block's
        # matrix to that tile; the checker holds it to exactly that.
        narrow = '' if before is not None else ' data-tiles="after"'
        add('  <section class="consult-item consult-gallery" data-id="%s"'
            ' data-title="%s" data-variant="%s"%s>'
            % (e(ident), e(title), e(variant), narrow))
        add('    <h3><span class="consult-id">%s</span>%s</h3>'
            % (e(ident), e(title)))
        if kind == "unrequested":
            flag = FLAG[lang]
            if row.get("also"):
                flag += " · " + ALSO[lang] + ", ".join(
                    variant_label(v, lang) for v in row["also"])
            add('    <p class="gal-flag">%s</p>' % e(flag))
        shape = "sample" if kind == "sample" else \
            ("pair" if before is not None else "new")
        label = variant_label(variant, lang)
        add('    <p>%s</p>' % e(INTRO[lang][shape]
                               % (label[:1].upper() + label[1:])))
        add('    <div class="gal">')
        alt = "%s · %%s" % title
        if before is not None:
            add(figure(root, before, "before", words["before"], cell,
                       alt % words["before"], assets, copies))
            add(figure(root, after, "after", words["after"], cell,
                       alt % words["after"], assets, copies))
        else:
            add(figure(root, after, "after", words["new"], cell,
                       alt % words["new"], assets, copies))
        add('    </div>')
        if kind != "sample":
            out.extend(verdicts(ident, lang))
        out.extend(notes(lang))
        add('  </section>')
    add('</section>')
    if assets is not None:
        dest = os.path.join(os.path.dirname(os.path.abspath(page)), assets)
        os.makedirs(dest, exist_ok=True)
        for name, full in sorted(copies.items()):
            # Content-addressed: a file already there holds these bytes.
            if not os.path.isfile(os.path.join(dest, name)):
                shutil.copyfile(full, os.path.join(dest, name))
    return "\n".join(out) + "\n"


def main(argv):
    ap = argparse.ArgumentParser(
        prog="gallery-items.sh",
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
        die("--group-id %r is not an html id — it becomes id=, data-id= and the "
            "rail's anchor, so it starts with a letter and holds letters, "
            "digits, '-' and '_' only" % args.group_id)
    if not os.path.isabs(args.root):
        die("--root must be an absolute path (got '%s') — a file:// URL "
            "built from a relative one resolves nowhere" % args.root)
    doc = load(args.rows)
    sys.stdout.write(render(doc, args.root, args.group_id, args.group_title,
                            args.lang, page=args.page))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
