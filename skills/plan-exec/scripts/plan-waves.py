#!/usr/bin/env python3
"""Print the launch waves of a multi-file plan: plan-waves.py <plan-dir>

Rules: a phase is done when its checkpoint boxes are all ticked; ready when every
depends_on phase is done; ready phases share a wave only if their **Files:** paths are
disjoint (a slashless name in parentheses only clashes with another phase's real path);
at most three per wave; a phase with no **Files:** paths or phase-type hitl-* runs alone.
Later waves assume every earlier wave completed. Checkpoint boxes are those under every
heading naming Checkpoint; a phase without one is judged on every box in the file.
A phase file is NN-<phase>.md (1-3 digits); other digit-led names are skipped and named on
stderr. 00-index.md is silently not a phase; any other file numbered 0 (00-ui-contract.md,
00-golden-guard.md) is phase 0 only with a `# Phase` heading or phase-type:/depends_on: front
matter, and without one it is skipped and named on stderr.
With a second argument `--fanout`, nothing is printed; exit 1 and a stderr line naming the
phases and the file when a fan-out run (every dependency-ready phase launched together) would
put two phases with a shared path, or one with no **Files:** paths, in one wave.
Refused on stderr with exit 1: no plan directory, no phase files, two phase files with
one number.
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


def paths_of(line):
    """(token, weak) for each backticked token of one line. A token inside parentheses with
    no `/` is weak: the canon template's annotation (`ClassName.method`, a field name), or
    a bare file name ("or extend `api.ts`") that must still clash with a real path."""
    depth, out = 0, []
    for tok in re.findall(r"`[^`]+`|[()]", line):
        if tok in "()":
            depth = max(depth + (1 if tok == "(" else -1), 0)
        else:
            out.append((tok[1:-1], depth > 0 and "/" not in tok))
    return out


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
            out += [(norm(x), weak) for line in block for x, weak in paths_of(line)]
        else:
            i += 1
    return out


def dep_entries(fm):
    """Ints stay ints; anything else (slug) stays a string that is never done."""
    m = re.search(r"^depends_on:[ \t]*(.*)$", fm, re.M)
    if not m:
        return []
    raw = re.sub(r"\s+#.*$", "", m.group(1)).strip()
    if raw.lower() in ("null", "none", "~"):
        return []
    if raw.startswith("["):
        items = raw.strip("[]").split(",")
    elif raw:
        items = raw.split(",")
    else:
        items = []
        for line in fm[m.end():].split("\n")[1:]:
            if re.match(r"\s*#", line):
                continue
            item = re.match(r"\s*-\s*(.+)$", line)
            if not item:
                break
            items.append(item.group(1))
    items = [x.strip().strip("'\"") for x in items if x.strip()]
    return [int(x) if x.isdigit() else x for x in items]


def unfenced(text):
    """The text with every line of a ``` or ~~~ fenced block blanked (same length), so a
    `# comment` in a code block is not read as a heading."""
    out, fence = [], False
    for line in text.split("\n"):
        marker = re.match(r"\s*(```|~~~)", line)
        out.append(" " * len(line) if fence or marker else line)
        fence = fence != bool(marker)
    return "\n".join(out)


