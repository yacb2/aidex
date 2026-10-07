#!/usr/bin/env python3
"""
subagent_spend.py — where the spend goes: the main session against one row per
(subagent model, agent type), in tokens and USD.

Answers BL-402's question, which the idle-footprint snapshot cannot: subagents are
the savings mechanism, so the lever is MODEL CHOICE inside them, and a count of
subagents says nothing about it. Read-only.

Five rules are the whole of this script. Every one of them is a WRONG NUMBER, not an
error, if dropped — the table still prints, still totals, still looks plausible:

1. NOTHING IS DROPPED FOR BEING A SIDECHAIN. The extractor this walk descends from
   (claude-session-handoff BL-035) filtered on `isSidechain` and reported the
   remainder as the session's cost — i.e. it removed exactly the turns the question
   is about. Every assistant turn carrying `usage` is attributed here.

2. ONE API MESSAGE IS ONE TURN, however many lines it occupies, AND ONE PROJECT IS
   THE SCOPE. Claude Code writes a line per content block, and re-writes a message
   once it settles: the first line carries a partial `usage` (`output_tokens: 1`),
   the last carries the total. Censused over 300 real agent transcripts: 4,141
   duplicate-id groups, last occurrence largest in all of them — so within a file,
   keep the LAST. Across files, the same id recurs for two reasons: a resumed
   session replays its parent's records verbatim (571 of 571 real main-vs-main
   duplicates carry identical tokens), and the turn that LAUNCHED an agent is copied
   into the child's transcript as context, with a stale `output_tokens`. So the
   dedupe is scoped per project, first file to settle an id keeps it, and main
   transcripts are walked before subagent ones — which credits a launch turn to
   `main`, where it was produced. Crediting the child would charge the parent's
   thinking to the child and corrupt the one comparison this table is for.

3. A NON-`message` USAGE ITERATION IS ITS OWN TURN, ON ITS OWN MODEL. The settled
   line's top-level `usage` is the sum of its `type: "message"` iterations ONLY. An
   iteration of type `advisor_message` (20,736 in the author's corpus) or
   `fallback_message` (10) carries its own `model` and its own tokens, is billed
   separately, and appears nowhere in that top-level block. Those iterations
   routinely run a MORE expensive model than the agent hosting them, so folding them
   into the parent's row would price opus work at sonnet rates. They get their own
   row, and never an `(inherited)` label: the iteration names its model outright.

4. THE FLAT CACHE-CREATION FIELD BEATS A STALE DICT. On a multi-iteration message,
   `cache_creation_input_tokens` is the aggregate while
   `cache_creation.ephemeral_5m_input_tokens` still holds iteration 0's value alone
   (real example: 8480 against 6976). ASSUMPTION, stated because the record does not
   settle it: when the dict's 5m+1h disagrees with the flat field, the flat field is
   the total and the whole excess is charged to the 5m class. 1h creation is rare and
   the dict's 1h value is taken as correct. If a future record splits the excess
   differently, this misprices the difference between 6.25 and 10 USD/Mtok.

5. THE TRANSCRIPT'S MODEL PRICES THE TURN; THE META FILE ONLY LABELS IT. A subagent
   whose meta names no model ran on whatever the main session was using, so its row
   is labelled `<model> (inherited)` — the model is still the real one from the
   transcript, because that is what was billed.

USD is accumulated per TURN, never per row, so a row that mixes models (`main` after
a `/model` switch) is still priced correctly. A model `pricing.py` does not know
contributes its tokens and no USD: that table is a dated snapshot, and pricing an
unknown model at zero would understate the total while the row still looked
complete. Such a row is marked `*` when it has priced turns too and `n/a` when it has
none, and the footer counts them — an unmarked partial sum is indistinguishable from
a complete one.

Usage:
  subagent_spend.py [--transcripts-root DIR]     # default ~/.claude/projects
"""
import os, sys, glob, json, argparse, collections

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pricing

