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
  5. aidex orchestrator (SKILL.md + agents/context-auditor.md) mentions every
     TYPES + OPTIONAL_TYPES name
  6. rules/aidex-conventions.md NEVER section ⊇ every do-not-hand-edit index the
     per-type canons declare (backlog / plans / audits auto-generated indexes)

SCOPE — this file guards the PROSE copies of the registry, not every executable one.
That distinction cost 2.5 months once (BL-097): migrate-conventions.py kept its own
hand-copied `TYPES_WITH_ARCHIVE` and went stale while this test reported "all in sync",
because it never looked at migrate-conventions.py. It no longer has a copy to check —
it imports validate.py — and test_migrate_conventions.py holds that guard. If you add
another executable consumer of the registry, guard it there or here, but do not read
this test's "in sync" as covering it.

SCOPE — every skills/* walk below goes through _owned_skills(), never the raw root.
Installed, that root also holds the user's own skills, which this repo does not ship
and has no standing to judge (BL-115).
  7. every skills/*/agents/*.md declares BOTH model and effort (an absent effort
     silently inherits the spawning session's — see the check for the probe)
  7b. every skill that fans out — by DECLARING Workflow/Agent in allowed-tools, or by
     mandating one in its BODY — declares a `model-policy:` AND states it in the body,
     and a body mandate not covered by the declaration is reported as its own failure.
     Guard 7 only walks agents/*.md, so a skill whose subagent prompts live inline in a
     Workflow script passes it vacuously — which is how aidex-review came to spawn 34
     agents that all inherited the session's model by omission. The declaration trigger
     had the same hole one level out: aidex-audit mandated a Workflow fan-out and an
     Agent-tool arbiter consult while declaring neither, and so satisfied 7b by omission
     (BL-153). Each trigger carries its own good/bad probes — a trigger with no probe is
     the omission this guard exists to catch.

Adding a new artifact type? Update validate.py AND every file above, or this
test fails loudly. Run with:

    python3 skills/aidex-conventions/scripts/test_registry_lockstep.py
"""
from __future__ import annotations

import importlib.util
import re
import shutil
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SKILLS_DIR = SCRIPT_DIR.parent.parent
GLOBAL_CANON = SCRIPT_DIR.parent / "references" / "00-global.md"
RULES_SUMMARY = SKILLS_DIR.parent / "rules" / "aidex-conventions.md"
AIDEX_FILES = [
    SKILLS_DIR / "aidex" / "SKILL.md",
    SKILLS_DIR / "aidex" / "agents" / "context-auditor.md",
]


MODEL_POLICIES = ("inherit-session", "per-stage")

# A body that mandates a fan-out. Either the tool is named outright, or a launch verb
# governs a subagent. `Task` is the launcher's legacy name and is matched so the drift
# is reported rather than missed; `Agent` is the name this suite writes.
FANOUT_BODY = re.compile(
    r"\b(?:Workflow|Agent|Task) tool\b"
    r"|\b(?:launch|spawn|delegate)\w*\b[^.]{0,60}\bsubagent\b",
    re.I,
)


def _model_policy_failures(rel: str, head: str, body: str) -> list[str]:
    """A skill that spawns subagents must declare, and state, its model policy.

    Split out as a function so the guard can be run against known-good and known-bad
    input on every execution — including the body-triggered branch, whose whole point
    is that a declaration cannot be trusted to reveal the use.

    Two triggers, because the declaration is not the use. A skill that fans out in its
    BODY while declaring neither tool satisfied the old declaration-only trigger by
    omission, which is the same vacuous pass 7b was built to close one level in.
    """
    tools = re.search(r"^allowed-tools:\s*(.+)$", head, re.M)
    # No allowed-tools line at all is a stance, not drift: the skill restricts nothing,
    # so there is no whitelist to be missing from. The rule is that a whitelist, once
    # declared, must cover what the body mandates.
    if not tools:
        return []
    declared_fanout = bool(re.search(r"\b(Workflow|Agent|Task)\b", tools.group(1)))
    # Flattened: markdown wraps mid-sentence, and a line-anchored search silently misses
    # any mandate that straddles a newline — how the aidex-dash Skill mandate hid (BL-080).
    body_fanout = bool(FANOUT_BODY.search(re.sub(r"\s+", " ", body)))

    failures: list[str] = []
    if body_fanout and not declared_fanout:
        failures.append(f"{rel} mandates a fan-out in its body (Workflow / Agent tool / "
                        f"launching a subagent) but allowed-tools declares only: "
                        f"{tools.group(1).strip()} — the omission costs a permission stop "
                        f"mid-run, which is what the declaration exists to prevent")
    if re.search(r"\bTask\b", tools.group(1)):
        failures.append(f"{rel} declares 'Task' in allowed-tools; this suite names the "
                        f"subagent launcher 'Agent' (aidex-review/SKILL.md) — one name, "
                        f"or the reader has two contradictory examples")
    if not (declared_fanout or body_fanout):
        return failures
    declared = re.search(r"^model-policy:\s*(\S+)", head, re.M)
    if not declared:
        failures.append(f"{rel} fans out but declares no `model-policy:` — its subagents "
                        f"would inherit the spawning session's model and effort by "
                        f"omission, which is a decision nobody made and the reader cannot "
                        f"see. Valid: {', '.join(MODEL_POLICIES)}")
        return failures
    value = declared.group(1)
    if value not in MODEL_POLICIES:
        failures.append(f"{rel} has model-policy '{value}'; valid: "
                        f"{', '.join(MODEL_POLICIES)}")
    elif value not in body:
        failures.append(f"{rel} declares model-policy '{value}' in front-matter but never "
                        f"states it in the body — a policy that satisfies only the linter "
                        f"is not one the reader can act on")
    return failures


def _owned_skills() -> list[Path]:
    """Skill directories aidex ships — never the user's own.

    Installed, SKILLS_DIR is ~/.aidex/skills, which also holds whatever skills
    the user put there; ~/.aidex/.manifest is install.sh's record of which ones
    are ours. Without this filter the guard judged foreign skills and FAILed on
    a clean tree for every installed user, while the repo copy — where the root
    is aidex-only by construction — printed OK (BL-115).
    """
    manifest = SKILLS_DIR.parent / ".manifest"
    if manifest.is_file():
        owned = [
            SKILLS_DIR / line.split("/", 1)[1]
            for line in manifest.read_text(encoding="utf-8").split()
            if line.startswith("skills/") and line.count("/") == 1
        ]
        owned = [p for p in owned if (p / "SKILL.md").is_file()]
        if owned:
            return sorted(owned)
    return sorted(p for p in SKILLS_DIR.iterdir()
                  if p.is_dir() and (p / "SKILL.md").is_file())


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
    owned = _owned_skills()
    owned_skill_mds = [d / "SKILL.md" for d in owned]
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

    # 4b — external ref forms (BL-070) are a second cross-ref namespace; both the
    # canon and the always-on rules summary must teach them, or the registry-lag
    # drift reappears one namespace over.
    external_probes = [("issue/", v.EXTERNAL_ISSUE_FORMAT.match("issue/GH-1")),
                       ("BL-NNN", v.CROSS_REPO_FORMAT.match("some_repo/BL-1"))]
    for token, matched in external_probes:
        if not matched:
            failures.append(f"validate.py no longer accepts the external ref form '{token}'")
        if token not in canon:
            failures.append(f"00-global.md never documents the external ref form '{token}'")
        if token not in rules_text:
            failures.append(f"rules/aidex-conventions.md never documents the external ref form '{token}'")

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

    # 6 — auto-generated indexes: every index a per-type canon marks "do not
    # hand-edit" must be named in the always-on rules summary's NEVER section. A
    # canon that starts regenerating a new index without teaching the summary is
    # the registry-lag drift, at the index level (Phase 4, 2026-07-19 remediation).
    references_dir = SCRIPT_DIR.parent / "references"
    never_m = re.search(r"##\s+NEVER\n(.*?)\n##\s+", rules_text, re.S)
    rules_never = never_m.group(1) if never_m else ""
    if not rules_never:
        failures.append("could not isolate the NEVER section of rules/aidex-conventions.md")
    # (canon file, index token the rules NEVER section must contain verbatim,
    #  proof the canon still declares that index auto-generated / do-not-hand-edit)
    autogen_indexes = [
        ("00-global.md", "backlog/00-index.md",
         re.compile(r"`00-index\.md`.*?auto-regenerated", re.S)),
        ("plan-conventions.md", "plans/00-index.md",
         re.compile(r"plans/00-index\.md`.*?auto-generated", re.S)),
        ("audit-conventions.md", "audits/<methodology>/00-index.md",
         re.compile(r"auto-generates `00-index\.md`.*?hand-edit", re.S)),
    ]
    for canon_name, token, canon_re in autogen_indexes:
        canon_path = references_dir / canon_name
        canon_txt = canon_path.read_text(encoding="utf-8") if canon_path.exists() else ""
        if not canon_txt:
            failures.append(f"per-type canon not found: {canon_path}")
        elif not canon_re.search(canon_txt):
            failures.append(f"{canon_name} no longer declares its auto-generated index the "
                            f"way this guard expects — re-sync the autogen_indexes list here")
        if token not in rules_never:
            failures.append(f"rules/aidex-conventions.md NEVER section is missing auto-gen "
                            f"index '{token}' (declared do-not-hand-edit in {canon_name})")

    # 7. Every shipped subagent declares BOTH model and effort.
    #
    # An absent `effort:` is not neutral: it inherits the effort of whatever session
    # happened to spawn the agent. Probed 2026-07-26 on Claude Code 2.1.220 — the same
    # definition with no effort key ran at `low` under a `--effort low` parent and at
    # `high` under a `--effort high` one, while an explicit `effort: high` won over a
    # `low` parent. So an undeclared agent's reasoning depth is set by its caller, which
    # for a safety gate like durability-arbiter is the caller deciding how carefully its
    # own stop gets judged. Declaring model without effort is half a decision.
    agent_files = sorted(
        p for d in owned for p in d.glob("agents/*.md")
        if not p.name.endswith(".eval.md")
    )
    if not agent_files:
        failures.append("no subagent definitions found under skills/*/agents/ — "
                        "this guard is looking in the wrong place")
    valid_effort = {"low", "medium", "high", "xhigh", "max"}
    for path in agent_files:
        fm = path.read_text(encoding="utf-8").split("---")
        head = fm[1] if len(fm) > 2 else ""
        rel = path.relative_to(SKILLS_DIR)
        model = re.search(r"^model:\s*(\S+)", head, re.M)
        effort = re.search(r"^effort:\s*(\S+)", head, re.M)
        if not model:
            failures.append(f"{rel} declares no model")
        if not effort:
            failures.append(f"{rel} declares no effort — it would inherit the spawning "
                            f"session's effort; pick one explicitly")
        elif effort.group(1) not in valid_effort:
            failures.append(f"{rel} has effort '{effort.group(1)}'; valid: "
                            f"{', '.join(sorted(valid_effort))}")

    # 7b. Every skill that fans out must declare a model policy.
    #
    # Guard 7 above only walks skills/*/agents/*.md. A skill whose finder and verifier
    # prompts live inline in a Workflow script has no agents/ directory, so guard 7
    # passes over it without ever looking — vacuously, which is the same shape as the
    # cell that "covered" the dangling cross-repo link while never entering its window.
    # aidex-review spawned 34 agents that way, every one of them inheriting the session's
    # model and effort by omission, and that inheritance — not the finder count — was
    # the dominant term in a run that came in ~17x its announced floor.
    #
    # `inherit-session` is a legitimate answer: /code-review inherits too (its prompt
    # says "run one verifier via the Task tool" with no model; what its effort levels
    # vary is the PROMPT — 8 angles at medium/high, 10 plus a sweep at xhigh/max —
    # extracted from 2.1.226). What is not legitimate is leaving it undeclared, because
    # then nobody chose it and the reader cannot see it at the moment they decide to run.
    #
    # Hence the second condition: the policy must also appear in the BODY. A key that
    # satisfies only the linter is the failure mode this repo keeps rediscovering.
    fanout_failures = _model_policy_failures
    fanout_skills = []
    for d in owned:
        skill_md = d / "SKILL.md"
        if not skill_md.is_file():
            continue
        txt = skill_md.read_text(encoding="utf-8")
        parts = txt.split("---")
        head = parts[1] if len(parts) > 2 else ""
        body = "---".join(parts[2:]) if len(parts) > 2 else ""
        tools_line = re.search(r"^allowed-tools:\s*(.+)$", head, re.M)
        if tools_line and re.search(r"\b(Workflow|Agent|Task)\b", tools_line.group(1)):
            fanout_skills.append(d.name)
        failures.extend(fanout_failures(f"{d.name}/SKILL.md", head, body))

    # ...and the guard proves it is not a no-op, on every run — one probe pair per
    # trigger, because a second trigger with no probe of its own is the omission this
    # very guard exists to catch.
    _probe_bad = _model_policy_failures(
        "probe", "allowed-tools: Bash Workflow\n", "no policy stated here\n")
    if not _probe_bad:
        failures.append("the fan-out model-policy guard passed a skill that declares "
                        "Workflow and no policy — the guard is a no-op")
    _probe_good = _model_policy_failures(
        "probe", "allowed-tools: Bash Workflow\nmodel-policy: inherit-session\n",
        "The fan-out runs at inherit-session, stated in the triage step.\n")
    if _probe_good:
        failures.append(f"the fan-out model-policy guard rejects a valid skill: {_probe_good}")
    # Body trigger: the mandate is in the prose and the declaration hides it. Wrapped
    # across a newline on purpose — a line-anchored search would pass this vacuously.
    _probe_body_bad = _model_policy_failures(
        "probe", "allowed-tools: Bash Read\n",
        "Consult the arbiter and pass it to the Agent\ntool (`model: sonnet`).\n")
    if not any("allowed-tools declares only" in f for f in _probe_body_bad):
        failures.append("the fan-out guard passed a skill whose body mandates an Agent "
                        "tool call while declaring neither — the body trigger is a no-op")
    # ...and prose that merely mentions subagents, with no launch verb governing them,
    # is not a mandate: a guard that fires on the word alone is unusable.
    _probe_body_good = _model_policy_failures(
        "probe", "allowed-tools: Bash Read\n",
        "The `aidex` skill holds the subagent specifications used during audits.\n")
    if _probe_body_good:
        failures.append(f"the fan-out guard fires on prose that only mentions subagents: "
                        f"{_probe_body_good}")

    # 8. Every canonical prefix-zero filename the migrator refuses to rename is
    #    also named in the canon that tells auditors what to flag.
    #
    #    Origin: 2026-07-29. `00-profile.md` (the docs-census keystone) shipped
    #    registered nowhere outside its own skill. `migrate-conventions.py --apply`
    #    date-renamed it, `docs-census.py` then exited 2 on a file that still
    #    existed under a new name, and `validate.py` reported the tree clean both
    #    before and after — the checker-lies-by-omission shape this suite has
    #    already been bitten by twice. The list lived in one private tuple; this
    #    guard is the second site so it cannot drift alone again.
    mig_path = SKILLS_DIR / "aidex-conventions" / "scripts" / "migrate-conventions.py"
    mig_txt = mig_path.read_text(encoding="utf-8") if mig_path.is_file() else ""
    if not mig_txt:
        failures.append(f"migrator not found at {mig_path}")
    else:
        block = re.search(r"CANONICAL_PREFIX_ZERO_NAMES\s*=\s*\((.*?)\)", mig_txt, re.S)
        if not block:
            failures.append("migrate-conventions.py no longer defines "
                            "CANONICAL_PREFIX_ZERO_NAMES — this guard cannot see the list")
        else:
            names = set(re.findall(r'"([^"]+\.md)"', block.group(1)))
            if "00-profile.md" not in names:
                failures.append("CANONICAL_PREFIX_ZERO_NAMES is missing '00-profile.md' — "
                                "the migrator would date-rename the docs-census keystone")
            ref_canon = (SKILLS_DIR / "aidex-conventions" / "references"
                         / "reference-conventions.md").read_text(encoding="utf-8")
            for n in sorted(names):
                if n in ("index.md", "findings.md"):
                    continue  # audit-owned; declared in audit-conventions.md
                if n not in ref_canon and n not in (
                        SKILLS_DIR / "aidex-conventions" / "references"
                        / "audit-conventions.md").read_text(encoding="utf-8"):
                    failures.append(f"'{n}' is exempt from renaming in the migrator but is "
                                    f"named in no conventions canon — auditors will flag it")

    # 9. Every shipped audit methodology appears in every document that claims to
    #    enumerate them.
    #
    #    Origin: 2026-07-29. `test-coverage` drifted out of audit-conventions.md at
    #    v0.21.1 and was reported on 2026-07-25 without a guard being added, so the
    #    very next methodology (`docs-coverage`) reproduced the identical drift.
    #    Runtime was correct in both cases; the documents agents are pointed at as
    #    "the full convention" were not.
    lib = SKILLS_DIR / "aidex-audit" / "scripts" / "_lib.sh"
    lib_txt = lib.read_text(encoding="utf-8") if lib.is_file() else ""
    m_types = re.search(r"AUDIT_TYPES=\(([^)]*)\)", lib_txt)
    if not m_types:
        failures.append(f"could not parse AUDIT_TYPES out of {lib}")
    else:
        methodologies = [x for x in m_types.group(1).split() if x and x != "custom"]
        enum_sites = {
            "audit-conventions.md": SKILLS_DIR / "aidex-conventions" / "references" / "audit-conventions.md",
            "aidex-audit/references/04-playbooks.md": SKILLS_DIR / "aidex-audit" / "references" / "04-playbooks.md",
            "aidex-audit/SKILL.md": SKILLS_DIR / "aidex-audit" / "SKILL.md",
        }
        for site_name, site in enum_sites.items():
            if not site.is_file():
                failures.append(f"methodology enumeration site not found: {site}")
                continue
            txt = site.read_text(encoding="utf-8")
            for meth in methodologies:
                if f"`{meth}`" not in txt and f"[{meth}]" not in txt:
                    failures.append(f"{site_name} is missing audit methodology "
                                    f"'{meth}' (in AUDIT_TYPES)")
            tmpl = (SKILLS_DIR / "aidex-audit" / "assets" / "templates"
                    / "methodology" / f"{meth}.md.template")
        for meth in methodologies:
            tmpl = (SKILLS_DIR / "aidex-audit" / "assets" / "templates"
                    / "methodology" / f"{meth}.md.template")
            if not tmpl.is_file():
                failures.append(f"audit methodology '{meth}' has no playbook template "
                                f"at {tmpl.relative_to(SKILLS_DIR)}")

        # 9b. AUDIT_TYPES declares; normalize_type() decides. They were independent
        #     lists until 2026-08-05, when `new-audit.sh rule-ablation` failed with
        #     "unknown type: rule-ablation (valid: ... rule-ablation ...)" — the error
        #     listing the type it was rejecting. Check 9 above reads AUDIT_TYPES against
        #     three DOCUMENTS and never touches the validator, so a type could be fully
        #     documented, fully templated, green here, and dead at runtime.
        #
        #     Invoke the function rather than parsing its `case` statement: a regex over
        #     the branches would be one more checker free to drift from the code.
        all_types = [x for x in m_types.group(1).split() if x]
        bash = shutil.which("bash")
        if not bash:
            failures.append("bash not found — cannot verify normalize_type() accepts "
                            "every declared audit type")
        else:
            for meth in all_types:
                probe = subprocess.run(
                    [bash, "-c", f'. "$1"; normalize_type "$2"', "_", str(lib), meth],
                    capture_output=True, text=True)
                if probe.returncode != 0:
                    failures.append(f"audit methodology '{meth}' is in AUDIT_TYPES but "
                                    f"normalize_type() rejects it — new-audit.sh will "
                                    f"refuse a type this registry calls valid")
                elif probe.stdout.strip() != meth:
                    failures.append(f"normalize_type('{meth}') returned "
                                    f"'{probe.stdout.strip()}' — AUDIT_TYPES must hold "
                                    f"canon short names that normalize to themselves")

            # A methodology with no display name falls through to the raw slug, which
            # silently renders "rule-ablation audit" instead of "Rule Ablation audit"
            # in every seeded board.
            name_fn = re.search(r"methodology_name\(\)\s*\{(.*?)\n\}", lib_txt, re.S)
            if name_fn:
                for meth in all_types:
                    if meth == "custom":
                        continue
                    if not re.search(rf"(^\s*|\|){re.escape(meth)}\)", name_fn.group(1), re.M):
                        failures.append(f"audit methodology '{meth}' has no "
                                        f"methodology_name() branch — templates will "
                                        f"render the raw slug")

    # 8. Skill-NAME lockstep. Checks 1-7 guard artifact TYPES; nothing guarded skill
    #    NAMES, and a probe on 2026-08-01 renamed 14 of 17 skill directories with every
    #    cross-reference left stale while this test still printed OK / exit 0. The 17
    #    description scalars alone carry 83 cross-skill references that no test read.
    #    Any consolidation or rename would therefore land fully green and silently broken.
    live_skills = {p.name for p in owned}
    if not live_skills:
        failures.append("no skills/*/SKILL.md found — the name-lockstep check cannot run")

    # Only names in the aidex-* namespace are ours to guarantee; a reference to a
    # third-party skill (skill-creator, session-handoff) is out of scope by design.
    name_re = re.compile(r"\baidex(?:-[a-z0-9]+)*\b")
    # Sections whose skill references are load-bearing routing, not prose.
    section_re = re.compile(r"^##\s+(Boundaries|Related)\s*$.*?(?=^##\s|\Z)",
                            re.M | re.S)

    def _referenced_names(text: str) -> set[str]:
        found: set[str] = set()
        fm = re.match(r"^---\n(.*?)\n---\n", text, re.S)
        if fm:
            desc = re.search(r"^description:\s*(>[-+]?|\|[-+]?)?\s*\n?"
                             r"((?:.|\n)*?)(?=\n[a-zA-Z_-]+:|\Z)", fm.group(1), re.M)
            if desc:
                found |= set(name_re.findall(desc.group(2)))
        for sec in section_re.findall(text):
            found |= set(name_re.findall(sec))
        return found

    checked_refs = 0
    for skill_md in owned_skill_mds:
        rel = skill_md.relative_to(SKILLS_DIR)
        for name in sorted(_referenced_names(skill_md.read_text(encoding="utf-8"))):
            checked_refs += 1
            if name not in live_skills:
                failures.append(f"{rel} references skill '{name}', which has no "
                                f"skills/{name}/SKILL.md — stale cross-reference")

    # 8b. Description-surface budget. The canon sets <900 chars for a single
    #     `description` (skill-conventions.md:147, checklist :360); Anthropic's hard
    #     cap is 1,024. Two skills had drifted to 953 and 919 (measured 2026-08-01)
    #     with nothing watching, because the budget lived only in prose.
    desc_re = re.compile(r"^description:\s*(>[-+]?|\|[-+]?)?\s*\n?"
                         r"((?:.|\n)*?)(?=\n[a-zA-Z_-]+:|\Z)", re.M)
    for skill_md in owned_skill_mds:
        fm = re.match(r"^---\n(.*?)\n---\n", skill_md.read_text(encoding="utf-8"), re.S)
        if not fm:
            continue
        d = desc_re.search(fm.group(1))
        if not d:
            continue
        n = len(" ".join(d.group(2).split()))
        if n >= 900:
            failures.append(f"{skill_md.relative_to(SKILLS_DIR)} description is {n} "
                            f"chars — the canon budget is <900 (hard cap 1,024)")

    # The router can only ever emit a skill that exists; a rename silently turns a
    # routing directive into an instruction to invoke nothing.
    router = SKILLS_DIR.parent / "hooks" / "aidex-router.sh"
    if router.is_file():
        rtext = router.read_text(encoding="utf-8")
        for name in sorted(set(re.findall(r'skill="(aidex[a-z-]*)"', rtext))):
            checked_refs += 1
            if name not in live_skills:
                failures.append(f"hooks/aidex-router.sh can emit skill '{name}', "
                                f"which has no skills/{name}/SKILL.md")

    if failures:
        print("FAIL")
        for f in failures:
            print(f"  {f}")
        return 1
    print(f"OK — registry lockstep: {len(v.TYPES)} canonical + {len(v.OPTIONAL_TYPES)} optional types, "
          f"{len(prefix_set)} cross-ref prefixes, {len(v.TYPES_WITH_ARCHIVE)} archive types, "
          f"{len(autogen_indexes)} auto-gen indexes, "
          f"{len(AIDEX_FILES)} orchestrator files, "
          f"{len(agent_files)} subagents declaring model+effort, "
          f"{len(fanout_skills)} fan-out skills declaring a model policy, "
          f"{len(names) if 'names' in dir() else 0} canonical prefix-zero names, "
          f"{checked_refs} skill-name references over {len(live_skills)} live skills "
          f"all in sync")
    return 0


if __name__ == "__main__":
    sys.exit(main())
