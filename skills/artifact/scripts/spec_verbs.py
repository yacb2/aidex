#!/usr/bin/env python3
"""spec_verbs.py — the per-operation edits an agent makes to a page SPEC.

The third layer of the spec route, and the one the editing model (Q2 of the
plan) exists for: **the agent never edits the built HTML.** It calls a verb, the
verb rewrites the `.spec.md`, and `spec_build.build()` regenerates the page. The
spec stays the single source of truth a rebuild can always be replayed from.

Four properties this file is written to keep, in the order they are
load-bearing:

1. **A verb is a text transform on the spec and nothing else.** `add_item`,
   `decide` and `new_round` take spec text and return spec text. They import no
   emitter, spell no HTML, and hold no opinion about markup — every byte of the
   page comes out of `spec_build.py`, which is why a verb cannot drift from the
   kit. The three pure functions are the API; the `_file` wrappers are the I/O
   around them.

2. **Refusing is atomic.** A verb that cannot find its id, or whose result would
   not build, writes NOTHING: the candidate spec goes through the SAME gate the
   rebuild runs — parse, build, wrap and `check_artifact.py`, against a
   throwaway page in a temp dir — before the file is touched, and the write
   itself is a `os.replace` of a sibling temp file. A half-edited spec is worse
   than a refused edit, because the refusal says which id it could not find and
   the half-edit says nothing at all. A weaker gate here than the rebuild's is
   not a smaller promise but the opposite of one: it writes a spec no verb can
   build again, so the next verb call also writes and also fails, and the spec
   is wedged with no verb able to recover it. That is why the gate is the whole
   `spec_build.main` and not `build()` alone — and why a rebuild that fails
   anyway (the real page's dir carries a baseline the trial's did not) rolls the
   spec back to the bytes it had.

3. **The author's formatting survives.** A verb edits the lines it is changing
   and rejoins the rest verbatim: no reflow, no re-indent, no attr reordering,
   no re-quoting, and no normalising of the trailing newline. `decide` rewrites
   the span of one attr inside one fence line (the span comes from the
   tokenizer's own attr walk, `spec_parser._parse_attrs(..., spans=)`, so there
   is no second scanner to disagree with it) and leaves the other bytes of that
   line where they were.

4. **Ids are the interface.** Every verb addresses its target by the `#id` the
   spec wrote, never by position or by title. §8.1 is why: a reply that says "on
   Q3 I disagree" has to mean the same claim next round, so a verb that
   renumbers or re-slugs is a verb that silently answers a different question.

Idempotency is decided per verb, and stated on each one — see the docstrings.
The short of it:

    add-item   REFUSES a second call with the same id (two different items
               would end up sharing a paste key; one would shadow the other).
    decide     IDEMPOTENT for the same verdict (byte-identical spec, rebuild
               still runs); a DIFFERENT verdict overwrites, because
               `owner-changed` — the reader revising an earlier answer — is one
               of the four documented round labels, and `wrap_report.py`
               already re-stamps `data-decided-round` when the verdict text
               changes.
    new-round  IDEMPOTENT by construction: it syncs the ledger to the decided
               items, keyed by id, and a key already there is left untouched.

What `new-round` does and does NOT do is worth pinning, because the name reads
like it moves a counter. It does not: the round number lives in
`<meta name="consult-round">`, which `wrap-report.sh` derives from the contract
baseline on every wrap, and any verb that also wrote it would be a second
counter to disagree with the first. The spec-level work a round transition
needs is the LEDGER — "what earlier rounds settled, so a later round does not
re-ask it" (`04-block-vocabulary.md`) — so that is what this verb writes, one
row per decided item. `check_artifact.py` has the matching rule in the other
direction (`decided but still asked`: a ledger key naming an item that is still
open is a failure), so the pairing this verb produces is the one the contract
already wants.
"""

import argparse
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "dash"))

import check_artifact                                       # noqa: E402
import contract_defects                                     # noqa: E402
import md_body                                              # noqa: E402
import spec_build                                           # noqa: E402
import spec_parser                                          # noqa: E402
from spec_build import SpecBuildError                       # noqa: E402
from spec_parser import SpecSyntaxError                     # noqa: E402

# The ledger row separator, borrowed from the builder rather than re-spelled:
# `emit_ledger` splits a row on it, so a row this file writes with a different
# dash is a row the build then refuses.
SEP = spec_build.HINT_SEP