MAIN = "main"


def tok(u):
    """(input, create_5m, create_1h, cache_read, output), for a `usage` block or for
    one of its `iterations` — both carry the same fields.

    Rule 4 lives here. The delegation monitor's hook reads the dict first and the flat
    field only as a fallback; on a multi-iteration message that dict is stale, which
    is 14.5M tokens across the corpus. Records with no dict at all (the older shape)
    land on the same branch: 5m+1h is 0, so the flat field becomes 5m creation.
    """
    cc = u.get("cache_creation") or {}
    c5 = cc.get("ephemeral_5m_input_tokens", 0)
    c1 = cc.get("ephemeral_1h_input_tokens", 0)
    flat = u.get("cache_creation_input_tokens", c5 + c1)
    if c5 + c1 != flat:
        c5 = flat - c1
    return (u.get("input_tokens", 0), c5, c1,
            u.get("cache_read_input_tokens", 0), u.get("output_tokens", 0))


def turns(path, claimed):
    """[(model, tokens, iteration type or None)] for one transcript.

    Deduped by `message.id`: last line wins within the file, and an id already in
    `claimed` (a set scoped to the project) is skipped entirely — see rule 2. Every
    non-`message` iteration of a surviving message is appended as its own entry,
    carrying its own model — rule 3.

    `<synthetic>` placeholders are skipped: Claude Code writes them with a full usage
    block, which is why extract.py:286 drops them from the adjacency channel too.
    """
    seen = collections.OrderedDict()
    try:
        fh = open(path, errors="replace")
    except OSError:
        return []
    with fh:
        for i, line in enumerate(fh):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if not isinstance(d, dict):
                continue
            m = d.get("message")
            if not (isinstance(m, dict) and m.get("role") == "assistant" and m.get("usage")):
                continue
            if m.get("model") == "<synthetic>":
                continue
            # A record with no message.id cannot be deduped; key it by line so it is
            # kept rather than collapsed onto every other id-less record in the file.
            # Such a key is deliberately not a str, so it never enters `claimed`.
            seen[m.get("id") or ("line", i)] = m
    out = []
    for key, m in seen.items():
        if isinstance(key, str):
            if key in claimed:
                continue
            claimed.add(key)
        u = m["usage"]
        model = m.get("model")
        out.append((model, tok(u), None))
        for it in u.get("iterations") or []:
            if not isinstance(it, dict) or it.get("type") == "message":
                continue
            out.append((it.get("model") or model, tok(it), it.get("type")))
    return out


def agent_meta(path):
    """(agent type, whether the row should be labelled inherited) for an agent
    transcript.

    A MISSING meta is the same case as a meta without a `model`: nothing asked for a
    model, so the agent ran on the main session's — inherited, and unremarkable.

    A meta that exists and cannot be read is a THIRD case, not that one. It is
    silent about the launch, so claiming the model was inherited states a fact
    nobody has; and folding it in loses the only signal that a file is broken. Type
    `unknown`, no label, one line on stderr, exit unaffected. (`.get` on a
    `[]`-shaped meta also used to raise AttributeError and take the whole report
    down.)
    """
    mp = path[:-len(".jsonl")] + ".meta.json"
    if not os.path.exists(mp):
        return "unknown", True
    try:
        with open(mp) as fh:
            d = json.load(fh)
        if not isinstance(d, dict):
            raise ValueError("meta is not a JSON object")
    except (OSError, ValueError) as e:
        print(f"WARNING: unreadable agent meta, agent type unknown: {mp} ({e})",
              file=sys.stderr)
        return "unknown", False
    model = d.get("model")
    # "inherit" is an explicit value naming the absent case: 1 of 400 sampled metas.
    return d.get("agentType") or "unknown", not (bool(model) and model != "inherit")


