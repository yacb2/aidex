"""The composer's page-defect report in a pasted reply (LOOP-008 Q10).

A `#### Fallo de la página` (en: `#### Page problem`) sub-block at the END of
an item's `### ` block, the reader's text verbatim under it. It is no part of
the answer and no marker. Every reader of a reply cuts it through here:
check_artifact, save_reply, spec_verbs and gallery_reply (which imports no
other dash module, hence this one).
"""
import re

DEFECT_HEAD = re.compile(r"^#### (?:Fallo de la p\u00e1gina|Page problem)[ \t]*$", re.M)


def split_defect(block):
    """(block without its page-defect sub-block, the reported text or "")."""
    found = list(DEFECT_HEAD.finditer(block))
    if not found:
        return block, ""
    m = found[-1]                  # the composer emits it last: an earlier one is note text
    return block[:m.start()], block[m.end():].strip()


def blank_defects(chunk):
    """The reply with every item block's page-defect sub-block blanked (lines
    kept, so refusal line numbers still match): for the readers that parse by
    line (the gallery reply parser), which know no `####` sub-block. A block
    ends at the next `## ` or `### ` line (save_reply splits saves apart first)."""
    lines = chunk.split("\n")
    start = None
    for k, line in enumerate(lines + ["## end"]):
        if line.startswith(("## ", "### ")):
            if start is not None:
                hits = [j for j in range(start, k) if DEFECT_HEAD.match(lines[j])]
                if hits:
                    for j in range(hits[-1], k):
                        lines[j] = ""
            start = k + 1
    return "\n".join(lines)