class VerbError(Exception):
    """A verb that refused. Nothing was written when this is raised.

    Deliberately NOT a subclass of `SpecSyntaxError` or `SpecBuildError`: those
    two say a SPEC is wrong and carry its line; this one says an EDIT is wrong
    and carries the id and the file the caller named. A caller that cannot tell
    them apart cannot tell "your spec is broken" from "your id is not in it".
    """


# --- reading the tree --------------------------------------------------------
def _split(text):
    """The spec's physical lines, the way `spec_parser.parse` counts them.

    `split("\\n")` leaves a trailing `""` for a text that ends in a newline;
    it is kept here (and dropped by `parse`) so that rejoining with `"\\n"`
    reproduces the input byte for byte, trailing newline or no trailing
    newline. Line N of the parser is `lines[N - 1]` either way.
    """
    return text.split("\n")


def _walk(nodes):
    for node in nodes:
        yield node
        for sub in _walk(node.children):
            yield sub


def _end_line(node):
    """The last physical line of `node`, 1-based and inclusive.

    For an authored fence that is its CLOSING `:::`, derived from the parser's
    own invariant rather than by re-scanning the text: inside a fence every line
    is a content line (folded into a prose child), a nested open fence, or the
    close — so the line after the last child's last line IS the close, and a
    fence with no children closes on the line after it opened.
    """
    if not node.authored:
        return node.line + len(node.raw_body) - 1
    last = node.line
    for child in node.children:
        last = _end_line(child)
    return last + 1


def _by_id(tree, ident):
    for node in _walk(tree):
        if node.id == ident:
            return node
    return None


def _ids_of(tree, block_type):
    return [n.id for n in _walk(tree) if n.block_type == block_type and n.id]


def _ledgers(tree):
    """Every `ledger` in the spec, innermost ones included."""
    return [n for n in _walk(tree) if n.block_type == "ledger"]


def _ledger_keys(ledger):
    """The KEY half of each row of `ledger` — the text before the hint
    separator, exactly the span `spec_build.emit_ledger` turns into `.k`."""
    out = []
    if ledger is None:
        return out
    for child in ledger.children:
        for ln in child.raw_body:
            if md_body.MARKER.match(ln):
                row = md_body.MARKER.sub("", ln, count=1).strip()
                out.append(row.partition(SEP)[0].strip())
    return out


def _ledger_ids(tree):
    """The ids the ledger NAMES, read the way the contract reads them.

    A key is a compound in the field — `c35 · T-265`, `c1 + c12` — so the id is
    a token inside the key and not the key itself; `check_artifact.ledger_ids`
    harvests it with `LEDGER_TOKEN`, and that constant is imported here rather
    than re-spelled so the two cannot drift. Whole-string equality is what made
    `new-round` append a second row next to a compound one, and what made
    `add-item` hand a ledger's own id to a new question.
    """
    out = set()
    for ledger in _ledgers(tree):
        for key in _ledger_keys(ledger):
            out.update(check_artifact.LEDGER_TOKEN.findall(key))
    return out


def _eol(lines):
    """`"\\r"` when the spec's own lines are CRLF-terminated, `""` otherwise.

    `_split` splits on `"\\n"` only, so a CRLF line keeps its `"\\r"` as its
    last byte. A verb that inserts bare-LF lines into such a spec has reflowed
    the file — the one thing property 3 says a verb never does — so every line a
    verb writes carries the terminator the file already used.
    """
    return "\r" if any(ln.endswith("\r") for ln in lines) else ""


def _terminated(block, eol):
    return [ln.rstrip("\r") + eol for ln in block] if eol else block


def _parse(text, where):
    try:
        return spec_parser.parse(text)
    except SpecSyntaxError as exc:
        raise VerbError("%s does not parse (line %d: %s) — fix the spec before "
                        "a verb can edit it" % (where, exc.line, exc.message))


def _quotable(value):
    """An attr value spelled for a fence line, escapes included.

    `spec_parser.quote_value` and nothing else: this file WRITES the syntax the
    tokenizer reads, and a second opinion here about which characters need a
    backslash is how the two stop agreeing. It used to REFUSE a value holding a
    double quote, because the grammar had no escape for one; it has had `\\"`
    since the corpus conversion (`03-spec-grammar.md` § Values and quoting), so
    a title the author really wrote now round-trips instead of being rejected.
    """
    return spec_parser.quote_value(value)


