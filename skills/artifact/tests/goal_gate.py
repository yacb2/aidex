#!/usr/bin/env python3
"""The goal's own gate. Seven lines, always, in one fixed order.

`goal-gate.sh` is the entry point; this is its body. Read that file's header
for what the gate is FOR; this one is how each number is taken.

    corpus:     N/30   converted pages whose build matches the original page
    escapes:    N      converted pages that needed an escape hatch
    blind:      N/3    Phase 5's blind trial, counted from the corpus's
                       blind-trial-log.md; informative, and 0/3 with a reason
                       when the log is malformed or truncated
    figures:    C/45   figures carried on the rung the corpus's
                       figure-census.md assigns them, re-derived against the
                       pages and the specs; `0/unknown` with a reason when
                       that census is malformed or does not cover the sample
    newly-fail: N      pages whose original passes the contract and whose
                       build does not; `unknown` under --no-contract
    ladder:     r1 A · r2 B · r3 C   figures ASSIGNED to each rung (informative)
    baseline:   A -> B what a page cost to write, before and after

Exit status: non-zero when `corpus` or `escapes` REGRESS, when a converted
page stops matching its original, when a figure is not carried on its rung,
or when `newly-fail` is not 0 (or not measured). The floor `corpus` and
`escapes` regress from is `GATE-FLOOR.json`, kept beside the specs and advanced
by hand. The gate does not write its own floor: a gate that records its own
high-water mark has no memory of a regression, only of the last run.
`figures` and `newly-fail` need no floor: their target is completion.

Exit 2, with nothing on stdout, when `AIDEX_SPEC_CORPUS` is unset or names a
directory that lacks any corpus file (a missing blind log or census included):
the corpus is built from private pages and lives outside this repo, and a gate
that ran without it would print counts that measured nothing.
"""

import hashlib
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(SKILL, "scripts"))

sys.path.insert(0, os.path.join(SKILL, "scripts", "dash"))

import chart_svg                                          # noqa: E402
import check_artifact                                     # noqa: E402
import corpus_diff                                        # noqa: E402
import diagram_layout                                     # noqa: E402
import figure_extract                                     # noqa: E402
import spec_build                                         # noqa: E402
import graph_svg                                          # noqa: E402
import spec_parser                                        # noqa: E402

# The corpus is built from the owner's private pages, so it does not ship with
# this repo: it lives wherever `AIDEX_SPEC_CORPUS` points (an absolute dir), and
# every path the gate reads is derived from it. Unset, the paths are empty and
# `main` refuses to run — see `corpus_missing`.
CORPUS_ENV = "AIDEX_SPEC_CORPUS"
CORPUS = os.environ.get(CORPUS_ENV, "")


def _in_corpus(*parts):
    return os.path.join(CORPUS, *parts) if CORPUS else ""


SAMPLE = _in_corpus("corpus-sample.json")
BASELINE = _in_corpus("baseline.json")
SPECS = _in_corpus("corpus-specs")
FLOOR = _in_corpus("corpus-specs", "GATE-FLOOR.json")
BLIND_LOG = _in_corpus("blind-trial-log.md")
FIGURE_CENSUS = _in_corpus("figure-census.md")
BUILD = os.path.join(SKILL, "scripts", "spec_build.py")


# --- the naming rule ---------------------------------------------------------
def spec_name(entry_path):
    """`<project>/…/<page>.html` -> `<project>__<page>.spec.md`.

    The project prefix is not decoration: two of the sampled projects each
    carry a `2026-08-18-backlog-triage.html`-shaped name, and a basename-only
    rule would have had them share one spec. `check_names()` re-derives the
    whole set on every run so a future sample cannot collide in silence.
    """
    project = entry_path.split("/", 1)[0]
    page = os.path.basename(entry_path)
    return "%s__%s" % (project, page[:-len(".html")] + ".spec.md")


def check_names(pages):
    seen = {}
    for entry in pages:
        name = spec_name(entry["path"])
        if name in seen:
            raise SystemExit(
                "goal-gate: %r and %r map to the same spec name %r — the "
                "naming rule cannot address this sample"
                % (seen[name], entry["path"], name))
        seen[name] = entry["path"]


# --- escapes -----------------------------------------------------------------
# An ESCAPE is a converted page that needed something OUTSIDE the grammar to
# come out right. Three detectors, and they are the whole definition:
#
#   1. a fence whose type is an escape hatch (`html`, `raw`, `passthrough`,
#      `embed`). None is registered today, so this also guards against one
#      being added quietly later;
#   2. a PASSTHROUGH: a `<tag …>` written in the spec that reaches the built
#      page as markup instead of as the characters the author typed. Checked by
#      building the page and looking for the tag together with the text that
#      follows it, so a tag the BUILDER emits (every page has real `<p>`s) is
#      never mistaken for one the author smuggled in.
#
#      An earlier version of this detector flagged the mere PRESENCE of a tag
#      in a spec line. It fired on three of the six pilot pages and every one
#      was a false positive: `` `<style>` ``, `` `issue/<NNN>` `` and a Vue
#      template quoted as evidence are all literal text, `md_body` escapes
#      them, and the text diff proves they arrive intact. A count that rises
#      because a page talks ABOUT html is a count nobody can act on;
#   3. a hand-edit of built output, or a block the grammar could not express.
#      Both land as a file beside the spec: any `.html` in `corpus-specs/` is
#      built output someone kept and edited (the gate builds into a temp dir
#      and keeps nothing), and a `<name>.escape.md` is the converter writing
#      down, by name, what they could not say.
#
# Why this definition and not "pages I felt were awkward": every one of the
# three is a FILE or a LINE, so the count is reproducible by anyone and cannot
# drift with who is running it. And detector 3 is the one that matters: the
# plan's claim is that `escapes` reaches 0, and the only honest way to reach 0
# is for a converter to have nowhere to hide a page that did not fit. A page
# the grammar cannot express is a grammar gap to close, never a page to leave
# out of the sample — so the sidecar exists to be COUNTED, not to be tolerated.
ESCAPE_TYPES = ("html", "raw", "passthrough", "embed")
HTML_TAG = re.compile(r"</?[a-zA-Z][a-zA-Z0-9]*(?:\s[^<>]*)?/?>")
FENCE = re.compile(r"^\s*(```|~~~)")
# How much of the text AFTER a tag has to travel with it for a match to mean
# passthrough rather than coincidence. Short enough that a tag at the end of a
# line still matches, long enough that `<p>` alone never does.
TAIL = 12


