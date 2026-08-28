#!/usr/bin/env python3
"""sweep-eligible.py — partition open backlog items for an autonomous sweep.

An item is ELIGIBLE only when it is DEFINED — the contract define-check.py reads
(type, priority, estimate, surface, verify, touches, Context, Acceptance) — and
nothing parks it: not blocked, not awaiting the owner, and not living in another
repo (`touches` / cited paths under a sibling project — a sweep of THIS repo cannot
close it). Everything else is NEEDS-DECISION and belongs in the kickoff consultation,
not in the run; "underdefined" is answered by `/aidex-backlog define`, not by the
sweep (owner's call 2026-08-27, Q8).

Measured on echo_lab 2026-08-24 (research/2026-08-24-small-sweep-throughput-analysis):
25% of a 79-item sweep carried no Acceptance, and the two worst rework items —
four commits each, across two repos — were both in that group.

Usage:
  sweep-eligible.py [--size XS,S] [--json] [--needs-decision]
"""
import argparse, json, os, re, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib
define_check = importlib.import_module('define-check')


ROOT = None


def find_root(start=None):
    d = os.path.abspath(start or os.getcwd())
    while d != os.path.dirname(d):
        if os.path.isdir(os.path.join(d, '.context', 'backlog')):
            return d
        d = os.path.dirname(d)
    sys.exit('no .context/backlog found above cwd')


def section(text, name):
    m = re.search(r'^##\s+' + name + r'\s*$(.*?)(^##\s|\Z)', text, re.S | re.M)
    if not m:
        return ''
    return re.sub(r'<!--.*?-->', '', m.group(1), flags=re.S).strip()


# The register-item template writes a skeleton: a "Done means:" lead-in and an
# empty bullet holding a comment. Stripping comments alone leaves "Done means:\n-",
# which is long enough to read as filled — BL-521 entered a sweep that way. Strip
# the scaffolding too, so what remains is only what a human wrote.
_SCAFFOLD = re.compile(r'^\s*(done means:?|-|\*|\d+\.)\s*$', re.I)


def acceptance_body(text):
    lines = [ln for ln in section(text, 'Acceptance').splitlines()
             if ln.strip() and not _SCAFFOLD.match(ln)]
    return '\n'.join(lines).strip()


# §1b of the sweep policy, mechanized. Every one of these was learned from an item
# that passed the Acceptance gate and had to be pulled after a full body read:
# an owner call on a name already delivered, a backfill against a production
# database, a fix living in another workspace, a fork with API-compat stakes.
#
# A signal does NOT exclude — it says "read this body before starting". Tried as an
# auto-exclusion first and it gutted the queue: 38 of 48 items, because `\bMAC\b`
# matches any passing mention of the client and `\bdroplet\b` any mention of where
# the app runs. A regex over prose can say where to look; it cannot say what a
# sentence means. So the run reads 10 bodies instead of 48, and still decides.
_SIGNALS = [
    (re.compile(r'\bowner call\b|\bowner\'s call\b|is an owner\b', re.I), 'owner call'),
    (re.compile(r'\bdecide whether\b|\bdecided by\b|\ba decision is recorded\b', re.I), 'decision, not a task'),
    (re.compile(r'_prod\b|\bproduction database\b|\bagainst prod\b', re.I), 'class 1 — production data'),
    (re.compile(r'\bmust not be run\b|\bnot settleable\b|\bdo not run\b', re.I), 'explicitly not runnable here'),
    (re.compile(r'\bdroplet\b|\bfirewall\b|\bsystemctl\b|\bnginx\b', re.I), 'class 1 — live server'),
    (re.compile(r'\b\w+_ws/|\bboilerplate\b|\bbackport\b', re.I), 'outside this repo'),
    (re.compile(r'\bMAC\b|\bthe client\b|\bthird party\b', re.I), 'depends on a third party'),
    (re.compile(r'\bexceeds\b.{0,40}\bboundary\b|\bmore than the sweep\b', re.I), 'item says it exceeds the sweep'),
]


def body_signals(text):
    """Reasons the body gives for why a run must not take this on — each with the
    sentence that fired it, because a regex over prose can only point, not judge:
    `A decision is recorded on whether …` is an acceptance criterion, not an owner call,
    and the word alone sent BL-576 to REVIEW on 2026-08-28."""
    out = {}
    for rx, label in _SIGNALS:
        m = rx.search(text)
        if m and label not in out:
            s = text[max(0, text.rfind('\n', 0, m.start()) + 1):]
            s = s.split('\n', 1)[0].strip(' -*')
            out[label] = f'{label} — «{s[:80]}»'
    return [out[k] for k in sorted(out)]


_QUEUED = re.compile(r'^\d+\. \[ \] (BL-\d+)\b', re.M)