def _blankish(lines, index):
    """Is the 0-based line at `index` absent or blank?"""
    return index < 0 or index >= len(lines) or not lines[index].strip()


# --- the verbs, as pure text transforms --------------------------------------
def add_item(spec_text, group_id, item_id, title, body="", options=()):
    """A new `::: item` at the END of the group `#group_id`.

    REFUSES when `#item_id` is already used anywhere in the spec — by a BLOCK
    or by a LEDGER ROW, which are one keyspace and not two: `check_artifact.
    ledger_ids` reads a ledger key's tokens as item ids, so an id the ledger
    already owns is an id the page already answers to. Refusing rather than
    being idempotent. Two calls with the same id are two different questions
    (the second carries its own title and options) and ids are the paste key:
    keeping both would put one reply key on two questions, and overwriting the
    first would delete an item the reader may already have answered. Neither is
    an edit this verb may make on its own.

    The item lands last inside the group because that is the only position that
    does not renumber the reader's context: an item inserted above another does
    not change any id, but it does move every question the reader had already
    scrolled past.
    """
    tree = _parse(spec_text, "the spec")
    if not spec_parser.NAME.fullmatch(item_id):
        raise VerbError("%r is not a usable id — an id starts with a letter "
                        "and holds letters, digits, '-' and '_' only"
                        % item_id)
    masthead = next((n for n in tree if n.block_type == "masthead"), None)
    if masthead is not None and item_id in masthead.attrs.get(
            "dropped-ids", "").split():
        raise VerbError("%s was dropped in an earlier round; give the new item "
                        "a new id" % item_id)
    ledger_ids = _ledger_ids(tree)
    clash = _by_id(tree, item_id)
    if clash is not None:
        raise VerbError("id #%s is already used by the `%s` block at line %d — "
                        "ids are the reply's key and a page carries each one "
                        "once; pick another id, or use `decide` if you meant "
                        "that item" % (item_id, clash.block_type, clash.line))
    if item_id in ledger_ids:
        raise VerbError("id #%s is already used by a ledger row — the ledger "
                        "records it as SETTLED, so asking it again as a new "
                        "item is the `decided but still asked` failure the "
                        "contract names; pick another id, or drop the ledger "
                        "row if the question is genuinely reopening"
                        % item_id)
    group = None
    for node in _walk(tree):
        if node.block_type == "group" and node.id == group_id:
            group = node
            break
    if group is None:
        known = _ids_of(tree, "group")
        raise VerbError("no `group` with id #%s in the spec — the groups it "
                        "has are: %s" % (group_id,
                                         ", ".join("#" + i for i in known)
                                         or "(none)"))
    block = ['::: item {#%s title=%s}' % (item_id, _quotable(title))]
    body_lines = [ln for ln in body.split("\n")] if body else []
    while body_lines and not body_lines[-1].strip():
        body_lines.pop()
    block.extend(body_lines)
    if options:
        if body_lines:
            block.append("")
        for opt in options:
            block.append("- " + opt)
    block.append(":::")

    # The body is the caller's TEXT and it is spliced in as spec source, so it
    # can close the fence this function just opened: a body line of `:::` ends
    # the item and turns everything after it into a sibling block — ids and all,
    # past the clash check that already ran. Re-parsing the block ALONE is what
    # says so: the shape this verb promises is exactly one node, carrying
    # exactly the id it was given.
    try:
        sub = spec_parser.parse("\n".join(block) + "\n")
    except SpecSyntaxError as exc:
        raise VerbError("the --body for #%s is not usable spec text (line %d "
                        "of the block: %s) — a body is prose, options and nested blocks, and "
                        "its `:::` fences have to close"
                        % (item_id, exc.line, exc.message))
    if len(sub) != 1 or sub[0].id != item_id or sub[0].block_type != "item":
        raise VerbError("the --body for #%s closes the item's own fence — a "
                        "`:::` of its own at the start of a line ends the item "
                        "and makes everything after it a sibling block, which "
                        "is not an edit this verb may make; indent it, or open "
                        "the block with its own verb" % item_id)
    for nested in _walk(sub[0].children):
        if not nested.id:
            continue
        inner = _by_id(tree, nested.id)
        if (inner is not None or nested.id in ledger_ids
                or nested.id == item_id):
            raise VerbError("the --body for #%s carries a block with id #%s, "
                            "which the spec already uses — one id, one claim"
                            % (item_id, nested.id))

    lines = _split(spec_text)
    eol = _eol(lines)
    at = _end_line(group) - 1            # 0-based index of the group's close
    before_notes = next((c for c in group.children
                         if c.block_type == "notes"), None)
    if before_notes is not None:
        # The general-notes item is ALWAYS LAST (02-local-first-artifacts.md
        # §7.3: "the page-level notes item is additional, always last"). When it
        # lives inside the target group, the end of the group is behind it, so
        # the new item goes in front of it instead. `check_artifact.py` does not
        # check that ordering, which is exactly why it cannot be left to it.
        at = before_notes.line - 1
    if not _blankish(lines, at - 1):
        # One blank line between the previous content and the new fence: the
        # grammar does not require it (blank lines around a fence carry no
        # meaning) and a human reading the spec does.
        block.insert(0, "")
    if before_notes is not None and not _blankish(lines, at):
        block.append("")
    return "\n".join(lines[:at] + _terminated(block, eol) + lines[at:])


