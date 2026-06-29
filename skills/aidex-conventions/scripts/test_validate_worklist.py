#!/usr/bin/env python3
"""Focused tests for validate-worklist.py. Run: python3 test_validate_worklist.py"""
import importlib.util, tempfile, os, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("vw", HERE / "validate-worklist.py")
vw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vw)

VALID = """---
title: "t"
status: doing
created: 2026-06-29
updated: 2026-06-29
gate-policy:
  publish: ask
  destructive: deny
---
# t
## Queue (in execution order)
1. [ ] BL-1 — do a   <!-- ref: backlog -->
2. [x] inline — do b   <!-- ref: inline -->

## Deferred / emergent
- [ ] inline — c
"""

CASES = [
    ("valid", VALID, 0),
    ("unnumbered-queue", VALID.replace("1. [ ] BL-1", "- [ ] BL-1"), 1),       # item drops out → queue-empty/order
    ("missing-ref", VALID.replace("   <!-- ref: backlog -->", ""), 1),          # no ref comment
    ("bad-status", VALID.replace("status: doing", "status: wip"), 1),           # status vocab
    ("publish-not-gated", VALID.replace("publish: ask", "publish: yolo"), 1),   # gate-policy.publish
    ("destructive-not-deny", VALID.replace("destructive: deny", "destructive: allow"), 1),
    ("missing-title", VALID.replace('title: "t"', ""), 1),
]

def run():
    failed = 0
    for name, content, expect_violations in CASES:
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as fh:
            fh.write(content); p = fh.name
        try:
            findings = vw.validate(Path(p))
        finally:
            os.unlink(p)
        has = len(findings) > 0
        want = expect_violations > 0
        ok = has == want
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}: "
              f"{'violations' if has else 'clean'} (expected {'violations' if want else 'clean'})")
        if not ok:
            failed += 1
            for x in findings:
                print(f"       - {x['rule']}: {x['message']}")
    if failed:
        print(f"\n{failed} test(s) FAILED"); sys.exit(1)
    print(f"\nall {len(CASES)} worklist validator tests passed")

if __name__ == "__main__":
    run()
