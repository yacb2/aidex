#!/usr/bin/env python3
"""Vocabulary lockstep: `04-block-vocabulary.md` against the builder's dispatch.

What this holds, and why it is worth a test of its own: the block vocabulary is
documented in one file and implemented in another, and Phase 6 adds `diagram` to
both. A type added to the builder and not to the doc ships a construct no agent
knows how to write; a type written into the doc and not into the builder sends
an agent to a fence that refuses. Neither shows up in any other test here —
`test_build.py` asserts one case per type it already knows about, so it grows
with the code and never notices the doc.

THE RULE, stated rather than silently applied.

  DOC SIDE — every row of the table under `## The types`, read as the backticked
  name in its first cell. **No row is excluded.** `prose` is on the list and its
  Purpose cell says "Not a fence."; `num`, `pill` and `chip` are on it and are
  inline, not block-level. Dropping them would make the test blind to exactly
  the rows whose status is easiest to get wrong.

  CODE SIDE — `spec_build.EMITTERS` (the dispatch table) UNION
  `spec_build.INLINE_HINT` (the types the builder knows by name and refuses as
  fences, each with the sentence saying where the construct really goes). That
  union is the builder's whole closed vocabulary: a name it can either emit or
  place. Anything outside it reaches the author as "unknown block type".

  So `prose` is matched by `EMITTERS` — it is registered, because it is the type
  the TOKENIZER gives a run of markdown outside any fence, which is what makes
  that run build; the doc's "not a fence" is about what an AUTHOR may write, and
  `emit_prose` refuses an authored `::: prose` on its own line number. And
  `num`/`pill`/`chip` are matched by `INLINE_HINT`. Two sets, one union, and
  every row of the doc accounted for by one of them.

  DISJOINT — a type may not be in both tables. `emit_node` reaches for
  `INLINE_HINT` only when `EMITTERS` has no entry, so a name in both would carry
  a refusal message no author can ever see.

The dispatch is read by IMPORTING `spec_build`, not by scanning its text for
`@emitter`: the registration seam is `register()`, which Phases 2 and 6 may call
from anywhere, and a regex over one file would agree with the doc while
disagreeing with the program. The imported dict is what `emit_node` dispatches
on — the truth this test is supposed to compare against.

Run with: python3 skills/artifact/tests/test_lockstep.py
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(SKILL, "scripts"))
sys.path.insert(0, os.path.join(SKILL, "scripts", "dash"))

import spec_build                                           # noqa: E402

VOCAB = os.path.join(SKILL, "references", "04-block-vocabulary.md")
ROUTE_S = os.path.join(SKILL, "references", "02-local-first-artifacts.md")
# Every table that lists the vocabulary, and the heading it sits under. The
# Route S copy is the one an author reads first, and it drifted: it said
# "Fifteen types" and had no `diagram`, `graph` or `figure` row.
TABLES = ((VOCAB, "## The types"),
          (ROUTE_S, "### The vocabulary, in one table"))

# A table row whose first cell is a single backticked name. The heading row and
# the `|---|` separator both fail it, so no row-index arithmetic is needed.
ROW = re.compile(r"^\|\s*`([^`|]+)`\s*\|")


def doc_types(path=VOCAB, heading="## The types"):
    """The Type column of the table under `heading`, in written order.

    Bounded to that one section on purpose: `## What is deliberately NOT a type`
    and `## Worked examples` below it also write backticked names, and one of
    them (the NOT-a-type list) is a set this test must never read as vocabulary.
    """
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    try:
        start = lines.index(heading)
    except ValueError:
        raise SystemExit("FAIL: %s has no `%s` heading — the table "
                         "this test reads moved or was renamed" % (path, heading))
    level = heading.split(" ")[0] + " "
    out = []
    for line in lines[start + 1:]:
        if line.startswith("## ") or line.startswith(level):
            break
        m = ROW.match(line)
        if m:
            out.append(m.group(1))
    return out


def main():
    failures = []
    for path, heading in TABLES:
        failures.extend(check_table(path, heading))
    if failures:
        for line in failures:
            print("FAIL: %s" % line)
        return 1
    print("OK — %d block types in lockstep across %d tables"
          % (len(doc_types()), len(TABLES)))
    return 0


def check_table(path, heading):
    failures = []
    name = "`%s` § %s" % (os.path.basename(path), heading.lstrip("# "))

    rows = doc_types(path, heading)
    if not rows:
        failures.append("the %s table yielded NO rows — the table "
                        "shape changed and this test would pass vacuously" % name)

    dup = sorted({t for t in rows if rows.count(t) > 1})
    if dup:
        failures.append("%s lists a type twice: %s" % (name, ", ".join(dup)))

    documented = set(rows)
    emitters = set(spec_build.EMITTERS)
    inline = set(spec_build.INLINE_HINT)

    both = sorted(emitters & inline)
    if both:
        failures.append(
            "registered in EMITTERS *and* in INLINE_HINT: %s — `emit_node` "
            "only reads INLINE_HINT when EMITTERS has no entry, so the hint "
            "for these can never reach an author" % ", ".join(both))

    registered = emitters | inline

    missing_from_doc = sorted(registered - documented)
    if missing_from_doc:
        failures.append(
            "the builder knows %d type(s) %s does not list: %s — add a row "
            "or drop the registration"
            % (len(missing_from_doc), name, ", ".join(missing_from_doc)))

    missing_from_code = sorted(documented - registered)
    if missing_from_code:
        failures.append(
            "%s lists %d type(s) the builder "
            "neither emits nor names as inline: %s — an author writing one gets "
            "\"unknown block type\". Register it in spec_build.EMITTERS (or in "
            "INLINE_HINT if it is inline), or remove the row"
            % (name, len(missing_from_code), ", ".join(missing_from_code)))
    return failures


if __name__ == "__main__":
    sys.exit(main())