def decide(spec_text, item_id, verdict):
    """Record `#item_id`'s verdict as `decided="…"` on its fence.

    IDEMPOTENT for the same verdict: the spec comes back byte-identical and the
    caller still rebuilds, so running it twice is safe. A DIFFERENT verdict
    OVERWRITES rather than refusing — `owner-changed`, the reader revising an
    earlier answer, is one of the four labels a round's brief carries, and
    `wrap_report.stamp_decided_rounds` already handles it: a decided item whose
    verdict text changed loses the carried round and is stamped with this one.
    Refusing here would leave that documented case reachable only by hand-editing
    the spec, which is the route this whole module exists to remove.

    Only the ONE attr moves. The rest of the fence line — spacing, attr order,
    the way the title is quoted — is the author's and is copied through.
    """
    tree = _parse(spec_text, "the spec")
    node = _by_id(tree, item_id)
    if node is None:
        raise VerbError("no block with id #%s in the spec — the items it has "
                        "are: %s"
                        % (item_id,
                           ", ".join("#" + i for i in _ids_of(tree, "item"))
                           or "(none)"))
    if node.block_type != "item":
        raise VerbError("#%s is a `%s` block (line %d), not an `item` — only "
                        "an item carries a decision"
                        % (item_id, node.block_type, node.line))
    if not verdict.strip():
        raise VerbError("an empty verdict for #%s — pass the chosen option's "
                        "label, or the text that says what was decided"
                        % item_id)
    # On an item with options, `yes` makes the builder check the {recommended}
    # option: the author's advice, not what the reader chose. The verdict is
    # the chosen option's label (LOOP-006 review).
    if verdict.strip().lower() in contract_defects.NOT_A_VERDICT:
        try:
            offers = spec_build.has_options(node)
        except SpecBuildError as exc:
            raise VerbError("#%s cannot be read (line %d: %s)"
                            % (item_id, exc.line, exc.message))
        if offers:
            raise VerbError(
                "#%s has options, and %r would record its {recommended} option "
                "as the verdict whatever the reader chose — pass the chosen "
                "option's label as the verdict (e.g. --verdict \"<label>\")"
                % (item_id, verdict.strip()))

    try:
        chosen = spec_build.chosen_labels(node)
    except SpecBuildError as exc:
        raise VerbError("#%s cannot be read (line %d: %s)"
                        % (item_id, exc.line, exc.message))
    # Compared in the plain form the page's data-label carries (and the
    # reader's reply with it): `Use uv` is the option written `Use **uv**`.
    plain = [spec_build.PLAIN.sub("", c) for c in chosen]
    if chosen and (spec_build.PLAIN.sub("", verdict.strip())
                   not in plain + [", ".join(plain)]):
        raise VerbError(
            "#%s carries {chosen} on %s, so deciding %r would leave the page "
            "checking one option and naming another: move the {chosen} marker "
            "to the new winner first" % (item_id, ", ".join(map(repr, chosen)),
                                         verdict.strip()))
    # The same verdict in another spelling (`Dos` for a recorded `**Dos**`, or
    # back) is already recorded: rewriting it would break idempotence and reset
    # the round stamp, which compares the raw decided text.
    if (spec_build.PLAIN.sub("", node.attrs.get("decided", "").strip())
            == spec_build.PLAIN.sub("", verdict.strip())):
        return spec_text
    lines = _split(spec_text)
    if not _set_attr(lines, node, "decided", verdict):
        return spec_text
    return "\n".join(lines)


