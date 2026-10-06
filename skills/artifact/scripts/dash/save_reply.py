#!/usr/bin/env python3
"""save_reply.py — save a consultation reply BEFORE the next round is built
(02-local-first-artifacts.md § "The reply is saved before the next round is
built (BL-475)"). Logic lives here; save-reply.sh is the entry, the same
split every other dash/*.py script has.

The reader's marks live in browser storage and in the paste, never on disk.
This writes the paste verbatim to `.aidex-artifact-prev/<stem>.reply.md`, AND
snapshots the page as it stood when the reader answered it to
`.aidex-artifact-prev/<stem>.answered.html` — the FIXED reference every marker
check in check_artifact.py (`check_marker_duties`) judges the next round
against. Not the moving `.aidex-artifact-prev/<stem>.html` contract baseline:
that one is overwritten by every passing wrap (by design, for id stability),
so a check keyed to it silently stopped enforcing on the first re-wrap inside
a round (BL-504) — a round shipped 7 `[show-me]` items and 0 figures because
the show-me check had already been defeated by the visual grader's own fixes
before the reader ever saw the round.

A SECOND save must not be able to do the same thing from the other side
(review finding 1, 2026-09-29): saving a follow-up reply that marks nothing
used to unconditionally REPLACE reply.md/answered.html, which silently
cleared any duty the FIRST reply still had outstanding — a page whose Q1
never got its figure started passing once the reader's next message (however
unrelated) was saved. `save_reply` now checks the page on disk against the
reply that is already there before writing anything: while a duty is still
unmet, the new paste is APPENDED under a timestamped separator and
answered.html is left untouched; only once every outstanding duty is met
does a new reply replace the file and re-snapshot the page. The same append
happens when the page is the one the previous save came from (two saves in
one round, no rebuild between): the second paste must not erase the first.
Each separator carries that page's fingerprint; with none, the previous
page is the answered snapshot (BL-644). That page check wins over the duty
check: a page unchanged since the last save is labelled `same-round` even
with a duty unmet, so a later full composer paste from it supersedes the
earlier one (BL-598).

Usage: save-reply.sh <page.html> [<reply-file>|-]
  <reply-file> omitted or "-": read the paste from stdin.
"""
import contextlib
import datetime
import hashlib
import html
import io
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_artifact as ca  # noqa: E402
import gallery_reply  # noqa: E402
from gallery_items import VERDICTS  # noqa: E402
import wrap_report  # noqa: E402


def _prev_dir(page_path):
    return os.path.join(os.path.dirname(os.path.abspath(page_path)),
                        ".aidex-artifact-prev")


def _paths(page_path):
    prev_dir = _prev_dir(page_path)
    stem = os.path.splitext(os.path.basename(page_path))[0]
    return (prev_dir, os.path.join(prev_dir, stem + ".reply.md"),
           os.path.join(prev_dir, stem + ".answered.html"))


_PAGE_FP = re.compile(r" page:([0-9a-f]+) ")


def _fingerprint(path):
    # the decoded text, read the way the replace path below reads the page it
    # writes to answered.html: raw bytes of a CRLF page never match that copy
    with open(path, encoding="utf-8", errors="replace") as fh:
        return hashlib.sha256(fh.read().encode("utf-8")).hexdigest()[:16]


APPROVED = {"Aprobada", "Approved"}
NEEDS_CHANGES = {pairs[1][0] for pairs in VERDICTS.values()}
# Every answer a reader can give that is not the approval: Needs changes,
# Cannot judge and the kit's two "Other" labels.
OWING_VERDICTS = set(gallery_reply.ANSWERS) - APPROVED
GALLERY_NEEDS_DUTY = ("the reader said this gallery row needs changes: read "
                      "its note and change what it names")
GALLERY_OTHER_DUTY = ("the reader did not approve this gallery row (Other / "
                      "Cannot judge): read its note and answer what it says")
GALLERY_MARK_DUTY = ("the reader marked regions of this gallery row's capture: "
                     "fix what each mark's note names")