def escapes_in(spec_path):
    """The reasons this page counts as an escape. Empty list = none."""
    why = []
    if os.path.exists(spec_path[:-len(".spec.md")] + ".html"):
        why.append("built output kept beside the spec (a hand-edit)")
    sidecar = spec_path[:-len(".spec.md")] + ".escape.md"
    if os.path.exists(sidecar):
        why.append("an `.escape.md` sidecar: %s"
                   % open(sidecar, encoding="utf-8").readline().strip())
    with open(spec_path, encoding="utf-8") as fh:
        spec = fh.read()

    candidates, fence = [], None
    for n, line in enumerate(spec.split("\n"), 1):
        m = FENCE.match(line)
        if fence is not None:
            if m and m.group(1) == fence:
                fence = None
            continue
        if m:
            fence = m.group(1)
            continue
        if line.startswith(":::"):
            parts = line.lstrip(":").split()
            if parts and parts[0] in ESCAPE_TYPES:
                why.append("line %d opens a `%s` escape-hatch block"
                           % (n, parts[0]))
            continue
        for hit in HTML_TAG.finditer(line):
            candidates.append((n, line[hit.start():hit.end() + TAIL]))

    if candidates:
        try:
            body = corpus_diff.build_body(spec_path)
        except Exception:
            body = ""
        for n, needle in candidates:
            if needle in body:
                why.append("line %d passes `%s` through as markup"
                           % (n, needle.split(">")[0] + ">"))
    return why


# --- the blind trial (Phase 5) ------------------------------------------------
# `blind:` used to be a stub. It is now read from the corpus's
# `blind-trial-log.md`, and the whole design of this parser is one requirement: a log that is
# malformed, truncated, half-written or absent must NOT be able to report 3/3.
# A loose word count cannot promise that — `grep -c pass` on a file whose second
# half was lost still counts whatever survived, and counts the prose too. So the
# log carries a MACHINE BLOCK: a declared record count, a fenced list, and one
# fixed-order line per run. Every deviation raises, and a raise prints 0/3 with
# the reason on stderr. The three ways a log can lie are each closed:
#
#   truncated  — the closing fence is gone, or fewer records than `runs=` says;
#   padded     — more records than `runs=` says, or two records for one run id;
#   reworded   — a field missing, out of order, or holding an unknown value.
#
# `runs=` must itself be EXPECTED_RUNS: a log that lowers its own denominator to
# match what it has is the same lie in the other direction.
EXPECTED_RUNS = 3
VERDICT_HEADER = re.compile(
    r'^<!-- BLIND-TRIAL-VERDICTS v(\d+) runs=(\d+) -->$', re.M)
VERDICT_LINE = re.compile(
    r'^run=(?P<run>[A-Za-z0-9_-]+) '
    r'spec=(?P<spec>\S+) '
    r'verb=(?P<verb>\S+) '
    r'build1=(?P<build1>\S+) '
    r'build2=(?P<build2>\S+) '
    r'handwritten-html=(?P<html>\S+) '
    r'verdict=(?P<verdict>\S+)$')


class BlindLogError(Exception):
    """The log cannot be read as a record of three runs."""


def blind_records(path=None):
    """The machine block's records, or raise. Never returns a partial list.

    `path` defaults to `BLIND_LOG` at CALL time, not at definition time, so a
    test can point the whole gate at another log by setting the module
    attribute — the end-to-end "a malformed log does not read 3/3" case.
    """
    path = path or BLIND_LOG
    if not os.path.exists(path):
        raise BlindLogError("no %s" % os.path.basename(path))
    with open(path, encoding="utf-8") as fh:
        text = fh.read()

    heads = VERDICT_HEADER.findall(text)
    if len(heads) != 1:
        raise BlindLogError(
            "%d BLIND-TRIAL-VERDICTS header(s), want exactly 1" % len(heads))
    version, declared = heads[0][0], int(heads[0][1])
    if version != "1":
        raise BlindLogError("unknown verdict-block version v%s" % version)
    if declared != EXPECTED_RUNS:
        raise BlindLogError("header declares runs=%d, the trial is %d runs"
                            % (declared, EXPECTED_RUNS))

    after = text[VERDICT_HEADER.search(text).end():]
    lines = after.split("\n")
    # The fence must OPEN on the first non-blank line after the header: a block
    # that drifted away from its header is a block that may not be its header's.
    i = 0
    while i < len(lines) and not lines[i].strip():
        i += 1
    if i >= len(lines) or lines[i].strip() != "```verdicts":
        raise BlindLogError("no ```verdicts fence right after the header")
    body, closed = [], False
    for line in lines[i + 1:]:
        if line.strip() == "```":
            closed = True
            break
        body.append(line)
    if not closed:
        raise BlindLogError("the ```verdicts fence is never closed "
                            "(a truncated log)")

    records, seen = [], set()
    for n, line in enumerate(body, 1):
        if not line.strip():
            continue
        m = VERDICT_LINE.match(line)
        if not m:
            raise BlindLogError("verdict line %d is malformed: %r" % (n, line))
        rec = m.groupdict()
        if rec["run"] in seen:
            raise BlindLogError("run %r appears twice" % rec["run"])
        seen.add(rec["run"])
        records.append(rec)
    if len(records) != declared:
        raise BlindLogError("header declares runs=%d, the block has %d record(s)"
                            % (declared, len(records)))
    return records