def _set_attr(lines, node, name, value):
    """Set `name=value` on `node`'s fence line, in place; False when unchanged."""
    i = node.line - 1
    line = lines[i]
    brace = line.find("{")
    if brace < 0:                        # `item` requires an #id; a masthead may not
        pad = "" if line.endswith(" ") else " "
        new = line + pad + "{%s=%s}" % (name, _quotable(value))
    else:
        spans = {}
        _, _, _, end = spec_parser._parse_attrs(node.line, line, brace, spans)
        if name in spans:
            lo, hi = spans[name]
            new = line[:lo] + "%s=%s" % (name, _quotable(value)) + line[hi:]
        else:
            close = end - 1              # the index of the closing '}'
            pad = "" if (close and line[close - 1] in " \t") else " "
            new = (line[:close] + pad + "%s=%s" % (name, _quotable(value))
                   + line[close:])
    if new == line:
        return False
    lines[i] = new
    return True


def new_round(spec_text, dropped=()):
    """`_sync_ledger`, then record `dropped` ids on the masthead (BL-533).

    `dropped` is the ids this round takes OFF the page: the author removed the
    blocks from the spec, and the id-stability check refuses a disappearing id
    unless the page declares it. Each must really be gone from the spec; one that
    stays takes `dropped="reason"` on its item instead. Recorded once, kept by
    later rounds. Not derived from the old page: a removal nobody declared is
    still the BL-396 failure, and the rebuild still refuses it.
    """
    text = _sync_ledger(spec_text)
    dropped = [i for i in (d.strip().lstrip("#") for d in dropped) if i]
    if not dropped:
        return text
    tree = _parse(text, "the spec")
    live = [i for i in dropped if _by_id(tree, i) is not None]
    if live:
        raise VerbError("--drop %s: still in the spec. A dropped id is one the "
                        "page no longer carries; an item that stays is marked "
                        "dropped=\"reason\" on its fence instead"
                        % ", ".join("#" + i for i in live))
    masthead = next((n for n in tree if n.block_type == "masthead"), None)
    if masthead is None:
        raise VerbError("the spec has no `masthead` to record the dropped ids on")
    have = masthead.attrs.get("dropped-ids", "").split()
    merged = have + [i for i in dict.fromkeys(dropped) if i not in have]
    lines = _split(text)
    if not _set_attr(lines, masthead, "dropped-ids", " ".join(merged)):
        return text
    return "\n".join(lines)


def _sync_ledger(spec_text):
    """Sync the ledger to the decided items: one row per decision, keyed by id.

    IDEMPOTENT by construction. A row whose key is already in the ledger is left
    exactly as it stands — including a row an author has since rewritten, which
    is the common case and the reason the key, not the text, is what is
    compared. A spec with nothing decided comes back unchanged; the caller still
    rebuilds, and the rebuild is what advances `consult-round` (see the module
    docstring: the round counter is the wrap's, not this verb's).

    The ledger is created after the masthead when the spec has none — that is
    where `references/02-local-first-artifacts.md` puts it ("before the first
    block: the header, a figure section, and the ledger").
    """
    tree = _parse(spec_text, "the spec")
    decided = [n for n in _walk(tree)
               if n.block_type == "item" and n.id
               and n.attrs.get("decided", "").strip()]

    ledgers = _ledgers(tree)
    if len(ledgers) > 1:
        raise VerbError("the spec carries %d `ledger` blocks (lines %s) — a "
                        "page records what earlier rounds settled in ONE, and "
                        "this verb will not guess which; merge them first"
                        % (len(ledgers),
                           ", ".join(str(n.line) for n in ledgers)))
    ledger = ledgers[0] if ledgers else None
    if ledger is not None and ledger not in tree:
        # A ledger nested inside a group is not the page's ledger: appending
        # settled rows there would drop them into the middle of the question
        # set, which is the one place `02-local-first-artifacts.md` says the
        # record must not be ("before the first block").
        raise VerbError("the only `ledger` in the spec is nested inside "
                        "another block (line %d) — the page's ledger sits at "
                        "the top level, before the first block; move it there "
                        "before syncing a round" % ledger.line)
    keys = _ledger_ids(tree)

    rows = []
    for node in decided:
        if node.id in keys:
            continue
        title = node.attrs.get("title", "").strip() or node.id
        verdict = node.attrs["decided"].strip()
        # `yes`/`true` is the plain "this is settled" mark and says nothing a
        # row should repeat; any other value is the verdict TEXT the author
        # wrote and belongs in the row beside the title.
        value = title if verdict in ("yes", "true") else "%s (%s)" % (title,
                                                                      verdict)
        rows.append("- %s%s%s" % (node.id, SEP, value))
    if not rows:
        return spec_text

    lines = _split(spec_text)
    eol = _eol(lines)
    if ledger is not None:
        at = _end_line(ledger) - 1       # before the ledger's close fence
        return "\n".join(lines[:at] + _terminated(rows, eol) + lines[at:])

    masthead = next((n for n in tree if n.block_type == "masthead"), None)
    at = _end_line(masthead) if masthead is not None else 0
    block = ["::: ledger"] + rows + [":::"]
    if not _blankish(lines, at - 1):
        block.insert(0, "")
    if not _blankish(lines, at):
        block.append("")
    return "\n".join(lines[:at] + _terminated(block, eol) + lines[at:])