def _drop_items(chunk, ordinary):
    """The chunk with every `### <id>` block whose id is an ordinary item of
    the page blanked out (lines kept, so refusal line numbers still match).
    A `### <ordinary-id> · ...` line pasted inside a gallery row's notes blanks
    what follows it too, marks included: the parser's existing limit, where
    any such heading hands the rest to that item's block."""
    out, keep = [], True
    for line in chunk.splitlines(keepends=True):
        if line.startswith("### "):
            keep = line[4:].partition(" · ")[0].strip() not in ordinary
        elif line.startswith("## "):
            keep = True
        out.append(line if keep else "\n")
    return "".join(out)


def _states_owe(row):
    """A states row owes changes when some declared state is ticked and some is
    not (partial approval: the rest needs changes), or when none is ticked and
    notes say why. All ticked owes nothing, even with notes; none ticked and no
    notes is a blank row, which owes nothing exactly like a review row with no
    verdict. Without the page's declared states (`id` absent) the ticked labels
    alone cannot say what is unticked, so only the notes count."""
    ticked = sum(1 for s in row["states"] if s["approved"])
    if row["states"] and "id" in row["states"][0]:
        if 0 < ticked < len(row["states"]):
            return True
        return ticked == 0 and bool(row["notes"].strip())
    return bool(row["notes"].strip())


_STATE_BOX = re.compile(r'<input\b[^>]*type="checkbox"[^>]*\bname="([^"]*)"'
                        r'[^>]*\bdata-label="([^"]*)"')


def states_in_page(page_text):
    """{states row id: [{id, label}]} read from the page's own states items, so
    a reply is parsed against the labels the reader was shown."""
    out = {}
    text = ca.strip_html_comments(page_text)
    for m in ca.ITEM_OPEN.finditer(text):
        if ca.GROUP_CLASS.search(m.group(0)):
            continue                  # a block is a context, never a row
        ident = html.unescape(next(g for g in m.groups()[1:] if g is not None))
        if not ident.endswith("-states"):
            continue
        body = ca.strip_script_style(ca._subtree(text, m.group(1), m.end()))
        boxes = [{"id": html.unescape(b.group(1))[len(ident) + 1:],
                  "label": html.unescape(b.group(2))}
                 for b in _STATE_BOX.finditer(body)]
        if boxes:
            out[ident] = boxes
    return out


def gallery_duties_for(reply_text, ordinary=(), states=None):
    """[(id, tag, duty text)] for gallery rows (gallery_reply's parser) whose
    answer is anything but Approved, or that carry region marks even when
    approved (BL-632). An approved row with no mark owes nothing. Each saved
    paste is parsed on its own (the separator an appended save writes would
    read as text after a row's marks) and the LATEST paste wins per row id: a
    row a later paste turns Approved with no marks leaves the list. A paste
    gallery_reply refuses yields an `unreadable` row instead of nothing, so
    "nothing owed" cannot print over rows nobody read. `ordinary`: ids the
    page shows as ordinary items, never read as gallery rows (BL-654)."""
    by_id, unreadable = {}, []
    for chunk in ca._SAVE_SEP.split(reply_text):
        err = io.StringIO()
        try:
            with contextlib.redirect_stderr(err):
                rows = gallery_reply.parse(_drop_items(chunk, ordinary),
                                           lenient=True,
                                           states=states)["rows"]
        except SystemExit:
            msg = err.getvalue().strip().replace("gallery-reply: ", "", 1)
            if msg not in unreadable:
                unreadable.append(msg)
            continue
        for row in rows:
            duties = []
            if row["verdict"] in NEEDS_CHANGES:
                duties.append((row["id"], "needs-changes", GALLERY_NEEDS_DUTY))
            elif row["verdict"] in OWING_VERDICTS:
                duties.append((row["id"], "other-verdict", GALLERY_OTHER_DUTY))
            elif row["kind"] == "states" and _states_owe(row):
                duties.append((row["id"], "needs-changes", GALLERY_NEEDS_DUTY))
            if row["marks"]:
                duties.append((row["id"], "region-marks", GALLERY_MARK_DUTY))
            by_id.pop(row["id"], None)
            by_id[row["id"]] = duties
    out = [d for duties in by_id.values() for d in duties]
    for msg in unreadable:
        out.append(("(gallery)", "unreadable",
                    "gallery rows in this paste could not be read: %s; list "
                    "their duties by hand" % msg))
    return out


