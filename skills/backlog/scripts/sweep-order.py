#!/usr/bin/env python3
"""sweep-order.py — cluster-order a sweep queue from sweep-eligible.py's JSON (stdin).

Pure data work, kept out of sweep-kickoff.sh so it is testable and so bash 3.2 never
parses Python: union-find over `touches:` tokens (items sharing a token cluster
adjacently), a stable topological order over `depends:` (Kahn; priority, estimate, file
as the tiebreak so the same backlog always yields the same queue), and `merge:BL-NNN`
marking a MERGE pair — the same change seen twice, closed in one commit carrying both
`Backlog:` trailers. An item whose dependency or MERGE twin is open (or unknown) and not
in the queue is moved to needs_decision (`depends on open BL-NNN`), never queued.

usage: sweep-order.py <backlog-dir> [--include BL-N,..] [--exclude BL-N,..]
                      [--format json|summary|refs]
Exit 2 on a `depends:` cycle (a queue that cannot be ordered is a kickoff error).
"""
import argparse, importlib, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
define_check = importlib.import_module('define-check')


def fm(path):
    return (define_check.parse(path) or {'fm': {}})['fm']


RANK = define_check.ESTIMATE_RANK


class Cycle(Exception):
    """Kahn stalled: .pending is every node it could not place."""


def kahn(nodes, deps, k, fatal=True):
    done, pending = [], set(nodes)
    while pending:
        ready = sorted([n for n in pending if not (deps[n] & pending)], key=k)
        if not ready:
            if not fatal:
                raise Cycle(pending)
            print('depends: cycle among ' + ', '.join(sorted(pending)), file=sys.stderr)
            sys.exit(2)
        done.append(ready[0])
        pending.remove(ready[0])
    return done


