#!/usr/bin/env python3
"""conformance-sweep.py — where does a project restate a globally-owned rule?

Fixing a globally-owned rule leaves its copy-pasted descendants untouched, and no
census reveals them. That is the defect behind BL-120 (8 projects carrying an E2E
mandate three days after the global rule stopped saying it), BL-121 (2 projects
teaching an ask-first DB policy the global canon replaced with "never"), and BL-123
(a silencing decision made once and never propagated).

One instrument for all three: walk every project's CLAUDE.md, flag restatements of
topics that a global rule owns, and report skillOverrides drift alongside.

A restatement is not automatically wrong — a project may legitimately name its own
databases or ports. What is wrong is a project restating the NORMATIVE content of a
globally-owned rule, because the copy cannot be updated when the owner changes.

Read-only. Prints a census; changes nothing.

Usage:
  conformance-sweep.py [--root ~/Documents/projects] [--json OUT]
"""
import argparse, collections, glob, json, os, re, sys

DEFAULT_ROOT = os.path.expanduser("~/Documents/projects")

# topic -> (owning global rule, patterns that indicate a NORMATIVE restatement)
TOPICS = {
    "e2e-absolute-mandate": (
        "rules/e2e-testing.md",
        [re.compile(r"ALWAYS use ['\"`]?test-e2e\.sh", re.I),
         re.compile(r"NEVER run playwright directly", re.I),
         re.compile(r"siempre.{0,20}test-e2e\.sh", re.I)],
    ),
    "db-ask-first": (
        "rules/database-protection.md",
        [re.compile(r"(always|siempre).{0,40}(ask|pregunt).{0,60}(destructive|drop|reset|borr)", re.I),
         re.compile(r"(ask|pregunt).{0,30}before.{0,30}(destructive|dropping|resetting)", re.I),
         re.compile(r"confirm.{0,30}before.{0,30}(drop|reset|truncat)", re.I)],
    ),
    "language-scope": (
        "rules/aidex-conventions.md (D-04)",
        [re.compile(r"\.context/.{0,40}(in|en)\s+(spanish|espa[nñ]ol)", re.I),
         re.compile(r"(write|escribe).{0,30}artifacts?.{0,30}(spanish|espa[nñ]ol)", re.I)],
    ),
    "artifact-publish": (
        "rules/artifacts-local-first.md",
        [re.compile(r"(always|siempre).{0,30}publish.{0,30}artifact", re.I)],
    ),
}


# Skills an always-on rule instructs the model to LOAD. A project that sets these to
# `off` (or `user-invocable-only`) creates a rule/config contradiction: the rule says
# "load this" and the setting says the model cannot. Found 2026-08-05 in 5 projects,
# aidex among them — `theme-factory` is the artifact flow's design-guidance fallback
# for surfaces without `artifact-design` (headless `claude -p` has none), so disabling
# it leaves an artifact request with no design path at all, which is the field
# regression rules/artifacts-local-first.md exists to prevent.
REQUIRED_LOADABLE = {
    "theme-factory": "rules/artifacts-local-first.md (design-guidance fallback)",
    "dataviz": "rules/artifacts-local-first.md (charts fallback)",
}
BLOCKS_MODEL_LOAD = {"off", "user-invocable-only"}


def scan_claude_md(path):
    try:
        lines = open(path, errors="replace").read().splitlines()
    except OSError:
        return []
    hits = []
    for i, line in enumerate(lines, 1):
        for topic, (owner, pats) in TOPICS.items():
            for p in pats:
                if p.search(line):
                    hits.append(dict(topic=topic, owner=owner, line=i,
                                     text=line.strip()[:120]))
                    break
    return hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=DEFAULT_ROOT)
    ap.add_argument("--json")
    a = ap.parse_args()
    root = os.path.expanduser(a.root)

    projects = sorted(d for d in glob.glob(os.path.join(root, "*")) if os.path.isdir(d))
    if not projects:
        sys.exit(f"no projects under {root}")

    rows, overrides, no_settings, no_claudemd = [], {}, [], []
    for p in projects:
        name = os.path.basename(p)
        cmd = os.path.join(p, "CLAUDE.md")
        if os.path.isfile(cmd):
            for h in scan_claude_md(cmd):
                rows.append(dict(project=name, **h))
        else:
            no_claudemd.append(name)

        sl = os.path.join(p, ".claude", "settings.local.json")
        if os.path.isfile(sl):
            try:
                d = json.load(open(sl))
                overrides[name] = d.get("skillOverrides") or {}
            except Exception:
                overrides[name] = {}
        elif os.path.isfile(cmd):
            no_settings.append(name)

    print(f"scanned {len(projects)} projects under {root}\n")

    print("=== restatements of globally-owned rules ===")
    if not rows:
        print("  none")
    else:
        by_topic = collections.defaultdict(list)
        for r in rows:
            by_topic[r["topic"]].append(r)
        for topic in sorted(by_topic):
            owner = by_topic[topic][0]["owner"]
            projs = sorted({r["project"] for r in by_topic[topic]})
            print(f"\n  {topic}  (owner: {owner})")
            print(f"  {len(by_topic[topic])} restatement(s) across {len(projs)} project(s)")
            for r in sorted(by_topic[topic], key=lambda r: (r["project"], r["line"])):
                print(f"    {r['project']}/CLAUDE.md:{r['line']}  {r['text']}")

    print("\n=== rule/config contradictions ===")
    contra = []
    for proj, ov in overrides.items():
        for skill, why in REQUIRED_LOADABLE.items():
            v = ov.get(skill)
            if v in BLOCKS_MODEL_LOAD:
                contra.append((proj, skill, v, why))
    if not contra:
        print("  none — no project disables a skill an always-on rule tells the model to load")
    for proj, skill, v, why in sorted(contra):
        print(f"  {proj}/.claude/settings.local.json: {skill}={v}")
        print(f"    but {why} instructs the model to load it. Use `name-only` to keep the")
        print(f"    context saving without blocking the load.")

    print("\n=== skillOverrides drift ===")
    have = {k: v for k, v in overrides.items() if v}
    print(f"  {len(have)} of {len(overrides)} projects with settings.local.json declare skillOverrides")
    if no_settings:
        print(f"  {len(no_settings)} project(s) with CLAUDE.md and NO settings.local.json: "
              f"{', '.join(sorted(no_settings))}")
    empty = sorted(k for k, v in overrides.items() if not v)
    if empty:
        print(f"  {len(empty)} with settings but no skillOverrides: {', '.join(empty)}")
    freq = collections.Counter()
    for v in have.values():
        for skill in v:
            freq[skill] += 1
    if freq:
        print("\n  most-silenced skills (project count):")
        for skill, n in freq.most_common(12):
            vals = {overrides[p].get(skill) for p in have if skill in overrides[p]}
            print(f"    {skill:28s} {n:3d}/{len(have):<3d}  values={sorted(v for v in vals if v)}")

    if a.json:
        json.dump(dict(restatements=rows, overrides=overrides,
                       no_settings=no_settings, no_claudemd=no_claudemd),
                  open(a.json, "w"), indent=2)
        print(f"\nwrote {a.json}")


if __name__ == "__main__":
    main()
