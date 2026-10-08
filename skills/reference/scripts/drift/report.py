#!/usr/bin/env python3
"""Turn a drift.workflow.js result into a markdown report; optionally register each finding in the backlog.

usage: report.py RESULT.json WORK_DIR [--transcripts DIR] [--file]

RESULT.json is the Workflow's returned JSON (shape in the header of assets/workflows/drift.workflow.js).
WORK_DIR holds manifest.json; its `skipped` list is printed so the report never looks clean for code that was
never read. --transcripts DIR is the Workflow's agent transcript directory (journal.jsonl + agent-*.jsonl);
without it the cost section says so. Cost is reported, never a pass/fail line.
--file registers one backlog item per finding through register-item.sh --origin manual and writes nothing else.
"""
import argparse
import collections
import glob
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REGISTER = os.path.join(HERE, "..", "..", "..", "backlog", "scripts", "register-item.sh")

# USD per million tokens: (input, cache_create_5m, cache_create_1h, cache_read, output). Keys are model-id
# prefixes, longest match wins. Copied from the owner's pricing table (platform pricing page, read 2026-10-07):
# the pilot's pricing.py lives outside this repo. Only the models drift agents can run on.
PRICES = {
    "claude-opus-5-5": (4, 5, 8, 0.20, 20),
    "claude-opus-5": (5, 6.25, 10, 0.50, 25),
    "claude-sonnet-5-5": (2, 2.50, 4, 0.10, 10),
    "claude-sonnet-5": (2, 2.50, 4, 0.20, 10),
    "claude-sonnet-4-5": (3, 3.75, 6, 0.30, 15),
    "claude-haiku-4-5": (1, 1.25, 2, 0.10, 5),
    "claude-haiku-5-5": (0.10, 0.125, 0.20, 0.01, 0.50),
}
HAIKU_5_5_HIGH = (0.50, 0.625, 1, 0.05, 2.50)  # one request with prompt > 100k tokens


def usd_request(model, tok):
    """tok = (input, create_5m, create_1h, cache_read, output) of ONE request; None for an unpriced model."""
    best = max((k for k in PRICES if (model or "").startswith(k)), key=len, default=None)
    if best is None:
        return None
    p = HAIKU_5_5_HIGH if best == "claude-haiku-5-5" and sum(tok[:4]) > 100_000 else PRICES[best]
    return sum(t * r for t, r in zip(tok, p)) / 1e6


def cost(tdir):
    """USD and max prompt per stage (label prefix before ':'). `usage` repeats on every content-block line of
    one message, so it is counted once per message id (the last line wins)."""
    labels = {}
    with open(os.path.join(tdir, "journal.jsonl")) as fh:
        for line in fh:
            try:
                d = json.loads(line)
            except ValueError:
                continue  # a run still writing leaves a truncated last line
            if d.get("type") == "started":
                labels[d["agentId"]] = d["label"]
    stage = collections.defaultdict(lambda: dict(usd=0.0, maxprompt=0, unpriced=0))
    for p in sorted(glob.glob(os.path.join(tdir, "agent-*.jsonl"))):
        aid = os.path.basename(p)[len("agent-"):-len(".jsonl")]
        seen = {}
        with open(p) as fh:
            for line in fh:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                m = d.get("message")
                if isinstance(m, dict) and m.get("role") == "assistant" and m.get("usage"):
                    # No id: nothing to dedupe on, so each line counts (a shared None key would collapse them).
                    seen[m.get("id") or f"line{len(seen)}"] = m
        s = stage[labels.get(aid, aid).split(":")[0]]
        for m in seen.values():
            u = m["usage"]
            cc = u.get("cache_creation") or {}
            tok = (u.get("input_tokens", 0),
                   cc.get("ephemeral_5m_input_tokens", 0) if cc else u.get("cache_creation_input_tokens", 0),
                   cc.get("ephemeral_1h_input_tokens", 0), u.get("cache_read_input_tokens", 0),
                   u.get("output_tokens", 0))
            c = usd_request(m.get("model"), tok)
            if c is None:
                s["unpriced"] += 1
            s["usd"] += c or 0
            s["maxprompt"] = max(s["maxprompt"], sum(tok[:4]))
    return dict(stages={k: dict(v) for k, v in sorted(stage.items())}, total=sum(v["usd"] for v in stage.values()))


