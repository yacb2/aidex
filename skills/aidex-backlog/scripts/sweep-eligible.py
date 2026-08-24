#!/usr/bin/env python3
"""sweep-eligible.py — partition open backlog items for an autonomous sweep.

An item is ELIGIBLE only when its Acceptance block says what "done" means.
Everything else is NEEDS-DECISION and belongs in the kickoff consultation, not
in the run. Front-matter already declares Acceptance "required before
open->doing"; this makes that declaration checkable.

Measured on echo_lab 2026-08-24 (research/2026-08-24-small-sweep-throughput-analysis):
25% of a 79-item sweep carried no Acceptance, and the two worst rework items —
four commits each, across two repos — were both in that group.

Usage:
  sweep-eligible.py [--size XS,S] [--json] [--needs-decision]
"""
import argparse, json, os, re, sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'aidex-conventions', 'scripts'))


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
    """Reasons the body gives for why a run must not take this on."""
    return sorted({label for rx, label in _SIGNALS if rx.search(text)})


def parse(path):
    t = open(path).read()
    m = re.match(r'---\n(.*?)\n---', t, re.S)
    if not m:
        return None
    fm = {k: v.strip().strip('"') for k, v in re.findall(r'^([\w_]+):\s*(.*)$', m.group(1), re.M)}
    return {
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

    d = os.path.join(find_root(), '.context', 'backlog')
    items = []
    for f in sorted(os.listdir(d)):
        if not f.endswith('.md') or f.startswith('00-'):
            continue
        it = parse(os.path.join(d, f))
        if it and it['status'] in ('open', 'doing'):
            items.append(it)

    if sizes:
        items = [i for i in items if i['estimate'].upper() in sizes]

    eligible, review, needs = [], [], []
    for i in items:
        if i['blocked_by']:
            i['reason'] = 'blocked_by ' + i['blocked_by']
            needs.append(i)
        elif len(i['acceptance']) < 10:
            i['reason'] = 'no Acceptance'
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
        print(f'ELIGIBLE ({len(eligible)}) — Acceptance filled, no autonomy signal')
        for i in eligible:
            print(f"  {i['id']:8} {i['priority']:3} {i['estimate']:3}  {i['title'][:70]}")
        print()
        print(f'REVIEW ({len(review)}) — defined, but read the body before starting')
        for i in review:
            print(f"  {i['id']:8} {i['priority']:3} {i['estimate']:3}  {i['reason'][:34]:34} {i['title'][:40]}")
        print()
    print(f'NEEDS-DECISION ({len(needs)}) — route to the user, never into the run')
    for i in needs:
        print(f"  {i['id']:8} {i['priority']:3} {i['estimate']:3}  {i['reason']:22} {i['title'][:50]}")


if __name__ == '__main__':
    main()
