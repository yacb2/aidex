#!/usr/bin/env python3
"""mine-rule-applicability.py — Stage A of the `rule-ablation` methodology.

Answers one question per always-on rule: **how often does the situation this rule
governs actually arise?** Read-only over ~/.claude/projects.

What this does NOT measure
--------------------------
Effect. Every session in the corpus ran with the rules loaded, so there is no
counterfactual to difference against — a corpus cannot say whether a rule changed
behaviour. Applicability and effect are different quantities; the playbook
(`assets/templates/methodology/rule-ablation.md.template`) keeps them apart on
purpose, because a table labelled "effect" is how a screening number gets
promoted into a deletion decision six weeks later.

The prohibition asymmetry
-------------------------
A prohibition rule that works perfectly leaves no trace: a session where the DB
guard stopped a `dropdb` is indistinguishable from a session that never touched a
database. For those rules the number below is a FLOOR on applicability and is
never evidence of low value. They are on the playbook's never-ablate list.

Usage
-----
  mine-rule-applicability.py [--since YYYY-MM-DD] [--json OUT.json]

Adding a rule: append to SIGNATURES. Each signature must be decidable from tool
calls alone — no LLM judge — or Stage A stops being cheap and starts being
arguable.
"""
import argparse, collections, datetime, glob, json, os, re, sys

PROJECTS = os.path.expanduser("~/.claude/projects")
RULES_DIR = os.path.expanduser("~/.claude/rules")

# --- signatures ------------------------------------------------------------
# Each entry: rule-name -> dict(kind=..., ...). `prohibition` marks rules whose
# successful operation is invisible (see module docstring).
DB_RX = re.compile(r"\b(dropdb|drop\s+database|truncate\b|reset_db|createdb|"
                   r"pg_restore|manage\.py\s+flush|migrate\s+\w+\s+zero|"
                   r"docker\s+volume\s+rm)", re.I)
E2E_RX = re.compile(r"(playwright|test:e2e|test-e2e\.sh|pnpm\s+e2e|npx\s+pw\b)", re.I)
VER_RX = re.compile(r"\b(pytest|vitest|jest|npm\s+(run\s+)?test|pnpm\s+test|"
                    r"npm\s+run\s+build|tsc\b|ruff|mypy|eslint)", re.I)
RUN_SKILLS = {"aidex-plan-exec", "aidex-audit", "aidex-loop"}

SIGNATURES = {
    "aidex-conventions":     dict(prohibition=False, note="writes under .context/"),
    "artifacts-local-first": dict(prohibition=False, note="Artifact tool or .html write"),
    "autonomy":              dict(prohibition=False, note="unattended-run skill invoked",
                                  undercount="runs also begin without a Skill call"),
    "database-protection":   dict(prohibition=True,  note="DB lifecycle command appears"),
    "e2e-testing":           dict(prohibition=True,  note="E2E runner invoked"),
    "verification-before-claims": dict(prohibition=True, note="test/build/lint command run"),
    "root-cause-first":      dict(prohibition=False, note=None,
                                  undercount="no tool-call signature exists"),
}


def rule_words():
    """Word count per always-on rule. A rule with `paths:` front-matter is gated
    and therefore not always-on — exclude it, or the denominator lies."""
    out = {}
    for f in sorted(glob.glob(os.path.join(RULES_DIR, "*.md"))):
        try:
            txt = open(f, errors="replace").read()
        except OSError:
            continue
        if txt.lstrip().startswith("---") and "paths:" in txt.split("---")[1]:
            continue
        out[os.path.basename(f)[:-3]] = len(txt.split())
    return out


# The "did a human speak here" predicate is shared, not restated. This file
# used to carry its own thinner copy — it rejected only `<`-prefixed text, so
# SDK harnesses and expanded skill bodies counted as human turns and every
# session containing one was scored as human-driven. See
# usage-retro/prompt_kinds.py for the measurement that established it.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "usage-retro"))
from prompt_kinds import is_real_user  # noqa: E402


