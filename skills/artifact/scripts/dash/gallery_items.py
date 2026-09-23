#!/usr/bin/env python3
"""gallery_items.py — a rows JSON becomes one consult-group of gallery items.

A gallery row is ONE screen state seen in every tile the matrix declares
(light/dark x desktop/mobile). The project owns the matrix and emits it as rows
JSON (`gallery_board.py --rows-json` in dashboard_template); this script turns
that document into markup the kit already understands — `consult-item
consult-gallery` sections with an `.opts one` verdict group and a notes
textarea, so `composer.js` pastes them like any other item and every existing
rule in check_artifact.py keeps applying.

Neither side re-declares the other's matrix. That duplication is what the
project's own board avoids on purpose, and a second copy of the cell list in
the kit would drift the first time a state is added.

The output is DETERMINISTIC: row order is the document's, tile order is the
document's `tiles` list, and nothing here reads the clock, the filesystem or
the environment. Two runs on one JSON are byte-identical, which is what makes
a re-generated round a diff of what actually changed.

Images are linked, never inlined: `src="file://<root>/<path>"`. `--root` is the
absolute checkout the paths are relative to, so the same JSON serves a worktree
and a clone. Copying the baselines next to the page is a separate step at
close-out (decision D2), not this script's business.

Usage:
  gallery-items.sh <rows.json> --root <abs repo root> \
      --group-id <id> --group-title <title> [--lang es|en]
"""

import argparse
import html
import json
import os
import re
import sys

LANGS = ("es", "en")

# What a tile name says, in the page's language. A tile is `<mode>-<viewport>`;
# anything that does not split into two known words is captioned with its own
# name rather than guessed at — a wrong caption on a screenshot is worse than a
# technical one.
MODE_WORDS = {"es": {"light": "claro", "dark": "oscuro"},
              "en": {"light": "light", "dark": "dark"}}
VIEW_WORDS = {"es": {"desktop": "escritorio", "mobile": "móvil"},
              "en": {"desktop": "desktop", "mobile": "mobile"}}

VERDICTS = {
    "es": [("Aprobada", "Aprobada: las celdas quedan como baseline"),
           ("Necesita cambios", "Necesita cambios (di cuáles en las notas)"),
           ("No puedo juzgarla así", "No puedo juzgarla con esta captura")],
    "en": [("Approved", "Approved: these cells stand as the baseline"),
           ("Needs changes", "Needs changes (say which in the notes)"),
           ("Cannot judge", "Cannot judge it from this capture")],
}

INTRO = {
    "es": ("Las celdas de esta fila, leídas del baseline. Marca el veredicto "
           "y, si necesita cambios, di cuáles en las notas de esta fila."),
    "en": ("This row's cells, read from the committed baseline. Mark the "
           "verdict and, if it needs changes, say which in the row's notes."),
}

NOTES_LABEL = {"es": "Notas sobre esta fila", "en": "Notes on this row"}
NOTES_PLACEHOLDER = {"es": "Qué cambiar y en qué celda…",
                     "en": "What to change, and in which cell…"}

ROW_ID = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)+$")
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


def tile_label(tile, lang):
    parts = tile.split("-")
    if len(parts) == 2:
        mode = MODE_WORDS[lang].get(parts[0])
        view = VIEW_WORDS[lang].get(parts[1])
        if mode and view:
            return mode + " · " + view
    return tile


def check_tile_name(name, where):
    """A tile name is one token. `data-tiles` on the block is a SPACE-SEPARATED
    list, so a name with a space in it declares two tiles the checker then
    cannot find, and the row it came from is reported missing a tile that
    exists."""
    if not isinstance(name, str):
        die("%s: every tile name must be a string, not %s"
            % (where, type(name).__name__))
    if not name.strip() or name.split() != [name]:
        die("%s: the tile name %r contains whitespace — data-tiles on the "
            "block is a space-separated list, so a name with a space in it is "
            "two tiles no row can satisfy" % (where, name))


def check_path(value, cell, tile):
    """A row path is relative to the repo root, because `--root` is what turns
    it into a URL. An absolute one silently ignores --root and pins the page to
    one machine; a `..` climbs out of the checkout, and the page then shows
    whatever is up there."""
    if not isinstance(value, str):
        die("row '%s': the path for tile '%s' must be a string, not %s"
            % (cell, tile, type(value).__name__))
    if not value.strip():
        die("row '%s' has an empty path for tile '%s'" % (cell, tile))
    if value.startswith("/") or os.path.isabs(value) \
            or ".." in value.replace("\\", "/").split("/"):
        die("row '%s': the path for tile '%s' (%r) must be relative to the "
            "repo root — --root is what makes it a URL, and a path that "
            "ignores it pins the page to one machine or points outside the "
            "checkout" % (cell, tile, value))


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
    for key in ("gallery", "tiles", "rows"):
        if key not in doc:
            die("the rows document has no '%s' key" % key)
    if not isinstance(doc["tiles"], list) or not doc["tiles"]:
        die("'tiles' must be a non-empty list of tile names")
    for t in doc["tiles"]:
        check_tile_name(t, "'tiles'")
    if len(set(doc["tiles"])) != len(doc["tiles"]):
        die("'tiles' names the same tile twice: %s" % " ".join(doc["tiles"]))
    if not isinstance(doc["rows"], list):
        die("'rows' must be a list")
    return doc