def duties_for(reply_text, ordinary=(), states=None):
    """[(id, marker, duty text)]. 3+ REAL asks (excluding `[page-defect]` and
    `[not-now]`, review finding 2) collapse to a single STACKED_DUTY row
    instead of one per marker — that is the duty: rewrite the item, not each
    ask. `[page-defect]` and `[not-now]` always print their own line, stacked
    or not: neither is answered by a rewrite of the item."""
    out = []
    for ident, marks in ca.marker_duties_of(reply_text):
        stack_eligible = [m for m in marks if m not in ca.NO_STACK_MARKERS]
        if len(stack_eligible) >= 3:
            out.append((ident, "3+ asks (" + ", ".join(stack_eligible) + ")",
                       ca.STACKED_DUTY))
        else:
            for m in stack_eligible:
                duty = ca.MARKER_DUTIES.get(m)
                if duty is not None:
                    out.append((ident, m, duty))
        for m in marks:
            if m in ca.NO_STACK_MARKERS:
                duty = ca.MARKER_DUTIES.get(m)
                if duty is not None:
                    out.append((ident, m, duty))
    return out + gallery_duties_for(reply_text, ordinary, states)


def save_reply(page_path, reply_text):
    """Writes the reply and the answered snapshot (or appends/keeps them when
    a duty is still outstanding or the round has not been rebuilt — see the
    module docstring). Returns (duties, reply_path, answered_path, appended),
    where appended is False, "duty" or "same-round"."""
    prev_dir, reply_path, answered_path = _paths(page_path)
    os.makedirs(prev_dir, exist_ok=True)
    had_previous = os.path.isfile(reply_path) and os.path.isfile(answered_path)
    # The duty check of the OLD reply against the CURRENT page — run BEFORE
    # anything is written, so it reads the files this save is about to touch.
    outstanding = had_previous and bool(ca.check_marker_duties(page_path)[0])
    appended = "duty" if outstanding else False
    # Two saves inside one round: this paste comes from the same page as the
    # save before it, so it adds to that one instead of replacing it. Checked
    # even when a duty is outstanding: a later full paste from the same page
    # may supersede the earlier one (BL-598). The page of the save before is
    # the fingerprint its separator carries; with none (the first save, or a
    # separator written before BL-644) it is the answered snapshot. Comparing
    # only with answered.html made two saves from one rebuilt, duty-failing
    # page both `duty`, i.e. two rounds (BL-644).
    with open(page_path, encoding="utf-8", errors="replace") as fh:
        page_text = fh.read()
    ordinary = ca.ordinary_item_ids(page_text)
    states = states_in_page(page_text)
    if had_previous:
        page_fp = _fingerprint(page_path)
        with open(reply_path, encoding="utf-8", errors="replace") as fh:
            seps = ca._SAVE_SEP.findall(fh.read())
        last = _PAGE_FP.search(seps[-1]) if seps else None
        if page_fp == (last.group(1) if last else _fingerprint(answered_path)):
            appended = "same-round"
    if appended:
        stamp = datetime.datetime.now().isoformat(timespec="seconds")
        with open(reply_path, "a", encoding="utf-8") as fh:
            # the mode tells check_artifact._live_reply whether this paste
            # is from the same page as the one before it (BL-598); the page
            # fingerprint is what the next save compares with (BL-644)
            fh.write(f"\n\n<!-- reply saved {stamp} page:{page_fp} {appended} -->"
                     f"\n\n{reply_text}")
        with open(reply_path, encoding="utf-8") as fh:
            combined = fh.read()
        return duties_for(combined, ordinary, states), reply_path, answered_path, appended
    with open(reply_path, "w", encoding="utf-8") as fh:
        fh.write(reply_text)
    with open(answered_path, "w", encoding="utf-8") as fh:
        fh.write(page_text)
    return duties_for(reply_text, ordinary, states), reply_path, answered_path, False