def cell(s):
    return str(s).replace("|", "\\|").replace("\n", " ")


REF_RE = re.compile(r"\.context/references/\S+?\.md")
# One token of the evidence: a code path with an extension, then :N, :N-M or :LN. Tokens are cut on whitespace and
# brackets, so "12:30 meeting" (no extension) and "see .context/references/a.md:3" (a reference path) do not pass.
EVIDENCE_TOKEN_RE = re.compile(r"\.{0,2}/?[\w./-]+\.\w+:L?\d+(-L?\d+)?")
# An absence claim cannot cite a line; its evidence is the search that came back empty: the word Glob or grep
# plus the code path searched (BL-743). "Glob returned no files" names no path, so it still fails.
SEARCH_RE = re.compile(r"\b(glob|grep)\b", re.I)


def has_code_evidence(ev):
    toks = [t.rstrip(".:") for t in re.split(r"[\s,;()\[\]]+", ev)]
    code = [t for t in toks if ".context/" not in t]
    return (any(EVIDENCE_TOKEN_RE.fullmatch(t) for t in code)
            or (SEARCH_RE.search(ev) is not None and any("/" in t for t in code)))


def normal_reference(ref, root):
    """The comparer may write an absolute path, a ./ path or add a section note; keep the repo-relative path."""
    ref = ref.strip()
    if root and ref.startswith(root.rstrip("/") + "/"):
        ref = ref[len(root.rstrip("/")) + 1:]
    ref = ref[2:] if ref.startswith("./") else ref
    m = REF_RE.search(ref)
    if not m:
        # The comparer sometimes drops the prefix and writes `backend/04-permissions.md`.
        m = REF_RE.search(".context/references/" + ref)
    return m.group(0) if m else ref


def split_findings(findings, manifest, root=""):
    """(accepted, rejected). A finding is rejected, with the reason, when its reference is not one of its unit's
    references in the manifest (the comparer was never given it) or its evidence is not a code file:line.
    An accepted finding carries the normalised reference so spellings of one path group together."""
    refs = {u["slug"]: set(u["references"]) for u in manifest.get("units", [])}
    accepted, rejected = [], []
    for f in findings:
        ref = normal_reference(f["reference"], root)
        if f["unit"] not in refs:
            why = "unit not in manifest"
        elif ref not in refs[f["unit"]]:
            why = "reference is not one of this unit's references"
        elif not has_code_evidence(f["evidence"]):
            why = "evidence is not file:line"
        else:
            accepted.append(dict(f, reference=ref))
            continue
        rejected.append(dict(f, why=why))
    return accepted, rejected


