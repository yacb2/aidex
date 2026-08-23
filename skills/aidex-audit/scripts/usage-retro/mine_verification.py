#!/usr/bin/env python3
"""
mine_verification.py — who catches the defect: the test suite, me, or the user?

Builds a per-item event stream from the sessions already attributed by mine_items.py,
and splits every detected defect by its DISCOVERER. That split is bounded and
size-normalized, unlike raw test-run counts.

  test-caught : a test command ran, its result shows failure, an edit followed
  user-caught : a user turn reports a defect  (strongest sub-signal: it carries a
                pasted image, or lands after the commit that closed the work)

A third bucket, me-caught (a problem flagged in assistant text with no failing
command), is DESIGNED but not implemented — nothing computes it and the report
prints only the two above. Do not read the ratio as three-way. (Weekend review
2026-08-23, finding 5.)

Traps handled:
  - tool_result.is_error is NOT test failure (it catches typos, denied perms, missing
    files). Test outcome is read from the RESULT TEXT of a command matching TESTCMD.
  - Completion is anchored on `git commit` in a Bash input — mechanical and timestamped
    — not on a phrase list.
  - User images are counted structurally (content blocks of type image / image-cache
    paths), so the signal is language-independent.

DATA SOURCE (promoted 2026-08-23, BL-134/BL-135 forward census, phase 10 of
suite-speed-and-coverage-rollout). This used to read a per-item `agg.json` whose
producer did not survive the 2026-08-07 study — that file is gone and nothing
regenerates it. `targets` is now derived directly from `items.jsonl` + `spans.jsonl`,
the two files `mine_items.py` actually writes: run that first (`--out DIR`), then
point `--data-dir` at the same DIR. A target is any item whose spans in that
directory sum to `--min-edits` (default 10) or more — the same "real usage" bar the
retired `agg.json.bucket=='real'` filter enforced, restated as a threshold on the
one signal (`edits`) both the old and new pipeline agree on.

WINDOWING. `--since ISO-DATE` restricts to spans whose `last` timestamp falls on or
after that date. Required for a forward census: measuring over all history
re-measures the baseline into the numerator and reports no change, which is the
arithmetic trap BL-134's own re-run note exists to prevent.
"""
import json, re, os, sys, glob, argparse, datetime, statistics as st
from collections import defaultdict, Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mine_items as M

COMMIT = re.compile(r'\bgit\s+commit\b')

# user reporting something is wrong with the running product
DEFECT = re.compile(r'\b(no funciona|sigue (fallando|sin|roto)|falla|est[aá] (mal|roto)|incorrecto|no se ve|no aparece|no carga|se rompe|roto|error|bug|no era (eso|lo)|eso no es|no me deja|no hace nada|sigue igual|mal calculad|no coincide|no correspond|deber[ií]a (mostrar|salir|ser)|todav[ií]a (no|sigue))\b', re.I)
CODE = re.compile(r'\.(py|ts|tsx|js|jsx|vue|go|rs|java|rb|php|sql|css|scss|html)$')


def is_code(fp):
    return bool(fp) and '/.context/' not in fp and bool(CODE.search(fp))


def parse_since(s):
    if not s:
        return None
    return datetime.datetime.fromisoformat(s + "T00:00:00+00:00")


def parse_ts(s):
    if not s:
        return None
    try:
        return datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None


def test_outcome(txt):
    """'fail' | 'pass' | 'unknown' from a runner's own output.

    Calibrated against real payloads: rtk summarizes vitest/jest as `PASS (n) FAIL (m)`;
    pytest emits `N failed, M passed` or a bare `N passed`. Anything else is 'unknown'
    rather than silently counted — a truncated tail must not read as a failure.
    """
    m = re.search(r'PASS\s*\((\d+)\)\s*FAIL\s*\((\d+)\)', txt)
    if m:
        return 'fail' if int(m.group(2)) > 0 else 'pass'
    m = re.search(r'(\d+)\s+failed', txt, re.I)
    if m:
        return 'fail' if int(m.group(1)) > 0 else 'pass'
    if re.search(r'\b(\d+)\s+passed\b', txt, re.I) and not re.search(r'\bfailed\b|\berror', txt, re.I):
        return 'pass'
    if re.search(r'\b\d+\s+(error|errors)\b', txt, re.I):
        return 'fail'
    return 'unknown'


