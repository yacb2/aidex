#!/usr/bin/env python3
"""gallery_reply.py — a pasted consultation reply becomes JSON.

The input is exactly the block the page's copy button produced (`collect()`
in composer.js), nothing before or after it:

  ## <group id> · <group title>
  ### <item id> · <item title>

  - <option label>            (the checked options, one line each)

  <notes paragraphs>

  [mark <tile> x,y wxh] note  (one line per region mark, always last)

A GALLERY ROW is an item whose heading title is `<gallery> · <cell> ·
<variant>` (the row's `data-title`; the human `title` of the rows JSON is only
what the page shows, so a titled row pastes the same heading) and whose id is `<gallery>-<cell>-<variant>`, with `-<kind>` added
for a row that is not a review (`-unrequested`, `-sample`); a not-applicable
row is `<gallery> · <cell>` / `<gallery>-<cell>-not-applicable` (kind
`not-applicable`, variant "") — exactly what gallery_items.py writes. A row of
the old light/dark matrix (`<gallery> · <cell>` / `<gallery>-<cell>`) is
refused on its line. It is recognised by that heading, never by carrying
marks: an approved row has none and is still a row. Every other item goes to `other` untouched (id, title, raw
body), so a reply mixing gallery rows and ordinary questions loses nothing.

A row's body splits in three, in the order readItem pastes it:
  answer   the first paragraph, ONLY if every line in it is `- <known label>`
           (on an `alternatives` row also the labels of `--rows`: the spec named them),
           optionally ending in ` [provisional]`. Known labels are the verdicts
           (gallery_items.VERDICTS), the kit's two "Other" labels, and markers
           like `[question]` or `[not-now]`. Otherwise that paragraph is notes:
           dictated bullets are not a verdict. From it come
             verdict      the one verdict or "Other" label, suffix removed, ""
                          if none; two of them is refused
             asks         the marker labels, in paste order
             provisional  true if any line carried ` [provisional]`
  notes    everything after the answer up to the first `[mark ` line (with
           the space: `[markdown]` is a note), blank lines trimmed at both ends
  marks    every line from the first `[mark ` on; blank lines between them are
           skipped, any other text there is refused. Text after the paste (a
           dictated sentence) cannot be told apart from notes, so the input
           must be the copied block alone.

Mark numbers are percentages of the tile with one decimal, and the edge is
inclusive: x+w == 100 is a mark flush against the right edge. Float sums are
exact enough here — for every one-decimal pair a + b whose true sum is 100.0,
the float sum is 100.0 too (checked exhaustively), and any other true sum is at
least 0.1 away from the edge.

Refusals exit 2 with one plain line naming the input line, like
gallery_items.py: a malformed mark, text after a row's marks or two answers in
one row is the paste's defect, and a traceback — or
half a JSON document — would hide which line it was.

Usage:
  gallery-reply.sh [--rows <rows.json>]... [--tiles "<t1> <t2> ..."] [<reply.md>]
                                                    (no file or `-`: stdin)
"""

import argparse
import json
import re
import sys

from gallery_items import KINDS, NONE_OF_THEM, OTHER, VERDICTS, row_id

NUM = r"(\d{1,3}\.\d)"
MARK = re.compile(r"^\[mark (\S+) %s,%s %sx%s\](?: (.*))?$"
                  % (NUM, NUM, NUM, NUM))


# OTHER (the kit's injected "Other" label, L.other in composer.js) lives in
# gallery_items, which is also what refuses an alternative named like it.
ANSWERS = {label for pairs in VERDICTS.values() for label, _ in pairs} \
    | set(OTHER)
MARKER = re.compile(r"^\[[a-z-]+\]$")
PROVISIONAL = " [provisional]"


def die(msg):
    sys.stderr.write("gallery-reply: " + msg + "\n")
    raise SystemExit(2)


