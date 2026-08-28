#!/usr/bin/env python3
"""define-check.py — is each open backlog item DEFINED enough to be worked unattended?

The contract (01-backlog-conventions.md § Definition contract), read-only:

  front-matter  type · priority · estimate · surface · verify · touches   (non-empty)
  body          ## Context with prose · ## Acceptance with >= 1 real criterion

`depends` is optional by nature. An item missing any of the above is UNDERDEFINED:
`sweep-eligible.py` keeps it out of the queue (owner's call 2026-08-27, Q8) and this
script says what is missing — plus what a script can already deduce from the body, so
the writer (`define-item.sh`) has something to write:

  touches candidates   backticked paths in the body that exist in this repo
  cross-repo           paths whose first segment is a sibling project, not this repo —
                       the work happens THERE; a sweep of this repo cannot close it
  depends candidates   BL-NNN ids the body cites (a relation, not yet a direction)
  clusters             items that share a `touches` token or cite each other — the
                       "these could be one change / one review" list the owner asked for

Census that motivated it (2026-08-27): 393 open items in 17 projects, 0 with surface /
verify / touches / depends, 142 without an acceptance criterion.

Usage:
  define-check.py [--json] [--quiet] [BL-NNN ...]
Exit 1 when any checked item is underdefined (so triage.sh can gate on it).
"""
import argparse, json, os, re, sys

MIN_FIELDS = ('type', 'priority', 'estimate', 'surface', 'verify', 'touches')
SURFACES = ('internal', 'behaviour', 'ui', 'ops')


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


# The register-item template writes a skeleton: a "Done means:" lead-in and an empty
# bullet holding a comment. Stripping comments alone leaves "Done means:\n-", which is
# long enough to read as filled — BL-521 entered a sweep that way.
_SCAFFOLD = re.compile(r'^\s*(done means:?|-|\*|\d+\.)\s*$', re.I)


def acceptance_body(text):
    lines = [ln for ln in section(text, 'Acceptance').splitlines()
             if ln.strip() and not _SCAFFOLD.match(ln)]
    return '\n'.join(lines).strip()


def parse(path):
    t = open(path, encoding='utf-8').read()
    m = re.match(r'---\n(.*?)\n---', t, re.S)
    if not m:
        return None
    fm = {k: v.strip().strip('"') for k, v in re.findall(r'^([\w_]+):[ \t]*(.*)$', m.group(1), re.M)}
    body = t[m.end():]
    return {'file': os.path.basename(path), 'fm': fm, 'body': body, 'text': t}


_PATH = re.compile(r'`([A-Za-z0-9_.@-]+(?:/[A-Za-z0-9_.@*-]+)+)`')
_BL = re.compile(r'\bBL-(\d{3,})\b')


def deduce(root, item):
    """What the body already says, checked against the filesystem."""
    siblings = set()
    parent = os.path.dirname(root)
    try:
        siblings = {d for d in os.listdir(parent) if os.path.isdir(os.path.join(parent, d))}
    except OSError:
        pass
    touches, cross = [], []
    for p in dict.fromkeys(_PATH.findall(item['body'])):
        p = p.rstrip('/')
        if p == '_tmp' or p.startswith('_tmp/'):
            continue  # scratch output is deletable without asking; never a touches token
        if os.path.exists(os.path.join(root, p)):
            touches.append(p)
        else:
            head = p.split('/', 1)[0]
            if head in siblings and head != os.path.basename(root):
                cross.append(p)
    declared = [x.strip() for x in item['fm'].get('touches', '').split(',') if x.strip()]
    for d in declared:
        head = d.split('/', 1)[0]
        if not os.path.exists(os.path.join(root, d)) and head in siblings and head != os.path.basename(root):
            cross.append(d)
    me = item['fm'].get('id', '')
    cites = sorted({'BL-' + n for n in _BL.findall(item['body']) if 'BL-' + n != me})
    return {'touches_candidates': touches, 'cross_repo': sorted(set(cross)), 'cites': cites}


def check(root, item):
    fm = item['fm']
    missing = []
    for k in MIN_FIELDS:
        v = fm.get(k, '')
        if v in ('', '[]'):
            missing.append(k)
    if fm.get('surface') and fm['surface'] not in SURFACES:
        missing.append('surface (invalid: %s)' % fm['surface'])
    if len(section(item['body'], 'Context')) < 10:
        missing.append('Context')
    if len(acceptance_body(item['body'])) < 10:
        missing.append('Acceptance')
    d = deduce(root, item)
    return {
        'file': item['file'],
        'id': fm.get('id', '?'),
        'title': fm.get('title', ''),
        'status': fm.get('status', '?'),
        'estimate': fm.get('estimate', '-'),
        'awaiting': fm.get('awaiting', ''),
        'touches': fm.get('touches', ''),
        'missing': missing,
        'defined': not missing,
        **d,
    }


def clusters(results):
    """Items sharing a touches token (declared or deduced) or citing each other."""
    by_token = {}
    for r in results:
        toks = {x.strip() for x in r['touches'].split(',') if x.strip()} | set(r['touches_candidates'])
        for tok in toks:
            by_token.setdefault(tok, set()).add(r['id'])
    out = {tok: sorted(ids) for tok, ids in by_token.items() if len(ids) > 1}
    ids = {r['id'] for r in results}
    for r in results:
        for c in r['cites']:
            if c in ids:
                out.setdefault('cites', set())
                if isinstance(out['cites'], set):
                    out['cites'].add('%s -> %s' % (r['id'], c))
    if 'cites' in out:
        out['cites'] = sorted(out['cites'])
    return out


def scan(root, only=None):
    d = os.path.join(root, '.context', 'backlog')
    results = []
    for f in sorted(os.listdir(d)):
        if not f.endswith('.md') or f.startswith('00-'):
            continue
        it = parse(os.path.join(d, f))
        if not it or it['fm'].get('status') not in ('open', 'doing'):
            continue
        if only and it['fm'].get('id') not in only:
            continue
        results.append(check(root, it))
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('ids', nargs='*', help='limit to these BL-NNN ids')
    ap.add_argument('--json', action='store_true')
    ap.add_argument('--quiet', action='store_true', help='summary line only')
    a = ap.parse_args()
    root = find_root()
    results = scan(root, set(a.ids) or None)
    under = [r for r in results if not r['defined']]
    cl = clusters(results)
    if a.json:
        print(json.dumps({'items': results, 'underdefined': len(under), 'clusters': cl}, indent=2))
        return 1 if under else 0
    if not a.quiet:
        for r in results:
            mark = 'ok ' if r['defined'] else '!! '
            print(f"{mark}{r['id']:8} {r['estimate']:3} {r['title'][:60]}")
            if r['missing']:
                print(f"           missing: {', '.join(r['missing'])}")
            if r['touches_candidates']:
                print(f"           touches?: {', '.join(r['touches_candidates'][:6])}")
            if r['cross_repo']:
                print(f"           cross-repo: {', '.join(r['cross_repo'][:6])}")
            if r['cites']:
                print(f"           cites: {', '.join(r['cites'])}")
        if cl:
            print('\nclusters (shared touches token, or citations between open items):')
            for tok, ids in cl.items():
                print(f"  {tok}: {', '.join(ids)}")
        print()
    print(f"definition: {len(results) - len(under)}/{len(results)} defined, {len(under)} underdefined"
          + (" — front-matter fields: define-item.sh; Context/Acceptance: edit the body" if under else ""))
    return 1 if under else 0


if __name__ == '__main__':
    sys.exit(main())
