#!/usr/bin/env python3
"""validate-worklist.py — focused validator for .context/worklists/ run-queues.

Work-lists are runtime execution-state, not knowledge artifacts, so they have their
own lightweight validator (kept out of the conventions validate.py, whose minimal
YAML parser does not model the nested gate-policy map).

Checks: required front-matter (title/status/created/updated + gate-policy.publish/
destructive), status vocab, ISO dates, a numbered `## Queue` whose items carry a
`<!-- ref: backlog|plan|audit|inline -->` comment.

CLI:  validate-worklist.py <path> [--json]
Exit: 0 OK · 1 violations · 2 usage error.
"""
from __future__ import annotations
import argparse, json, re, sys
from pathlib import Path

STATUS = {"open", "doing", "done", "dropped"}
PUBLISH = {"ask", "preauthorized"}
REF_KINDS = {"backlog", "plan", "audit", "inline"}
ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
QUEUE_ITEM = re.compile(r"^\s*(\d+)\.\s+\[[ x]\]\s+.+", )
REF_COMMENT = re.compile(r"<!--\s*ref:\s*([a-z]+)\s*-->")


def parse_frontmatter(text: str) -> dict | None:
    """Minimal YAML with exactly one level of nesting (for gate-policy)."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    fm: dict = {}
    parent = None
    for ln in lines[1:]:
        if ln.strip() == "---":
            return fm
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        indented = ln[0] in " \t"
        if ":" not in ln:
            continue
        key, _, val = ln.strip().partition(":")
        key = key.strip()
        val = val.strip().strip('"').strip("'")
        if indented and parent is not None:
            fm.setdefault(parent, {})[key] = val
        else:
            if val == "":
                parent = key
                fm.setdefault(key, {})
            else:
                fm[key] = val
                parent = None
    return None  # no closing ---


def validate(path: Path) -> list[dict]:
    f = []

    def err(rule, msg):
        f.append({"file": str(path), "rule": rule, "severity": "violation", "message": msg})

    if not path.is_file():
        return [{"file": str(path), "rule": "missing", "severity": "violation",
                 "message": "file does not exist"}]
    text = path.read_text(encoding="utf-8", errors="replace")
    fm = parse_frontmatter(text)
    if fm is None:
        err("frontmatter-missing", "no YAML front-matter block (--- ... ---)")
        return f
    for k in ("title", "status", "created", "updated"):
        if not fm.get(k):
            err("frontmatter-field-missing", f"required field '{k}' missing or empty")
    st = fm.get("status", "")
    if st and st not in STATUS:
        err("status-invalid", f"status={st!r} not in {sorted(STATUS)}")
    for d in ("created", "updated"):
        v = fm.get(d, "")
        if v and not ISO_DATE.match(v):
            err("date-format-invalid", f"{d}={v!r} is not YYYY-MM-DD")
    gp = fm.get("gate-policy")
    if not isinstance(gp, dict):
        err("gate-policy-missing", "gate-policy map missing (publish + destructive)")
    else:
        if gp.get("publish") not in PUBLISH:
            err("gate-policy-publish-invalid",
                f"gate-policy.publish={gp.get('publish')!r} not in {sorted(PUBLISH)}")
        if gp.get("destructive") != "deny":
            err("gate-policy-destructive-invalid",
                "gate-policy.destructive must be 'deny' (global destructive rule)")
    # Queue section: numbered, sequential, ref-commented
    body = text.split("---", 2)[-1]
    if "## Queue" not in body:
        err("queue-missing", "no '## Queue' section")
    else:
        queue = body.split("## Queue", 1)[1].split("\n## ", 1)[0].splitlines()
        items = [ln for ln in queue if QUEUE_ITEM.match(ln)]
        if not items:
            err("queue-empty", "'## Queue' has no numbered `N. [ ]` items")
        for idx, ln in enumerate(items, 1):
            n = int(QUEUE_ITEM.match(ln).group(1))
            if n != idx:
                err("queue-unordered", f"queue item out of order: expected {idx}, got {n}")
            m = REF_COMMENT.search(ln)
            if not m:
                err("queue-ref-missing", f"queue item {idx} has no <!-- ref: ... --> comment")
            elif m.group(1) not in REF_KINDS:
                err("queue-ref-invalid", f"queue item {idx} ref={m.group(1)!r} not in {sorted(REF_KINDS)}")
    return f


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    findings = validate(Path(args.path))
    if args.json:
        print(json.dumps(findings, indent=2, ensure_ascii=False))
    else:
        for x in findings:
            print(f"  [{x['severity']}] {x['rule']}: {x['message']}")
        print("OK" if not findings else f"{len(findings)} violation(s)")
    sys.exit(1 if findings else 0)


if __name__ == "__main__":
    main()
