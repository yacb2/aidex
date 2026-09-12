#!/usr/bin/env python3
"""read_sweep.py — the residue reader of the `backlog` facet's sweep stage.

Reads every sweep report `sweep-report.py` left under
`<projects-root>/*/.context/worklists/_archive/*-report.md` and prints one row per
report. The section headings are that generator's contract (`## Metrics`,
`## Closed items`, `## Awaiting owner — …`, `## Deferrals and mid-flight skips`,
`## Boundary gate — verbatim`); nothing here is inferred from prose.

Prints `reports processed: N` LAST, always — a reader that saw nothing must say 0.

usage: read_sweep.py --projects-root DIR
"""
import os, re, sys, glob, argparse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import mine_items  # noqa: E402


def section(body, name):
    m = re.search(r'^## ' + re.escape(name) + r'[^\n]*\n(.*?)(?=^## |\Z)', body, re.S | re.M)
    return m.group(1) if m else ""


def metric(metrics, label):
    m = re.search(r'^\|\s*' + re.escape(label) + r'[^|]*\|\s*([^|]*?)\s*\|', metrics, re.M)
    return m.group(1) if m else "?"


def read_report(path):
    txt = open(path, errors="replace").read()
    metrics = section(txt, "Metrics")
    bullets = lambda s: len(re.findall(r'^- ', s, re.M))  # noqa: E731
    gate = section(txt, "Boundary gate")
    return {
        "report": os.path.basename(path),
        "queued": metric(metrics, "items queued at kickoff"),
        "closed": len(re.findall(r'^### ', section(txt, "Closed items"), re.M)),
        "emergent": metric(metrics, "emergent items appended").split()[0] if metric(metrics, "emergent items appended").split() else "?",
        "awaiting": bullets(section(txt, "Awaiting owner")),
        "deferrals": bullets(section(txt, "Deferrals and mid-flight skips")),
        "gate_runs": len(re.findall(r'^- run \d+', gate, re.M)),
        "gate_verdicts": ",".join(re.findall(r'verdict \*\*([^*]+)\*\*', gate)) or "-",
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mine_items.add_root_args(ap)
    args = ap.parse_args()
    mine_items.configure(args)
    mine_items.require_projects_root()

    reports = [read_report(f) for f in sorted(glob.glob(os.path.join(
        mine_items.PROJ_ROOT, "*", ".context", "worklists", "_archive", "*-report.md")))]
    print("report                                                        queued  closed  emergent  awaiting  deferrals  gate-runs  verdicts")
    for r in reports:
        print(f"{r['report'][:60]:<60} {r['queued']:>7}  {r['closed']:>6}  {r['emergent']:>8}  "
              f"{r['awaiting']:>8}  {r['deferrals']:>9}  {r['gate_runs']:>9}  {r['gate_verdicts']}")
    print(f"reports processed: {len(reports)}")


if __name__ == "__main__":
    main()
