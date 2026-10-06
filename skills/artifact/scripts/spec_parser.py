#!/usr/bin/env python3
"""spec_parser.py — the page-spec tokenizer: `:::` fences and `{...}` attrs.

It implements `references/03-spec-grammar.md` and nothing else. That file is the
contract; a disagreement between the two is a bug HERE, not a licence to
re-derive a grammar from the prior art.

TWO LAYERS, and this is the first one. The tokenizer knows SHAPE only — where a
fence opens, where it closes, how the attrs inside `{}` are spelled. It knows
nothing about `item`, `masthead` or `chart`: an unknown-but-well-formed block
type, an unknown attr key and a missing required attr all tokenize cleanly and
are the BUILDER's to refuse (`spec_build.py`). Folding the vocabulary in here
would turn "`chrt` is not a block type — did you mean `chart`?" into "unexpected
token at line 42".

The only error surface is `SpecSyntaxError`, and it always carries the 1-based
line number of the offending line. Nothing is guessed, nothing is repaired, and
no malformed block is ever swallowed into raw HTML passthrough — that silent
fallback is the failure mode decision d1 of the plan exists to prevent.

`md_body.FENCE` is IMPORTED rather than re-spelled. The grammar says a ``` code
fence is tracked "with the same marker rule md_body.py already uses", and two
copies of a regex that must agree is how they stop agreeing.
"""

import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "dash"))
import md_body  # noqa: E402

# The code-fence marker rule, borrowed whole. See the module docstring.
CODE_FENCE = md_body.FENCE

# A close fence: three or more colons and nothing else. Classified FIRST, so a
# bare `:::` is never read as an open fence with an empty type.
CLOSE = re.compile(r"^:::+[ \t]*$")
# An open fence ATTEMPT: colons at column 0 followed by at least one space or
# tab. What follows is then parsed and may still be malformed — the attempt is
# what commits the line to being markup. `:::item` (no space) is content, and so
# is any line whose colons are indented.
OPEN = re.compile(r"^(:{3,})[ \t]+(.*)$")
# Lowercase ASCII, digits, single hyphens, no trailing hyphen.
TYPE = re.compile(r"^[a-z](?:[a-z0-9]|-(?=[a-z0-9]))*$")
NAME = re.compile(r"[A-Za-z][A-Za-z0-9_-]*")
KEY = re.compile(r"[a-z][a-z0-9-]*")
# An unquoted value: anything but whitespace, quotes and braces.
BARE = re.compile(r"[^\s\"'{}]+")


class SpecSyntaxError(Exception):
    """A malformed spec. `line` is 1-based and counts physical lines."""

    def __init__(self, line, message):
        self.line = line
        self.message = message
        super().__init__("line %d: %s" % (line, message))


class BlockNode:
    """One node of the spec tree.

    `block_type` is the fence's type, or `"prose"` for a run of content lines
    outside any fence — the fence-less default `04-block-vocabulary.md` lists as
    the type every other one is an exception to.

    A prose node carries `raw_body` (its lines, verbatim, unescaped) and no
    children. A fence node carries `children` and an empty `raw_body`: its prose
    runs are prose children, in written order, so a block that mixes prose and
    nested fences keeps the order it was written in.

    Attrs are split the way they are written: `attrs` holds the `key="value"`
    pairs only, `classes` the `.class` list in written order, `id` the single
    `#id` or None. Values are always strings — `n=3` is `"3"`, and any coercion
    is the builder's, per block type.

    `authored` says whether a `:::` fence was WRITTEN for this node. It matters
    for exactly one type: `prose` is both the fence-less default and a spellable
    fence name, and the two are different things — `::: prose` is a fence whose
    body lives in a prose CHILD, so a builder that treats it as an implicit
    prose run reads `text` off the wrong node and drops the body without a word.
    04-block-vocabulary.md says `prose` is "Not a fence."; this flag is what
    lets the builder say so instead of silently agreeing.
    """

    __slots__ = ("line", "block_type", "attrs", "classes", "id", "children",
                 "raw_body", "authored")

    def __init__(self, line, block_type, attrs=None, classes=None, ident=None,
                 authored=False):
        self.line = line
        self.block_type = block_type
        self.authored = authored
        self.attrs = attrs if attrs is not None else {}
        self.classes = classes if classes is not None else []
        self.id = ident
        self.children = []
        self.raw_body = []

    @property
    def text(self):
        """A prose node's lines as one string."""
        return "\n".join(self.raw_body)

    def __repr__(self):
        return "BlockNode(%d, %r, attrs=%r, classes=%r, id=%r, %d children)" % (
            self.line, self.block_type, self.attrs, self.classes, self.id,
            len(self.children))


