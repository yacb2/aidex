#!/usr/bin/env python3
"""Smoke tests for validate.py against fixtures/good and fixtures/bad.

Asserts that the good fixture produces zero violations, and that the bad
fixture produces every expected rule ID at least once. Run with:

    python3 skills/aidex-conventions/scripts/test_validate.py
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
FIXTURES = SCRIPT_DIR / "fixtures"
VALIDATOR = SCRIPT_DIR / "validate.py"

EXPECTED_BAD_RULES = {
    "filename-format",
    "frontmatter-missing",
    "status-invalid",
    "date-format-invalid",
    "cross-ref-format-invalid",
    "cross-ref-pending",
    "cross-ref-target-missing",
    "backlog-priority-invalid",
}

def run(fixture: str) -> dict:
    ctx = FIXTURES / fixture / ".context"
    res = subprocess.run(
        [sys.executable, str(VALIDATOR), str(ctx), "--json"],
        capture_output=True, text=True,
    )
    return json.loads(res.stdout)

def main() -> int:
    failures: list[str] = []

    good = run("good")
    if good["summary"]["violations"] != 0:
        failures.append(f"good fixture: expected 0 violations, got {good['summary']['violations']}")
        for v in good["violations"]:
            failures.append(f"  unexpected: [{v['rule']}] {v['file']}: {v['message']}")

    bad = run("bad")
    if bad["summary"]["violations"] == 0:
        failures.append("bad fixture: expected >0 violations, got 0")
    rules_fired = {v["rule"] for v in bad["violations"]} | {w["rule"] for w in bad["warnings"]}
    missing = EXPECTED_BAD_RULES - rules_fired
    if missing:
        failures.append(f"bad fixture: expected rules did not fire: {sorted(missing)}")

    if failures:
        print("FAIL")
        for f in failures:
            print(f"  {f}")
        return 1
    print(f"OK — good: 0 violations · bad: {bad['summary']['violations']} violations, "
          f"{bad['summary']['warnings']} warnings · all {len(EXPECTED_BAD_RULES)} expected rules fired")
    return 0

if __name__ == "__main__":
    sys.exit(main())
