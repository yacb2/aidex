#!/usr/bin/env python3
"""LOOP-010's gate: the artifact module review, read from its ledger.

See review-night-gate.sh for the five lines and what each one means. This file
holds the logic; every count fails CLOSED — a row whose evidence cannot be
found is unresolved, never skipped.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

LEDGER_REL = Path(".context/research/2026-10-07-artifact-module-review/ledger.tsv")
COLUMNS = ["partition", "lens", "id", "file_line", "verdict", "severity", "action", "ref", "note"]
PARTITIONS = "ABCD"
LENSES = ("correctness", "simplify")
VERDICTS = {"RAN", "CONFIRMED", "PLAUSIBLE", "REFUTED"}
# The commit the night started from (night/integration at the v1.6.0 release).
BASE = "2d3feed0"
# artifact-sonnet's reading set: two references whole, and reference 02 from its
# Route S heading to the next top-level heading. A file Phase D makes that agent
# read joins this list in the same commit, or T1 under-counts.
READING_WHOLE = ("skills/artifact/references/03-spec-grammar.md",
                 "skills/artifact/references/04-block-vocabulary.md")
READING_SLICE = ("skills/artifact/references/02-local-first-artifacts.md", "## Route S")
SOURCE_PREFIXES = ("skills/artifact/", "skills/ui-contract/", "agents/")
BUDGET = "skills/conventions/scripts/test_skill_budget.sh"
OWNER_TEST = "skills/ui-contract/tests/test-gallery-rules-owner.sh"
CAP = 5000


def git(repo: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)


def find_ledger(repo: Path) -> Path | None:
    env = os.environ.get("AIDEX_REVIEW_LEDGER")
    if env:
        return Path(env)
    top = git(repo, "rev-parse", "--show-toplevel").stdout.strip() or str(repo)
    for parent in [Path(top), *Path(top).parents]:
        if (parent / LEDGER_REL).is_file():
            return parent / LEDGER_REL
    return None


def route_slice(text: str, start: str) -> str | None:
    """Lines from the `start` heading to the next `## ` heading outside a fence."""
    out, inside, fence = [], False, False
    for line in text.splitlines(keepends=True):
        if line.startswith("```"):
            fence = not fence
        if not fence and line.startswith("## "):
            if inside:
                break
            inside = line.startswith(start)
        if inside:
            out.append(line)
    return "".join(out) if out else None


def reading_tokens(repo: Path, ref: str) -> int | None:
    def show(path: str) -> str | None:
        r = git(repo, "show", f"{ref}:{path}")
        return r.stdout if r.returncode == 0 else None

    total = 0
    for path in READING_WHOLE:
        text = show(path)
        if text is None:
            return None
        total += len(text.encode())
    text = show(READING_SLICE[0])
    part = route_slice(text, READING_SLICE[1]) if text is not None else None
    if part is None:
        return None
    return (total + len(part.encode())) // 4


def commit_ok(repo: Path, sha: str) -> list[str] | None:
    """Files the commit touched, or None when it is not in HEAD's history."""
    if not re.fullmatch(r"[0-9a-f]{7,40}", sha):
        return None
    if git(repo, "merge-base", "--is-ancestor", sha, "HEAD").returncode != 0:
        return None
    r = git(repo, "show", "--name-only", "--format=", sha)
    return [f for f in r.stdout.splitlines() if f] if r.returncode == 0 else None


def backlog_has(ws: Path, bl: str) -> bool:
    m = re.fullmatch(r"BL-(\d+)", bl)
    return bool(m) and any((ws / ".context/backlog").rglob(f"*bl-{int(m.group(1))}-*"))


def loc_delta(repo: Path, shas: set[str]) -> int:
    net = 0
    for sha in shas:
        r = git(repo, "show", "--numstat", "--format=", sha)
        for line in r.stdout.splitlines():
            added, deleted, path = line.split("\t", 2)
            if added == "-" or "/tests/" in path or not path.startswith(SOURCE_PREFIXES):
                continue
            net += int(added) - int(deleted)
    return net


