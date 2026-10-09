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

A STATES row (`-states`, N captures of one component, one checkbox each) answers
with its ticked labels: given `--rows` the row carries `states: [{id, label,
approved}]` for every declared state; without it the row is refused (an
unticked state cannot be told from one that does not exist), except under
`lenient`, which returns `states: [{label, approved: true}]` for the ticked
labels only. `verdict` is "" unless the composer's "Other" choice was ticked:
that label is then the verdict, in both modes, and never a state. A mark on a
states row names one of ITS states (`--tiles` is the block's before/after
matrix and does not apply to it; under `lenient` any one-token tile is read).

A row's body splits in three, in the order readItem pastes it:
  answer   the first paragraph, ONLY if every line in it is `- <known label>`
           (on an `alternatives` row also the labels of `--rows`: the spec named them),
           optionally ending in ` [provisional]`. Known labels are the verdicts
           (gallery_items.VERDICTS), the kit's two "Other" labels, and markers
           like `[question]` or `[not-now]`. Otherwise that paragraph is notes:
           dictated bullets are not a verdict. Exception, not on a states row: when the first bullet is exactly an owing
           label (Needs changes, Cannot judge, the kit's "Other"; on an
           alternatives row also the none-of-them label) it is the verdict and
           the remaining bullets go to the notes, so a reason typed as a bullet
           cannot drop the row's duty. From it come
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
import contextlib
import io
import json
import re
import sys

from _usage import read_stdin
from reply_defect import blank_defects, is_block_head
from gallery_items import (KINDS, alternatives_states, MARKER_LABEL, NONE_OF_THEM, OTHER, VERDICTS,
                           na_row_id, row_id)

NUM = r"(\d{1,3}\.\d)"
MARK = re.compile(r"^\[mark (\S+) %s,%s %sx%s\](?: (.*))?$"
                  % (NUM, NUM, NUM, NUM))


# OTHER (the kit's injected "Other" label, L.other in composer.js) lives in
# gallery_items, which is also what refuses an alternative named like it.
ANSWERS = {label for pairs in VERDICTS.values() for label, _ in pairs} \
    | set(OTHER)
# The answers that owe the next round something (everything but Approved).
OWING_FIRST = ANSWERS - {pairs[0][0] for pairs in VERDICTS.values()}
NONE_LABELS = {pair[0] for pair in NONE_OF_THEM.values()}
PROVISIONAL = " [provisional]"
GALLERY_REPLY_FORM = ('gallery-reply.sh [--rows <rows.json>]... [--tiles "<t1> <t2> ..."] '
                      "[<reply.md>|-]  (or pipe the reply on stdin)")


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
        if ident == na_row_id(*parts):
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


def parse_answer(ident, para, extra=(), alt=False, many=False, warn=True):
    """The answer block, or None when `para` is not one (then it is notes).
    `extra`: the labels an alternatives row's radios carry, known from the
    rows document (`--rows`); bullets that are not one of them stay notes.
    `extra=None` on an alternatives row means the labels are unknown (BL-632,
    `parse(..., lenient=True)`): the first bullet is taken as the choice."""
    verdict, verdict_line, asks, provisional = "", 0, [], False
    checked = []
    for n, line in para:
        if not line.startswith("- "):
            return None
        label = line[2:]
        if label.endswith(PROVISIONAL):
            label = label[:-len(PROVISIONAL)]
            provisional = True
        if MARKER_LABEL.match(label):
            asks.append(label)
        elif many and label in OTHER:
            # The composer adds "Other" to every `.opts` group: it is the
            # row's verdict, never a state (a states row has no other verdict).
            verdict, verdict_line = label, n
        elif many and (extra is None or label in extra):
            checked.append(label)
        elif (alt and extra is None and not verdict) \
                or label in ((extra or ()) if alt else ANSWERS):
            if verdict:
                die("line %d: row '%s' has more than one answer ('%s' on "
                    "line %d, '%s' here) — the page lets you pick one"
                    % (n, ident, verdict, verdict_line, label))
            verdict, verdict_line = label, n
        else:
            if warn and (alt or many) and label not in ANSWERS:
                sys.stderr.write('warning: row %s: "%s" is not a label of the '
                                 '--rows document; kept as a note (stale '
                                 '--rows?)\n' % (ident, label))
            return None
    return {"verdict": verdict, "asks": asks, "provisional": provisional,
            "checked": checked}


