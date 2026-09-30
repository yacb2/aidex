#!/usr/bin/env python3
"""Print the launch waves of a multi-file plan: plan-waves.py <plan-dir>

Rules: a phase is done when its checkpoint boxes are all ticked; ready when every
depends_on phase is done; ready phases share a wave only if their **Files:** paths are
disjoint; at most three per wave; a phase with no **Files:** paths or phase-type hitl-*
runs alone. Later waves assume every earlier wave completed.
"""
import re
import sys
from pathlib import Path

CAP = 3


def front_matter(text):
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    return m.group(1) if m else ""


def norm(s):
    s = re.sub(r"^(Create|Modify)\s+", "", s.strip(), flags=re.I)
    s = re.sub(r":[0-9,-]+$", "", s)
    if s.startswith("~/"):
        s = str(Path.home()) + s[1:]
    return s.rstrip("/")


def files_of(text):
    """Backticked paths of every line starting with **Files:**, plus its paragraph; if the
    marker line carries nothing, the paragraph after one blank line."""
    lines, out, i = text.split("\n"), [], 0
    while i < len(lines):
        if lines[i].startswith("**Files:**"):
            block, i = [lines[i]], i + 1
            while i < len(lines) and lines[i].strip():
                block.append(lines[i])
                i += 1
            if not "".join(block).replace("**Files:**", "").strip() and i + 1 < len(lines):
                i += 1
                while i < len(lines) and lines[i].strip():
                    block.append(lines[i])
                    i += 1
            out += [norm(x) for x in re.findall(r"`([^`]+)`", "\n".join(block))]
        else:
            i += 1
    return out


def dep_entries(fm):
    """Ints stay ints; anything else (slug) stays a string that is never done."""
    m = re.search(r"^depends_on:[ \t]*(.*)$", fm, re.M)
    if not m:
        return []
    raw = re.sub(r"\s+#.*$", "", m.group(1)).strip()
    if raw.startswith("["):
        items = raw.strip("[]").split(",")
    elif raw:
        items = [raw]
    else:
        items = re.findall(r"^\s*-\s*(.+)$", fm[m.end():].split("\n\n")[0], re.M)
    items = [x.strip().strip("'\"") for x in items if x.strip()]
    return [int(x) if x.isdigit() else x for x in items]


def parse_phase(path):
    text = path.read_text()
    fm = front_matter(text)
    deps = dep_entries(fm)
    ptype = re.search(r"^phase-type:\s*(\S+)", fm, re.M)
    files = files_of(text)
    ck = text.split("Checkpoint", 1)[-1] if "Checkpoint" in text else ""
    boxes = re.findall(r"^\s*- \[([ xX])\]", ck, re.M)
    return {
        "n": int(re.match(r"\d+", path.name).group()),
        "deps": deps,
        "hitl": bool(ptype and ptype.group(1).startswith("hitl")),
        "files": [f for f in files if f],
        "done": bool(boxes) and all(b != " " for b in boxes),
    }


def clash1(a, b):
    if "*" in a or "*" in b:
        pa, pb = a.split("*")[0], b.split("*")[0]
        return pa.startswith(pb) or pb.startswith(pa)
    return a == b or a.startswith(b + "/") or b.startswith(a + "/")


def tails(p):
    parts = p.split("/")
    return ["/".join(parts[i:]) for i in range(len(parts))]


def clash(a, b):
    """Fail closed: the same file, a directory and its content, or a glob and anything under
    its literal prefix, under any spelling: one side may lack leading components (a repo
    prefix), so each side is also tried with leading components dropped."""
    return any(clash1(a, t) for t in tails(b)) or any(clash1(t, b) for t in tails(a))


def overlaps(p, q):
    return any(clash(a, b) for a in p["files"] for b in q["files"])


def alone(p):
    return p["hitl"] or not p["files"]


def waves(phases):
    done = {p["n"] for p in phases if p["done"]}
    pending = [p for p in phases if not p["done"]]
    out = []
    while pending:
        ready = [p for p in pending if all(d in done for d in p["deps"])]
        if not ready:
            break
        wave = []
        for p in ready:
            if len(wave) == CAP:
                break
            if alone(p):
                if not wave:
                    wave = [p]
                    break
                continue
            if not any(overlaps(p, q) for q in wave):
                wave.append(p)
        out.append(wave)
        done |= {p["n"] for p in wave}
        pending = [p for p in pending if p not in wave]
    return out, pending


def main():
    plan = Path(sys.argv[1])
    phases = [parse_phase(f) for f in sorted(plan.glob("[0-9]*.md")) if not f.name.startswith("00-")]
    out, blocked = waves(phases)
    for i, w in enumerate(out, 1):
        print(f"wave {i}: " + ", ".join(str(p["n"]) for p in w))
    if blocked:
        print("blocked (unmet or cyclic dependency): " + ", ".join(str(p["n"]) for p in blocked))


if __name__ == "__main__":
    main()
