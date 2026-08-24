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
PLAN_CANON = SCRIPT_DIR.parent / "references" / "plan-conventions.md"

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
    "communication-legacy-body-name",
    "communication-direction-mismatch",
    "communication-paste-unsafe",
    "plan-phase-gateless-afk",
    "plan-phase-missing-acceptance",
    "plan-phase-tests-missing",
    "plan-phase-tests-invalid",
    "plan-phase-tests-none-no-reason",
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
    for m in re.finditer(rf"^\s*{key}:\s*\S+\s+#\s*([a-z0-9 |]+)", text, re.M):
        tokens = {t.strip() for t in m.group(1).split("|") if t.strip()}
        if must_contain in tokens:
            return tokens
    return None


def check_canon_lockstep(failures: list[str]) -> None:
    """Guard (BL-023): validate.py's COMM_* enums must stay in lockstep with the
    communication-conventions.md canon. A canon edit that adds/changes a channel,
    direction, or status without updating validate.py fails here loudly — so the
    validator cannot drift behind the canon again. Also guards PLAN_TESTS_VOCAB
    against plan-conventions.md's `tests:` canon line (Phase 7, tests: field)."""
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
    if not PLAN_CANON.exists():
        failures.append(f"canon lockstep: canon not found at {PLAN_CANON}")
    else:
        plan_text = PLAN_CANON.read_text(encoding="utf-8")
        pairs.append(("plan tests vocab", _canon_enum(plan_text, "tests", "e2e"), v.PLAN_TESTS_VOCAB))
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


def check_plan_tests_field_unit(failures: list[str]) -> None:
    """Direct cells for check_plan_tests_field (Phase 7, tests: field): an afk-impl
    phase with no `tests:` warns missing; an out-of-vocabulary value warns invalid;
    `tests: none` with no reason comment warns; a valid value, a written reason, a
    list of valid values, and hitl-align/_archive all pass clean."""
    v = _load_validator()
    def rules(text: str, fm: dict | None = None,
              path: Path = Path("x.md")) -> list[str]:
        return [f.rule for f in v.check_plan_tests_field(path, text, fm)]

    missing = "### Phase 1 — Do it  (phase-type: afk-impl)\n**Acceptance:**\n- x\n\n**Verify:** `pytest`\n"
    if "plan-phase-tests-missing" not in rules(missing):
        failures.append("tests-field unit: afk-impl phase with no tests: did not warn missing")

    # Weekend review 2026-08-23, finding 4: a declared-but-EMPTY field parsed to
    # [] and validated cleaner than no field at all — the value regex admits a
    # bare space, so `tests: )` slipped past both missing and invalid.
    empty = "### Phase 1 — Do it  (phase-type: afk-impl, tests: )\n**Acceptance:**\n- x\n\n**Verify:** `pytest`\n"
    if "plan-phase-tests-missing" not in rules(empty):
        failures.append("tests-field unit: afk-impl phase with EMPTY tests: did not warn missing")

    valid = "### Phase 1 — Do it  (phase-type: afk-impl, tests: unit)\n**Acceptance:**\n- x\n\n**Verify:** `pytest`\n"
    if rules(valid):
        failures.append("tests-field unit: valid tests: unit warned (false positive)")

    invalid = "### Phase 1 — Do it  (phase-type: afk-impl, tests: fuzz)\n**Acceptance:**\n- x\n\n**Verify:** `pytest`\n"
    if "plan-phase-tests-invalid" not in rules(invalid):
        failures.append("tests-field unit: out-of-vocabulary tests: value did not warn invalid")

    none_no_reason = "### Phase 1 — Do it  (phase-type: afk-impl, tests: none)\n**Acceptance:**\n- x\n\n**Verify:** `pytest`\n"
    if "plan-phase-tests-none-no-reason" not in rules(none_no_reason):
        failures.append("tests-field unit: tests: none with no reason did not warn")

    none_reason = ("### Phase 1 — Do it  (phase-type: afk-impl, tests: none)  "
                   "# reason: config only, no code path to assert on\n"
                   "**Acceptance:**\n- x\n\n**Verify:** `pytest`\n")
    if "plan-phase-tests-none-no-reason" in rules(none_reason):
        failures.append("tests-field unit: tests: none with a written reason still warned (false positive)")

    none_mixed = "### Phase 1 — Do it  (phase-type: afk-impl, tests: [unit, none])\n**Acceptance:**\n- x\n\n**Verify:** `pytest`\n"
    if "plan-phase-tests-invalid" not in rules(none_mixed):
        failures.append("tests-field unit: tests: [unit, none] (none mixed with other values) did not warn invalid")

    valid_list = "### Phase 1 — Do it  (phase-type: afk-impl, tests: [unit, api])\n**Acceptance:**\n- x\n\n**Verify:** `pytest`\n"
    if rules(valid_list):
        failures.append("tests-field unit: valid tests: [unit, api] list warned (false positive)")

    hitl = "### Phase 1 — Align  (phase-type: hitl-align)\n- decide scope\n"
    if rules(hitl):
        failures.append("tests-field unit: hitl-align phase warned (should be exempt)")

    # multi-file phase file: tests: carried in front-matter
    fm_missing = "# Phase 1: Do it\n**Acceptance:**\n- x\n\n**Verify:** `pytest`\n"
    if "plan-phase-tests-missing" not in rules(fm_missing, {"phase-type": "afk-impl", "gate": "pytest"}):
        failures.append("tests-field unit: front-matter afk-impl phase with no tests: did not warn missing")
    if rules(fm_missing, {"phase-type": "afk-impl", "gate": "pytest", "tests": "e2e"}):
        failures.append("tests-field unit: front-matter tests: e2e warned (false positive)")
    if "plan-phase-tests-none-no-reason" not in rules(
            "---\nphase-type: afk-impl\ngate: pytest\ntests: none\n---\n# Phase 1: Do it\n"
            "**Acceptance:**\n- x\n\n**Verify:** `pytest`\n",
            {"phase-type": "afk-impl", "gate": "pytest", "tests": "none"}):
        failures.append("tests-field unit: front-matter tests: none with no reason comment did not warn")
    if "plan-phase-tests-none-no-reason" in rules(
            "---\nphase-type: afk-impl\ngate: pytest\ntests: none  # reason: config only\n---\n"
            "# Phase 1: Do it\n**Acceptance:**\n- x\n\n**Verify:** `pytest`\n",
            {"phase-type": "afk-impl", "gate": "pytest", "tests": "none"}):
        failures.append("tests-field unit: front-matter tests: none with a written reason still warned (false positive)")

    # Archived plans are finished — exempt, same as the gate/acceptance checks.
    archived_path = Path(".context/plans/_archive/2026-01-01-old/01-x.md")
    if rules(missing, None, archived_path):
        failures.append("tests-field unit: archived plan warned (should be exempt — _archive/)")

    # 'Phase N Checkpoint' sections must not be treated as a phase.
    checkpoint = valid + "\n## Phase 1 Checkpoint\n\n- [ ] Task 1.1: brief\n"
    if rules(checkpoint):
        failures.append("tests-field unit: 'Phase N Checkpoint' section treated as a phase (FP)")

    # Regression: a phase title that mentions "tests:" in prose (as this very
    # field's own phase does — "the `tests:` phase field") must not be misread
    # as a declaration; it should fall through to the correct front-matter value.
    prose = ("### Phase 7 (q1, q2): the `tests:` phase field  (phase-type: afk-impl)\n"
             "**Acceptance:**\n- x\n\n**Verify:** `pytest`\n")
    if rules(prose, {"phase-type": "afk-impl", "gate": "pytest", "tests": "unit"}):
        failures.append("tests-field unit: `tests:` mentioned in heading prose read as a declaration (FP)")


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
    # Regression (2026-07-19, found by the check flagging its own remediation plan):
    # "## Phase N Checkpoint" sections match the phase-heading regex and must be
    # excluded from phase splitting — in BOTH the acceptance and the gates check.
    checkpoint = with_acc + "\n## Phase 1 Checkpoint\n\n- [ ] Task 1.1: brief\n"
    if "plan-phase-missing-acceptance" in rules(checkpoint):
        failures.append("spec-shape unit: 'Phase N Checkpoint' section treated as a phase (acceptance FP)")
    if "plan-phase-gateless-afk" in [f.rule for f in v.check_plan_phase_gates(single, checkpoint, None)]:
        failures.append("phase-gate unit: 'Phase N Checkpoint' section treated as a phase (gateless FP)")
    index = Path(".context/plans/2026-01-01-x/00-index.md")
    if "plan-file-oversize" in rules(filler, None, index):
        failures.append("spec-shape unit: 00-index.md warned oversize (size budgets are per plan/phase file)")