def parse_mark(line, n, tiles=None):
    m = MARK.match(line)
    if not m:
        die("line %d: %r does not match the mark contract "
            "'[mark <tile> x,y wxh] note' (numbers with one decimal)"
            % (n, line))
    # The tile is any one token unless the caller passes the page's own list
    # (`--tiles`, the block's data-tiles): the paste does not carry the
    # matrix, and the composer only writes a name one of the figures has.
    tile, raw, note = m.group(1), m.group(2, 3, 4, 5), m.group(6) or ""
    if tiles is not None and tile not in tiles:
        die("line %d: tile '%s' is not one of the page's tiles (%s)"
            % (n, tile, " ".join(tiles)))
    x, y, w, h = (float(v) for v in raw)
    for name, v in zip("xywh", (x, y, w, h)):
        if v > 100:
            die("line %d: %s=%.1f is outside 0-100" % (n, name, v))
    if x + w > 100:
        die("line %d: x+w = %.1f runs past the right edge (100)" % (n, x + w))
    if y + h > 100:
        die("line %d: y+h = %.1f runs past the bottom edge (100)" % (n, y + h))
    return {"tile": tile, "x": x, "y": y, "w": w, "h": h,
            "note": note.strip()}


def trim(lines):
    """Drop blank lines at both ends; keep the ones inside."""
    while lines and not lines[0][1].strip():
        lines = lines[1:]
    while lines and not lines[-1][1].strip():
        lines = lines[:-1]
    return lines


def gallery_key(ident, title, n):
    """(gallery, cell, variant, kind) when the heading is a gallery row's."""
    parts = title.split(" · ")
    if len(parts) == 2 and all(parts):
        # A not-applicable row has no variant; its id carries the suffix.
        if ident == "%s-%s-not-applicable" % tuple(parts):
            return parts + ["", "not-applicable"]
        # `<gallery>-<cell>` alone is the OLD light/dark matrix row: its
        # verdict was given on four captures, and reading it as a row of this
        # contract would mislabel it.
        if ident == "%s-%s" % tuple(parts):
            die("line %d: row '%s' comes from an old light/dark matrix page "
                "(id <gallery>-<cell>) — re-emit the rows and answer the "
                "rebuilt page" % (n, ident))
    if len(parts) != 3 or not all(parts):
        return None
    for kind in KINDS:
        if ident == row_id(*parts, kind):
            return parts + [kind]
    return None


def parse_answer(ident, para, extra=(), alt=False):
    """The answer block, or None when `para` is not one (then it is notes).
    `extra`: the labels an alternatives row's radios carry, known from the
    rows document (`--rows`); bullets that are not one of them stay notes."""
    verdict, verdict_line, asks, provisional = "", 0, [], False
    for n, line in para:
        if not line.startswith("- "):
            return None
        label = line[2:]
        if label.endswith(PROVISIONAL):
            label = label[:-len(PROVISIONAL)]
            provisional = True
        if MARKER.match(label):
            asks.append(label)
        elif label in (extra if alt else ANSWERS):
            if verdict:
                die("line %d: row '%s' has more than one answer ('%s' on "
                    "line %d, '%s' here) — the page lets you pick one"
                    % (n, ident, verdict, verdict_line, label))
            verdict, verdict_line = label, n
        else:
            if alt and label not in ANSWERS:
                sys.stderr.write('warning: row %s: "%s" is not a label of the '
                                 '--rows document; kept as a note (stale '
                                 '--rows?)\n' % (ident, label))
            return None
    return {"verdict": verdict, "asks": asks, "provisional": provisional}