def _scan_quoted(open_at, s):
    """A double-quoted attr value starting at the `"` at `s[open_at]`.

    Returns `(index_of_closing_quote, value)`, or `(-1, "")` when the value is
    never closed. `\\"` and `\\\\` are the two escapes; a backslash before
    anything else is a backslash, exactly as `md_body._inline` reads one a
    layer down, so `title="a\\_b"` still hands `a\\_b` to that renderer and its
    own escape decides.

    The escape exists because the grammar's "a value cannot contain a '\"'"
    made one sampled page unconvertible: `dynamic_sites_ws`'s 2026-09-03 close
    report writes a `group` heading with a straight quote in it, and a heading
    is VISIBLE text. The only other ways out were changing the author's
    characters (a typographic `”` the author did not write) or leaving the page
    out of the sample — the two outcomes this module's "degrade, never drop"
    rule exists to refuse.
    """
    i = open_at + 1
    n = len(s)
    buf = []
    while i < n:
        c = s[i]
        if c == "\\" and i + 1 < n and s[i + 1] in '\\"':
            buf.append(s[i + 1])
            i += 2
            continue
        if c == '"':
            return i, "".join(buf)
        buf.append(c)
        i += 1
    return -1, ""


def quote_value(value):
    """`value` spelled as a quoted attr value — the inverse of `_scan_quoted`.

    The one writer of attr syntax, so that `spec_verbs.py` (which rewrites a
    fence line in place) and the tokenizer cannot disagree about which
    characters need a backslash. Order matters: backslashes first, or the one
    this adds before a quote gets doubled by the next pass.
    """
    return '"%s"' % value.replace("\\", "\\\\").replace('"', '\\"')


