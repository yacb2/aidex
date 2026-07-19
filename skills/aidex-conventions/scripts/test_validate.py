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
    "plan-phase-missing-acceptance",
    "plan-file-oversize",
    "plan-code-heavy",
    "readme-in-context",
    "body-language-not-english",
    "audit-legacy-board-name",
    "audit-board-duplicate",
    "audit-run-legacy-name",
    "audit-run-name-invalid",
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
    # Archived plans are finished — the gateless warning is only actionable
    # pre-execution (field regression 2026-07-02: 52/53 warnings in a real
    # project were _archive/ noise).
    archived = [f.rule for f in v.check_plan_phase_gates(
        Path(".context/plans/_archive/2026-01-01-old/01-x.md"), pos, None)]
    if "plan-phase-gateless-afk" in archived:
        failures.append("phase-gate unit: archived plan warned (should be exempt — _archive/)")


def check_plan_spec_shape_unit(failures: list[str]) -> None:
    """Direct cells for check_plan_spec_shape (spec-first canon, ADR
    2026-07-19-plan-spec-first): afk-impl phases need an **Acceptance** block;
    plan files warn over the soft size budget (Execution log excluded) and when
    fenced code dominates the spec body; _archive/ and 00-index.md are exempt."""
    v = _load_validator()
    single = Path(".context/plans/2026-01-01-x.md")
    phase = Path(".context/plans/2026-01-01-x/01-slice.md")

    def rules(text: str, fm: dict | None = None, path: Path = single) -> list[str]:
        return [f.rule for f in v.check_plan_spec_shape(path, text, fm)]

    no_acc = "### Phase 1 — Do it  (phase-type: afk-impl)\n- work\n\n**Verify:** `pytest`\n"
    if "plan-phase-missing-acceptance" not in rules(no_acc):
        failures.append("spec-shape unit: afk-impl phase without Acceptance did not warn")
    with_acc = ("### Phase 1 — Do it  (phase-type: afk-impl)\n"
                "**Acceptance:**\n- reset email lands in MailHog\n\n**Verify:** `pytest`\n")
    if "plan-phase-missing-acceptance" in rules(with_acc):
        failures.append("spec-shape unit: phase with Acceptance warned (false positive)")
    hitl = "### Phase 1 — Align  (phase-type: hitl-align)\n- decide scope\n"
    if "plan-phase-missing-acceptance" in rules(hitl):
        failures.append("spec-shape unit: hitl-align phase warned (should be exempt)")
    # multi-file phase file carrying metadata in front-matter, no in-file heading
    if "plan-phase-missing-acceptance" not in rules("- work\n", {"phase-type": "afk-impl"}, phase):
        failures.append("spec-shape unit: front-matter afk-impl phase file without Acceptance did not warn")

    filler = ("English spec prose line that is deliberately long enough to add bytes.\n" * 130)
    if "plan-file-oversize" not in rules(with_acc + filler):  # ~9.5 KB > 8 KB single budget
        failures.append("spec-shape unit: 9KB+ single-file plan did not warn oversize")
    if "plan-file-oversize" in rules(with_acc):
        failures.append("spec-shape unit: small plan warned oversize (false positive)")
    logged = with_acc + "\n## Execution log\n\n" + filler
    if "plan-file-oversize" in rules(logged):
        failures.append("spec-shape unit: Execution log bytes counted against the size budget")

    code = "```python\n" + ("x = 1  # pre-written implementation line\n" * 90) + "```\n"
    if "plan-code-heavy" not in rules(with_acc + code):  # ~3.4 KB code > 50% of body
        failures.append("spec-shape unit: code-dominated plan did not warn code-heavy")
    small_code = with_acc + "```python\ndef contract(x: int) -> str: ...\n```\n"
    if "plan-code-heavy" in rules(small_code):
        failures.append("spec-shape unit: small contract block warned code-heavy (false positive)")

    archived = Path(".context/plans/_archive/2026-01-01-x.md")
    if rules(no_acc + filler + code, None, archived):
        failures.append("spec-shape unit: archived plan produced findings (should be exempt)")
    index = Path(".context/plans/2026-01-01-x/00-index.md")
    if "plan-file-oversize" in rules(filler, None, index):
        failures.append("spec-shape unit: 00-index.md warned oversize (size budgets are per plan/phase file)")


