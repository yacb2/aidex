#!/usr/bin/env python3
"""Test suite for references-root-gate.sh.

  python3 hooks/test-references-root-gate.py
"""
import json, os, subprocess, sys

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "references-root-gate.sh")
fails = []


def run(stdin):
    p = subprocess.run(["sh", HOOK], input=stdin, capture_output=True, text=True)
    return p.returncode, p.stdout


def denied(path, tool="Write"):
    code, out = run(json.dumps({"tool_name": tool, "tool_input": {"file_path": path}}))
    return code == 0 and '"deny"' in out


def check(name, ok):
    print(("  PASS  " if ok else "  FAIL  ") + name)
    if not ok:
        fails.append(name)


R = "/w/proj/.context/references/"
check("flat dated file at root is denied", denied(R + "2026-09-20-sweep-findings.md"))
check("the reason names research/", "research/" in run(json.dumps(
    {"tool_name": "Write", "tool_input": {"file_path": R + "2026-09-20-x.md"}}))[1])
check("00-profile.md passes", not denied(R + "00-profile.md"))
check("init's undated 01-project-commands.md passes", not denied(R + "01-project-commands.md"))
check("legacy YYYYMMDD name is denied", denied(R + "20260920-x.md"))
check("topic module passes", not denied(R + "hooks/01-gate.md"))
check("topic index passes", not denied(R + "hooks/00-index.md"))
check("research spike passes", not denied("/w/proj/.context/research/2026-09-20-x.md"))
check("a skill's own references/ passes", not denied("/w/aidex/skills/plan/references/01-x.md"))
# An Edit never creates a file: a legacy flat file must stay editable until it is moved.
check("Edit of an existing flat file passes", not denied(R + "2026-09-20-x.md", tool="Edit"))
check("garbage stdin fails open", run("not json") == (0, ""))
check("empty stdin fails open", run("") == (0, ""))

print(f"\n{12 - len(fails)}/12")
sys.exit(1 if fails else 0)