def check_plan_scoped_shape_unit(failures: list[str]) -> None:
    """Direct cells for check_plan_scoped_shape (plan-conventions.md § Plan mode).
    The scoped mode's whole claim is that its caps are mechanical rather than prose,
    so each cap gets a positive and the backwards-compat case gets a negative."""
    v = _load_validator()
    single = Path(".context/plans/2026-01-01-x.md")
    scoped = {"mode": "scoped"}

    def rules(text: str, fm: dict | None = scoped, path: Path = single) -> list[str]:
        return [f.rule for f in v.check_plan_scoped_shape(path, text, fm)]

    ok = ("---\nmode: scoped\n---\n\n"
          "## Phase 1 — Add the panel search\n\n"
          "**Acceptance:**\n- typing filters the scripts panel\n\n"
          "**Out of scope:** the timeline search\n\n"
          "**Files:**\n- Modify: `src/panels/ScriptPanel.tsx`\n\n"
          "**Verify:** `pnpm vitest run ScriptPanel`\n")
    if rules(ok):
        failures.append(f"scoped unit: conforming scoped plan fired {rules(ok)} (false positive)")

    # Every finding is a violation, never a warning — the mechanical-gate claim.
    sevs = {f.severity for f in v.check_plan_scoped_shape(single, "---\nmode: scoped\n---\n", scoped)}
    if sevs != {"violation"}:
        failures.append(f"scoped unit: expected only violations, got severities {sorted(sevs)}")

    two = ok + "\n## Phase 2 — And the timeline\n\n**Verify:** `pnpm vitest run Timeline`\n"
    if "plan-scoped-phase-count" not in rules(two):
        failures.append("scoped unit: two-phase scoped plan did not fire plan-scoped-phase-count")

    # Found by reviewing this function with aidex-review (correctness / edge-and-error),
    # verified against the live validator: the canon says "exactly one phase", and a
    # `> 1` test passes a plan with ZERO phases — which has no Goal or Acceptance for
    # the necessity recheck to pair files against, yet reported clean.
    zero = ("---\nmode: scoped\n---\n\n# Zero phase\n\n"
            "**Out of scope:** everything else.\n\n"
            "**Files:**\n- Modify: `src/a.py`\n\n**Verify:** `pytest`\n")
    if "plan-scoped-phase-count" not in rules(zero):
        failures.append("scoped unit: zero-phase scoped plan did not fire plan-scoped-phase-count")

    # Regression: '## Phase N Checkpoint' matches PHASE_HEADING_RE but is a tracking
    # section, not a phase — a scoped plan carrying one must still read as one phase.
    with_ckpt = ok + "\n## Phase 1 Checkpoint\n\n- [ ] Task 1.1: wire the filter\n"
    if "plan-scoped-phase-count" in rules(with_ckpt):
        failures.append("scoped unit: 'Phase 1 Checkpoint' counted as a second phase")

    no_files = ok.replace("**Files:**\n- Modify: `src/panels/ScriptPanel.tsx`\n\n", "")
    if "plan-scoped-no-file-contract" not in rules(no_files):
        failures.append("scoped unit: missing **Files:** did not fire plan-scoped-no-file-contract")

    no_bound = ok.replace("**Out of scope:** the timeline search\n\n", "")
    if "plan-scoped-no-boundary" not in rules(no_bound):
        failures.append("scoped unit: missing **Out of scope:** did not fire plan-scoped-no-boundary")

    empty_bound = ok.replace("**Out of scope:** the timeline search", "**Out of scope:**")
    if "plan-scoped-no-boundary" not in rules(empty_bound):
        failures.append("scoped unit: empty **Out of scope:** did not fire plan-scoped-no-boundary")

    # A list-form boundary is legitimate — the phase template writes non-goals as bullets.
    list_bound = ok.replace("**Out of scope:** the timeline search",
                            "**Out of scope:**\n- the timeline search")
    if "plan-scoped-no-boundary" in rules(list_bound):
        failures.append("scoped unit: list-form **Out of scope:** fired (false positive)")

    no_gate = ok.replace("**Verify:** `pnpm vitest run ScriptPanel`\n", "")
    if "plan-scoped-no-machine-gate" not in rules(no_gate):
        failures.append("scoped unit: gateless scoped plan did not fire plan-scoped-no-machine-gate")

    # Backwards compatibility: this is what protects every plan written before the mode.
    bare = "## Phase 1 — Do it\n\n## Phase 2 — Do more\n"
    if rules(bare, fm=None) or rules(bare, fm={"status": "open"}) or rules(bare, fm={"mode": "full"}):
        failures.append("scoped unit: a plan without mode: scoped fired scoped rules")

    archived = Path(".context/plans/_archive/2026-01-01-old.md")
    if rules("---\nmode: scoped\n---\n", path=archived):
        failures.append("scoped unit: archived scoped plan fired (should be exempt — _archive/)")


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


