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
        'acceptance': section(t, 'Acceptance'),
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

    eligible, needs = [], []
    for i in items:
        if i['blocked_by']:
            i['reason'] = 'blocked_by ' + i['blocked_by']
            needs.append(i)
        elif len(i['acceptance']) < 10:
            i['reason'] = 'no Acceptance'
            needs.append(i)
        else:
            eligible.append(i)

    # cheapest first inside each priority, oldest first on ties
    rank = {'XS': 0, 'S': 1, 'M': 2, 'L': 3, 'XL': 4, '-': 5}
    eligible.sort(key=lambda i: (i['priority'], rank.get(i['estimate'].upper(), 9), i['file']))

    if a.json:
        print(json.dumps({'eligible': eligible, 'needs_decision': needs}, indent=2))
        return

    if not a.needs_decision:
        print(f'ELIGIBLE ({len(eligible)}) — Acceptance filled, not blocked')
        for i in eligible:
            print(f"  {i['id']:8} {i['priority']:3} {i['estimate']:3}  {i['title'][:70]}")
        print()
    print(f'NEEDS-DECISION ({len(needs)}) — route to the user, never into the run')
    for i in needs:
        print(f"  {i['id']:8} {i['priority']:3} {i['estimate']:3}  {i['reason']:22} {i['title'][:50]}")


if __name__ == '__main__':
    main()