def parse_phase(path):
    text = path.read_text()
    fm = front_matter(text)
    deps = dep_entries(fm)
    ptype = re.search(r"^phase-type:\s*(\S+)", fm, re.M)
    files = files_of(text)
    scan = unfenced(text)
    heads = list(re.finditer(r"^(#+)\s.*\bCheckpoint\b.*$", scan, re.M))
    ck = "" if heads else text
    for head in heads:
        end = re.search(rf"^#{{1,{len(head.group(1))}}}\s", scan[head.end():], re.M)
        ck += text[head.end():head.end() + end.start()] if end else text[head.end():]
    boxes = re.findall(r"^\s*- \[([ xX])\]", ck, re.M)
    return {
        "n": int(re.match(r"\d+", path.name).group()),
        "name": path.name,
        "deps": deps,
        "hitl": bool(ptype and ptype.group(1).startswith("hitl")),
        "files": [f for f, weak in files if f and not weak],
        "weak": [f for f, weak in files if f and weak],
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


def wild(name, pat):
    """Only `*` is special: `[id]` and `?` are literal."""
    return re.fullmatch(".*".join(map(re.escape, pat.split("*"))), name) is not None


def comp(x, y):
    return x == y or ("*" in x and "*" in y) or wild(x, y) or wild(y, x)


def pmatch(p, q, last=None):
    """Pattern components p against path components q: the same path, a directory holding a
    match, or content under a match. `*` is one component and has no content under it when
    it ends the pattern; `**` spans any number."""
    if not p:
        return not q or last != "*"
    if not q:
        return True
    if p[0] == "**":
        return pmatch(p[1:], q, "**") or pmatch(p, q[1:], "**")
    if q[0] == "**":
        return pmatch(p, q[1:]) or pmatch(p[1:], q)
    return comp(p[0], q[0]) and pmatch(p[1:], q[1:], p[0])


def clash_tail(t, p, q):
    """A dropped tail with an empty literal prefix (`*/S.md`) is matched as a pattern."""
    if t != p and t.startswith("*"):
        return pmatch(t.split("/"), q.split("/"))
    return clash1(t, q)


def clash(a, b):
    """Fail closed: the same file, a directory and its content, or a glob and anything under
    its literal prefix, under any spelling: one side may lack leading components (a repo
    prefix), so each side is also tried with leading components dropped."""
    return any(clash_tail(t, b, a) for t in tails(b)) or any(clash_tail(t, a, b) for t in tails(a))


def shared(p, q):
    """The first (path, path) pair of p and q that clash, or None."""
    pairs = [(a, b) for a in p["files"] for b in q["files"] + q["weak"]] + [
        (a, b) for a in p["weak"] for b in q["files"]]
    return next(((a, b) for a, b in pairs if clash(a, b)), None)


def overlaps(p, q):
    return shared(p, q) is not None


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


def fanout_refusal(phases):
    """The reason a fan-out run must not start, or None. A fan-out run launches every phase
    whose depends_on are met together (no file split), so each such wave must be provably
    disjoint: a member with no declared files cannot be proven so. hitl-* phases are not in
    a fan-out batch (they run interactively) and are left out; pending phases that no wave
    can reach (unknown or cyclic depends_on) are refused, never skipped."""
    done = {p["n"] for p in phases if p["done"]}
    pending = [p for p in phases if not p["done"] and not p["hitl"]]
    wave_no = 0
    while pending:
        wave = [p for p in pending if all(d in done for d in p["deps"])]
        if not wave:
            return "fan-out: no wave can run, unmet or cyclic depends_on among " + ", ".join(p["name"] for p in pending)
        wave_no += 1
        if len(wave) > 1:
            for i, p in enumerate(wave):
                if not p["files"]:
                    return f"fan-out wave {wave_no}: {p['name']} declares no **Files:** paths, so it cannot be proven disjoint from the rest of its wave"
                for q in wave[i + 1:]:
                    hit = shared(p, q)
                    if hit:
                        return f"fan-out wave {wave_no}: {p['name']} and {q['name']} share {hit[0]}" + (f" (vs {hit[1]})" if hit[1] != hit[0] else "")
        done |= {p["n"] for p in wave}
        pending = [p for p in pending if p not in wave]
    return None


def phase_marked(path):
    text = path.read_text()
    return (re.search(r"^# Phase\b", text, re.M)
            or re.search(r"^(phase-type|depends_on):", front_matter(text), re.M))


def die(msg):
    sys.exit(f"plan-waves: {msg}")


def main():
    fan = sys.argv[2:] == ["--fanout"]
    if len(sys.argv) != 2 and not (len(sys.argv) == 3 and fan):
        die("usage: plan-waves.py <plan-dir> [--fanout]")
    plan = Path(sys.argv[1])
    if not plan.is_dir():
        die(f"{plan} is not a directory")
    named = [f for f in sorted(plan.glob("[0-9]*.md")) if f.name != "00-index.md"]
    skipped = [f.name for f in named if not re.match(r"\d{1,3}-", f.name)]
    if skipped:
        print("plan-waves: skipped, not NN-<phase>.md: " + ", ".join(skipped), file=sys.stderr)
    unmarked = [f.name for f in named if re.match(r"0{1,3}-", f.name) and not phase_marked(f)]
    if unmarked:
        print("plan-waves: skipped, numbered 0 without a `# Phase` heading or phase-type:/depends_on:"
              " front matter: " + ", ".join(unmarked), file=sys.stderr)
    phases = [parse_phase(f) for f in named if f.name not in skipped + unmarked]
    if not phases:
        die(f"{plan} has no phase files")
    for n in sorted({p["n"] for p in phases}):
        same = [p["name"] for p in phases if p["n"] == n]
        if len(same) > 1:
            die(f"duplicate phase number {n}: " + ", ".join(same))
    if fan:
        refusal = fanout_refusal(phases)
        if refusal:
            die(refusal)
        return
    out, blocked = waves(phases)
    for i, w in enumerate(out, 1):
        print(f"wave {i}: " + ", ".join(str(p["n"]) for p in w))
    if blocked:
        print("blocked (unmet or cyclic dependency): " + ", ".join(str(p["n"]) for p in blocked))


if __name__ == "__main__":
    main()