def check_baseline_key_granularity(failures: list[str]) -> None:
    """BL-043: the v1 `file|rule` baseline key masked a NEW violation of a rule the
    file was ALREADY dirty for. The v2 key adds the message, so a second missing
    cross-ref in an already-baselined file is reported. A v1 baseline (no version
    field) keeps matching on the coarse key — an existing baseline must never
    silently turn its whole accepted set into NEW violations."""
    import json as _json, shutil, tempfile
    target = Path("decisions") / "2026-05-14-pending-ref.md"
    with tempfile.TemporaryDirectory() as td:
        ctx = Path(td) / ".context"
        shutil.copytree(FIXTURES / "bad" / ".context", ctx)
        bp = ctx / ".validate-baseline.json"

        def run_v() -> tuple[int, dict]:
            res = subprocess.run([sys.executable, str(VALIDATOR), str(ctx), "--json"],
                                 capture_output=True, text=True)
            return res.returncode, _json.loads(res.stdout)

        freeze = subprocess.run([sys.executable, str(VALIDATOR), str(ctx), "--baseline"],
                                capture_output=True, text=True)
        if "accepted keys from" not in freeze.stdout:
            failures.append(f"baseline granularity: freeze line must report keys AND raw "
                            f"violations (got {freeze.stdout.strip()!r})")
        data = _json.loads(bp.read_text(encoding="utf-8"))
        if data.get("version") != 2:
            failures.append(f"baseline granularity: written baseline must be version 2 "
                            f"(got {data.get('version')!r})")

        # A SECOND missing cross-ref in the same already-baselined file: same
        # file, same rule, new message -> must surface as NEW under v2.
        text = (ctx / target).read_text(encoding="utf-8")
        text = text.replace("origin_ref: plan/2099-12-31-does-not-exist",
                            "origin_ref: plan/2099-12-31-does-not-exist\n"
                            "blocked_by: plan/2099-12-31-also-missing")
        (ctx / target).write_text(text, encoding="utf-8")
        rc, d = run_v()
        new = d.get("new_violations", [])
        if rc != 1 or not any("also-missing" in x["message"] for x in new):
            failures.append(f"baseline granularity: a NEW violation of an already-accepted "
                            f"rule in the same file was masked (rc={rc}, new={len(new)})")

        # Same state re-keyed as a v1 baseline: the coarse key still matches, so
        # the run stays green and the report says the baseline needs refreshing.
        data["keys"] = sorted({"|".join(k.split("|")[:2]) for k in data["keys"]})
        data.pop("version", None)
        bp.write_text(_json.dumps(data, indent=2) + "\n", encoding="utf-8")
        rc, d = run_v()
        if rc != 0 or d["summary"]["baseline"].get("version") != 1:
            failures.append(f"baseline granularity: a v1 baseline must keep matching on the "
                            f"coarse key (rc={rc}, summary={d['summary'].get('baseline')})")
        plain = subprocess.run([sys.executable, str(VALIDATOR), str(ctx)],
                               capture_output=True, text=True)
        if "refresh with --baseline" not in plain.stdout:
            failures.append("baseline granularity: v1 baseline did not print the refresh notice")

        # Refresh policy: an accepted violation that is gone is reported, not
        # auto-dropped — a validation run must never mutate the baseline.
        subprocess.run([sys.executable, str(VALIDATOR), str(ctx), "--baseline"],
                       capture_output=True, text=True)
        frozen = bp.read_text(encoding="utf-8")
        (ctx / target).unlink()
        rc, d = run_v()
        if d["summary"]["baseline"].get("resolved", 0) < 1:
            failures.append("baseline granularity: resolved (no-longer-present) accepted "
                            "keys were not reported")
        if bp.read_text(encoding="utf-8") != frozen:
            failures.append("baseline granularity: baseline file was mutated by a read-only run")


