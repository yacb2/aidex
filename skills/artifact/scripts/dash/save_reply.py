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
happens when the page still equals the answered snapshot (two saves in one
round, no rebuild between): the second paste must not erase the first.

Usage: save-reply.sh <page.html> [<reply-file>|-]
  <reply-file> omitted or "-": read the paste from stdin.
"""
import datetime
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_artifact as ca  # noqa: E402
import wrap_report  # noqa: E402


def _prev_dir(page_path):
    return os.path.join(os.path.dirname(os.path.abspath(page_path)),
                        ".aidex-artifact-prev")


def _paths(page_path):
    prev_dir = _prev_dir(page_path)
    stem = os.path.splitext(os.path.basename(page_path))[0]
    return (prev_dir, os.path.join(prev_dir, stem + ".reply.md"),
           os.path.join(prev_dir, stem + ".answered.html"))


def duties_for(reply_text):
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
    return out


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
    # Two saves inside one round: the page has not been rebuilt since the last
    # save (it still equals the answered snapshot), so the second paste adds to
    # the first instead of replacing it.
    if had_previous and not outstanding:
        with open(page_path, encoding="utf-8", errors="replace") as fh:
            page_now = fh.read()
        with open(answered_path, encoding="utf-8", errors="replace") as fh:
            if page_now == fh.read():
                appended = "same-round"
    if appended:
        stamp = datetime.datetime.now().isoformat(timespec="seconds")
        with open(reply_path, "a", encoding="utf-8") as fh:
            fh.write(f"\n\n<!-- reply saved {stamp} -->\n\n{reply_text}")
        with open(reply_path, encoding="utf-8") as fh:
            combined = fh.read()
        return duties_for(combined), reply_path, answered_path, appended
    with open(reply_path, "w", encoding="utf-8") as fh:
        fh.write(reply_text)
    with open(page_path, encoding="utf-8", errors="replace") as fh:
        page_text = fh.read()
    with open(answered_path, "w", encoding="utf-8") as fh:
        fh.write(page_text)
    return duties_for(reply_text), reply_path, answered_path, False


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
    if reply_arg == "-":
        reply_text = sys.stdin.read()
    else:
        with open(reply_arg, encoding="utf-8") as fh:
            reply_text = fh.read()
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
            print(f"ERROR: {lock} is a stale build lock (older than "
                  f"{ca.BUILD_LOCK_STALE_AFTER // 60} min): no build is running, but "
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