# --- the file half: validate in memory, then write, then rebuild -------------
def default_out(spec_path):
    """The page a spec builds to: `x.spec.md` -> `x.html`."""
    base = os.path.basename(spec_path)
    stem = base[:-len(".spec.md")] if base.endswith(".spec.md") \
        else os.path.splitext(base)[0]
    if not stem:
        raise VerbError("cannot derive an output name from %r — pass --out"
                        % spec_path)
    return os.path.join(os.path.dirname(os.path.abspath(spec_path)),
                        stem + ".html")


def _write(path, text):
    """Replace `path` in one step. A verb that dies mid-write would leave the
    half-edited spec this module's whole refusal policy is against.

    Through `realpath` first: `os.replace` onto a SYMLINK replaces the link
    itself, so a spec symlinked into a page's folder would be silently forked
    into two files, the verb editing one and every later build reading the
    other. The edit belongs to the file the link names.

    An `OSError` here — a read-only directory, a full disk — is a refusal and
    not a crash: the read path is already wrapped, and an asymmetry between the
    two only means the write side reports with a traceback.
    """
    path = os.path.realpath(path)
    tmp = path + ".spec-verbs.tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)
    except OSError as exc:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise VerbError("cannot write %s: %s" % (path, exc))


def _trial_build(spec_path, new, out_name, lang):
    """Put the candidate spec through the WHOLE rebuild, into a throwaway dir.

    The candidate is written beside the real spec, because that directory is
    what `spec_build.main` passes as `base_dir`: a trial run from anywhere else
    would resolve the spec's figure paths against the wrong folder and refuse an
    edit that is fine. The PAGE goes to a temp dir, so the trial leaves neither
    the page nor the wrap's `.aidex-artifact-prev/` sidecar behind.

    Raises `VerbError` when the rebuild would not pass, naming the wrap's own
    output as the place the failure was printed.
    """
    spec_dir = os.path.dirname(os.path.abspath(spec_path))
    cand = os.path.join(spec_dir,
                        "." + os.path.basename(spec_path) + ".spec-verbs-trial")
    try:
        trial_dir = tempfile.mkdtemp(prefix="spec-verbs-trial-")
    except OSError as exc:
        raise VerbError("cannot make a temp dir for the trial build: %s" % exc)
    try:
        _write(cand, new)
        rc = spec_build.main([cand, "-o", os.path.join(trial_dir, out_name),
                              "--lang", lang])
    finally:
        for path in (cand, cand + ".spec-verbs.tmp"):
            try:
                os.unlink(path)
            except OSError:
                pass
        shutil.rmtree(trial_dir, ignore_errors=True)
    if rc != 0:
        raise VerbError(
            "the edit would leave %s unbuildable — a trial build of the result "
            "exited %d (the reason is printed above, by the same build and "
            "contract the rebuild runs). Nothing was written: a spec written "
            "here is a spec no verb could build again" % (spec_path, rc))