def blind_count(path=None):
    """`(passing, note)` — `note` is "" only when the log parsed.

    A run counts ONLY if both builds cleared the contract and no HTML was
    hand-written; the verdict token alone is not enough, because the verdict is
    the part a writer could get wrong while the evidence fields say otherwise.
    A disagreement between them is a malformed log, not a judgement call.
    """
    try:
        records = blind_records(path)
    except BlindLogError as e:
        return 0, str(e)
    except Exception as e:                          # noqa: BLE001 — fail closed
        return 0, "the blind log could not be read (%s)" % e

    good = 0
    for rec in records:
        earned = (rec["build1"] == "OK" and rec["build2"] == "OK"
                  and rec["html"] == "no")
        claimed = rec["verdict"] == "pass"
        if earned != claimed:
            return 0, ("run %s claims verdict=%s but its evidence says %s — a "
                       "log that disagrees with itself counts as none"
                       % (rec["run"], rec["verdict"],
                          "it passed" if earned else "it did not"))
        if earned:
            good += 1
    return good, ""


# --- the figure census (deterministic figures, Phase 1) ----------------------
# `figures:` replaces `diagrams:`. One census, the corpus's `figure-census.md`,
# records EVERY `<figure>` of the 30 pages once — svg or img — with the rung of
# the ladder that carries it and the block it is carried as:
#
#   rung 1  a closed stdlib block: `chart` (as = its type) or `diagram` (as =
#           its shape), today's or an extension the census lists;
#   rung 2  `graph`, Graphviz DOT (as = `dot`);
#   rung 3  `figure`, the original drawing as a file (as = svg / png / jpg).
#
# The parser is `blind:`'s and the old flow census's — a declared count, a
# fenced block, one fixed-order line per figure, every deviation raises — and
# the rung is the ONE judgement it records. Everything else is re-derived on
# every run:
#
#   * the recorded (page, fig) pairs must be EXACTLY the figures of the 30
#     pages: a fig the page does not draw, a figure the census misses, or a page
#     outside the sample leaves the line with no denominator;
#   * per page, the spec's figure blocks (`chart`, `diagram`, `graph`,
#     `figure`), in document order, are matched in order against the page's
#     records by block and `as` — and a `figure` block also by the sha256 of
#     its file, which must be the one the census records for the extracted
#     original (v2, Phase 2). A spec block that matches no remaining record — a
#     figure on another rung than assigned, a placeholder file, a drawing with
#     no source figure on a page that has others, two blocks in the wrong
#     order — makes the whole page count as NOT carried: the spec side must
#     never be able to run ahead of the source side;
#   * a page counts only when its spec BUILDS (`measure()` builds it once):
#     a block that parses and draws nothing carries nothing;
#   * a rung-3 svg record may end in `waived=<reason>` (`WAIVER_REASONS`, the
#     owner's amendment of the stop condition): it stays uncarried and does
#     not block the exit, but only while its sha256 is still the original's
#     and the original is still refused by the figure rules. A stale waiver
#     blocks like an uncarried figure.
#
# Only pages WITH a census record are examined. A spec that draws a figure on a
# page whose original has none is never looked at here — it cannot raise the
# count (there is no record for it to match), and it is not refused either.
#
# Blocks that do not exist yet (`graph`, a chart type or diagram shape still on
# the extension list) cannot be written in a spec that builds, so their
# records simply never match.
#
# The rung-1 extension list lives in the header (`extensions=block:as,…`) so it
# is checked, not just written: an extension must not already be built, and
# must be asked for by at least two records — the plan's rule for growing a
# closed block. A record whose chart type or diagram shape is neither built
# nor listed is refused, so a typo cannot read as "a block not built yet".
#
# Fail closed: a census that cannot be read, or does not cover the sample
# exactly, prints `figures: 0/unknown` — never `0/0`, which would read as done.
FIGURE_ELEMENT = figure_extract.FIGURE_ELEMENT
CENSUS_HEADER = re.compile(
    r'^<!-- FIGURE-CENSUS v(\d+) figures=(\d+) extensions=(\S*) -->$', re.M)
CENSUS_LINE = re.compile(
    r'^page=(?P<page>\S+) fig=(?P<fig>[0-9]+) kind=(?P<kind>\S+) '
    r'rung=(?P<rung>\S+) block=(?P<block>\S+) as=(?P<as>\S+)'
    r'(?: sha256=(?P<sha256>[0-9a-f]{64}))?'
    r'(?: waived=(?P<waived>[a-z0-9-]+))?$')
KINDS = ("flow", "chart", "screenshot", "mockup", "grid", "illustration")
RUNG_BLOCKS = {"1": ("chart", "diagram"), "2": ("graph",), "3": ("figure",)}
FIGURE_FILES = ("svg", "png", "jpg")
# Why a figure may stay uncarried, by name (the owner's amendment of the stop
# condition, 2026-09-24). Closed: a new reason is a new owner decision, never a
# census edit. `literal-colours` — the original draws with hex paint the
# `figure` block refuses; it holds only on a rung-3 svg record, and only while
# the extracted original is still refused by the figure rules.
WAIVER_REASONS = ("literal-colours",)


