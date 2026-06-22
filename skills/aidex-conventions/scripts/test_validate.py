#!/usr/bin/env python3
"""Smoke tests for validate.py against fixtures/good and fixtures/bad.

Asserts that the good fixture produces zero violations, and that the bad
fixture produces every expected rule ID at least once. Run with:

    python3 skills/aidex-conventions/scripts/test_validate.py
"""
from __future__ import annotations

import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
FIXTURES = SCRIPT_DIR / "fixtures"
VALIDATOR = SCRIPT_DIR / "validate.py"
COMM_CANON = SCRIPT_DIR.parent / "references" / "communication-conventions.md"

EXPECTED_BAD_RULES = {
    "filename-format",
    "frontmatter-missing",
    "status-invalid",
    "date-format-invalid",
    "cross-ref-format-invalid",
    "cross-ref-pending",
    "cross-ref-target-missing",
    "backlog-priority-invalid",
    "communication-channel-invalid",
    "plan-phase-gateless-afk",
}

def _load_validator():
    """Import validate.py as a module to read its COMM_* constants."""
    spec = importlib.util.spec_from_file_location("validate", VALIDATOR)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["validate"] = mod  # required so @dataclass can resolve __module__
    spec.loader.exec_module(mod)
    return mod


def _canon_enum(text: str, key: str, must_contain: str) -> set[str] | None:
    """Extract the `a | b | c` enum from a `key: value  # a | b | c` YAML example
    line in the canon. Picks the enum whose tokens include `must_contain` (so the
    two `channel:` examples — async vs meeting — are told apart)."""
    for m in re.finditer(rf"^\s*{key}:\s*\S+\s+#\s*([a-z |]+)", text, re.M):
        tokens = {t.strip() for t in m.group(1).split("|") if t.strip()}
        if must_contain in tokens:
            return tokens
    return None


def check_canon_lockstep(failures: list[str]) -> None:
    """Guard (BL-023): validate.py's COMM_* enums must stay in lockstep with the
    communication-conventions.md canon. A canon edit that adds/changes a channel,
    direction, or status without updating validate.py fails here loudly — so the
    validator cannot drift behind the canon again."""
    if not COMM_CANON.exists():
        failures.append(f"canon lockstep: canon not found at {COMM_CANON}")
        return
    text = COMM_CANON.read_text(encoding="utf-8")
    v = _load_validator()
    pairs = [
        ("async channels", _canon_enum(text, "channel", "email"), v.COMM_ASYNC_CHANNELS),
        ("meeting channels", _canon_enum(text, "channel", "meeting"), v.COMM_MEETING_CHANNELS),
        ("directions", _canon_enum(text, "direction", "received"), v.COMM_DIRECTIONS),
        ("status", _canon_enum(text, "status", "draft"), v.COMM_STATUS),
    ]
    for label, canon_set, code_set in pairs:
        if canon_set is None:
            failures.append(
                f"canon lockstep: could not parse {label} enum from canon "
                f"(format changed? update this guard in test_validate.py)")
        elif canon_set != set(code_set):
            failures.append(
                f"canon lockstep [{label}]: canon={sorted(canon_set)} != "
                f"validate.py={sorted(code_set)} — update both in lockstep")


def check_phase_gate_unit(failures: list[str]) -> None:
    """Direct cells for check_plan_phase_gates (no good-fixture pollution): an afk-impl
    gateless phase warns; a gated afk-impl phase, a hitl-align phase, and a default-type
    gated phase do not."""
    v = _load_validator()
    def warns(text: str, fm: dict | None = None) -> list[str]:
        return [f.rule for f in v.check_plan_phase_gates(Path("x.md"), text, fm)]
    pos = "### Phase 1 — Do it  (phase-type: afk-impl)\n- work, no verify\n"
    if "plan-phase-gateless-afk" not in warns(pos):
        failures.append("phase-gate unit: afk-impl gateless phase did not warn")
    neg_gate = "### Phase 1 — Do it  (phase-type: afk-impl)\n- work\n\n**Verify:** `pytest`\n"
    if warns(neg_gate):
        failures.append("phase-gate unit: gated afk-impl phase warned (false positive)")
    neg_hitl = "### Phase 1 — Align  (phase-type: hitl-align)\n- decide scope, no gate\n"
    if warns(neg_hitl):
        failures.append("phase-gate unit: hitl-align phase warned (should be exempt)")
    neg_default = "### Phase 1 — Do it\n- work\n\n**Verify:** `make test`\n"
    if warns(neg_default):
        failures.append("phase-gate unit: default-type gated phase warned (false positive)")
    # multi-file phase file: gate declared in front-matter -> no warn
    neg_fm = "# Phase 1: Do it\n- work\n"
    if warns(neg_fm, {"phase-type": "afk-impl", "gate": "pytest"}):
        failures.append("phase-gate unit: front-matter-gated phase warned (false positive)")


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

    check_canon_lockstep(failures)
    check_phase_gate_unit(failures)

    if failures:
        print("FAIL")
        for f in failures:
            print(f"  {f}")
        return 1
    print(f"OK — good: 0 violations · bad: {bad['summary']['violations']} violations, "
          f"{bad['summary']['warnings']} warnings · all {len(EXPECTED_BAD_RULES)} expected rules fired "
          f"· canon lockstep OK")
    return 0

if __name__ == "__main__":
    sys.exit(main())