def apply_edit(spec_path, transform, out=None, lang="es"):
    """Run one transform over `spec_path`, then rebuild the page.

    The order is the contract: read, transform, VALIDATE with the REBUILD'S OWN
    gate (parse, build, the title the wrap needs, and then the wrap and
    `check_artifact.py` over a throwaway page in a temp dir), and only then
    write. Every refusal happens before the first byte is written, so a refused
    verb leaves the spec byte-identical.

    Validating with anything weaker than the rebuild is the one failure this
    function cannot report its way out of: the spec would be written, the
    rebuild would fail, and every later verb call would write and fail the same
    way, because each of them rebuilds too. The spec would be wedged with no
    verb able to recover it — a refusal the caller can act on turned into a file
    only a hand edit can save.

    The trial page is built in a temp dir, so the real page on disk is not
    touched either. What the trial cannot see is what the real output dir
    carries — a baseline the wrap compares against — so a rebuild can still fail
    after a green trial; the spec is then ROLLED BACK to the bytes it had and
    the failure is reported.

    Returns the output path. Raises `VerbError` for a refusal (nothing written)
    and `BuildFailed` for a rebuild that failed after a green trial (the spec is
    back to its previous bytes; the page is whatever the wrap left).
    """
    try:
        with open(spec_path, encoding="utf-8") as fh:
            old = fh.read()
    except OSError as exc:
        raise VerbError("cannot read the spec %s: %s" % (spec_path, exc))

    new = transform(old)
    base_dir = os.path.dirname(os.path.abspath(spec_path))
    out = out or default_out(spec_path)

    # The body is built for a page, because a gallery copies its captures
    # beside the page it goes into and refuses a body with none. The page is
    # named like the real one (the copies' folder is `<stem>-assets`) but sits
    # in a temp dir: a refusal here must leave nothing behind.
    def build_error(text):
        try:
            with tempfile.TemporaryDirectory(prefix="spec-verbs-check-") as tmp:
                spec_build.build(text, lang=lang, base_dir=base_dir,
                                 page=os.path.join(tmp, os.path.basename(out)))
        except (SpecSyntaxError, SpecBuildError) as exc:
            return exc
        return None

    exc = build_error(new)
    if exc is not None:
        # A spec that already fails on disk is not the edit's doing, and the
        # candidate's line numbers are shifted by whatever the verb inserted
        # (new-round's ledger rows): name the file's own line instead.
        before = build_error(old) if new != old else exc
        if before is not None:
            raise VerbError(
                "%s is unbuildable as it stands (line %d: %s) — the verb did "
                "not cause this; fix that line, then run it again — nothing "
                "was written" % (spec_path, before.line, before.message))
        raise VerbError(
            "the edit would leave %s unbuildable (line %d: %s) — nothing was "
            "written" % (spec_path, exc.line, exc.message))
    title = spec_build.page_title(new)
    if not title:
        raise VerbError(
            "%s has no masthead title, so the page it builds has no <title> — "
            "nothing was written" % spec_path)

    if os.path.abspath(out) == os.path.abspath(spec_path):
        raise VerbError("--out %s is the spec itself" % out)

    if new != old:
        _trial_build(spec_path, new, os.path.basename(out), lang)
        _write(spec_path, new)
    # The page is produced HERE and only here, by the same CLI a hand build
    # runs: `build()` for the body, `wrap-report.sh` for the envelope, the kit
    # and the build stamp. No verb writes HTML.
    rc, findings = _rebuild_capturing_findings(spec_path, out, lang)
    if rc != 0:
        rolled = ""
        if new != old:
            _write(spec_path, old)
            rolled = " and %s was rolled back to the bytes it had" % spec_path
        raise BuildFailed(
            "rebuilding %s exited %d (the trial build of the same spec "
            "passed, so the difference is in the output folder — a baseline, "
            "a sibling file); the page on disk is the previous one%s%s"
            % (out, rc, rolled, findings))
    return out


def _rebuild_capturing_findings(spec_path, out, lang):
    """(rc, text): spec_build.main with fds 1-2 captured (the wrap's subprocess
    writes the FAIL lines there), replayed to stderr, and the FAIL lines of
    the output-folder checks returned for the BuildFailed message."""
    import tempfile
    sys.stdout.flush()
    sys.stderr.flush()
    saved = (os.dup(1), os.dup(2))
    with tempfile.TemporaryFile() as tmp:
        os.dup2(tmp.fileno(), 1)
        os.dup2(tmp.fileno(), 2)
        try:
            rc = spec_build.main([spec_path, "-o", out, "--lang", lang])
        finally:
            sys.stdout.flush()
            sys.stderr.flush()
            os.dup2(saved[0], 1)
            os.dup2(saved[1], 2)
            os.close(saved[0])
            os.close(saved[1])
        tmp.seek(0)
        err = tmp.read().decode("utf-8", "replace")
    sys.stderr.write(err)
    fails = [l.strip() for l in err.splitlines()
             if "FAIL [consult-decided-trace]" in l
             or "FAIL [consult-spec-items]" in l]
    return rc, ("; failing check: " + " | ".join(fails)) if fails else ""