def parse_row(ident, key, body, tiles=None, labels=None, lenient=False,
              states=None, alt_tiles=None):
    gallery, cell, variant, kind = key
    body = trim(body)
    first = 0
    while first < len(body) and body[first][1].strip():
        first += 1
    extra = ()
    if kind == "alternatives":
        if lenient and (labels is None or gallery not in labels):
            extra = None
        elif labels is None or gallery not in labels:
            die("row '%s' is an alternatives row: its labels are the spec's, "
                "so pass the rows document that built the page with "
                "--rows <rows.json> (without it a chosen alternative cannot "
                "be told from a bullet in the notes)" % ident)
        else:
            extra = labels[gallery] | set(OTHER)
    declared = None
    if kind == "states":
        declared = (states or {}).get(ident)
        if declared is not None:
            extra = {st["label"] for st in declared}
        elif lenient:
            extra = None
        else:
            die("row '%s' is a states row: an unticked state cannot be told "
                "from one that does not exist, so pass the rows document "
                "that built the page with --rows <rows.json>" % ident)
    if declared is not None:
        tiles = [st["id"] for st in declared]    # a mark is on a state's figure
    elif kind == "states":
        tiles = None                             # unknown ids under lenient
    elif kind == "alternatives" and gallery in (alt_tiles or {}):
        tiles = alt_tiles[gallery]               # the alternatives' own figures
    # An owing first bullet (Needs changes, Cannot judge, the kit's "Other";
    # on an alternatives row also the none-of-them label) is the verdict even
    # when a reason bullet follows: that bullet stays a note, so a reason typed
    # as a bullet cannot drop the row's duty (U3-1, N1; BL-754). Markers right
    # after it stay asks. Not on states rows; on a strict alternatives row the
    # page offers only Other and none-of-them, so only those count.
    label = body[0][1][2:] if first and body[0][1].startswith("- ") else ""
    if label.endswith(PROVISIONAL):
        label = label[:-len(PROVISIONAL)]
    if kind == "alternatives":
        owing = label in (set(OTHER) | NONE_LABELS if extra is not None
                          else OWING_FIRST | NONE_LABELS)
    else:
        owing = kind != "states" and label in OWING_FIRST
    answer = parse_answer(ident, body[:first], extra,
                          kind == "alternatives",
                          kind == "states", warn=not owing) if first else None
    if not answer and owing:
        answer = {"verdict": label, "asks": [], "provisional": False,
                  "checked": []}
        first = 1
        for _, line in body[1:]:
            mark = line[2:] if line.startswith("- ") else ""
            bare = mark[:-len(PROVISIONAL)] if mark.endswith(PROVISIONAL) else mark
            if not MARKER_LABEL.match(bare):
                break
            answer["provisional"] |= bare != mark
            answer["asks"].append(bare)
            first += 1
        answer["provisional"] |= body[0][1].endswith(PROVISIONAL)
    if answer:
        body = body[first:]
    else:
        answer = {"verdict": "", "asks": [], "provisional": False,
                  "checked": []}
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
    row = {"id": ident, "gallery": gallery, "cell": cell,
           "variant": variant, "kind": kind,
           "verdict": answer["verdict"],
           "notes": "\n".join(l for _, l in trim(notes)),
           "asks": answer["asks"], "provisional": answer["provisional"],
           "marks": marks}
    if kind == "states":
        row["states"] = [{"id": st["id"], "label": st["label"],
                          "approved": st["label"] in answer["checked"]}
                         for st in declared] if declared is not None else \
            [{"label": l, "approved": True} for l in answer["checked"]]
    return row


def parse(text, tiles=None, labels=None, lenient=False, states=None,
          alt_tiles=None):
    """`lenient`: an alternatives row needs no --rows document (its chosen
    label is read as the first bullet); save_reply uses it, which only wants
    to know what is owed, not which alternative was chosen."""
    items, groups, cur = [], [], None
    text = blank_defects(text)       # the composer's page-defect sub-block is no row text
    for n, line in enumerate(text.splitlines(), 1):
        if is_block_head(line) and line.startswith("### "):
            ident, _, title = line[4:].partition(" ·")
            cur = {"id": ident.strip(), "title": title.strip(), "body": [],
                   "line": n}
            items.append(cur)
        elif is_block_head(line):
            # A block's own notes (BL-701) sit under its heading, before its items.
            ident, _, title = line[3:].partition(" ·")
            cur = {"id": ident.strip(), "title": title.strip(), "body": []}
            groups.append(cur)
        elif cur is not None:
            cur["body"].append((n, line))
    rows, other = [], []
    for it in items:
        key = gallery_key(it["id"], it["title"], it["line"])
        if key:
            rows.append(parse_row(it["id"], key, it["body"], tiles, labels,
                                  lenient, states, alt_tiles))
        else:
            other.append({"id": it["id"], "title": it["title"],
                          "body": "\n".join(l for _, l in trim(it["body"]))})
    groups = [{"id": g["id"], "title": g["title"],
               "notes": "\n".join(l for _, l in trim(g["body"]))} for g in groups]
    return {"rows": rows, "other": other,
            "groups": [g for g in groups if g["notes"]]}


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
            text = read_stdin(GALLERY_REPLY_FORM, binary=True, blank_is_empty=True).decode("utf-8-sig")
        else:
            with open(args.reply, encoding="utf-8-sig") as fh:
                text = fh.read()
    except FileNotFoundError:
        die("no such reply file: %s" % args.reply)
    except OSError as e:
        die("cannot read %s: %s" % (args.reply, e.strerror))
    except UnicodeDecodeError:
        die("%s is not UTF-8 text" % args.reply)
    labels, states, alt_tiles = {}, {}, {}
    for path in args.rows:
        try:
            with open(path, encoding="utf-8") as fh:
                doc = json.load(fh)
            # Merged, not assigned: a states row and an alternatives row of
            # one gallery come in two documents with the same slug.
            labels.setdefault(doc["gallery"], set()).update(
                {a["label"].strip() for a in doc.get("alternatives", [])}
                | {pair[0] for pair in NONE_OF_THEM.values()})
            alts = doc.get("alternatives")
            if alts:
                try:
                    with contextlib.redirect_stderr(io.StringIO()):
                        per = alternatives_states(doc, list(doc["variants"]), alts, False)
                except SystemExit:
                    die("--rows %s is not a valid rows document" % path)
                alt_tiles[doc["gallery"]] = (
                    [a["id"] + "-" + st for a in alts for st in per]
                    if per else [a["id"] for a in alts])
            for r in doc["rows"]:
                if r.get("kind") == "states" and "states" in r:
                    states[row_id(doc["gallery"], r["cell"], r["variant"],
                                  "states")] = [
                        {"id": st["id"], "label": st["label"].strip()}
                        for st in r["states"]]
        except (OSError, ValueError, KeyError, TypeError, AttributeError):
            die("--rows %s is not a readable rows document" % path)
    sys.stdout.write(json.dumps(parse(text, args.tiles.split() if args.tiles is not None else None, labels, states=states, alt_tiles=alt_tiles), ensure_ascii=False, indent=2)
                     + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