def parse_row(ident, key, body, tiles=None, labels=None):
    gallery, cell, variant, kind = key
    body = trim(body)
    first = 0
    while first < len(body) and body[first][1].strip():
        first += 1
    extra = ()
    if kind == "alternatives":
        if labels is None or gallery not in labels:
            die("row '%s' is an alternatives row: its labels are the spec's, "
                "so pass the rows document that built the page with "
                "--rows <rows.json> (without it a chosen alternative cannot "
                "be told from a bullet in the notes)" % ident)
        extra = labels[gallery] | set(OTHER)
    answer = parse_answer(ident, body[:first], extra,
                          kind == "alternatives") if first else None
    if answer:
        body = body[first:]
    else:
        answer = {"verdict": "", "asks": [], "provisional": False}
    notes, marks, in_marks = [], [], False
    for n, line in body:
        if line.startswith("[mark "):
            in_marks = True
            marks.append(parse_mark(line, n, tiles))
        elif in_marks:
            if line.strip():
                die("line %d: %r comes after the marks of row '%s' — marks "
                    "are the last thing in a row; feed only the block the "
                    "page's copy button produced" % (n, line, ident))
        else:
            notes.append((n, line))
    return {"id": ident, "gallery": gallery, "cell": cell,
            "variant": variant, "kind": kind,
            "verdict": answer["verdict"],
            "notes": "\n".join(l for _, l in trim(notes)),
            "asks": answer["asks"], "provisional": answer["provisional"],
            "marks": marks}


def parse(text, tiles=None, labels=None):
    items, cur = [], None
    for n, line in enumerate(text.splitlines(), 1):
        if line.startswith("### "):
            ident, _, title = line[4:].partition(" · ")
            cur = {"id": ident.strip(), "title": title.strip(), "body": [],
                   "line": n}
            items.append(cur)
        elif line.startswith("## "):
            cur = None
        elif cur is not None:
            cur["body"].append((n, line))
    rows, other = [], []
    for it in items:
        key = gallery_key(it["id"], it["title"], it["line"])
        if key:
            rows.append(parse_row(it["id"], key, it["body"], tiles, labels))
        else:
            other.append({"id": it["id"], "title": it["title"],
                          "body": "\n".join(l for _, l in trim(it["body"]))})
    return {"rows": rows, "other": other}


def main(argv):
    ap = argparse.ArgumentParser(
        prog="gallery-reply.sh",
        description="Turn a pasted consultation reply into JSON: gallery rows "
                    "with verdict, asks, notes and marks, other items "
                    "untouched. The input is exactly the block the page's "
                    "copy button produced, nothing added before or after.")
    ap.add_argument("reply", nargs="?", default="-", metavar="<reply.md>",
                    help="the copied reply (default: stdin)")
    ap.add_argument("--rows", action="append", default=[],
                    metavar="<rows.json>",
                    help="the rows document a page was built from (repeat for "
                         "several galleries): required when the reply holds "
                         "an alternatives row, whose labels it names")
    ap.add_argument("--tiles", metavar='"<t1> <t2> ..."',
                    help="the page's tile names (the block's data-tiles); a "
                         "mark on any other tile is refused. Without it, any "
                         "one-token tile name is read")
    args = ap.parse_args(argv)
    try:
        if args.reply == "-":
            text = sys.stdin.buffer.read().decode("utf-8-sig")
        else:
            with open(args.reply, encoding="utf-8-sig") as fh:
                text = fh.read()
    except FileNotFoundError:
        die("no such reply file: %s" % args.reply)
    except UnicodeDecodeError:
        die("%s is not UTF-8 text" % args.reply)
    labels = {}
    for path in args.rows:
        try:
            with open(path, encoding="utf-8") as fh:
                doc = json.load(fh)
            labels[doc["gallery"]] = {a["label"].strip() for a in
                                      doc.get("alternatives", [])} \
                | {pair[0] for pair in NONE_OF_THEM.values()}
        except (OSError, ValueError, KeyError, TypeError, AttributeError):
            die("--rows %s is not a readable rows document" % path)
    sys.stdout.write(json.dumps(parse(text, args.tiles.split() if args.tiles is not None else None, labels), ensure_ascii=False, indent=2)
                     + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