def result_text(o):
    """tool_use_id -> text, for the tool_result blocks carried on a user message."""
    out = {}
    c = o.get("message", {}).get("content")
    if not isinstance(c, list):
        return out
    for b in c:
        if isinstance(b, dict) and b.get("type") == "tool_result":
            cc = b.get("content")
            if isinstance(cc, list):
                cc = " ".join(x.get("text", "") for x in cc
                              if isinstance(x, dict) and x.get("type") == "text")
            out[b.get("tool_use_id", "")] = (cc if isinstance(cc, str) else "")
    return out


def user_images(o):
    c = o.get("message", {}).get("content")
    n = 0
    if isinstance(c, list):
        for b in c:
            if isinstance(b, dict):
                if b.get("type") == "image":
                    n += 1
                elif b.get("type") == "text" and "image-cache" in b.get("text", ""):
                    n += b.get("text", "").count("image-cache")
    return n


def load_targets(data_dir, min_edits, since_dt):
    """items.jsonl + spans.jsonl -> {(project, slug): {session, ...}}.

    Replaces the retired agg.json['bucket']=='real' filter with a threshold on the
    one signal both pipelines agree on: total edits across the item's spans.
    `--since` narrows to spans whose `last` timestamp is in the window, which also
    narrows which sessions are walked below (a forward census must not read
    pre-window sessions back into the numerator).
    """
    spans_by_item = defaultdict(list)
    for line in open(os.path.join(data_dir, 'spans.jsonl')):
        s = json.loads(line)
        spans_by_item[(s['project'], s['slug'])].append(s)

    targets = {}
    for k, spans in spans_by_item.items():
        if since_dt is not None:
            spans = [s for s in spans if (parse_ts(s.get('last')) or datetime.datetime.min.replace(tzinfo=datetime.timezone.utc)) >= since_dt]
        if not spans:
            continue
        if sum(s.get('edits', 0) for s in spans) < min_edits:
            continue
        targets[k] = {s['session'] for s in spans}
    return targets


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", default=".",
                    help="dir already holding items.jsonl + spans.jsonl, written by "
                         "mine_items.py --out DIR (run that first)")
    ap.add_argument("--min-edits", type=int, default=10,
                    help="an item counts as 'real usage' at this many summed edits "
                         "across its spans (default 10, the retired agg.json bar)")
    ap.add_argument("--since", default="",
                    help="ISO date (YYYY-MM-DD); only spans whose 'last' timestamp "
                         "falls on or after this date. Required for a forward census "
                         "— an unwindowed run re-measures the baseline into itself.")
    M.add_root_args(ap)
    args = ap.parse_args()
    M.configure(args)

    since_dt = parse_since(args.since)
    targets = load_targets(args.data_dir, args.min_edits, since_dt)

    per = {}
    for k, sessions in targets.items():
        proj, slug = k
        files = [f for d in M.tx_dirs_for(proj) for f in glob.glob(d + "*.jsonl")
                 if os.path.basename(f) in sessions]
        ev = []
        for f in files:
            try:
                objs = [json.loads(l) for l in open(f, errors='replace') if l.strip()]
            except Exception:
                continue
            pending = {}          # tool_use_id -> ('test'|'commit', ts)
            for o in objs:
                ts = o.get("timestamp", "")
                if not ts:
                    continue
                if o.get("type") == "assistant":
                    txt, tools = M.assistant_parts(o)
                    for b in o.get("message", {}).get("content", []):
                        if not (isinstance(b, dict) and b.get("type") == "tool_use"):
                            continue
                        inp = b.get("input", {}) or {}
                        cmd = str(inp.get("command", ""))
                        if M.TESTCMD.search(cmd):
                            pending[b.get("id", "")] = ('test', ts)
                        elif COMMIT.search(cmd):
                            ev.append((ts, 'commit', ''))
                        fp = inp.get("file_path") or inp.get("path") or ""
                        if b.get("name") in ("Edit", "Write", "NotebookEdit") and is_code(fp):
                            ev.append((ts, 'edit', fp))
                elif o.get("type") == "user":
                    res = result_text(o)
                    for tid, txt in res.items():
                        if tid in pending:
                            kind, _ = pending.pop(tid)
                            if kind == 'test':
                                oc = test_outcome(txt)
                                ev.append((ts, 'test_' + ('fail' if oc == 'fail'
                                           else 'pass' if oc == 'pass' else 'unknown'), ''))
                    t = M.user_text(o)
                    if t:
                        imgs = user_images(o)
                        if DEFECT.search(t):
                            ev.append((ts, 'user_defect', 'img' if imgs else ''))
                        elif imgs:
                            ev.append((ts, 'user_image', ''))
        ev.sort()
        kinds = Counter(e[1] for e in ev)
        # test-caught = a failing test followed by an edit within the next 12 events
        tc = 0
        for i, (ts, kd, _) in enumerate(ev):
            if kd == 'test_fail' and any(e[1] == 'edit' for e in ev[i + 1:i + 13]):
                tc += 1
        first_commit = next((ts for ts, kd, _ in ev if kd == 'commit'), None)
        post = sum(1 for ts, kd, _ in ev if kd == 'user_defect' and first_commit and ts > first_commit)
        per[k] = dict(test_fail=kinds['test_fail'], test_pass=kinds['test_pass'],
                      test_caught=tc, user_defect=kinds['user_defect'],
                      user_defect_img=sum(1 for _, kd, m in ev if kd == 'user_defect' and m == 'img'),
                      user_img=kinds['user_image'], commits=kinds['commit'],
                      edits=kinds['edit'], post_commit_defect=post,
                      test_unknown=kinds['test_unknown'],
                      ran_tests=kinds['test_fail'] + kinds['test_pass'] + kinds['test_unknown'] > 0)

    n = len(per)
    if n == 0:
        print("no items met --min-edits in this window — nothing to measure")
        return 1
    v = list(per.values())
    print(f"items analysed (real-usage, >={args.min_edits} edits" +
          (f", since {args.since}" if args.since else "") + f"): {n}")
    print(f"\n--- did any automated test run at all while working the item?")
    ran = sum(1 for x in v if x['ran_tests'])
    print(f"  items where a test command ran: {ran}/{n} = {ran/n*100:.0f}%")
    print(f"  test runs: fail={sum(x['test_fail'] for x in v)} pass={sum(x['test_pass'] for x in v)} "
          f"unparseable={sum(x['test_unknown'] for x in v)}")
    print(f"  items where NO test ever ran:   {n-ran}/{n} = {(n-ran)/n*100:.0f}%")
    print(f"\n--- who caught the defect (totals across all items)")
    tot_tc = sum(x['test_caught'] for x in v)
    tot_ud = sum(x['user_defect'] for x in v)
    tot_ui = sum(x['user_defect_img'] for x in v)
    print(f"  test-caught (failing test -> edit): {tot_tc}")
    print(f"  user-caught (user reports defect):  {tot_ud}   of which with a pasted image: {tot_ui}")
    print(f"  ratio user:test = {tot_ud/max(1,tot_tc):.2f} : 1")
    print(f"  user defects reported AFTER the first commit: {sum(x['post_commit_defect'] for x in v)}")
    print(f"\n--- per-item incidence")
    print(f"  items with >=1 user-reported defect: {sum(1 for x in v if x['user_defect'])}/{n} = {sum(1 for x in v if x['user_defect'])/n*100:.0f}%")
    print(f"  items with >=1 test-caught defect:   {sum(1 for x in v if x['test_caught'])}/{n} = {sum(1 for x in v if x['test_caught'])/n*100:.0f}%")
    print(f"  items where user pasted any image:   {sum(1 for x in v if x['user_img'] or x['user_defect_img'])}/{n}")
    print(f"\n--- does running tests reduce user-caught defects? (size-controlled: 10-60 edits)")
    band = [x for x in v if 10 <= x['edits'] < 60] or v
    with_t = [x for x in band if x['ran_tests']]
    no_t = [x for x in band if not x['ran_tests']]
    for nm, g in (("tests ran", with_t), ("no tests ran", no_t)):
        if not g:
            continue
        print(f"  {nm:14s} n={len(g):3d}  user-defects/item {st.mean([x['user_defect'] for x in g]):.2f}"
              f"  median edits {st.median([x['edits'] for x in g]):.0f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