class BuildFailed(Exception):
    """The trial build passed and the real rebuild did not — the difference is
    in the output folder, not in the spec. The spec has been rolled back to the
    bytes it had; the page is whatever the wrap left."""


def add_item_file(spec_path, group_id, item_id, title, body="", options=(),
                  out=None, lang="es"):
    return apply_edit(spec_path,
                      lambda text: add_item(text, group_id, item_id, title,
                                            body, options),
                      out=out, lang=lang)


def decide_file(spec_path, item_id, verdict, out=None, lang="es"):
    return decide_many_file(spec_path, [(item_id, verdict)], out=out, lang=lang)


def decide_many_file(spec_path, pairs, out=None, lang="es"):
    """Record several `(id, verdict)` pairs, then rebuild ONCE: one reader reply
    that decides N items is one round, not N (BL-497). One refused pair refuses
    the whole call, nothing written."""
    def transform(text):
        for item_id, verdict in pairs:
            text = decide(text, item_id, verdict)
        return text
    return apply_edit(spec_path, transform, out=out, lang=lang)


def new_round_file(spec_path, out=None, lang="es", dropped=()):
    return apply_edit(spec_path, lambda text: new_round(text, dropped),
                      out=out, lang=lang)


# --- CLI ---------------------------------------------------------------------
def main(argv):
    p = argparse.ArgumentParser(
        prog="spec_verbs.py",
        description="Edit a page SPEC and rebuild its page. The verbs never "
                    "touch the built HTML.")
    subs = p.add_subparsers(dest="verb", metavar="<verb>")

    def common(sp):
        sp.add_argument("spec", metavar="<spec.md>")
        sp.add_argument("--out", metavar="<page.html>",
                        help="the page to rebuild (default: the spec's name "
                             "with .html)")
        sp.add_argument("--lang", default="es", choices=spec_build.LANGS)
        return sp

    a = common(subs.add_parser("add-item", help="add an item to a group"))
    a.add_argument("--group", required=True, metavar="<#id>")
    a.add_argument("--id", required=True, dest="ident", metavar="<#id>")
    a.add_argument("--title", required=True)
    a.add_argument("--body", default="", help="the question and its evidence")
    a.add_argument("--option", action="append", default=[], dest="options",
                   help="one option line; repeat it")

    d = common(subs.add_parser("decide", help="record an item's verdict"))
    d.add_argument("--id", required=True, action="append", dest="ident",
                   metavar="<#id>", help="repeat --id/--verdict to record "
                   "several items from one reply; the page rebuilds once")
    d.add_argument("--verdict", required=True, action="append",
                   help="the chosen option's label, or the text that says "
                        "what was decided. `yes` is refused on an item with "
                        "options (it would record the recommended option, not "
                        "the reader's) and fails the build on one without")

    n = common(subs.add_parser(
        "new-round", help="sync the ledger to the decided items and rebuild"))
    n.add_argument("--drop", action="append", default=[], dest="dropped",
                   metavar="<#id>", help="an item this round removed from the "
                   "spec; its id is recorded on the masthead so the page may "
                   "lose it (repeat for several)")

    args = p.parse_args(argv)
    if not args.verb:
        p.print_help(sys.stderr)
        return 2

    try:
        if args.verb == "add-item":
            out = add_item_file(args.spec, args.group.lstrip("#"),
                                args.ident.lstrip("#"), args.title, args.body,
                                args.options, out=args.out, lang=args.lang)
        elif args.verb == "decide":
            idents = [i.lstrip("#") for i in args.ident]
            if len(set(idents)) != len(idents):
                p.error("decide repeats an --id: one verdict per item per call")
            if len(idents) != len(args.verdict):
                p.error("decide needs one --verdict per --id (got %d and %d)"
                        % (len(idents), len(args.verdict)))
            out = decide_many_file(
                args.spec, list(zip(idents, args.verdict)),
                out=args.out, lang=args.lang)
        else:
            out = new_round_file(args.spec, out=args.out, lang=args.lang,
                                 dropped=[i.lstrip("#") for i in args.dropped])
    except VerbError as exc:
        sys.stderr.write("spec-verbs %s: %s\n" % (args.verb, exc))
        return 1
    except BuildFailed as exc:
        sys.stderr.write("spec-verbs %s: %s\n" % (args.verb, exc))
        return 1
    sys.stdout.write("%s\n" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