def bl710(repo: Path) -> tuple[bool, str]:
    r = subprocess.run(["bash", str(repo / BUDGET)], capture_output=True, text=True, cwd=repo)
    m = re.search(r"^\s*ui-contract\s+\d+ lines\s+~\s*(\d+) tokens", r.stdout, re.M)
    if r.returncode != 0 or not m:
        return False, "failing (skill budget guard did not pass or did not list ui-contract)"
    tokens = int(m.group(1))
    if tokens >= CAP:
        return False, f"failing (ui-contract SKILL.md ~{tokens} tokens, cap {CAP})"
    if not (repo / OWNER_TEST).is_file():
        return False, f"pending (no {OWNER_TEST})"
    t = subprocess.run(["bash", str(repo / OWNER_TEST)], capture_output=True, text=True, cwd=repo)
    if t.returncode != 0:
        return False, f"failing ({OWNER_TEST} rc {t.returncode})"
    return True, f"done (ui-contract SKILL.md ~{tokens} tokens)"


def main() -> int:
    ap = argparse.ArgumentParser(description="LOOP-010 review night gate")
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    ap.add_argument("--base", default=BASE)
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()
    repo = Path(a.repo)

    ledger = find_ledger(repo)
    if ledger is None or not ledger.is_file():
        print(f"review-night-gate: no ledger ({LEDGER_REL} above {repo}, or AIDEX_REVIEW_LEDGER)",
              file=sys.stderr)
        return 2
    ws = ledger.parents[3]
    lines = ledger.read_text().splitlines()
    if not lines or lines[0].split("\t") != COLUMNS:
        print(f"review-night-gate: {ledger} header is not {' '.join(COLUMNS)}", file=sys.stderr)
        return 2

    bad, ran, confirmed, resolved, applied, unresolved = 0, set(), 0, 0, 0, []
    applied_shas: set[str] = set()
    for n, raw in enumerate(lines[1:], start=2):
        if not raw.strip():
            continue
        row = dict(zip(COLUMNS, raw.split("\t")))
        if (len(raw.split("\t")) != len(COLUMNS) or row["partition"] not in PARTITIONS
                or row["lens"] not in LENSES or row["verdict"] not in VERDICTS):
            bad += 1
            print(f"review-night-gate: ledger line {n} malformed", file=sys.stderr)
            continue
        if row["verdict"] == "RAN":
            ran.add((row["partition"], row["lens"]))
            continue
        if row["verdict"] != "CONFIRMED":
            continue
        confirmed += 1
        action, ref = row["action"], row["ref"]
        ok = False
        if action in ("fixed", "applied"):
            files = commit_ok(repo, ref)
            ok = files is not None and (action == "applied" or any("/tests/" in f or f.startswith("tests/") for f in files))
            if ok and action == "applied":
                applied += 1
                applied_shas.add(ref)
        elif action == "filed":
            ok = backlog_has(ws, ref) and bool(row["note"].strip())
        if ok:
            resolved += 1
        else:
            unresolved.append(f"{row['partition']} {row['id']} {action} {ref}")

    parts = sum(all((p, lens) in ran for lens in LENSES) for p in PARTITIONS)
    done710, msg710 = bl710(repo)
    t0, t1 = reading_tokens(repo, a.base), reading_tokens(repo, "HEAD")

    print(f"partitions: {parts}/4")
    print(f"confirmed: {resolved}/{confirmed}")
    print(f"simplify: {applied} applied, net source LOC {loc_delta(repo, applied_shas):+d}")
    print(f"bl-710: {msg710}")
    print(f"canon-load: {t0 if t0 is not None else 'unknown'} -> {t1 if t1 is not None else 'unknown'}")
    if a.verbose:
        for u in unresolved:
            print(f"  unresolved: {u}")

    ok = (parts == 4 and resolved == confirmed and done710 and bad == 0
          and t0 is not None and t1 is not None and t1 < t0)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
