#!/usr/bin/env python3
"""stdin -> stdout: give a hand-written probe page the notes boxes check-artifact
now requires (BL-701), so a test about the COMPOSER does not have to repeat them
in every fixture.

Two additions, both skipped where the page already has them:
  - every `consult-group` ends with a `<div class="group-notes">` box (labelled);
  - every `<textarea>` of a consult item with no `.fieldlabel` before it in that
    item gets one.
`<script>` bodies are left alone (the probes build markup there as strings).
Not used by any test that is ABOUT the contract: those carry the boxes by hand.
"""
import re
import sys

BOX = ('<div class="group-notes"><p class="fieldlabel">Notes on this block</p>'
       '<textarea></textarea></div>')
LABEL = '<p class="fieldlabel">Free text</p>'
SECTION = re.compile(r'<section\b[^>]*>|</section\s*>', re.I)
GROUP = re.compile(r'<section\b[^>]*\bclass\s*=\s*["\'][^"\']*\bconsult-group\b', re.I)
ITEM = re.compile(r'<section\b[^>]*\bclass\s*=\s*["\'][^"\']*\bconsult-item\b', re.I)


def add_group_boxes(html):
    inserts, pos = [], 0
    for m in GROUP.finditer(html):
        depth, end = 1, None
        for t in SECTION.finditer(html, m.end()):
            depth += -1 if t.group(0).startswith("</") else 1
            if depth == 0:
                end = t.start()
                break
        if end is not None and "group-notes" not in html[m.end():end]:
            inserts.append(end)
    for at in sorted(inserts, reverse=True):
        html = html[:at] + BOX + html[at:]
    return html


def add_item_labels(html):
    out, last_item, last = [], -1, 0
    for m in re.finditer(r'<textarea\b', html, re.I):
        # the nearest item opener before this box, and whether a label sits between
        items = [i.start() for i in ITEM.finditer(html, 0, m.start())]
        start = items[-1] if items else -1
        scope = html[start:m.start()] if start >= 0 else ""
        in_script = html.rfind("<script", 0, m.start()) > html.rfind("</script", 0, m.start())
        if start >= 0 and "fieldlabel" not in scope and "group-notes" not in scope \
                and not in_script:
            out.append(html[last:m.start()] + LABEL)
            last = m.start()
    out.append(html[last:])
    return "".join(out)


def main():
    html = sys.stdin.read()
    sys.stdout.write(add_item_labels(add_group_boxes(html)))


if __name__ == "__main__":
    main()