def check_row(row, tiles, n):
    """Every refusal a row can earn, named by cell rather than by index."""
    if not isinstance(row, dict):
        die("row %d is not an object" % n)
    cell = row.get("cell")
    if not cell:
        die("row %d has no 'cell' key" % n)
    has_tiles, has_na = "tiles" in row, "notApplicable" in row
    if has_tiles and has_na:
        # Both is not a richer row, it is two contradictory claims: the reader
        # would be asked to judge screenshots of a state declared unreachable.
        die("row '%s' carries both 'tiles' and 'notApplicable' — a row is "
            "either shown in every tile or not applicable, never both" % cell)
    if not has_tiles and not has_na:
        die("row '%s' has neither 'tiles' nor 'notApplicable'" % cell)
    if has_na:
        # `str()` would turn null or false into a non-empty "reason", so the
        # same isinstance guard the tile paths carry applies here.
        if not isinstance(row["notApplicable"], str):
            die("row '%s': 'notApplicable' must be a string (the reason)"
                % cell)
        if not row["notApplicable"].strip():
            die("row '%s' is notApplicable with an empty reason" % cell)
        return cell, None, row["notApplicable"].strip()
    if not isinstance(row["tiles"], dict):
        die("row '%s': 'tiles' must be an object of tile -> path" % cell)
    for t in row["tiles"]:
        check_tile_name(t, "row '%s'" % cell)
    unknown = [t for t in row["tiles"] if t not in tiles]
    if unknown:
        # Sorted so the message is the same whatever the JSON's key order was.
        die("row '%s' names tile(s) the document does not declare: %s "
            "(declared: %s)" % (cell, " ".join(sorted(unknown)),
                                " ".join(tiles)))
    missing = [t for t in tiles if t not in row["tiles"]]
    if missing:
        die("row '%s' has no path for tile(s) %s — every declared tile is "
            "shown or the row is notApplicable"
            % (cell, " ".join(missing)))
    for t in tiles:
        check_path(row["tiles"][t], cell, t)
    return cell, row["tiles"], None


def render(doc, root, group_id, group_title, lang):
    gallery = doc["gallery"]
    tiles = list(doc["tiles"])
    root = root.rstrip("/")
    out = []
    add = out.append
    add('<section class="consult-group" id="%s" data-id="%s" data-title="%s"'
        ' data-tiles="%s">' % (e(group_id), e(group_id), e(group_title),
                               e(" ".join(tiles))))
    add('  <div class="sec-head">')
    add('    <h2>%s</h2>' % e(group_title))
    add('  </div>')
    for n, row in enumerate(doc["rows"], 1):
        cell, row_tiles, reason = check_row(row, tiles, n)
        ident = "%s-%s" % (gallery, cell)
        if not ROW_ID.match(ident):
            die("row id '%s' is not two or more lowercase slugs joined by "
                "hyphens — that shape is what keeps a row answerable across "
                "rounds" % ident)
        title = "%s · %s" % (gallery, cell)
        add('  <section class="consult-item consult-gallery" data-id="%s"'
            ' data-title="%s">' % (e(ident), e(title)))
        add('    <h3><span class="consult-id">%s</span>%s</h3>'
            % (e(ident), e(title)))
        add('    <p>%s</p>' % e(INTRO[lang]))
        if reason is not None:
            add('    <p class="gal-na">%s</p>' % e(reason))
        else:
            add('    <div class="gal">')
            for tile in tiles:
                url = "file://%s/%s" % (root, str(row_tiles[tile]).lstrip("/"))
                add('      <figure data-tile="%s"><img src="%s" alt="%s"'
                    ' loading="lazy"><figcaption>%s</figcaption></figure>'
                    % (e(tile), e(url), e("%s · %s" % (title, tile)),
                       e(tile_label(tile, lang))))
            add('    </div>')
        add('    <div class="opts one">')
        for label, text in VERDICTS[lang]:
            add('      <label><input type="radio" name="%s" data-label="%s">'
                '<span>%s</span></label>' % (e(ident), e(label), e(text)))
        add('    </div>')
        add('    <p class="fieldlabel">%s</p>' % e(NOTES_LABEL[lang]))
        add('    <textarea placeholder="%s"></textarea>'
            % e(NOTES_PLACEHOLDER[lang]))
        add('  </section>')
    add('</section>')
    return "\n".join(out) + "\n"


def main(argv):
    ap = argparse.ArgumentParser(
        prog="gallery-items.sh",
        description="Turn a gallery rows JSON into one consult-group of "
                    "gallery review items.")
    ap.add_argument("rows", metavar="<rows.json>",
                    help="the rows document the project emits")
    ap.add_argument("--root", required=True, metavar="<abs repo root>",
                    help="absolute checkout the row paths are relative to")
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
                            args.lang))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
