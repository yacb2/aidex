#!/usr/bin/env python3
"""mine-reference-reads.py — is a cited reference actually READ?

Answers the question that decides whether always-on content can be relocated:
when a skill cites a reference ("apply [Mode A autonomy](../references/x.md)"),
do its real sessions pull that file into context, or is the link decorative?

This matters because a markdown link is an invitation, not a load. Relocating
always-on content behind a pointer is only safe if the pointer is followed. If it
is not, the relocation removes governance and nothing replaces it — silently,
because the stub still says "read this" and nothing errors.

Measured 2026-08-05 for autonomy-conventions.md: cited 26 times across five run
skills, read in 5 of 180 sessions where a run skill fired (2.8%), and most of
those were Bash greps during development rather than a run consuming it. The
always-on summary was the sole delivery path. See
`assets/templates/methodology/rule-ablation.md.template`.

Read-only over ~/.claude/projects.

Usage:
  mine-reference-reads.py <reference-basename> [--when-skill S1,S2,...]

  <reference-basename>  e.g. autonomy-conventions.md
  --when-skill          restrict the denominator to sessions where one of these
                        skills fired. Without it, the denominator is all sessions.
"""
import argparse, collections, glob, json, os, sys

PROJECTS = os.path.expanduser("~/.claude/projects")


def pulls_into_context(name, inp, needle):
    """Tool calls that would put the file's CONTENT into the context window."""
    if name in ("Read", "NotebookEdit"):
        return needle in str(inp.get("file_path", ""))
    if name == "Bash":
        return needle in str(inp.get("command", ""))
    if name == "Grep":
        return needle in (str(inp.get("path", "")) + " " + str(inp.get("glob", "")))
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("reference")
    ap.add_argument("--when-skill", default="")
    a = ap.parse_args()
    gate = {s.strip() for s in a.when_skill.split(",") if s.strip()}
    needle = a.reference

    denom = 0
    hits = 0
    per_skill = collections.Counter()
    per_skill_read = collections.Counter()
    how = collections.Counter()

    for f in glob.glob(PROJECTS + "/*/*.jsonl"):
        try:
            lines = open(f, errors="replace").read().splitlines()
        except OSError:
            continue
        fired, touched = set(), set()
        for l in lines:
            if not l.strip():
                continue
            try:
                o = json.loads(l)
            except Exception:
                continue
            if o.get("type") != "assistant":
                continue
            for b in o.get("message", {}).get("content", []) or []:
                if not (isinstance(b, dict) and b.get("type") == "tool_use"):
                    continue
                name, inp = b.get("name") or "", b.get("input") or {}
                if name == "Skill":
                    sk = inp.get("skill") or ""
                    if sk:
                        fired.add(sk)
                if pulls_into_context(name, inp, needle):
                    touched.add(name)

        in_scope = bool(fired & gate) if gate else True
        if not in_scope:
            continue
        denom += 1
        for s in (fired & gate) if gate else fired:
            per_skill[s] += 1
        if touched:
            hits += 1
            for s in (fired & gate) if gate else fired:
                per_skill_read[s] += 1
            for t in touched:
                how[t] += 1

    if not denom:
        sys.exit("no sessions in scope")

    scope = f"sessions where {'/'.join(sorted(gate))} fired" if gate else "all sessions"
    print(f"reference: {needle}")
    print(f"scope:     {scope}")
    print(f"\n{denom} in scope · {hits} pulled it into context · {hits/denom:.1%}")
    if per_skill:
        print(f"\n{'skill':20s} {'in scope':>9s} {'read':>6s}")
        for s in sorted(per_skill):
            print(f"{s:20s} {per_skill[s]:9d} {per_skill_read[s]:6d}")
    print(f"\nhow it was pulled: {dict(how) or '(never)'}")
    print("\nNote: Bash hits include greps done while working ON the file, not only "
          "a run consuming it. Treat this rate as an upper bound.")


if __name__ == "__main__":
    main()
