#!/usr/bin/env bash
# Reference table-of-contents gate.
#
# The rule has one owner: skill-conventions.md § Reference File Organization (the
# "For files > 100 lines" sentence). This script enforces that sentence and restates
# nothing; read the canon for what passes. Zero files checked under ROOT is itself a failure.
#
# Scope: skills/*/references/**/*.md with more than 100 lines (the fixtures dir sits
# under scripts/, so it is never in scope for the repo root).
#
# Usage: bash skills/conventions/scripts/test_reference_toc.sh [ROOT]
#   ROOT defaults to the repo root this script sits in. Exit 1 on any failing file.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="${1:-$(cd "$SCRIPT_DIR/../../.." && pwd -P)}"

python3 - "$ROOT" <<'PY'
import os, re, sys

root = os.path.realpath(sys.argv[1])

def slug(text, seen):
    """github-slugger: a taken candidate keeps incrementing (ex, ex-1, ex-2)."""
    base = re.sub(r"[^\w\- ]", "", text.strip().lower().replace("`", "")).replace(" ", "-")
    s = base
    while s in seen:
        seen[base] = seen.get(base, 0) + 1
        s = f"{base}-{seen[base]}"
    seen[s] = 0
    return s

def scan(lines):
    """Return (ATX headings outside fences [(idx, level, text)], ended_inside_fence)."""
    out, fence = [], None
    for i, l in enumerate(lines):
        if fence:
            m = re.match(r" {0,3}(`{3,}|~{3,})[ \t]*$", l)
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= fence[1]:
                fence = None
            continue
        m = re.match(r" {0,3}(`{3,}|~{3,})(.*)$", l)
        if m and not (m.group(1)[0] == "`" and "`" in m.group(2)):
            fence = (m.group(1)[0], len(m.group(1)))
            continue
        m = re.match(r" {0,3}(#{1,6})(?:[ \t]+(.*?))?[ \t]*$", l)
        if m:
            t = re.sub(r"(^|[ \t]+)#+[ \t]*$", "", m.group(2) or "").strip()
            out.append((i, len(m.group(1)), t))
    return out, fence is not None

def check(path):
    lines = open(path, encoding="utf-8").read().splitlines()
    hs, open_fence = scan(lines)
    if open_fence:
        return "file ends inside an unclosed code fence"
    idx = next((i for i, lvl, t in hs
                if i < 40 and lvl == 2 and lines[i].rstrip() == "## Contents"), None)
    if idx is None:
        return "no `## Contents` heading within the first 40 lines"
    entries, j = [], idx + 1   # (line, indent, anchor)
    while j < len(lines) and lines[j].strip() == "":
        j += 1
    while j < len(lines) and re.match(r"\s*[-*]\s", lines[j]):
        m = re.match(r"( *)[-*]\s+\[[^\]]+\]\(#([^)]+)\)\s*$", lines[j])
        if not m or len(m.group(1)) not in (0, 2):
            return f"line {j+1}: Contents bullet is not a [text](#anchor) link (indent 0 or 2)"
        entries.append((j, len(m.group(1)), m.group(2)))
        j += 1
    if not entries:
        return "no bullet list of links directly under `## Contents`"
    seen, slugs, heading_slug = {}, {}, {}
    for i, lvl, t in hs:
        heading_slug[i] = slug(t, seen)
        slugs[heading_slug[i]] = i
    level = {i: lvl for i, lvl, t in hs}
    text = {i: t for i, lvl, t in hs}
    indent_of = {}
    for ln, ind, a in entries:
        if a not in slugs:
            return f"anchor #{a} resolves to no heading"
        indent_of[slugs[a]] = ind
    h2s = [i for i, lvl, t in hs if lvl == 2 and t != "Contents"]
    if entries[0][1] != 0:
        return f"line {entries[0][0]+1}: the first Contents entry must not be nested"
    parent = None
    for ln, ind, a in entries:
        tgt = slugs[a]
        if ind == 0:
            parent = tgt
        elif level[tgt] >= 3:
            enclosing = max((h for h in h2s if h < tgt), default=None)
            if parent != enclosing:
                return (f"line {ln+1}: `{text[tgt]}` is nested under the wrong parent "
                        "(it must sit under its enclosing H2)")
    order = [slugs[a] for _, _, a in entries]
    if any(x >= y for x, y in zip(order, order[1:])):
        return "Contents entries are not in document order"
    first_h2 = h2s[0] if h2s else None
    for i in h2s:
        if i not in indent_of:
            return (f"H2 `{text[i]}` (line {i+1}) is not linked in Contents "
                    f"(its anchor is #{heading_slug[i]})")
        if indent_of[i] != 0:
            return f"H2 `{text[i]}` (line {i+1}) must be a top-level Contents entry"
    for i, lvl, t in hs:
        if lvl != 3:
            continue
        want = 0 if first_h2 is None or i < first_h2 else 2
        if i in indent_of and indent_of[i] != want:
            return f"H3 `{t}` (line {i+1}) must be indented {want} spaces in Contents"
        if len(h2s) < 3 and i not in indent_of:
            return (f"H3 `{t}` (line {i+1}) is not linked in Contents "
                    f"(files with fewer than 3 H2s list every H3)")
    return None

checked = failing = 0
for d, _, fs in sorted(os.walk(os.path.join(root, "skills"))):
    parts = os.path.relpath(d, root).split(os.sep)
    if len(parts) < 3 or parts[2] != "references":
        continue
    for f in sorted(fs):
        if not f.endswith(".md"):
            continue
        p = os.path.join(d, f)
        if len(open(p, encoding="utf-8").read().splitlines()) <= 100:
            continue
        checked += 1
        why = check(p)
        if why:
            failing += 1
            print(f"FAIL {os.path.relpath(p, root)}: {why}")
if checked == 0:
    print(f"no reference files found under {root}")
    failing = 1
print(f"reference-toc: {checked} files checked, {failing} failing")
sys.exit(1 if failing else 0)
PY
