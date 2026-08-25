#!/usr/bin/env python3
"""test_fleet_version_lockstep.py — the fleet version canon and its schema stay in lockstep.

`references/fleet-version-conventions.md` is the single owner of the fleet release
procedure and of the `.claude/git-repos.json` schema
(`decision/2026-08-25-aidex-owns-the-fleet-version-procedure.md`). A single owner is only
safe while the document cannot quietly disagree with itself, and the standing rule it
publishes — "when a per-project fact has nowhere to live, extend the schema; never re-grow
prose in commands/" — is an invitation to add fields. A field added to the example and not
documented, or documented and not exampled, is the drift this guard exists to catch.

It also pins the two placement decisions the ADR took, because both are the kind a later
reader "fixes" back:

  * the procedure is a reference, NEVER a rule — aidex's rules/ installs always-on for every
    public user, and a fleet-length procedure there is paid for by readers with no fleet;
  * a project-level command and a project-level rule are a thin invocation and a set of
    invariants. A template that regrows numbered workflow steps is the 36-file defect
    starting over, one file at a time.

Run with: python3 skills/aidex-conventions/scripts/test_fleet_version_lockstep.py
Override the canon under test with CANON_OVERRIDE (used to prove this guard goes RED).
"""

import json
import os
import re
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SKILL_DIR = os.path.join(REPO, "skills", "aidex-conventions")
CANON = os.environ.get(
    "CANON_OVERRIDE", os.path.join(SKILL_DIR, "references", "fleet-version-conventions.md")
)
TEMPLATES = os.path.join(SKILL_DIR, "assets", "templates")
RULE_TPL = os.path.join(TEMPLATES, "versioning-rule.md")
CMD_TPL = os.path.join(TEMPLATES, "version-command.md")
SKILL_MD = os.path.join(SKILL_DIR, "SKILL.md")
CANON_NAME = "fleet-version-conventions.md"

failures = []


def fail(msg):
    failures.append(msg)


def read(path):
    if not os.path.isfile(path):
        fail("missing file: %s" % os.path.relpath(path, REPO))
        return ""
    with open(path, encoding="utf-8") as fh:
        return fh.read()


canon = read(CANON)

# ---------- (a) the canon is registered where a reader looks for it ----------
if CANON_NAME not in read(SKILL_MD):
    fail("aidex-conventions/SKILL.md does not list %s — an unregistered canon is unfindable" % CANON_NAME)

# ---------- (b) example JSON <-> documented fields, both directions ----------
blocks = re.findall(r"```json\n(.*?)\n```", canon, re.S)
if not blocks:
    fail("the canon carries no ```json example of git-repos.json")
else:
    try:
        example = json.loads(blocks[0])
    except json.JSONDecodeError as exc:
        example = None
        fail("the canon's git-repos.json example is not valid JSON: %s" % exc)

    def keys(node, acc):
        if isinstance(node, dict):
            for k, v in node.items():
                acc.add(k)
                keys(v, acc)
        elif isinstance(node, list):
            for v in node:
                keys(v, acc)
        return acc

    if example is not None:
        example_keys = keys(example, set())
        prose = re.sub(r"```json\n.*?\n```", "", canon, flags=re.S)
        for k in sorted(example_keys):
            # a table names a list field as `field[]`; both spellings count as documented
            if ("`%s`" % k) not in prose and ("`%s[]`" % k) not in prose:
                fail("field `%s` appears in the example but is documented nowhere in the canon" % k)

        # every field a table names must exist in the example
        documented = set()
        for row in re.findall(r"^\|\s*`([A-Za-z][A-Za-z0-9_]*)(?:\[\])?`\s*\|", canon, re.M):
            documented.add(row)
        for k in sorted(documented):
            if k not in example_keys:
                fail("field `%s` is documented in a table but missing from the example — the "
                     "example is what a project copies" % k)

# ---------- (c) the procedure is a reference, never a rule ----------
rules_dir = os.path.join(REPO, "rules")
if os.path.isdir(rules_dir):
    for name in os.listdir(rules_dir):
        if not name.endswith(".md"):
            continue
        body = read(os.path.join(rules_dir, name))
        if "git-repos.json" in body or "/version:release" in body:
            fail("rules/%s carries fleet release detail — rules/ is always-on for every public "
                 "aidex user; the procedure belongs in %s" % (name, CANON_NAME))

# ---------- (d) both templates exist, point at the canon, and stay thin ----------
for label, path, cap in (("rule", RULE_TPL, 30), ("command", CMD_TPL, 25)):
    body = read(path)
    if not body:
        continue
    if CANON_NAME not in body:
        fail("the %s template does not point at %s — a template that restates the procedure "
             "is a second owner" % (label, CANON_NAME))
    steps = re.findall(r"^\s*\d+\.\s+\*\*", body, re.M)
    if steps:
        fail("the %s template carries %d numbered workflow step(s) — a thin invocation and a "
             "set of invariants carry none; that is how the 36 copies grew" % (label, len(steps)))
    content = [ln for ln in body.splitlines() if ln.strip() and not ln.strip().startswith("<!--")]
    if len(content) > cap:
        fail("the %s template is %d content lines, over its %d cap — always-on and copied "
             "per project, so length is the whole point" % (label, len(content), cap))

# ---------- (e) the command template declares no repo topology ----------
cmd = read(CMD_TPL)
for banned in ("MONO-REPO", "pyproject.toml", "package.json", "CHANGELOG.md"):
    if banned in cmd:
        fail("the command template names `%s` — repo topology and version files are "
             "git-repos.json fields, never command prose" % banned)

if failures:
    for f in failures:
        print("FAIL: %s" % f)
    print("\n%d failure(s)" % len(failures))
    sys.exit(1)

print("PASS: fleet version canon lockstep (schema <-> docs, placement, template thinness)")