class CensusError(Exception):
    """The census cannot be read as one record per figure."""


def _built(block):
    """The `as` values a rung-1 block draws today."""
    return chart_svg.KINDS if block == "chart" else diagram_layout.SHAPES


def census_records(path=None):
    """The census's records, or raise. Never returns a partial list."""
    path = path or FIGURE_CENSUS
    if not os.path.exists(path):
        raise CensusError("no %s" % os.path.basename(path))
    with open(path, encoding="utf-8") as fh:
        text = fh.read()

    heads = CENSUS_HEADER.findall(text)
    if len(heads) != 1:
        raise CensusError(
            "%d FIGURE-CENSUS header(s), want exactly 1" % len(heads))
    version, declared, ext_field = heads[0][0], int(heads[0][1]), heads[0][2]
    # v2 (Phase 2): a rung-3 record carries `sha256=` of its extracted original.
    if version != "2":
        raise CensusError("unknown census version v%s" % version)
    if declared < 1:
        raise CensusError(
            "the header declares figures=%d — an empty census would print "
            "0/0, which reads as fully carried" % declared)
    extensions = set()
    for tok in (t for t in ext_field.split(",") if t):
        block, _, form = tok.partition(":")
        if block not in RUNG_BLOCKS["1"] or not form:
            raise CensusError("extension %r is not `chart:<type>` or "
                              "`diagram:<shape>`" % tok)
        if form in _built(block):
            raise CensusError("extension %r is already built — it is not an "
                              "extension" % tok)
        extensions.add((block, form))

    after = text[CENSUS_HEADER.search(text).end():]
    lines = after.split("\n")
    i = 0
    while i < len(lines) and not lines[i].strip():
        i += 1
    if i >= len(lines) or lines[i].strip() != "```census":
        raise CensusError("no ```census fence right after the header")
    body, closed = [], False
    for line in lines[i + 1:]:
        if line.strip() == "```":
            closed = True
            break
        body.append(line)
    if not closed:
        raise CensusError("the ```census fence is never closed "
                          "(a truncated census)")

    records, seen, asked = [], set(), {}
    for n, line in enumerate(body, 1):
        if not line.strip():
            continue
        m = CENSUS_LINE.match(line)
        if not m:
            raise CensusError("census line %d is malformed: %r" % (n, line))
        rec = m.groupdict()
        rec["fig"] = int(rec["fig"])
        if rec["fig"] < 1:
            raise CensusError("census line %d records fig=%d; figures are "
                              "numbered from 1" % (n, rec["fig"]))
        if rec["kind"] not in KINDS:
            raise CensusError("census line %d records kind=%r (%s)"
                              % (n, rec["kind"], ", ".join(KINDS)))
        if rec["rung"] not in RUNG_BLOCKS:
            raise CensusError("census line %d records rung=%r; the ladder is "
                              "1, 2, 3" % (n, rec["rung"]))
        if rec["block"] not in RUNG_BLOCKS[rec["rung"]]:
            raise CensusError(
                "census line %d records block=%s on rung %s, which is carried "
                "by %s" % (n, rec["block"], rec["rung"],
                           " or ".join(RUNG_BLOCKS[rec["rung"]])))
        block, form = rec["block"], rec["as"]
        if block in RUNG_BLOCKS["1"]:
            if (block, form) in extensions:
                asked[(block, form)] = asked.get((block, form), 0) + 1
            elif form not in _built(block):
                raise CensusError(
                    "census line %d records %s as=%s, which is neither built "
                    "(%s) nor on the header's extension list"
                    % (n, block, form, ", ".join(_built(block))))
        elif block == "graph" and form != "dot":
            raise CensusError("census line %d records graph as=%s; a graph "
                              "is DOT" % (n, form))
        elif block == "figure" and form not in FIGURE_FILES:
            raise CensusError("census line %d records figure as=%s (%s)"
                              % (n, form, ", ".join(FIGURE_FILES)))
        if rec["waived"] and (rec["waived"] not in WAIVER_REASONS
                              or rec["rung"] != "3" or rec["as"] != "svg"):
            raise CensusError(
                "census line %d records waived=%s; a waiver is one of %s, on a "
                "rung-3 svg record" % (n, rec["waived"], ", ".join(WAIVER_REASONS)))
        if (rec["rung"] == "3") != (rec["sha256"] is not None):
            raise CensusError(
                "census line %d: a rung-3 record carries the sha256 of its "
                "extracted original, and only a rung-3 record does" % n)
        key = (rec["page"], rec["fig"])
        if key in seen:
            raise CensusError("%s fig %d is recorded twice"
                              % (rec["page"], rec["fig"]))
        seen.add(key)
        records.append(rec)
    if len(records) != declared:
        raise CensusError("header declares figures=%d, the block has %d "
                          "record(s)" % (declared, len(records)))
    for block, form in sorted(extensions):
        if asked.get((block, form), 0) < 2:
            raise CensusError(
                "extension %s:%s is asked for by %d record(s); a closed block "
                "grows only for a need seen at least twice"
                % (block, form, asked.get((block, form), 0)))
    _attach_graph_labels(text, records)
    return records


