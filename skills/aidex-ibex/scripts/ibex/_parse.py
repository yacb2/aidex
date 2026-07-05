#!/usr/bin/env python3
"""Markdown parsing helpers for the ibex render layer. Stdlib only, no YAML lib.

The renderers parse the existing `.context/` markdown (front-matter blocks,
pipe tables, GitHub checkboxes) exactly like reindex-plans.sh / validate.py do,
so no new JSON is introduced. Every helper is tolerant of missing or partial
input and returns an empty result rather than raising.
"""
import re
import sys


def die(msg):
    """Print a plain-text error and exit 2 (never a traceback)."""
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(2)


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="ignore") as f:
            return f.read()
    except OSError as e:
        die(f"cannot read {path}: {e.strerror}")


def _strip_quotes(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
        return v[1:-1]
    return v


def front_matter(path):
    """Parse a leading `---` front-matter block into a dict of str->str.

    Tolerates surrounding quotes on values. Returns {} if the file has no
    front-matter block (does not open at line 1 with `---`).
    """
    text = read_text(path)
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    out = {}
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if ":" not in line:
            continue
        key, _, val = line.partition(":")
        out[key.strip()] = _strip_quotes(val)
    return out


def md_table(lines):
    """Parse the first GitHub pipe table found in `lines` (list of str).

    Returns (headers, rows): headers is a list of column names, rows is a list
    of lists of cell strings. The separator row (---|---) is skipped. Returns
    ([], []) if no table is found.
    """
    if isinstance(lines, str):
        lines = lines.splitlines()

    def cells(line):
        s = line.strip()
        if s.startswith("|"):
            s = s[1:]
        if s.endswith("|"):
            s = s[:-1]
        return [c.strip() for c in s.split("|")]

    headers, rows, in_table = [], [], False
    for line in lines:
        s = line.strip()
        is_row = s.startswith("|") and s.count("|") >= 2
        if not in_table:
            if is_row:
                headers = cells(line)
                in_table = True
            continue
        # inside the table
        if not is_row:
            break
        c = cells(line)
        if all(re.fullmatch(r":?-+:?", x or "") for x in c if x != ""):
            continue  # separator row
        rows.append(c)
    return headers, rows


def checkbox_counts(text):
    """Count GitHub task-list checkboxes in `text`.

    Returns (done, total) where done counts `- [x]` / `- [X]` and total counts
    every `- [ ]` or `- [x]` bullet. Non-checkbox bullets are ignored.
    """
    done = len(re.findall(r"(?m)^\s*[-*]\s+\[[xX]\]", text))
    todo = len(re.findall(r"(?m)^\s*[-*]\s+\[ \]", text))
    return done, done + todo