def walk(tx_root):
    """{row key: [turns, tokens[5], usd, unpriced turns]} plus the file count.

    Main transcripts are `<root>/<project>/*.jsonl`. Agent transcripts live one level
    under `subagents/` AND nested in `subagents/workflows/wf_*/` — 7,289 of the
    author's are at the nested depth against 3,164 at the flat one, so the one-level
    glob the rest of this package uses omits two thirds of them. The recursive glob
    also picks up `journal.jsonl`, which carries no assistant turn and contributes
    nothing.

    Row keys: `main`; `("A", model)` for an iteration inside a main turn, so that
    `main` stays one comparable line; `("S", label, agent type)` for a subagent.
    """
    root = tx_root.rstrip("/")
    rows = collections.defaultdict(lambda: [0, [0] * 5, 0.0, 0])
    n_files = 0
    for pdir in sorted(glob.glob(root + "/*/")):
        # Per project, and main files first: rule 2.
        files = [(f, False) for f in sorted(glob.glob(pdir + "*.jsonl"))]
        files += [(f, True) for f in sorted(glob.glob(pdir + "*/subagents/**/*.jsonl",
                                                      recursive=True))]
        n_files += len(files)
        claimed = set()
        for f, is_sub in files:
            atype, inherited = agent_meta(f) if is_sub else (None, None)
            for model, t, itype in turns(f, claimed):
                if not is_sub:
                    key = MAIN if itype is None else ("A", model or "unknown")
                else:
                    label = model or "unknown"
                    label += " (advisor)" if itype is not None else \
                             (" (inherited)" if inherited else "")
                    key = ("S", label, atype)
                r = rows[key]
                r[0] += 1
                r[1] = [a + b for a, b in zip(r[1], t)]
                u = pricing.usd_request(model, t)
                if u is None:
                    r[3] += 1
                else:
                    r[2] += u
    return rows, n_files


def label_of(key):
    if key == MAIN:
        return MAIN
    return f"main (advisor) {key[1]}" if key[0] == "A" else f"{key[1]} / {key[2]}"


def fmt(label, n, t, usd, unpriced):
    if unpriced:
        money = "n/a" if usd == 0.0 else f"{usd:.6f}*"
    else:
        money = f"{usd:.6f}"
    return (f"{label:56} {n:>7} {t[0]:>10} {t[1]:>10} {t[2]:>10} "
            f"{t[3]:>12} {t[4]:>10} {money:>11}")


def main():
    ap = argparse.ArgumentParser(description="spend by subagent model and agent type")
    ap.add_argument("--transcripts-root", default=os.path.expanduser("~/.claude/projects"))
    a = ap.parse_args()

    rows, n_files = walk(a.transcripts_root)
    if not rows:
        sys.exit(f"ERROR: no assistant turns with usage under {a.transcripts_root} "
                 f"({n_files} transcript files walked)")

    ordered = [(MAIN, rows[MAIN])] if MAIN in rows else []
    for group in ("A", "S"):
        ordered += sorted(((k, v) for k, v in rows.items()
                           if k != MAIN and k[0] == group), key=lambda kv: kv[0])

    print(f"transcript files walked: {n_files}")
    print("\nspend by subagent model and agent type (USD from pricing.py)")
    print(f"{'model / agent type':56} {'turns':>7} {'input':>10} {'cache_5m':>10} "
          f"{'cache_1h':>10} {'cache_read':>12} {'output':>10} {'usd':>11}")

    total = [0, [0] * 5, 0.0, 0]
    for key, (n, t, usd, unpriced) in ordered:
        print(fmt(label_of(key), n, t, usd, unpriced))
        total[0] += n
        total[1] = [x + y for x, y in zip(total[1], t)]
        total[2] += usd
        total[3] += unpriced
    print(fmt("TOTAL", total[0], total[1], total[2], total[3]))
    if total[3]:
        print(f"({total[3]} turn(s) ran on a model pricing.py does not know: their "
              f"tokens are counted, their USD is not. `*` marks a partial sum, `n/a` "
              f"a row with no priced turn at all.)")


if __name__ == "__main__":
    main()