# --- rung 2's content (Phase 5; Phase 1 review, F2) --------------------------
# A `graph` block in the right place is not enough for a rung-2 figure to count:
# any DOT would do. The census therefore records, per rung-2 figure, the labels
# of the ORIGINAL's boxes — its nodes and its containers — and the gate reads
# the same labels back out of the graph the spec builds (`graph_svg.labels`).
# They must agree as a multiset: a box dropped, added or renamed is a figure
# the graph does not carry. The EDGES are compared too, as a count per stroke
# kind (solid / dashed, `graph_svg.edges`): the captions these figures carry
# ("the dashed one has not happened") are about the edges, and a graph with
# its edges deleted or its two kinds swapped would otherwise still count.
# Direction and edge labels are not compared.
#
# Its own machine block, after the census block, so the census line keeps its
# six fields:
#
#   <!-- GRAPH-LABELS v1 -->
#   ```graph-labels
#   page=<page> fig=<n> edges=solid:<n>,dashed:<n> labels=<label> | …
#   ```
#
# Fail closed like the census: every rung-2 record needs exactly one line, a
# line for anything else is refused, and a census with rung-2 records and no
# block is refused.
LABELS_HEADER = re.compile(r'^<!-- GRAPH-LABELS v(\d+) -->$', re.M)
LABELS_LINE = re.compile(
    r'^page=(?P<page>\S+) fig=(?P<fig>[0-9]+) '
    r'edges=solid:(?P<solid>[0-9]+),dashed:(?P<dashed>[0-9]+) '
    r'labels=(?P<labels>.+)$')
LABELS_SEP = " | "


def _attach_graph_labels(text, records):
    """Give every rung-2 record its `labels` (a sorted list), or raise."""
    rung2 = {(r["page"], r["fig"]): r for r in records if r["rung"] == "2"}
    heads = LABELS_HEADER.findall(text)
    if not heads:
        if rung2:
            raise CensusError(
                "%d rung-2 record(s) and no GRAPH-LABELS block — a graph "
                "counts only against the original's node labels" % len(rung2))
        return
    if len(heads) != 1:
        raise CensusError(
            "%d GRAPH-LABELS header(s), want at most 1" % len(heads))
    if heads[0] != "1":
        raise CensusError("unknown GRAPH-LABELS version v%s" % heads[0])
    lines = text[LABELS_HEADER.search(text).end():].split("\n")
    i = 0
    while i < len(lines) and not lines[i].strip():
        i += 1
    if i >= len(lines) or lines[i].strip() != "```graph-labels":
        raise CensusError("no ```graph-labels fence right after its header")
    body, closed = [], False
    for line in lines[i + 1:]:
        if line.strip() == "```":
            closed = True
            break
        body.append(line)
    if not closed:
        raise CensusError("the ```graph-labels fence is never closed")
    seen = set()
    for n, line in enumerate(body, 1):
        if not line.strip():
            continue
        m = LABELS_LINE.match(line)
        if not m:
            raise CensusError("graph-labels line %d is malformed: %r"
                              % (n, line))
        key = (m.group("page"), int(m.group("fig")))
        if key not in rung2:
            raise CensusError(
                "graph-labels line %d names %s fig %d, which is not a rung-2 "
                "record of the census" % (n, key[0], key[1]))
        if key in seen:
            raise CensusError("graph-labels: %s fig %d is recorded twice" % key)
        seen.add(key)
        labels = [x.strip() for x in m.group("labels").split(LABELS_SEP)]
        if not all(labels):
            raise CensusError("graph-labels line %d has an empty label" % n)
        rung2[key]["labels"] = sorted(labels)
        rung2[key]["edges"] = {"solid": int(m.group("solid")),
                               "dashed": int(m.group("dashed"))}
    missing = sorted(set(rung2) - seen)
    if missing:
        raise CensusError(
            "%d rung-2 record(s) have no graph-labels line (%s)"
            % (len(missing), ", ".join("%s fig %d" % k for k in missing[:3])))


def page_figures(page_path):
    """How many `<figure>`s this page has — svg or img — in document order."""
    with open(page_path, encoding="utf-8", errors="replace") as fh:
        return len(FIGURE_ELEMENT.findall(fh.read()))


def _record_form(rec):
    if rec["block"] == "diagram":
        return diagram_layout.SHAPE_ALIASES.get(rec["as"], rec["as"])
    return rec["as"]


def _graph_content(node):
    """`(labels, edges)` of the graph a `graph` block builds — node labels
    sorted, edge counts per kind — or `(None, None)` when it does not build
    (no `dot`, bad DOT): a graph that cannot be drawn carries nothing."""
    dot = "\n".join(ln for child in node.children for ln in child.raw_body)
    try:
        svg, _version = graph_svg.render(dot)
    except graph_svg.GraphError:
        return None, None
    return sorted(graph_svg.labels(svg)), graph_svg.edges(svg)