def check_crossref_prefix_coverage(failures: list[str]) -> None:
    """Guard: CROSSREF_FORMAT must accept the 'loop' and 'worktree' cross-ref
    prefixes (aidex-audit's escalate --loop already emits escalated_to:
    loop/<slug>; worktree entries use worktree/<slug>)."""
    v = _load_validator()
    if not v.CROSSREF_FORMAT.match("loop/2026-07-01-example"):
        failures.append(
            "CROSSREF_FORMAT must accept the 'loop' prefix (aidex-audit's escalate "
            "--loop already emits escalated_to: loop/<slug>)")
    if not v.CROSSREF_FORMAT.match("worktree/00-index"):
        failures.append("CROSSREF_FORMAT must accept the 'worktree' prefix")


def check_worktrees_no_double_count(good: dict, failures: list[str]) -> None:
    """Regression (found via field-testing against a real project): the
    worktrees NN-*.md glob also matches 00-index.md itself, double-yielding it
    if not excluded. The good fixture has exactly one worktrees file."""
    files = good["summary"]["by_type"].get("worktrees", {}).get("files")
    if files != 1:
        failures.append(
            f"worktrees fixture has exactly one file but validator scanned "
            f"{files} — 00-index.md is likely being double-counted by the "
            f"NN-*.md glob in iter_files_for_type()")


def check_baseline_ratchet(failures: list[str]) -> None:
    """Ratchet mode: freezing a legacy project's violations via --baseline makes the
    enforceable rule 'zero NEW violations' — a clean re-run exits 0, and only a fresh
    violation flips it back to 1, reporting exactly the new key."""
    import shutil, tempfile
    with tempfile.TemporaryDirectory() as td:
        ctx = Path(td) / ".context"
        shutil.copytree(FIXTURES / "bad" / ".context", ctx)
        def run_v(*extra):
            return subprocess.run([sys.executable, str(VALIDATOR), str(ctx), "--json", *extra],
                                  capture_output=True, text=True)
        base = subprocess.run([sys.executable, str(VALIDATOR), str(ctx), "--baseline"],
                              capture_output=True, text=True)
        if base.returncode != 0 or not (ctx / ".validate-baseline.json").is_file():
            failures.append(f"ratchet: --baseline failed (rc={base.returncode}): {base.stderr[:120]}")
            return
        clean = run_v()
        d = json.loads(clean.stdout)
        if clean.returncode != 0 or d["summary"].get("baseline", {}).get("new_violations") != 0:
            failures.append(f"ratchet: clean re-run should exit 0 with new_violations=0 "
                            f"(rc={clean.returncode}, baseline={d['summary'].get('baseline')})")
        (ctx / "decisions" / "2026-06-30-fresh-violation.md").write_text(
            "no front-matter at all\n", encoding="utf-8")
        dirty = run_v()
        d = json.loads(dirty.stdout)
        new = d.get("new_violations", [])
        if dirty.returncode != 1 or not any("fresh-violation" in x["file"] for x in new):
            failures.append(f"ratchet: fresh violation should exit 1 and be listed as NEW "
                            f"(rc={dirty.returncode}, new={[x['file'] for x in new]})")


def check_body_language_unit(failures: list[str]) -> None:
    """Direct cells for check_body_language (BL-047): a clearly-Spanish body warns;
    English, bilingual-with-quote, Spanish-in-code-fence, and Spanish-in-front-matter
    bodies stay silent; communications/ are exempt entirely."""
    v = _load_validator()
    def warns(text: str, type_name: str = "research") -> bool:
        return v.check_body_language(type_name, Path("x.md"), text) is not None
    spanish = ("Este documento describe los pasos de la migración que se realizaron "
               "sobre el esquema. Cuando el proceso termina hay que verificar que "
               "todas las tablas del sistema tienen los datos correctos, pero si algo "
               "falla se puede restaurar una copia para que todo quede como antes.")
    if not warns(spanish):
        failures.append("body-language unit: clearly-Spanish body did not warn")
    english = ("This document describes the steps of the migration that were applied "
               "to the schema. When the process finishes, verify that all the tables "
               "have the correct data and that the indexes are in place before you "
               "restore anything from the backup directory.")
    if warns(english):
        failures.append("body-language unit: English body warned (false positive)")
    bilingual = english + "\n\nThe client wrote: \"la copia de seguridad que se hizo\"."
    if warns(bilingual):
        failures.append("body-language unit: English body with a Spanish quote warned "
                        "(heuristic not conservative enough)")
    fenced = "English intro.\n\n```\n" + spanish + "\n```\n"
    if warns(fenced):
        failures.append("body-language unit: Spanish inside a code fence warned")
    fm_only = "---\ntitle: \"Notas de la migración de los datos del sistema\"\n---\nShort English body.\n"
    if warns(fm_only):
        failures.append("body-language unit: Spanish front-matter values warned (should be exempt)")
    if warns(spanish, "communications"):
        failures.append("body-language unit: communications body warned (D-04 exemption)")


