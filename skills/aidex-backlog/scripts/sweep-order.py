#!/usr/bin/env python3
"""sweep-order.py — cluster-order a sweep queue from sweep-eligible.py's JSON (stdin).

Pure data work, kept out of sweep-kickoff.sh so it is testable and so bash 3.2 never
parses Python: union-find over `touches:` tokens (items sharing a token cluster
adjacently), a stable topological order over `depends:` (Kahn; priority, estimate, file
as the tiebreak so the same backlog always yields the same queue), and `merge:BL-NNN`
marking a MERGE pair — the same change seen twice, closed in one commit carrying both
`Backlog:` trailers.

usage: sweep-order.py <backlog-dir> [--include BL-N,..] [--exclude BL-N,..]
                      [--format json|summary|refs]
Exit 2 on a `depends:` cycle (a queue that cannot be ordered is a kickoff error).
"""
import argparse, json, os, re, sys


def fm(path):
    t = open(path).read()
    m = re.match(r'---\n(.*?)\n---', t, re.S)
    return {k: v.strip().strip('"') for k, v in re.findall(r'^([\w_]+):\s*(.*)$', m.group(1), re.M)} if m else {}


RANK = {'XS': 0, 'S': 1, 'M': 2, 'L': 3, 'XL': 4}


def order(part, bdir, inc, exc):
    queue = [i for i in part['eligible'] if i['id'] not in exc]
    queue += [i for i in part['review'] if i['id'] in inc]
    review_out = [i for i in part['review'] if i['id'] not in inc]
    by_id = {i['id']: i for i in queue}
    for i in queue:
        f = fm(os.path.join(bdir, i['file']))
        i['touches'] = [t.strip() for t in f.get('touches', '').split(',') if t.strip()]
        i['depends'] = [d.strip() for d in f.get('depends', '').split(',') if d.strip()]
        i['surface'] = f.get('surface') or 'internal'
    parent = {i['id']: i['id'] for i in queue}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        parent[find(a)] = find(b)

    owner = {}
    for i in queue:
        for t in i['touches']:
            if t in owner:
                union(i['id'], owner[t])
            else:
                owner[t] = i['id']
    merge_pairs = set()
    for i in queue:
        for d in i['depends']:
            if d.startswith('merge:') and d[6:] in by_id:
                union(i['id'], d[6:])
                merge_pairs.add(frozenset((i['id'], d[6:])))
    clusters = {}
    for i in queue:
        clusters.setdefault(find(i['id']), []).append(i)

    def key(i):
        return (i['priority'], RANK.get(i['estimate'].upper(), 9), i['file'])

    edges = {i['id']: set() for i in queue}
    for i in queue:
        for d in i['depends']:
            if not d.startswith('merge:') and d in by_id:
                edges[i['id']].add(d)
    cid = {i['id']: find(i['id']) for i in queue}
    cl_edges = {c: set() for c in clusters}
    for a, deps in edges.items():
        for b in deps:
            if cid[a] != cid[b]:
                cl_edges[cid[a]].add(cid[b])

    def kahn(nodes, deps, k):
        done, pending = [], set(nodes)
        while pending:
            ready = sorted([n for n in pending if not (deps[n] & pending)], key=k)
            if not ready:
                print('depends: cycle among ' + ', '.join(sorted(pending)), file=sys.stderr)
                sys.exit(2)
            done.append(ready[0])
            pending.remove(ready[0])
        return done

    cl_order = kahn(clusters.keys(), cl_edges, lambda c: min(key(i) for i in clusters[c]))
    out = []
    for c in cl_order:
        members = {i['id'] for i in clusters[c]}
        seq = kahn(members, {m: edges[m] & members for m in members}, lambda m: key(by_id[m]))
        label = sorted({t for m in members for t in by_id[m]['touches']})
        out.append({'cluster': ', '.join(label) or by_id[seq[0]]['title'][:40],
                    'merge': any(p <= members for p in merge_pairs),
                    'items': [{k: by_id[m][k] for k in ('id', 'title', 'priority', 'estimate', 'surface', 'touches', 'depends')} for m in seq]})
    return {'queue': out, 'review': review_out, 'needs_decision': part['needs_decision'],
            'n_eligible': len(queue), 'fan_out': len(queue) > 20}


def summary(d):
    print("QUEUE (%d items, %d clusters) — in execution order" % (d["n_eligible"], len(d["queue"])))
    n = 1
    for c in d["queue"]:
        print("  cluster: %s%s" % (c["cluster"], " [MERGE — one commit, all trailers]" if c["merge"] else ""))
        for i in c["items"]:
            dep = ("  depends: " + ", ".join(i["depends"])) if i["depends"] else ""
            print("    %2d. %-8s %-3s %-3s %-9s %s%s" % (n, i["id"], i["priority"], i["estimate"], i["surface"], i["title"][:52], dep))
            n += 1
    if d["fan_out"]:
        print("\nFAN OUT: %d > 20 eligible — triage with parallel readers (5 was the measured shape);" % d["n_eligible"])
        print("  each reader writes its verdict with sweep-triage.sh (estimate, surface, verify, touches, depends),")
        print("  then re-run the kickoff so the queue is ordered from the corrected items.")
    print("\nREVIEW (%d) — defined, but READ the body before starting; re-run with --include <id> to queue it" % len(d["review"]))
    for i in d["review"]:
        print("  %-8s %-3s %-3s  %-34s %s" % (i["id"], i["priority"], i["estimate"], i["reason"][:34], i["title"][:40]))
    print("\nNEEDS-DECISION (%d) — ONE consultation artifact, never into the run" % len(d["needs_decision"]))
    for i in d["needs_decision"]:
        print("  %-8s %-3s %-3s  %-22s %s" % (i["id"], i["priority"], i["estimate"], i["reason"], i["title"][:50]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('backlog_dir')
    ap.add_argument('--include', default='')
    ap.add_argument('--exclude', default='')
    ap.add_argument('--format', default='json', choices=['json', 'summary', 'refs'])
    a = ap.parse_args()
    split = lambda s: {x.strip() for x in s.split(',') if x.strip()}
    d = order(json.load(sys.stdin), a.backlog_dir, split(a.include), split(a.exclude))
    if a.format == 'json':
        print(json.dumps(d))
    elif a.format == 'summary':
        summary(d)
    else:  # refs — one tab-separated row per queued item, in order
        for c in d["queue"]:
            for i in c["items"]:
                print("\t".join([i["id"], i["title"].replace("\t", " "), c["cluster"].replace("\t", " "), "MERGE" if c["merge"] else ""]))


if __name__ == '__main__':
    main()