def check_waived_is_not_resolved(failures: list[str]) -> None:
    """A WAIVED violation is still present. Reporting it as resolved advises a
    refresh that would drop it from the baseline — the two suppression mechanisms
    cancelling each other out and quietly loosening the ratchet.

    The asymmetry was structural: the baseline is WRITTEN from `prewaiver_violations`
    but `resolved` was computed against the POST-waiver list, so every waiver made
    its own baselined key look like it had been fixed.
    """
    import shutil, tempfile
    with tempfile.TemporaryDirectory() as td:
        ctx = Path(td) / ".context"
        shutil.copytree(FIXTURES / "bad" / ".context", ctx)
        base = subprocess.run([sys.executable, str(VALIDATOR), str(ctx), "--baseline"],
                              capture_output=True, text=True)
        if base.returncode != 0:
            failures.append(f"waived-vs-resolved: --baseline failed rc={base.returncode}")
            return

        # Waive one violation that is STILL in the tree, and is in the baseline.
        target = "backlog/2026-05-14-no-frontmatter.md"
        (ctx / ".aidex-waivers").write_text(
            f"frontmatter-missing | .context/{target} | - | pinned by test | 2026-08-17\n",
            encoding="utf-8")
        run = subprocess.run(
            [sys.executable, str(VALIDATOR), str(ctx), "--json"],
            capture_output=True, text=True)
        d = json.loads(run.stdout)
        s = d["summary"]

        if s.get("waived") != 1:
            failures.append(f"waived-vs-resolved: fixture did not waive exactly one "
                            f"finding (waived={s.get('waived')}) — cannot exercise the bug")
            return
        if not (ctx / target).is_file():
            failures.append("waived-vs-resolved: the waived file must still exist")
        if s["baseline"].get("resolved", 0) != 0:
            failures.append(
                f"waived-vs-resolved: a waived-but-still-present violation was reported "
                f"as no-longer-present (resolved={s['baseline']['resolved']}); refreshing "
                f"on that advice would silently drop it from the baseline")


def check_html_body_language(failures: list[str]) -> None:
    """Rendered pages are the artifacts most often read, and every rule was blind to
    them because the walkers yielded only `*.md`.

    The load-bearing half is the NEGATIVE: `.html` is enumerated per type, so
    check_body_language's communications exemption carries. A flat rglob over
    .context/ would flag every Spanish `email.html` twin — the language check
    contradicting the language canon, which exempts communications by name (D-04).
    """
    v = _load_validator()

    # script/style contents must not count as language evidence: a JS object full
    # of English-looking keys would drown out a Spanish page.
    stripped = v.strip_html(
        "<script>var x={the:1,and:2,with:3,that:4,from:5}</script>"
        "<style>.a{from:x}</style><p>hola</p>")
    if "the" in stripped or "and" in stripped:
        failures.append(f"html language: script/style contents leaked into the "
                        f"language sample: {stripped!r}")
    if "hola" not in stripped:
        failures.append(f"html language: visible text was stripped away: {stripped!r}")

    spanish = ("<h1>Informe</h1><p>Este es el informe de la migracion que hemos hecho "
               "para el equipo, con las decisiones que se tomaron y por que se "
               "tomaron, para que todos los cambios queden documentados.</p>")
    if v.check_body_language("research", Path("r.html"), v.strip_html(spanish)) is None:
        failures.append("html language: a Spanish rendered report under research/ "
                        "was not flagged")
    if v.check_body_language("communications", Path("email.html"),
                             v.strip_html(spanish)) is not None:
        failures.append("html language: a Spanish email.html under communications/ was "
                        "flagged — D-04 exempts communications by name, and this is the "
                        "reason .html must be enumerated per type rather than by rglob")

    # And the walker itself only reaches known types, so a page under a type dir
    # is seen while the enumeration stays type-scoped.
    import shutil, tempfile
    with tempfile.TemporaryDirectory() as td:
        ctx = Path(td) / ".context"
        shutil.copytree(FIXTURES / "bad" / ".context", ctx)
        found = {p.name for p in v.iter_html_for_type(ctx, "research")}
        if "2026-06-20-informe-migracion.html" not in found:
            failures.append(f"html language: the research walker did not yield the "
                            f"fixture page (found={sorted(found)})")