def order(part, bdir, inc, exc):
    queue = [i for i in part['eligible'] if i['id'] not in exc]
    queue += [i for i in part['review'] if i['id'] in inc]
    review_out = [i for i in part['review'] if i['id'] not in inc]
    for i in queue:
        f = fm(os.path.join(bdir, i['file']))
        i['touches'] = [t.strip() for t in f.get('touches', '').split(',') if t.strip()]
        i['depends'] = [d.strip() for d in f.get('depends', '').split(',') if d.strip()]
        i['surface'] = f.get('surface') or 'internal'
    # BL-605: a dependency or MERGE twin that is still open (active or _deferred/) or found
    # nowhere (a typo) and is not in this queue blocks the item; closed ones live in
    # _archive/. Repeat until stable so an item depending on a just-blocked item is blocked
    # too. A cycle is reported first: blocking would otherwise hide it.
    ids = {i['id'] for i in queue}
    kahn(ids, {i['id']: {d for d in i['depends'] if d in ids} for i in queue}, lambda n: n)
    # Twins come from every backlog file, not only queued ones: the item holding the
    # `merge:` edge may sit outside the queue (off --size, review not included).
    still_open, known, twins = set(), set(), {}
    for d in (bdir, os.path.join(bdir, '_deferred'), os.path.join(bdir, '_archive')):
        for f in (sorted(os.listdir(d)) if os.path.isdir(d) else []):
            if f.endswith('.md') and not f.startswith('00-'):
                m = fm(os.path.join(d, f))
                known.add(m.get('id'))
                if m.get('status') in ('open', 'doing') and not d.endswith('_archive'):
                    still_open.add(m.get('id'))
                for dep in (x.strip() for x in m.get('depends', '').split(',')):
                    if dep.startswith('merge:'):
                        twins.setdefault(m.get('id'), set()).add(dep[6:])
                        twins.setdefault(dep[6:], set()).add(m.get('id'))
    needs = list(part['needs_decision'])
    while True:
        ids = {i['id'] for i in queue}
        outside = lambda x: x not in ids and (x in still_open or x not in known)
        blocked = {}
        for i in queue:
            deps = [d for d in i['depends'] if not d.startswith('merge:') and outside(d)]
            opn, unk = [d for d in deps if d in known], [d for d in deps if d not in known]
            tw = sorted(x for x in twins.get(i['id'], ()) if outside(x))
            why = (['depends on open ' + ', '.join(opn)] if opn else []) \
                + (['depends on unknown ' + ', '.join(unk)] if unk else []) \
                + (['merge partner ' + ', '.join(tw) + ' not queued'] if tw else [])
            if why:
                blocked[i['id']] = '; '.join(why)
        if not blocked:
            break
        for i in queue:
            if i['id'] in blocked:
                i['reason'] = blocked[i['id']]
                needs.append(i)
        queue = [i for i in queue if i['id'] not in blocked]
    n_blocked = len(needs) - len(part['needs_decision'])
    by_id = {i['id']: i for i in queue}

    def key(i):
        return (i['priority'], RANK.get(i['estimate'].upper(), 9), i['file'])

    edges = {i['id']: set() for i in queue}
    for i in queue:
        for d in i['depends']:
            if not d.startswith('merge:') and d in by_id:
                edges[i['id']].add(d)

    # Clusters are contracted `touches:` groups plus MERGE pairs. Contracting can turn an
    # acyclic item graph into a cyclic cluster graph (A -> x -> B with A and B sharing a
    # token), so a cycle is no verdict on the items: break up only the `touches:` clusters
    # that sit on the stalled cycle and retry. A cycle that survives that runs through a
    # MERGE pair, which cannot be kept adjacent: refuse, naming the pair.
    loose = set()
    while True:
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
            if i['id'] in loose:
                continue
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
        cid = {i['id']: find(i['id']) for i in queue}
        cl_edges = {c: set() for c in clusters}
        for a, deps in edges.items():
            for b in deps:
                if cid[a] != cid[b]:
                    cl_edges[cid[a]].add(cid[b])
        try:
            cl_order = kahn(clusters.keys(), cl_edges, lambda c: min(key(i) for i in clusters[c]), fatal=False)
            break
        except Cycle as e:
            core = set(e.args[0])  # drop what only waits on the cycle: keep nodes something in `core` needs
            while True:
                needed = {d for n in core for d in cl_edges[n] & core}
                if needed == core:
                    break
                core = needed
            members = {i['id'] for c in core for i in clusters[c]}
            grown = loose | members
            if grown == loose:
                pairs = sorted('/'.join(sorted(p)) for p in merge_pairs if p <= members)
                print('depends: cycle through MERGE pair ' + ', '.join(pairs or sorted(members))
                      + ' (its twins cannot stay adjacent)', file=sys.stderr)
                sys.exit(2)
            loose = grown
    out = []
    for c in cl_order:
        members = {i['id'] for i in clusters[c]}
        seq = kahn(members, {m: edges[m] & members for m in members}, lambda m: key(by_id[m]))
        label = sorted({t for m in members for t in by_id[m]['touches']})
        out.append({'cluster': ', '.join(label) or by_id[seq[0]]['title'][:40],
                    'merge': any(p <= members for p in merge_pairs),
                    'items': [{k: by_id[m][k] for k in ('id', 'title', 'priority', 'estimate', 'surface', 'touches', 'depends')} for m in seq]})
    return {'queue': out, 'review': review_out, 'needs_decision': needs,
            'n_eligible': len(queue), 'n_blocked': n_blocked, 'fan_out': len(queue) > 20,
            'deferred': part.get('deferred', [])}


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
        print("  each reader writes its verdict with define-item.sh (estimate, surface, verify, touches, depends),")
        print("  then re-run the kickoff with --dry-run until triage is done (a real run writes the work-list, and a second one the same day is refused).")
    print("\nREVIEW (%d) — defined, but READ the body before starting; re-run with --include <id> to queue it" % len(d["review"]))
    for i in d["review"]:
        print("  %-8s %-3s %-3s  %-34s %s" % (i["id"], i["priority"], i["estimate"], i["reason"][:34], i["title"][:40]))
        if len(i["reason"].partition(" — ")[0]) > 34:  # `waiting: <value>`: the clipped part is the value the reader needs
            print("  %-8s %-3s %-3s  %s" % ("", "", "", i["reason"]))
    print("\nNEEDS-DECISION (%d) — ONE consultation artifact, never into the run" % len(d["needs_decision"]))
    for i in d["needs_decision"]:
        print("  %-8s %-3s %-3s  %-22s %s" % (i["id"], i["priority"], i["estimate"], i["reason"], i["title"][:50]))
    shown = [i for i in d["deferred"] if i["verdict"] != "WAITING"]
    print("\nDEFERRED — condition check (%d, %d shown: READY go back with defer-item.sh reactivate, ASK OWNER need a date, BAD FORM need a fix, NEEDS APPROVAL were not written by defer)" % (len(d["deferred"]), len(shown)))
    for i in shown:
        print("  %-8s %-3s %-9s %s" % (i["id"], i["priority"], i["verdict"], i["title"][:50]))
        if i["verdict"] in ("BAD FORM", "NEEDS APPROVAL"):
            print("  %-8s %-3s %-9s ready_when %s" % ("", "", "", i["ready_when"]))


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