def _sha256(path):
    """The file's sha256, or None when there is no such file."""
    try:
        with open(path, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except OSError:
        return None


def spec_figures(spec_path):
    """`(block, as, sha256)` of every figure block in a spec, in document
    order. `sha256` is the hash of a `figure` block's file (resolved against the
    spec's directory, as the build resolves it), None for every other block. A
    `graph` carries two more items, `(labels, edges)` from `_graph_content`."""
    with open(spec_path, encoding="utf-8") as fh:
        nodes = spec_parser.parse(fh.read())
    base = os.path.dirname(os.path.abspath(spec_path))
    out = []

    def walk(items):
        for node in items:
            kind = node.block_type
            if kind == "chart":
                out.append((kind, (node.attrs.get("type") or "").strip(), None))
            elif kind == "diagram":
                shape = (node.attrs.get("shape") or "").strip()
                out.append((kind, diagram_layout.SHAPE_ALIASES.get(shape, shape),
                            None))
            elif kind == "graph":
                out.append((kind, "dot", None) + _graph_content(node))
            elif kind == "figure":
                src = (node.attrs.get("src") or "").strip()
                ext = os.path.splitext(src)[1].lstrip(".").lower()
                out.append((kind, "jpg" if ext == "jpeg" else ext,
                            _sha256(os.path.join(base, src)) if src else None))
            walk(node.children)

    walk(nodes)
    return out


def _content_agrees(rec, blk):
    """A record that names its content (a rung-2 figure's `labels`) is carried
    only by a block whose content is the same; any other record, by form."""
    if "labels" not in rec:
        return True
    return (len(blk) > 4 and blk[3] is not None and blk[3] == rec["labels"]
            and blk[4] == rec["edges"])


def carried_on_page(recs, blocks):
    """How many of one page's records its spec's blocks carry, or None."""
    got = _matched(recs, blocks)
    return None if got is None else len(got)


def _matched(recs, blocks):
    """The (page, fig) keys of one page's records its spec's blocks carry, or
    None.

    `None` means a block matched no remaining record, so the page carries
    nothing. A `figure` block agrees with a record only when its file's sha256
    is the one the census recorded for the extracted original (Phase 1 review,
    F2): a placeholder with the right extension is a different file. When
    `figure_count` has re-extracted the original page's figure, its hash
    (`original`) must agree too (review F-E): a census is not trusted to have
    recorded the original. Each block takes the EARLIEST remaining record it agrees with —
    which decides whether the blocks are an in-order subsequence of the
    records, and that is all "the matching position" can mean while figures
    before it are still uncarried.
    """
    recs = sorted(recs, key=lambda r: r["fig"])
    j, carried = 0, set()
    for b in blocks:
        block, form = b[0], b[1]
        sha = b[2] if len(b) > 2 else None
        k = next((k for k in range(j, len(recs))
                  if recs[k]["block"] == block and _record_form(recs[k]) == form
                  and (block != "figure" or (
                      recs[k].get("sha256") == sha
                      and recs[k].get("original", sha) == sha))
                  and _content_agrees(recs[k], b)),
                 None)
        if k is None:
            return None
        carried.add((recs[k].get("page"), recs[k]["fig"]))
        j = k + 1
    return carried


def figure_count(sample_pages, root, census=None, built=None):
    """`(carried, total_or_None, ladder_or_None, notes, short)` for
    `figures:`/`ladder:`.

    `total is None` means the census could not be read or does not cover the
    sample exactly — the caller prints `unknown`, never a denominator.

    `short` is what keeps `figures:` from being done: every uncarried record
    except a waived one whose waiver still holds — its census sha256 is the
    extracted original's and that original is still refused by the figure
    rules. A stale waiver would excuse whatever the figure does next, so it
    counts. A waiver is the owner's named amendment of the stop condition; it
    moves no count, so the line still prints carried/total. Unreadable
    census: `short` is 1.

    A page's figures count only when its spec BUILDS (Phase 1 review, F1): a
    `::: figure {src=nope.svg}` parses into a block that matches its record,
    and it draws nothing. `built` is `measure()`'s set of spec paths that
    built; None (a caller that has not built them) builds each spec here.
    """
    try:
        records = census_records(census)
    except CensusError as e:
        return 0, None, None, [str(e)], 1
    except Exception as e:                          # noqa: BLE001 — fail closed
        return 0, None, None, ["the figure census could not be read (%s)" % e], 1

    real = set()
    for p in sample_pages:
        n = page_figures(os.path.join(root, p["path"]))
        real.update((p["path"], i) for i in range(1, n + 1))
    recorded = {(r["page"], r["fig"]) for r in records}
    if recorded != real:
        extra = sorted(recorded - real)
        missed = sorted(real - recorded)
        why = []
        if extra:
            why.append("records %d figure(s) the sample does not draw (%s)"
                       % (len(extra), ", ".join("%s fig %d" % k for k in extra[:3])))
        if missed:
            why.append("misses %d figure(s) the sample draws (%s)"
                       % (len(missed), ", ".join("%s fig %d" % k for k in missed[:3])))
        return 0, None, None, ["the census does not cover the sample exactly: "
                               + "; ".join(why)], 1

    notes = []
    # Re-derive, never trust (review F-E): each rung-3 record's sha256 is
    # checked against the figure extracted from the ORIGINAL page now. A
    # record that disagrees keeps `original` set to what the page holds (or ""
    # when nothing can be extracted), which no embedded file can match twice.
    for rec in records:
        if rec["rung"] != "3":
            continue
        try:
            _ext, data = figure_extract.extract(
                os.path.join(root, rec["page"]), rec["fig"])
            rec["original"] = hashlib.sha256(data).hexdigest()
            # A waiver's reason must still hold on the original itself.
            rec["refused"] = bool(rec["waived"]) and bool(
                check_artifact.svg_embed_violations(
                    data.decode("utf-8", "replace")))
        except (OSError, ValueError):
            rec["original"] = ""
        if rec["original"] != rec["sha256"]:
            notes.append("%s fig %d: the census sha256 is not the hash of the "
                         "figure the original page holds, so it is not carried"
                         % (rec["page"], rec["fig"]))

    ladder = {r: sum(1 for x in records if x["rung"] == r) for r in RUNG_BLOCKS}
    by_page, carried = {}, set()
    for rec in records:
        by_page.setdefault(rec["page"], []).append(rec)
    for page, recs in sorted(by_page.items()):
        spec = os.path.join(SPECS, spec_name(page))
        if not os.path.exists(spec):
            notes.append("%s has no spec, so its %d figure(s) are not carried"
                         % (page, len(recs)))
            continue
        if not (spec in built if built is not None
                else spec_body(spec) is not None):
            notes.append("%s: its spec does not build, so its %d figure(s) "
                         "are not carried" % (page, len(recs)))
            continue
        try:
            blocks = spec_figures(spec)
        except Exception as e:                      # noqa: BLE001 — fail closed
            notes.append("%s: its spec could not be parsed (%s)" % (page, e))
            continue
        got = _matched(recs, blocks)
        if got is None:
            notes.append(
                "%s: its spec draws %s and the census records %s in that order "
                "— a spec block matches no record (a `figure` block matches "
                "only the file whose sha256 the census records), so none of "
                "the page's figures counts as carried"
                % (page, ", ".join("%s %s" % b[:2] for b in blocks),
                   ", ".join("fig %d %s %s" % (r["fig"], r["block"], r["as"])
                             for r in sorted(recs, key=lambda r: r["fig"])))
                + "".join(" · a graph draws %s %s" % (b[3], b[4])
                          for b in blocks if b[0] == "graph")
                + "".join(" · fig %d wants %s %s"
                          % (r["fig"], r["labels"], r["edges"])
                          for r in recs if "labels" in r))
            continue
        carried |= got
    short = 0
    for rec in records:
        if not rec["waived"]:
            short += (rec["page"], rec["fig"]) not in carried
        elif rec["original"] == rec["sha256"] and rec["refused"]:
            notes.append("%s fig %d: waived (%s), not carried"
                         % (rec["page"], rec["fig"], rec["waived"]))
        else:
            short += 1
            notes.append("%s fig %d: the waiver (%s) no longer holds — the "
                         "original changed or passes the figure rules now; "
                         "carry it or drop the waiver"
                         % (rec["page"], rec["fig"], rec["waived"]))
    return len(carried), len(records), ladder, notes, short

# --- the measurements --------------------------------------------------------
def spec_body(spec_path):
    """The spec's built body, or None when the build refuses it."""
    try:
        return corpus_diff.build_body(spec_path)
    except (spec_parser.SpecSyntaxError, spec_build.SpecBuildError):
        return None


def measure(pages, root, verbose=False):
    """`(converted, clean, escaped, after, built)`. `built` is the set of spec
    paths whose build succeeded — `figure_count` reads it, so a spec is built
    once per run and a figure is judged by the build, never by the parse."""
    converted, clean, escaped, after, built = [], 0, 0, [], set()
    for entry in pages:
        path = os.path.join(SPECS, spec_name(entry["path"]))
        if not os.path.exists(path):
            continue
        converted.append(entry)
        body = spec_body(path)
        if body is None:
            ok, problems = corpus_diff.compare(
                path, os.path.join(root, entry["path"]))
        else:
            built.add(path)
            ok, problems = corpus_diff.compare_body(
                body, os.path.join(root, entry["path"]))
        if ok:
            clean += 1
        elif verbose:
            sys.stderr.write("goal-gate: %s\n  %s\n"
                             % (spec_name(entry["path"]), "\n  ".join(problems)))
        why = escapes_in(path)
        if why:
            escaped += 1
            if verbose:
                sys.stderr.write("goal-gate: %s needed an escape: %s\n"
                                 % (spec_name(entry["path"]), "; ".join(why)))
        after.append((entry, path, os.path.getsize(path)))
    return converted, clean, escaped, after, built


def contract_pass(spec_path):
    """Does the page this spec builds satisfy the artifact contract?

    Through the real wrap, into a throwaway directory: `wrap-report.sh --out`
    is what runs `check-artifact` on a landed file, and a page checked any
    other way is a page checked differently from the one that ships.
    """
    tmp = tempfile.mkdtemp(prefix="goal-gate-")
    try:
        rc = subprocess.run(
            [sys.executable, BUILD, spec_path, "-o", os.path.join(tmp, "p.html")],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
        return rc == 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def contract_results(after):
    """One `contract_pass` per converted page, in `after`'s order.

    Computed ONCE per run: `newly-fail:` and the `baseline:` tail read the same
    list, so the two lines cannot disagree about which page failed.
    """
    return [contract_pass(p) for _e, p, _s in after]


def newly_fail(after, baseline, passes):
    """Pages whose ORIGINAL passes `check-artifact` and whose BUILD does not.

    Invisible until 2026-09-24: `corpus:` compares ids and visible text, so a
    page can keep every word while losing the structure the contract is about,
    and a converter that turned a passing page into a failing one read green.
    A blocking line since the deterministic-figures plan: the figure a build
    loses is what makes most of these pages fail.
    """
    by_path = {r["path"]: r for r in baseline}
    return sum(1 for (e, _p, _s), ok in zip(after, passes)
               if not ok and by_path.get(e["path"], {}).get("check_today_pass"))


def baseline_line(after, baseline, passes=None):
    """`<before> -> <after>`, over the CONVERTED pages only.

    Comparing 6 converted pages against the 30-page baseline would compare two
    different sets and call the difference an improvement. Informative in any
    case: nothing here can change the exit status (Q9). `passes` is
    `contract_results(after)`, or None when the contract was not measured; the
    tail repeats `newly-fail:` from the same list.
    """
    if not after:
        return "no page converted yet -> nothing to compare"
    by_path = {r["path"]: r for r in baseline}
    before_bytes = [by_path[e["path"]]["wrote_bytes"] for e, _p, _s in after
                    if e["path"] in by_path]
    after_bytes = [size for _e, _p, size in after]
    before_pass = sum(1 for e, _p, _s in after
                      if by_path.get(e["path"], {}).get("check_today_pass"))
    n = len(after)
    head = ("%d page(s) · median %d bytes written · %d/%d pass the contract"
            % (n, statistics.median(before_bytes) if before_bytes else 0,
               before_pass, n))
    if passes is None:
        return "%s -> median %d bytes of spec (%.0f%%) · contract not measured" % (
            head, statistics.median(after_bytes),
            100.0 * statistics.median(after_bytes)
            / (statistics.median(before_bytes) or 1))
    return ("%s -> median %d bytes of spec (%.0f%%) · %d/%d pass the contract "
            "· %d newly fail (source passed, build fails)"
            % (head, statistics.median(after_bytes),
               100.0 * statistics.median(after_bytes)
               / (statistics.median(before_bytes) or 1),
               sum(passes), n, newly_fail(after, baseline, passes)))


def corpus_missing():
    """Why the gate cannot measure anything, or "" when the corpus is there.

    Read from the module globals at CALL time, so a test that points one of
    them elsewhere is checked against what it pointed at. Every file is
    required: a gate run against half a corpus prints numbers — `corpus: 0/30`
    with no floor to regress from, `blind: 0/3` — that measured nothing, and
    an unmeasured count must never read as a result.
    """
    if not CORPUS:
        return ("%s is not set — point it at the spec corpus directory; "
                "nothing was measured" % CORPUS_ENV)
    if not os.path.isdir(CORPUS):
        return ("%s=%s is not a directory; nothing was measured"
                % (CORPUS_ENV, CORPUS))
    need = [SAMPLE, BASELINE, FLOOR, BLIND_LOG, FIGURE_CENSUS]
    lacks = [p for p in need if not os.path.isfile(p)]
    if not os.path.isdir(SPECS):
        lacks.insert(0, SPECS)
    if lacks:
        return ("%s=%s lacks %s; nothing was measured"
                % (CORPUS_ENV, CORPUS, ", ".join(
                    os.path.relpath(p, CORPUS) for p in lacks)))
    return ""


def main(argv):
    verbose = "--verbose" in argv
    contract = "--no-contract" not in argv

    missing = corpus_missing()
    if missing:
        sys.stderr.write("goal-gate: %s\n" % missing)
        return 2

    with open(SAMPLE, encoding="utf-8") as fh:
        sample = json.load(fh)
    with open(BASELINE, encoding="utf-8") as fh:
        baseline = json.load(fh)
    pages, root, total = sample["pages"], sample["root"], len(sample["pages"])
    check_names(pages)

    converted, clean, escaped, after, built = measure(pages, root,
                                                      verbose=verbose)

    # The seven lines, in the fixed order, ALWAYS — a phase that has not run yet
    # prints its stub rather than its line going missing, because the shape is
    # what downstream greps and a missing line reads as a passing one.
    print("corpus: %d/%d" % (clean, total))
    print("escapes: %d" % escaped)
    blind, blind_note = blind_count()
    if blind_note:
        sys.stderr.write("goal-gate: blind trial not counted: %s\n" % blind_note)
    print("blind: %d/%d" % (blind, EXPECTED_RUNS))
    carried, figs, ladder, fig_notes, fig_short = figure_count(
        pages, root, built=built)
    for note in fig_notes:
        sys.stderr.write("goal-gate: figures: %s\n" % note)
    print("figures: %d/%s" % (carried, "unknown" if figs is None else figs))
    passes = contract_results(after) if contract else None
    newly = None if passes is None else newly_fail(after, baseline, passes)
    print("newly-fail: %s" % ("unknown" if newly is None else newly))
    print("ladder: %s" % ("unknown" if ladder is None else " · ".join(
        "r%s %d" % (r, ladder[r]) for r in sorted(ladder))))
    print("baseline: %s" % baseline_line(after, baseline, passes))

    # corpus_missing() already refused a corpus without its floor; a default
    # here would be the one path that quietly lowers it if that guard regressed.
    with open(FLOOR, encoding="utf-8") as fh:
        floor = json.load(fh)

    bad = []
    if clean < floor["corpus"]:
        bad.append("corpus regressed: %d clean, floor is %d"
                   % (clean, floor["corpus"]))
    if escaped > floor["escapes"]:
        bad.append("escapes regressed: %d pages needed one, floor is %d"
                   % (escaped, floor["escapes"]))
    # A spec that is present and DIRTY is a regression even when the count has
    # not moved: adding a seventh page must not be able to hide the sixth
    # breaking. The count alone cannot see that, because a dirty spec simply
    # stops being counted.
    if clean < len(converted):
        bad.append("%d of the %d converted page(s) no longer match their "
                   "original — re-run with --verbose for the divergence"
                   % (len(converted) - clean, len(converted)))
    # `figures:` and `newly-fail:` gate on COMPLETION, not on a floor: the goal
    # is every figure carried and no page the build breaks. An unmeasured value
    # is not a pass — `unknown` fails like a shortfall does.
    if figs is None:
        bad.append("figures: the census could not be counted")
    elif fig_short:
        bad.append("figures: %d of %d figure(s) not carried on their assigned "
                   "rung, or waived and carried" % (fig_short, figs))
    if newly is None:
        bad.append("newly-fail: not measured (--no-contract); a blocking line "
                   "that measured nothing is not a pass")
    elif newly:
        bad.append("newly-fail: %d page(s) pass the contract as written and "
                   "fail it as built" % newly)
    for line in bad:
        sys.stderr.write("goal-gate: %s\n" % line)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
