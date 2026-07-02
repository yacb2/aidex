#!/usr/bin/env python3
"""Registry drift test — the anti-"4th repeat" guard.

Origin: audit/2026-07-02-suite-analysis. Three consecutive artifact-type
additions (worklists, workflows, worktrees) each missed the same registry
update sites, and the drift turned destructive: the aidex orchestrator's stale
tier lists made newly scaffolded directories deletion candidates.

Source of truth is validate.py (TYPES / OPTIONAL_TYPES / TYPES_WITH_ARCHIVE /
CROSSREF_FORMAT). This test asserts every registry that must know about a type
actually mentions it:

  1. 00-global.md §9 canonical block  ⊇ TYPES
  2. 00-global.md §9 optional block   ⊇ OPTIONAL_TYPES
  3. 00-global.md §5 archive list     ⊇ TYPES_WITH_ARCHIVE
  4. 00-global.md §3 + rules/aidex-conventions.md cross-ref prefixes ⊇ CROSSREF prefixes
  5. aidex orchestrator (SKILL.md + references/01-context-checks.md +
     agents/context-auditor.md) mentions every TYPES + OPTIONAL_TYPES name

Adding a new artifact type? Update validate.py AND every file above, or this
test fails loudly. Run with:

    python3 skills/aidex-conventions/scripts/test_registry_lockstep.py
"""
from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SKILLS_DIR = SCRIPT_DIR.parent.parent
GLOBAL_CANON = SCRIPT_DIR.parent / "references" / "00-global.md"
RULES_SUMMARY = SKILLS_DIR.parent / "rules" / "aidex-conventions.md"
AIDEX_FILES = [
    SKILLS_DIR / "aidex" / "SKILL.md",
    SKILLS_DIR / "aidex" / "references" / "01-context-checks.md",
    SKILLS_DIR / "aidex" / "agents" / "context-auditor.md",
]


def _load_validator():
    spec = importlib.util.spec_from_file_location("validate", SCRIPT_DIR / "validate.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["validate"] = mod
    spec.loader.exec_module(mod)
    return mod


def _section_code_block(text: str, heading: str) -> set[str]:
    """Return the `a · b · c` tokens of the first ``` block after `heading`."""
    m = re.search(rf"^###\s+{re.escape(heading)}.*?```\n(.*?)```", text, re.S | re.M)
    if not m:
        return set()
    return {t.strip() for t in re.split(r"[·\n]", m.group(1)) if t.strip()}


def main() -> int:
    failures: list[str] = []
    v = _load_validator()
    canon = GLOBAL_CANON.read_text(encoding="utf-8")

    # 1+2 — §9 tier blocks
    canonical = _section_code_block(canon, "Canonical")
    optional = _section_code_block(canon, "Acceptable-optional")
    for t in v.TYPES:
        if t not in canonical:
            failures.append(f"00-global §9 canonical block is missing '{t}' (in validate.py TYPES)")
    for t in v.OPTIONAL_TYPES:
        if t not in optional and t not in canonical:
            failures.append(f"00-global §9 optional block is missing '{t}' (in validate.py OPTIONAL_TYPES)")

    # 3 — §5 archive list
    archive_section = re.search(r"## 5\. Archive.*?## 6\.", canon, re.S)
    archive_text = archive_section.group(0) if archive_section else ""
    for t in v.TYPES_WITH_ARCHIVE:
        if f"`{t}/`" not in archive_text:
            failures.append(f"00-global §5 archive-required list is missing '{t}/' (in TYPES_WITH_ARCHIVE)")

    # 4 — cross-ref prefixes in §3 and the always-on rules summary
    prefixes = re.match(r"\^\(([a-z|]+)\)", v.CROSSREF_FORMAT.pattern)
    prefix_set = set(prefixes.group(1).split("|")) if prefixes else set()
    if not prefix_set:
        failures.append("could not parse prefixes out of validate.py CROSSREF_FORMAT")
    sec3 = re.search(r"## 3\. Cross-references.*?## 4\.", canon, re.S)
    sec3_text = sec3.group(0) if sec3 else ""
    rules_text = RULES_SUMMARY.read_text(encoding="utf-8") if RULES_SUMMARY.exists() else ""
    if not rules_text:
        failures.append(f"rules summary not found at {RULES_SUMMARY}")
    for p in prefix_set:
        if p not in sec3_text:
            failures.append(f"00-global §3 prefix set is missing '{p}' (in CROSSREF_FORMAT)")
        if not re.search(rf"\b{p}\b", rules_text):
            failures.append(f"rules/aidex-conventions.md is missing cross-ref prefix '{p}'")

    # 5 — the aidex orchestrator must know every type (its tier lists drive
    # deletion-candidate decisions; a missing type is a destructive-drift risk)
    for f in AIDEX_FILES:
        if not f.exists():
            failures.append(f"aidex orchestrator file not found: {f}")
            continue
        text = f.read_text(encoding="utf-8")
        for t in list(v.TYPES) + sorted(v.OPTIONAL_TYPES):
            if not re.search(rf"\b{t}\b", text):
                failures.append(f"{f.relative_to(SKILLS_DIR)} never mentions type '{t}'")

    if failures:
        print("FAIL")
        for f in failures:
            print(f"  {f}")
        return 1
    print(f"OK — registry lockstep: {len(v.TYPES)} canonical + {len(v.OPTIONAL_TYPES)} optional types, "
          f"{len(prefix_set)} cross-ref prefixes, {len(v.TYPES_WITH_ARCHIVE)} archive types, "
          f"{len(AIDEX_FILES)} orchestrator files all in sync")
    return 0


if __name__ == "__main__":
    sys.exit(main())