def check_external_crossrefs(failures: list[str]) -> None:
    """BL-070: refs whose target lives outside this .context/ — `issue/<id>` and the
    cross-repo `<repo>/BL-NNN` written by aidex-backlog's --escalate-to — are accepted
    on format alone. Local `<type>/…` refs stay resolvable, so typos in them still fail."""
    v = _load_validator()
    for ref in ("echo_lab_ws/BL-206", "issue/GH-1234", "aidex/BL-70"):
        if not v.is_external_ref(ref):
            failures.append(f"external cross-ref: {ref!r} should be recognised as external")
    for ref in ("backlog/2026-01-01-x", "plan/BL-206", "FCM/APNs credentials",
                "decision/pending"):
        if v.is_external_ref(ref):
            failures.append(f"external cross-ref: {ref!r} must NOT be treated as external")

    ctx = FIXTURES / "good" / ".context"
    def rules(fm: dict) -> list[str]:
        return [f.rule for f in v.check_crossrefs("backlog", Path("x.md"), fm, ctx)]
    for fm in ({"escalated_to": "echo_lab_ws/BL-206"}, {"origin_ref": "issue/GH-1234"}):
        if rules(fm):
            failures.append(f"external cross-ref: {fm} produced findings {rules(fm)}")
    if "cross-ref-target-missing" not in rules({"escalated_to": "plan/2099-12-31-nope"}):
        failures.append("external cross-ref: a local ref to a missing target must still fail")


def check_ignored_subtrees(failures: list[str]) -> None:
    """BL-037: a vendored/imported subtree listed in `<context>/.aidex-ignore` is
    exempt from every validator rule and reported as an `ignored` count, never
    silently dropped. Without the file, the same subtree is still judged."""
    import shutil, tempfile
    with tempfile.TemporaryDirectory() as td:
        ctx = Path(td) / ".context"
        shutil.copytree(FIXTURES / "good" / ".context", ctx)
        vendored = ctx / "research" / "vendor-upstream"
        vendored.mkdir(parents=True)
        (vendored / "README.md").write_text("Third-party readme, no front-matter.\n",
                                            encoding="utf-8")
        (vendored / "CONTRIBUTING.md").write_text("Also third-party.\n", encoding="utf-8")

        def run_v() -> dict:
            res = subprocess.run([sys.executable, str(VALIDATOR), str(ctx), "--json"],
                                 capture_output=True, text=True)
            return json.loads(res.stdout)

        before = run_v()
        if before["summary"]["violations"] == 0:
            failures.append("ignored subtrees: vendored files produced no violations to begin "
                            "with — the fixture no longer exercises the exemption")
        (ctx / ".aidex-ignore").write_text(
            "# imported upstream tree, not an aidex artifact\n"
            ".context/research/vendor-upstream\n", encoding="utf-8")
        after = run_v()
        if after["summary"]["violations"] != 0:
            failures.append(f"ignored subtrees: .aidex-ignore did not exempt the subtree "
                            f"({after['summary']['violations']} violations remain)")
        if after["summary"].get("ignored") != 2:
            failures.append(f"ignored subtrees: skipped files must be reported as an ignored "
                            f"count (got {after['summary'].get('ignored')!r}, expected 2)")


def check_artifact_prev_skipped(failures: list[str]) -> None:
    """BL-176: `.aidex-artifact-prev/` is wrap_report.py's baseline store, not a
    tier of `.context/`. Every file in it is a superseded copy of a page already
    judged at its canonical path, so judging the snapshot reports the same page
    twice — and a waiver cannot settle it, because the anchor is a hash of a file
    the next passing run replaces.

    Asserted as a PAIR. A test that only checked for silence would also pass if
    the walkers stopped reaching the type at all, which is how an exemption test
    quietly turns into a test of nothing."""
    import shutil, tempfile
    spanish = ("<html><body><p>Este informe describe la migracion de los datos y "
               "las decisiones que se tomaron para que el equipo pueda revisar el "
               "resultado de cada una de las fases del trabajo.</p></body></html>\n")
    with tempfile.TemporaryDirectory() as td:
        ctx = Path(td) / ".context"
        shutil.copytree(FIXTURES / "good" / ".context", ctx)
        research = ctx / "research"
        (research / "2026-06-20-informe.html").write_text(spanish, encoding="utf-8")
        prev = research / ".aidex-artifact-prev"
        prev.mkdir()
        (prev / "2026-06-20-informe.html").write_text(spanish, encoding="utf-8")
        # The markdown walker must skip it too: what is exempt is the directory,
        # not one extension.
        (prev / "Not A Valid Name.md").write_text("no front-matter here\n",
                                                  encoding="utf-8")

        res = subprocess.run([sys.executable, str(VALIDATOR), str(ctx), "--json"],
                             capture_output=True, text=True)
        out = json.loads(res.stdout)
        flagged = {f["file"] for f in out["violations"] + out["warnings"]}
        if not any(f.endswith("research/2026-06-20-informe.html") for f in flagged):
            failures.append("artifact-prev: the canonical Spanish page was not flagged, "
                            "so this test no longer discriminates")
        leaked = sorted(f for f in flagged if ".aidex-artifact-prev/" in f)
        if leaked:
            failures.append(f"artifact-prev: baseline snapshots were judged: {leaked}")