def scan(since=None):
    totals = collections.Counter()
    sess = collections.defaultdict(collections.Counter)   # rule -> bucket -> n
    events = collections.Counter()

    for f in glob.glob(PROJECTS + "/*/*.jsonl"):
        try:
            mt = datetime.datetime.fromtimestamp(os.path.getmtime(f)).date()
        except OSError:
            continue
        if since and mt < since:
            continue
        bucket = "aidex-dev" if "projects-aidex" in f else "real-usage"
        try:
            lines = open(f, errors="replace").read().splitlines()
        except OSError:
            continue

        saw_user, hits = False, set()
        for l in lines:
            if not l.strip():
                continue
            try:
                o = json.loads(l)
            except Exception:
                continue
            if is_real_user(o):
                saw_user = True
            if o.get("type") != "assistant":
                continue
            for b in o.get("message", {}).get("content", []) or []:
                if not (isinstance(b, dict) and b.get("type") == "tool_use"):
                    continue
                name, inp = b.get("name") or "", b.get("input") or {}
                def mark(rule):
                    hits.add(rule); events[rule] += 1
                if name in ("Write", "Edit", "NotebookEdit"):
                    fp = str(inp.get("file_path", ""))
                    if "/.context/" in fp:
                        mark("aidex-conventions")
                    if fp.endswith(".html"):
                        mark("artifacts-local-first")
                elif name == "Artifact":
                    mark("artifacts-local-first")
                elif name == "Skill":
                    if (inp.get("skill") or "") in RUN_SKILLS:
                        mark("autonomy")
                elif name == "Bash":
                    cmd = str(inp.get("command", ""))
                    if DB_RX.search(cmd):
                        mark("database-protection")
                    if E2E_RX.search(cmd):
                        mark("e2e-testing")
                    if VER_RX.search(cmd):
                        mark("verification-before-claims")

        if not saw_user:
            continue
        totals[bucket] += 1
        for r in hits:
            sess[r][bucket] += 1
    return totals, sess, events


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", help="ISO date lower bound on session mtime")
    ap.add_argument("--json", help="write the table here")
    a = ap.parse_args()
    since = datetime.date.fromisoformat(a.since) if a.since else None

    words = rule_words()
    totals, sess, events = scan(since)
    dev, field = totals["aidex-dev"], totals["real-usage"]
    alls = dev + field
    if not alls:
        sys.exit("no sessions in window")

    print(f"sessions: total={alls}  aidex-dev={dev}  real-usage={field}")
    print(f"window: {a.since or 'all'}\n")
    print(f"{'rule':28s} {'words':>5s} {'field %':>8s} {'dev %':>7s} "
          f"{'events':>7s}  waste/session")

    rows = []
    for rule, w in sorted(words.items(), key=lambda kv: -kv[1]):
        sig = SIGNATURES.get(rule, {})
        measurable = sig.get("note") is not None
        nf, nd = sess[rule]["real-usage"], sess[rule]["aidex-dev"]
        rf = nf / field if field else 0.0
        rd = nd / dev if dev else 0.0
        waste = round(w * (1 - rf))
        rows.append(dict(rule=rule, words=w, field_sessions=nf, field_rate=round(rf, 4),
                         dev_sessions=nd, dev_rate=round(rd, 4), events=events[rule],
                         waste_per_session=waste, prohibition=sig.get("prohibition"),
                         measurable=measurable, caveat=sig.get("undercount")))
        if not measurable:
            print(f"{rule:28s} {w:5d} {'—':>8s} {'—':>7s} {'—':>7s}  "
                  f"not measurable ({sig.get('undercount')})")
            continue
        flag = " [prohibition: floor]" if sig.get("prohibition") else ""
        print(f"{rule:28s} {w:5d} {rf:7.1%} {rd:6.1%} {events[rule]:7d} "
              f"{waste:8d}{flag}")

    print("\nfield % is the decision number: it is the rate a shipped rule meets "
          "in projects that are not aidex itself.")
    print("waste/session = words x (1 - field rate): words loaded into sessions "
          "where the governed situation never arose.")

    if a.json:
        json.dump(dict(window=a.since or "all", sessions=dict(totals), rows=rows),
                  open(a.json, "w"), indent=2)
        print(f"\nwrote {a.json}")


if __name__ == "__main__":
    main()