def render(result, manifest, cst=None):
    units = result["units"]
    findings, rejected = split_findings(result["findings"], manifest, result["run"].get("root", ""))
    failed = collections.defaultdict(list)
    for u in units:
        if u["status"] != "ok":
            failed[u["failed_stage"]].append(u["slug"])
    L = [f"# Reference drift: {manifest.get('project', '')}", ""]
    status = f"{len(units) - sum(map(len, failed.values()))} ok, {sum(map(len, failed.values()))} failed"
    if failed:
        status += " (" + "; ".join(f"{st}: {', '.join(sl)}" for st, sl in sorted(failed.items())) + ")"
    L += [f"Units: {status}. Verify stage: {'on' if result['run'].get('verify') else 'off'}.", ""]
    if not result["run"].get("verify"):
        L += [f"Inferred facts dropped: {sum(u.get('facts_dropped_inferred') or 0 for u in units)}. "
              f"Facts given to compare: {sum(u.get('facts_to_compare') or 0 for u in units)}.", ""]
    unread = [u for u in units if u.get("not_covered")]
    if unread:
        L += [f"Files the extractor did not read: {sum(u['not_covered'] for u in unread)} "
              f"in {len(unread)} unit(s): {', '.join(u['slug'] for u in unread)}.", ""]

    L += [f"## Findings ({len(findings)})", ""]
    by_ref = collections.defaultdict(list)
    for f in findings:
        by_ref[f["reference"]].append(f)
    if not by_ref:
        L += ["No findings in the units that completed.", ""]
    for ref in sorted(by_ref):
        L += [f"### {ref}", "", "| type | line | detail | evidence | unit |", "|---|---|---|---|---|"]
        for f in sorted(by_ref[ref], key=lambda f: (f["reference_line"], f["type"])):
            L.append(f"| {f['type']} | {f['reference_line']} | {cell(f['detail'])} | {cell(f['evidence'])} | {f['unit']} |")
        L.append("")

    if rejected:
        L += [f"## Rejected ({len(rejected)})", "", "| reference | line | evidence | unit | reason |", "|---|---|---|---|---|"]
        L += [f"| {cell(f['reference'])} | {f['reference_line']} | {cell(f['evidence'])} | {f['unit']} | {f['why']} |"
              for f in rejected]
        L.append("")

    skipped = manifest.get("skipped", [])
    L += [f"## Covered but never read ({len(skipped)})", ""]
    if skipped:
        L += ["| unit | reason | references |", "|---|---|---|"]
        L += [f"| {cell(s['unit'])} | {s['reason']} | {cell(', '.join(s['references']))} |" for s in skipped]
    else:
        L.append("None.")
    L.append("")

    L += ["## Cost", ""]
    if cst is None:
        L.append("Not available: pass --transcripts with the Workflow's agent transcript directory.")
    else:
        L += ["| stage | USD | max prompt tokens |", "|---|---|---|"]
        L += [f"| {k} | {v['usd']:.2f} | {v['maxprompt']} |" for k, v in cst["stages"].items()]
        L.append(f"| total | {cst['total']:.2f} | |")
        if any(v["unpriced"] for v in cst["stages"].values()):
            L.append("")
            L.append("Some requests ran on an unpriced model and count as 0 USD.")
    return "\n".join(L) + "\n"


def flat(s):
    return " ".join(s.split())


def registered_titles(root):
    """Titles already in <root>/.context/backlog/*.md (read only), unescaped from the YAML double-quoted scalar."""
    titles = set()
    for p in glob.glob(os.path.join(root, ".context", "backlog", "*.md")):
        with open(p) as fh:
            for line in fh:
                if line.startswith("title:"):
                    v = line[len("title:"):].strip()
                    if len(v) >= 2 and v[0] == v[-1] == '"':
                        v = re.sub(r'\\(["\\])', r"\1", v[1:-1])
                    titles.add(flat(v))
                    break
    return titles


def register(findings, root, script=REGISTER):
    """One backlog item per finding via register-item.sh --origin manual, run in the project root. Writes nothing
    else. A finding whose exact title is already in the backlog is skipped. Returns (registered, already)."""
    have = registered_titles(root)
    n = already = 0
    for f in findings:
        title = f"Reference drift ({f['type']}): {f['reference']}:{f['reference_line']} {f['detail']}"[:200]
        if flat(title) in have:
            already += 1
            continue
        n += 1
        context = (f"Found by /aidex:reference drift in unit {f['unit']}. {f['detail']} "
                   f"Reference: {f['reference']}:{f['reference_line']}. Code evidence: {f['evidence']}.")
        subprocess.run(["bash", script, "--origin", "manual", "--title", title, "--type", "task",
                        "--context", context], cwd=root, check=True)
    return n, already


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("result")
    ap.add_argument("work")
    ap.add_argument("--transcripts")
    ap.add_argument("--file", action="store_true")
    a = ap.parse_args(argv)
    with open(a.result) as fh:
        result = json.load(fh)
    with open(os.path.join(a.work, "manifest.json")) as fh:
        manifest = json.load(fh)
    sys.stdout.write(render(result, manifest, cost(a.transcripts) if a.transcripts else None))
    if a.file:
        n, already = register(split_findings(result["findings"], manifest, result["run"]["root"])[0], result["run"]["root"])
        print(f"registered {n}, already in the backlog {already}", file=sys.stderr)


if __name__ == "__main__":
    main()