def main(argv):
    if not argv:
        print("ERROR: usage: save-reply.sh <page.html> [<reply-file>|-]",
              file=sys.stderr)
        return 2
    page_path = argv[0]
    if not os.path.isfile(page_path):
        print(f"ERROR: {page_path} is not a file", file=sys.stderr)
        return 2
    reply_arg = argv[1] if len(argv) > 1 else "-"
    where = "on stdin" if reply_arg == "-" else reply_arg
    try:
        if reply_arg == "-":
            reply_text = sys.stdin.read()
        else:
            with open(reply_arg, encoding="utf-8") as fh:
                reply_text = fh.read()
    except OSError as exc:
        print(f"ERROR: cannot read the reply {where}: {exc}", file=sys.stderr)
        return 2
    except UnicodeDecodeError as exc:
        print(f"ERROR: the reply {where} is not UTF-8 (byte "
              f"0x{exc.object[exc.start]:02x} at offset {exc.start}) — save it "
              f"as UTF-8", file=sys.stderr)
        return 2
    if not reply_text.strip():
        print("ERROR: the reply is empty — nothing to save", file=sys.stderr)
        return 2
    lock = wrap_report.lock_path(page_path)
    if os.path.exists(lock):
        age = time.time() - os.path.getmtime(lock)
        # The page on disk is the delegate's intermediate wrap, not what the reader
        # answered; snapshotting it would skip a round (BL-507). No copy of the
        # reader's version is kept, so refuse rather than guess.
        if not -ca.BUILD_LOCK_STALE_AFTER <= age <= ca.BUILD_LOCK_STALE_AFTER:
            # Past the window artifact-open-once.sh honours (BL-542): no build is
            # running, the lock is left over from one that died or never ran --done.
            # A lock dated beyond the window in the FUTURE is stale too (the hook's
            # "absurd" band), but it is not older than anything (BL-562).
            window = ca.BUILD_LOCK_STALE_AFTER // 60
            when = (f"older than {window} min" if age > 0 else
                    f"dated more than {window} min in the future")
            print(f"ERROR: {lock} is a stale build lock ({when}): no build is running, but "
                  f"{page_path} may be a half-finished wrap. If it is the page the "
                  f"reader answered, clear the lock (wrap-report.sh --done --out "
                  f"{page_path}) and save the reply again.", file=sys.stderr)
            return 2
        shown = max(int(age), 0)
        print(f"ERROR: {lock} exists (age {shown // 60} min {shown % 60} s) — a build is still running, so {page_path} is "
              f"not the page the reader answered. End the build first "
              f"(wrap-report.sh --done --out {page_path}), then save the reply.",
              file=sys.stderr)
        return 2
    duties, reply_path, answered_path, appended = save_reply(page_path, reply_text)
    if appended == "same-round":
        print(f"reply APPENDED to {reply_path} — the page has not been rebuilt "
              f"since the last save, so this paste adds to that one and the "
              f"answered snapshot at {answered_path} was kept")
    elif appended:
        print(f"reply APPENDED to {reply_path} — an earlier duty is still "
              f"outstanding, so the answered snapshot at {answered_path} was "
              f"kept, not re-captured")
    else:
        print(f"reply saved: {reply_path}")
        print(f"answered snapshot: {answered_path}")
    if not duties:
        print("no marked items — nothing owed by the next round")
        return 0
    print("DUTIES the next round owes:")
    for ident, marker, duty in duties:
        print(f"{ident} [{marker}]: {duty}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