def check_baseline_scoped_write(failures: list[str]) -> None:
    """A scoped run must never be able to shrink or contradict the ratchet.

    Regression (deep audit 2026-07-25): `--baseline` froze the *type-filtered*,
    *post-waiver* violation set. Two symptoms from one line:
      A. `--type X --baseline` wrote a baseline containing only type X, so every other
         type's already-accepted debt came back as a NEW violation (rc=1) on the next
         full run — reachable by following the scoped commands 8 SKILL.md files prescribe.
      B. a filtered run reported the unscanned types' accepted keys as "no longer
         present", advising a --baseline refresh that destroys them. A filtered run
         cannot distinguish 'fixed' from 'not scanned', so it must not claim either.
    """
    import shutil, tempfile
    with tempfile.TemporaryDirectory() as td:
        ctx = Path(td) / ".context"
        shutil.copytree(FIXTURES / "bad" / ".context", ctx)

        def v(*extra):
            return subprocess.run([sys.executable, str(VALIDATOR), str(ctx), *extra],
                                  capture_output=True, text=True)

        full = v("--baseline")
        if full.returncode != 0:
            failures.append(f"scoped-baseline: full --baseline failed rc={full.returncode}")
            return
        bp = ctx / ".validate-baseline.json"
        accepted_full = len(json.loads(bp.read_text())["keys"])
        if accepted_full == 0:
            failures.append("scoped-baseline: fixture froze 0 keys — cannot exercise the bug")
            return

        # (A) a scoped --baseline must not be able to discard the other types' debt.
        scoped = v("--type", "decisions", "--baseline")
        if scoped.returncode == 0:
            accepted_after = len(json.loads(bp.read_text())["keys"])
            if accepted_after < accepted_full:
                failures.append(
                    f"scoped-baseline (A): `--type decisions --baseline` shrank the frozen set "
                    f"{accepted_full} -> {accepted_after}; the other types' accepted debt is now "
                    f"unfrozen and will report as NEW")
        elif "--type" not in (scoped.stderr + scoped.stdout):
            failures.append("scoped-baseline (A): scoped --baseline refused but did not say why "
                            "(the error must name --type so the user can act on it)")

        # A full run after the scoped attempt must still be clean.
        after = subprocess.run([sys.executable, str(VALIDATOR), str(ctx), "--json"],
                               capture_output=True, text=True)
        d = json.loads(after.stdout)
        nv = d["summary"].get("baseline", {}).get("new_violations")
        if after.returncode != 0 or nv:
            failures.append(f"scoped-baseline (A): a scoped --baseline must not turn accepted debt "
                            f"into NEW violations (rc={after.returncode}, new_violations={nv})")

        # (B) a filtered run must not advertise unscanned keys as resolved.
        filt = v("--type", "references")
        if "no longer present" in filt.stdout:
            failures.append("scoped-baseline (B): a --type run claims accepted keys are "
                            "'no longer present' — it cannot distinguish fixed from not-scanned")


def check_ignored_visible_in_plain(failures: list[str]) -> None:
    """`ignored: N` must be visible in DEFAULT output, not only in --json.

    Regression (deep audit 2026-07-25): two always-on promises — rules/aidex-conventions.md
    "Skipped files are reported as an `ignored: N` count" and 00-global.md "visible rather
    than silent" — were kept only in the --json branch. Plain output printed
    "scanned: 0 · violations: 0" and "OK — no violations" for a tree whose files had all
    been silently exempted, while the sibling suppression mechanism (`waived`) IS printed.
    """
    import shutil, tempfile
    with tempfile.TemporaryDirectory() as td:
        ctx = Path(td) / ".context"
        shutil.copytree(FIXTURES / "good" / ".context", ctx)
        vendored = ctx / "research" / "vendor-upstream"
        vendored.mkdir(parents=True)
        (vendored / "README.md").write_text("Third-party, no front-matter.\n", encoding="utf-8")
        (ctx / ".aidex-ignore").write_text(".context/research/vendor-upstream\n", encoding="utf-8")

        plain = subprocess.run([sys.executable, str(VALIDATOR), str(ctx)],
                               capture_output=True, text=True)
        if "ignored:" not in plain.stdout:
            failures.append("ignored-visible: plain output omits `ignored:` while files were "
                            "exempted — the always-on rule promises the count is visible")
        if "vendor-upstream" not in plain.stdout:
            failures.append("ignored-visible: plain output does not name the matched ignore "
                            "prefix, so the user cannot tell WHAT was exempted")


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


