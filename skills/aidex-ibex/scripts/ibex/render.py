#!/usr/bin/env python3
"""ibex render CLI — turn a `.context/` index/board into a self-contained HTML

render (one render per index/board, never per document). Markdown/JSON stays
canon; the HTML is a regenerable sibling with a GENERATED contract header.

Usage:
  render.py <workspace-root> backlog
  render.py <workspace-root> plans [<slug>]
  render.py <workspace-root> audit <methodology>
  render.py <workspace-root> coverage

Prints the output path on success. Unknown target or bad input -> a plain-text
`ERROR: ...` on stderr and exit 2 (never a traceback).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import _parse as P
import render_audit
import render_backlog
import render_coverage
import render_plans

USAGE = (
    "usage: render.py <workspace-root> <target> [arg]\n"
    "  targets: backlog | plans [slug] | audit <methodology> | coverage"
)


def _dispatch(root, target, arg):
    if not os.path.isdir(os.path.join(root, ".context")):
        P.die(f"no .context directory under {root}")
    if target == "backlog":
        return render_backlog.render(root)
    if target == "plans":
        return render_plans.render(root, arg)
    if target == "audit":
        return render_audit.render(root, arg)
    if target == "coverage":
        return render_coverage.render(root)
    P.die(f"unknown target '{target}'\n{USAGE}")


def main(argv):
    if len(argv) < 3:
        P.die("missing arguments\n" + USAGE)
    root, target = argv[1], argv[2]
    arg = argv[3] if len(argv) > 3 else None
    try:
        out = _dispatch(root, target, arg)
    except SystemExit:
        raise
    except Exception as e:  # never leak a traceback to the user
        P.die(f"{type(e).__name__}: {e}")
    print(out)


if __name__ == "__main__":
    main(sys.argv)