def check_waivers(failures: list[str]) -> None:
    """Waiver lifecycle (BL-048): an anchored waiver suppresses its finding and
    reports it under waived; a content change or a deleted waiver line resurfaces
    it; an anchorless waiver survives content changes."""
    import hashlib, shutil, tempfile
    with tempfile.TemporaryDirectory() as td:
        ctx = Path(td) / ".context"
        shutil.copytree(FIXTURES / "bad" / ".context", ctx)
        readme = ctx / "plans" / "README.md"
        anchor = hashlib.sha256(readme.read_bytes()).hexdigest()[:12]
        def run_v() -> tuple[int, dict]:
            res = subprocess.run([sys.executable, str(VALIDATOR), str(ctx), "--json"],
                                 capture_output=True, text=True)
            return res.returncode, json.loads(res.stdout)
        def has_readme_violation(d: dict) -> bool:
            return any(x["rule"] == "readme-in-context" and x["file"] == ".context/plans/README.md"
                       for x in d["violations"])
        _, d0 = run_v()
        base_v = d0["summary"]["violations"]
        if not has_readme_violation(d0):
            failures.append("waivers: expected readme-in-context on .context/plans/README.md pre-waiver")
            return
        wfile = ctx / ".aidex-waivers"
        wfile.write_text(
            "# accepted findings\n"
            f"readme-in-context | .context/plans/README.md | sha256:{anchor} | "
            "legacy readme kept on purpose | 2026-07-04\n", encoding="utf-8")
        _, d1 = run_v()
        if has_readme_violation(d1) or d1["summary"]["violations"] != base_v - 1:
            failures.append(f"waivers: anchored waiver did not suppress the finding "
                            f"(violations {d1['summary']['violations']} vs {base_v - 1})")
        if d1["summary"].get("waived") != 1 or not any(
                x["rule"] == "readme-in-context" for x in d1.get("waived", [])):
            failures.append("waivers: suppressed finding not counted/listed under waived")
        # Content change -> anchor mismatch -> finding resurfaces.
        readme.write_text(readme.read_text(encoding="utf-8") + "\nchanged\n", encoding="utf-8")
        _, d2 = run_v()
        if not has_readme_violation(d2) or d2["summary"].get("waived") != 0:
            failures.append("waivers: finding did not resurface after the anchored content changed")
        # Anchorless waiver ("-") keeps matching regardless of content.
        wfile.write_text("readme-in-context | .context/plans/README.md | - | accepted\n",
                         encoding="utf-8")
        _, d3 = run_v()
        if has_readme_violation(d3) or d3["summary"].get("waived") != 1:
            failures.append("waivers: anchorless waiver did not suppress after content change")
        # Waiver line removed -> finding resurfaces; bad lines are counted, not swallowed.
        wfile.write_text("# nothing left\nmalformed line without pipes\n", encoding="utf-8")
        _, d4 = run_v()
        if not has_readme_violation(d4):
            failures.append("waivers: finding did not resurface after the waiver line was removed")
        if d4["summary"].get("waiver_parse_errors") != 1:
            failures.append("waivers: unparseable waiver line was not counted")


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
    check_plan_spec_shape_unit(failures)
    check_crossref_prefix_coverage(failures)
    check_worktrees_no_double_count(good, failures)
    check_baseline_ratchet(failures)
    check_body_language_unit(failures)
    check_waivers(failures)

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