def check_archive_status_open_unit(failures: list[str]) -> None:
    """Direct cells for check_archive_status_open (Phase 4, registry-lag family):
    an archived work item still open/doing warns; a properly-closed archived item,
    an active-root open item, a loop STATE sidecar, and a non-archive-bearing type
    stay silent."""
    v = _load_validator()
    def result(type_name: str, p: str, fm: dict | None):
        return v.check_archive_status_open(type_name, Path(p), fm)
    if result("backlog", ".context/backlog/_archive/2026-01-01-x.md", {"status": "open"}) is None:
        failures.append("archive-status-open unit: archived open backlog item did not warn")
    if result("loops", ".context/loops/_archive/2026-01-01-x.md", {"status": "doing"}) is None:
        failures.append("archive-status-open unit: archived doing loop spec did not warn")
    if result("backlog", ".context/backlog/_archive/2026-01-01-x.md", {"status": "done"}) is not None:
        failures.append("archive-status-open unit: properly-closed archived item warned (false positive)")
    if result("backlog", ".context/backlog/2026-01-01-x.md", {"status": "open"}) is not None:
        failures.append("archive-status-open unit: active-root open item warned (only _archive/ counts)")
    if result("loops", ".context/loops/_archive/skill-eval-speedup-STATE.md", {"status": "doing"}) is not None:
        failures.append("archive-status-open unit: loop STATE sidecar warned (should be exempt)")
    if result("references", ".context/references/x/_archive/01-x.md", {"status": "open"}) is not None:
        failures.append("archive-status-open unit: non-archive-bearing type warned")


def check_backlog_placeholder_body_unit(failures: list[str]) -> None:
    """Direct cells for check_backlog_placeholder_body (Phase 4): an active entry
    still carrying a register-template placeholder comment warns; a filled-in entry
    and an archived entry stay silent."""
    v = _load_validator()
    active = Path(".context/backlog/2026-01-01-x.md")
    placeholder = ("---\ntitle: x\nstatus: open\n---\n# X\n\n## Context\n\n"
                   "<!-- Why is this worth doing? What problem does it solve? -->\n\n"
                   "## Acceptance\n\n- [ ] <!-- concrete, verifiable criterion -->\n")
    if v.check_backlog_placeholder_body(active, placeholder) is None:
        failures.append("placeholder-body unit: active entry with template placeholders did not warn")
    filled = ("---\ntitle: x\nstatus: open\n---\n# X\n\n## Context\n\nReal reason.\n\n"
              "## Acceptance\n\n- [ ] real criterion\n")
    if v.check_backlog_placeholder_body(active, filled) is not None:
        failures.append("placeholder-body unit: filled-in entry warned (false positive)")
    archived = Path(".context/backlog/_archive/2026-01-01-x.md")
    if v.check_backlog_placeholder_body(archived, placeholder) is not None:
        failures.append("placeholder-body unit: archived entry warned (should be exempt)")


def check_backlog_type_unit(failures: list[str]) -> None:
    """Direct cells for check_backlog_type (ADR 2026-07-23 type facet): a valid
    type is silent; an out-of-enum value is a violation; an absent value warns on
    an active item but is exempt when archived (warn-then-ratchet, no retro-fix)."""
    v = _load_validator()
    active = Path(".context/backlog/2026-01-01-x.md")
    archived = Path(".context/backlog/_archive/2026-01-01-x.md")
    if v.check_backlog_type(active, {"type": "bug"}) is not None:
        failures.append("backlog-type unit: valid type 'bug' flagged (false positive)")
    bad = v.check_backlog_type(active, {"type": "feature"})
    if bad is None or bad.rule != "backlog-type-invalid" or bad.severity != "violation":
        failures.append("backlog-type unit: out-of-enum type did not produce a violation")
    miss = v.check_backlog_type(active, {"status": "open"})
    if miss is None or miss.rule != "backlog-type-missing" or miss.severity != "warning":
        failures.append("backlog-type unit: absent type on active item did not warn")
    if v.check_backlog_type(archived, {"status": "done"}) is not None:
        failures.append("backlog-type unit: absent type on archived item warned (should be exempt)")


def check_backlog_priority_unit(failures: list[str]) -> None:
    """Direct cells for check_backlog_priority: P0-P3 are silent, and `Blocked` is
    a violation, not an accepted value. The canon says a blocked item KEEPS its
    priority and sets blocked_by (01-backlog-conventions.md:147); accepting
    `Blocked` as a priority let an item hide its urgency in the one value
    migrate-priorities.sh cannot repair."""
    v = _load_validator()
    path = Path(".context/backlog/2026-01-01-x.md")
    for good_val in ("P0", "P1", "P2", "P3"):
        if v.check_backlog_priority(path, {"priority": good_val}) is not None:
            failures.append(f"backlog-priority unit: valid {good_val} flagged (false positive)")
    blocked = v.check_backlog_priority(path, {"priority": "Blocked"})
    if blocked is None or blocked.rule != "backlog-priority-invalid" or blocked.severity != "violation":
        failures.append("backlog-priority unit: 'Blocked' accepted as a priority "
                        "(it is a modifier — keep the priority, set blocked_by)")
    elif "blocked_by" not in blocked.message:
        failures.append("backlog-priority unit: the 'Blocked' violation does not point at blocked_by")
    if v.check_backlog_priority(path, {"status": "open"}) is not None:
        failures.append("backlog-priority unit: absent priority produced a finding")


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