def sibling_trees(root):
    """Every checkout of this repo: the main tree and each linked worktree, minus `root`.

    A project that tracks `.context/` gives every worktree its OWN backlog and
    worklists — the 2026-08-28 incident was a sweep in worktree small-sweep-3 and a
    sweep in main taking the same items, each blind to the other's `doing` queue.
    Scanning only the local tree closes the main-vs-main case, not the one that happened."""
    try:
        out = subprocess.run(['git', '-C', root, 'worktree', 'list', '--porcelain'],
                             capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return []
    trees = [ln[len('worktree '):] for ln in out.splitlines() if ln.startswith('worktree ')]
    me = os.path.realpath(root)
    return [d for d in trees if os.path.realpath(d) != me]


def queued_elsewhere(root):
    """BL-id -> `worklist/<file>` (or `<tree>:worklist/<file>` in another checkout), for
    every unticked queue line of a `doing` work-list. An item is only ever in one queue."""
    out = {}
    for tree in [root] + sibling_trees(root):
        d = os.path.join(tree, '.context', 'worklists')
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if not f.endswith('.md') or f.startswith('00-'):
                continue
            t = open(os.path.join(d, f)).read()
            m = re.match(r'---\n(.*?)\n---', t, re.S)
            if not m or not re.search(r'^status:[ \t]*["\']?doing["\']?[ \t]*$', m.group(1), re.M):
                continue
            where = 'worklist/' + f if tree == root else os.path.basename(tree) + ':worklist/' + f
            for bl in _QUEUED.findall(t[m.end():]):
                out.setdefault(bl, where)
    return out


def parse(path):
    t = open(path).read()
    m = re.match(r'---\n(.*?)\n---', t, re.S)
    if not m:
        return None
    fm = {k: v.strip().strip('"') for k, v in re.findall(r'^([\w_]+):[ \t]*(.*)$', m.group(1), re.M)}
    dc = define_check.check(ROOT, {'file': os.path.basename(path), 'fm': fm, 'body': t[m.end():], 'text': t})
    return {
        'missing': dc['missing'],
        'cross_repo': dc['cross_repo'],
        'awaiting': fm.get('awaiting', ''),
        'file': os.path.basename(path),
        'id': fm.get('id', '?'),
        'title': fm.get('title', ''),
        'status': fm.get('status', '?'),
        'priority': fm.get('priority', '-'),
        'estimate': fm.get('estimate', '-'),
        'blocked_by': fm.get('blocked_by', ''),
        'acceptance': acceptance_body(t),
        'signals': body_signals(t),
        'context': section(t, 'Context'),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--size', default='', help='comma-separated estimates to keep, e.g. XS,S')
    ap.add_argument('--json', action='store_true')
    ap.add_argument('--needs-decision', action='store_true', help='print only the excluded items')
    a = ap.parse_args()
    sizes = [s.strip().upper() for s in a.size.split(',') if s.strip()]

    global ROOT
    ROOT = find_root()
    d = os.path.join(ROOT, '.context', 'backlog')
    items = []
    for f in sorted(os.listdir(d)):
        if not f.endswith('.md') or f.startswith('00-'):
            continue
        it = parse(os.path.join(d, f))
        if it and it['status'] in ('open', 'doing'):
            items.append(it)

    if sizes:
        items = [i for i in items if i['estimate'].upper() in sizes]

    queued = queued_elsewhere(ROOT)
    eligible, review, needs = [], [], []
    for i in items:
        if i['id'] in queued:
            i['reason'] = 'queued in ' + queued[i['id']]
            needs.append(i)
        elif i['blocked_by']:
            i['reason'] = 'blocked_by ' + i['blocked_by']
            needs.append(i)
        elif i['awaiting']:
            i['reason'] = 'awaiting ' + i['awaiting']
            needs.append(i)
        elif i['missing']:
            i['reason'] = 'underdefined: ' + ', '.join(i['missing'])
            needs.append(i)
        elif i['cross_repo']:
            i['reason'] = 'cross-repo: ' + ', '.join(sorted({p.split('/', 1)[0] for p in i['cross_repo']}))
            needs.append(i)
        elif i['signals']:
            i['reason'] = ', '.join(i['signals'])
            review.append(i)
        else:
            eligible.append(i)

    # cheapest first inside each priority, oldest first on ties
    rank = {'XS': 0, 'S': 1, 'M': 2, 'L': 3, 'XL': 4, '-': 5}
    eligible.sort(key=lambda i: (i['priority'], rank.get(i['estimate'].upper(), 9), i['file']))

    review.sort(key=lambda i: (i['priority'], rank.get(i['estimate'].upper(), 9), i['file']))

    if a.json:
        print(json.dumps({'eligible': eligible, 'review': review, 'needs_decision': needs}, indent=2))
        return

    if not a.needs_decision:
        print(f'ELIGIBLE ({len(eligible)}) — defined (define-check.py), in this repo, no autonomy signal')
        for i in eligible:
            print(f"  {i['id']:8} {i['priority']:3} {i['estimate']:3}  {i['title'][:70]}")
        print()
        print(f'REVIEW ({len(review)}) — defined, but read the body before starting')
        for i in review:
            # the reason carries the quoted sentence; a 34-char column cut it at «A decision
            label, _, quote = i['reason'].partition(' — ')
            print(f"  {i['id']:8} {i['priority']:3} {i['estimate']:3}  {label[:34]:34} {i['title'][:40]}")
            if quote:
                print(f"  {'':8} {'':3} {'':3}  {quote}")
        print()
    print(f'NEEDS-DECISION ({len(needs)}) — route to the user, never into the run')
    for i in needs:
        print(f"  {i['id']:8} {i['priority']:3} {i['estimate']:3}  {i['reason'][:40]:40} {i['title'][:40]}")
        if len(i['reason']) > 40:  # the clipped part is the work-list name — the part the reader needs
            print(f"  {'':8} {'':3} {'':3}  {i['reason']}")


if __name__ == '__main__':
    main()