def _parse_attrs(line_no, s, start, spans=None):
    """Parse `{...}` beginning at `s[start] == '{'`.

    Returns `(classes, ident, attrs, end)` where `end` is the index just past
    the closing brace. Raises on every malformed shape the grammar's table
    names.

    `spans`, when a dict is passed, is filled with `key -> (start, end)`: the
    half-open slice of `s` that holds the whole `key="value"` item. It exists
    for `spec_verbs.py`, which rewrites ONE attr of a fence line and must leave
    every other byte of that line — the author's spacing, order and quoting —
    exactly where it was. The alternative was a second attr scanner over the
    same syntax, and two scanners that must agree about where a quoted value
    ends is how they stop agreeing. Nothing here reads it; it is write-only.
    """
    i = start + 1
    classes, ident, attrs = [], None, {}
    n = len(s)
    while True:
        while i < n and s[i] in " \t":
            i += 1
        if i >= n:
            raise SpecSyntaxError(
                line_no, "the attr group opened with '{' is never closed")
        if s[i] == "}":
            return classes, ident, attrs, i + 1
        if s[i] == ".":
            m = NAME.match(s, i + 1)
            if not m or (m.end() < n and s[m.end()] not in " \t}"):
                raise SpecSyntaxError(
                    line_no,
                    "a class is `.name`, where name starts with a letter and "
                    "holds letters, digits, '-' and '_' only")
            classes.append(m.group(0))
            i = m.end()
            continue
        if s[i] == "#":
            m = NAME.match(s, i + 1)
            if not m or (m.end() < n and s[m.end()] not in " \t}"):
                raise SpecSyntaxError(
                    line_no,
                    "an id is `#name`, where name starts with a letter and "
                    "holds letters, digits, '-' and '_' only — it becomes an "
                    "HTML id, a data-id and the rail's anchor")
            if ident is not None:
                raise SpecSyntaxError(
                    line_no,
                    "a second #id on one fence (#%s after #%s) — a block has "
                    "exactly one id" % (m.group(0), ident))
            ident = m.group(0)
            i = m.end()
            continue
        km = KEY.match(s, i)
        if not km or km.end() >= n or s[km.end()] != "=":
            # Covers `{big}` (a bare flag: this grammar has none) and the token
            # left over by an unquoted value someone wrote with a space in it.
            #
            # `.split()` is Unicode-aware and the skip loop above is not, so a
            # run of non-ASCII whitespace (a pasted NBSP, `\x0b`, `\x0c`) is a
            # token to one and nothing to the other: `.split()[0]` then raised a
            # bare IndexError out of `parse()`, past both CLIs, and the author
            # got a traceback with no line number at all — the one error surface
            # this module promises is `SpecSyntaxError`. The rest of the group
            # IS the offending item when no token can be cut out of it.
            rest = s[i:].split("}")[0]
            tokens = rest.split()
            bad = tokens[0] if tokens else rest
            raise SpecSyntaxError(
                line_no,
                "attr item %r is none of `.class`, `#id` or `key=\"value\"` — "
                "there are no bare flags, and a value with a space in it must "
                "be quoted" % bad)
        key = km.group(0)
        if key in attrs:
            raise SpecSyntaxError(
                line_no, "attr key %r appears twice on one fence" % key)
        j = km.end() + 1
        if j < n and s[j] == '"':
            end, value = _scan_quoted(j, s)
            if end < 0:
                raise SpecSyntaxError(
                    line_no,
                    "the quoted value of %r is never closed — double quotes "
                    "only, and the two escapes inside one are `\\\"` for a "
                    "double quote and `\\\\` for a backslash" % key)
            attrs[key] = value
            i = end + 1
            if spans is not None:
                spans[key] = (km.start(), i)
            if i < n and s[i] not in " \t}":
                raise SpecSyntaxError(
                    line_no,
                    "text runs straight on after the quoted value of %r — "
                    "attr items are separated by whitespace" % key)
            continue
        if j < n and s[j] == "'":
            raise SpecSyntaxError(
                line_no,
                "the value of %r is single-quoted — double quotes are the only "
                "quoting there is (write `\\\"` for a quote inside one), and a "
                "\"'\" cannot appear in an unquoted value either" % key)
        vm = BARE.match(s, j)
        if not vm:
            raise SpecSyntaxError(
                line_no,
                "`%s=` has no value — write `%s=\"\"` for an empty one"
                % (key, key))
        attrs[key] = vm.group(0)
        i = vm.end()
        if spans is not None:
            spans[key] = (km.start(), i)


def _parse_open(line_no, rest):
    """The block type and attrs of an open fence, from the text after the
    colons. `rest` is already right-stripped."""
    if not rest:
        # Unreachable through `parse` (a colons-only line is a close fence), but
        # a direct caller must not get a silent empty type.
        raise SpecSyntaxError(line_no, "an open fence needs a block type")
    head = rest.split(None, 1)
    type_tok = head[0]
    if type_tok.startswith("{"):
        raise SpecSyntaxError(
            line_no,
            "an open fence needs a block type before its attrs — this grammar "
            "has no untyped `::: {.class}` div, because an untyped block has "
            "nothing to build")
    if not TYPE.match(type_tok):
        raise SpecSyntaxError(
            line_no,
            "block type %r is not `[a-z][a-z0-9-]*` — lowercase ASCII, digits "
            "and single hyphens, no trailing hyphen" % type_tok)
    tail = head[1].strip() if len(head) > 1 else ""
    if not tail:
        return type_tok, [], None, {}
    if not tail.startswith("{"):
        raise SpecSyntaxError(
            line_no,
            "expected `{` after the block type, got %r — an attr group is "
            "curly-braced, and nothing else may follow the type" % tail)
    classes, ident, attrs, end = _parse_attrs(line_no, tail, 0)
    if tail[end:].strip():
        raise SpecSyntaxError(
            line_no,
            "text after the attr group (%r) — nothing may follow the closing "
            "'}' but whitespace" % tail[end:].strip())
    return type_tok, classes, ident, attrs