def check_comm_paste_safe_unit(failures: list[str]) -> None:
    """The paste-safe rule (BL-218) is only correct if it stays OFF everywhere the
    construct is legitimate. The bad fixture proves it fires; these cells prove it
    does not over-fire — a received/ body full of tables and quoted `>` lines is a
    faithful capture, and RETRO-46 (quoted-inbound guardrail) was dismissed, so
    nothing else in the skill handles quoted text."""
    v = _load_validator()
    fm_base = {"channel": "email", "direction": "sent"}
    table = "\n| a | b |\n|---|---|\n| 1 | 2 |\n"
    quote = "\n> lo que escribiste\n"

    def rules(folder: str, name: str, body: str, fm: dict | None) -> list[str]:
        path = Path(f"/x/.context/communications/{folder}/2026-06-18-s/{name}")
        return [f.rule for f in v.check_comm_paste_safe(path, body, fm)]

    # Fires: outgoing email with either construct.
    for label, body in (("table", table), ("quote", quote)):
        if "communication-paste-unsafe" not in rules("sent", "body.md", body, fm_base):
            failures.append(f"paste-safe unit: a sent/ email {label} was not flagged")
    # Silent: inbound capture, non-email channels, meetings, fenced code, plain prose.
    for label, folder, name, body, fm in (
            ("received table", "received", "body.md", table, {"channel": "email", "direction": "received"}),
            ("received quote", "received", "body.md", quote, {"channel": "email", "direction": "received"}),
            ("sent whatsapp", "sent", "body.md", table, {"channel": "whatsapp", "direction": "sent"}),
            ("meeting notes", "meetings", "body.md", table, {"channel": "meeting"}),
            ("attachment", "sent", "notes.md", table, fm_base),
            ("no front-matter", "sent", "body.md", table, None),
            ("fenced code", "sent", "body.md", "\n```\n| a | b |\n|---|---|\n```\n", fm_base),
            ("prose with a pipe", "sent", "body.md", "\nel campo a | b es opcional\n", fm_base),
    ):
        fired = rules(folder, name, body, fm)
        if fired:
            failures.append(f"paste-safe unit: {label} was flagged {fired} — the rule is "
                            f"scoped to sent/ + channel email, and only real constructs")


def check_comm_direction_and_legacy_unit(failures: list[str]) -> None:
    """The legacy-name rule must beat the attachment exemption that hid `email.md`
    for as long as it existed, and must NOT touch real attachments."""
    v = _load_validator()
    def rule(rel: str) -> str | None:
        f = v.check_filename("communications", Path(f"/x/.context/communications/{rel}"))
        return f.rule if f else None

    if rule("received/2026-06-19-s/email.md") != "communication-legacy-body-name":
        failures.append("legacy-name unit: email.md inside an entry folder was not flagged")
    if rule("meetings/2026-06-19-s/conversation.md") != "communication-legacy-body-name":
        failures.append("legacy-name unit: conversation.md was not flagged")
    for ok in ("received/2026-06-19-s/body.md", "received/2026-06-19-s/transcript.md",
               "received/2026-06-19-s/email.html"):
        if rule(ok) is not None:
            failures.append(f"legacy-name unit: {ok} was flagged — attachments and body.md are fine")
    # Outside a dated entry folder the generic shape rule owns it, not this one.
    if rule("received/email.md") == "communication-legacy-body-name":
        failures.append("legacy-name unit: a stray email.md outside an entry folder should be "
                        "communication-shape-invalid, not a legacy-name finding")


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

    # The .html language check, asserted through validate() END TO END and by
    # FILENAME. The unit cells below exercise strip_html and the walker, but a
    # helper passing its own test proves nothing about whether validate() calls
    # it: with only those, the entire "Rendered pages" block could be deleted and
    # this suite stayed green, moving one unasserted warning count.
    html_lang = [w for w in bad["warnings"]
                 if w["rule"] == "body-language-not-english" and w["file"].endswith(".html")]
    if not any(w["file"].endswith("research/2026-06-20-informe-migracion.html")
               for w in html_lang):
        failures.append(
            "html language: the Spanish rendered report in fixtures/bad was not flagged "
            f"through validate() — got {[w['file'] for w in html_lang]}")

    # The negative, which is the one that matters: a flat rglob would reach
    # communications/ without a type name and flag every Spanish email.html, the
    # artifact D-04 exempts by name. Asserted on the GOOD fixture, which carries
    # exactly that file.
    comms = [w for w in good["warnings"]
             if w["rule"] == "body-language-not-english" and "/communications/" in w["file"]]
    if comms:
        failures.append(
            "html language: a communications page was flagged — D-04 exempts communications, "
            f"so .html must be enumerated per type, not by a flat rglob: {[w['file'] for w in comms]}")

    check_canon_lockstep(failures)
    check_phase_gate_unit(failures)
    check_plan_spec_shape_unit(failures)
    check_plan_tests_field_unit(failures)
    check_plan_scoped_shape_unit(failures)
    check_crossref_prefix_coverage(failures)
    check_worktrees_no_double_count(good, failures)
    check_baseline_ratchet(failures)
    check_baseline_key_granularity(failures)
    check_waived_is_not_resolved(failures)
    check_html_body_language(failures)
    check_external_crossrefs(failures)
    check_ignored_subtrees(failures)
    check_artifact_prev_skipped(failures)
    check_baseline_scoped_write(failures)
    check_ignored_visible_in_plain(failures)
    check_body_language_unit(failures)
    check_archive_status_open_unit(failures)
    check_backlog_placeholder_body_unit(failures)
    check_backlog_type_unit(failures)
    check_backlog_priority_unit(failures)
    check_waivers(failures)
    check_comm_paste_safe_unit(failures)
    check_comm_direction_and_legacy_unit(failures)

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