# How deep fences may nest. The parser itself is iterative, but the builder and
# the verbs walk the tree recursively and hit Python's recursion limit at about
# 500 levels (a RecursionError traceback, LOOP-008 D2). Real pages nest 3-4 deep.
MAX_DEPTH = 100


def parse(spec_text):
    """The spec as a list of top-level `BlockNode`s.

    Content lines are gathered into `prose` nodes: consecutive lines, blank
    lines included, form ONE prose block, and a prose block ends at the next
    open fence, the next close fence, or end of file. The same rule applies
    inside a fence.
    """
    lines = [ln[:-1] if ln.endswith("\r") else ln
             for ln in spec_text.split("\n")]
    # `split("\n")` on a text ending in a newline yields a trailing "" that is
    # not a physical line. Dropping it keeps a trailing blank out of the last
    # prose block and keeps the line numbers honest.
    if lines and lines[-1] == "":
        lines.pop()

    doc = []
    stack = []          # [(BlockNode, opening line_no)]
    prose = None        # the prose node currently being filled, or None
    code_marker = None  # the open ``` / ~~~ marker, or None
    code_open = None    # its opening line, which the closer is measured against
    code_line = 0

    def body():
        return stack[-1][0].children if stack else doc

    def flush():
        nonlocal prose
        prose = None

    for n, raw in enumerate(lines, 1):
        cm = CODE_FENCE.match(raw)
        if code_marker is not None:
            # Inside a code fence every line is literal content, `:::` included.
            # That is what lets a spec document this grammar, or paste a shell
            # run that echoes `:::`, without the example opening a block.
            if md_body.fence_closes(raw, code_open):
                code_marker = None
            if prose is None:
                prose = BlockNode(n, "prose")
                body().append(prose)
            prose.raw_body.append(raw)
            continue
        if cm:
            code_marker, code_open, code_line = cm.group(1), raw, n
            if prose is None:
                prose = BlockNode(n, "prose")
                body().append(prose)
            prose.raw_body.append(raw)
            continue
        if CLOSE.match(raw):
            if not stack:
                raise SpecSyntaxError(
                    n, "close fence with no block open")
            stack.pop()
            flush()
            continue
        m = OPEN.match(raw)
        if m:
            block_type, classes, ident, attrs = _parse_open(n, m.group(2).rstrip())
            if len(stack) >= MAX_DEPTH:
                raise SpecSyntaxError(
                    n, "this `%s` opens at depth %d — fences nest at most %d "
                    "deep; close the blocks above it before opening another"
                    % (block_type, len(stack) + 1, MAX_DEPTH))
            node = BlockNode(n, block_type, attrs, classes, ident,
                             authored=True)
            body().append(node)
            stack.append((node, n))
            flush()
            continue
        if prose is None:
            prose = BlockNode(n, "prose")
            body().append(prose)
        prose.raw_body.append(raw)

    if stack:
        node, opened = stack[-1]
        extra = ""
        if code_marker is not None:
            # The one place the two fence rules meet. A code fence left open at
            # EOF "takes the rest of its enclosing block as code" and is not an
            # error on its own — but it also swallowed every `:::` after it,
            # including the one meant to close this block. Naming it is the
            # difference between a fixable message and a mystery about a fence
            # the author can see is there.
            extra = (" (the `%s` code fence opened at line %d is still open, "
                     "so every `:::` after it was read as code)"
                     % (code_marker, code_line))
        raise SpecSyntaxError(
            opened,
            "block '%s' opened here is never closed%s" % (node.block_type, extra))
    return doc


def _main(argv):
    """Parse a spec and print its tree — a debugging entry, not an API."""
    if len(argv) != 1:
        sys.stderr.write("usage: spec_parser.py <spec.md>\n")
        return 2
    with open(argv[0], encoding="utf-8") as fh:
        text = fh.read()
    try:
        tree = parse(text)
    except SpecSyntaxError as exc:
        sys.stderr.write("%s: %s\n" % (argv[0], exc))
        return 1

    def show(nodes, depth):
        for nd in nodes:
            sys.stdout.write("%s%s\n" % ("  " * depth, nd))
            show(nd.children, depth + 1)

    show(tree, 0)
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
