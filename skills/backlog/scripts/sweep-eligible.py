#!/usr/bin/env python3
"""sweep-eligible.py — partition open backlog items for an autonomous sweep.

An item is ELIGIBLE only when it is DEFINED — the contract define-check.py reads
(type, priority, estimate, surface, verify, touches, Context, Acceptance) — and
nothing parks it: not blocked, not awaiting the owner, and not living in another
repo (`touches` / cited paths under a sibling project — a sweep of THIS repo cannot
close it). Everything else is NEEDS-DECISION and belongs in the kickoff consultation,
not in the run; "underdefined" is answered by `/aidex:backlog define`, not by the
sweep (owner's call 2026-08-27, Q8).

Measured on one project 2026-08-24 (research/2026-08-24-small-sweep-throughput-analysis):
25% of a 79-item sweep carried no Acceptance, and the two worst rework items —
four commits each, across two repos — were both in that group.

Usage:
  sweep-eligible.py [--size XS,S] [--json]
"""
import argparse, datetime, hashlib, json, os, re, signal, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import importlib
define_check = importlib.import_module('define-check')


ROOT = None


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


APPROVE = 'approve'  # ready(): a cmd: whose hash is not in the local allowlist — shown, never run


def cmd_hash(root, cmd):
    return hashlib.sha256((os.path.realpath(root) + '\n' + cmd).encode()).hexdigest()


def approved(cmd):
    """A cmd: front-matter value is arbitrary shell, and a cloned repo's backlog is not trusted:
    it runs only when the owner put sha256(root \\n cmd) into the local, untracked allowlist
    with approve-ready-when.sh (which needs a terminal, so an agent cannot)."""
    path = os.path.expanduser('~/.claude/aidex/ready-when-allow.txt')  # fixed: a repo-shipped env cannot move it
    root = os.path.realpath(ROOT)
    real = os.path.realpath(path)
    if real == root or real.startswith(root + os.sep):  # an allowlist inside the project is the project's, not the owner's
        return False
    try:
        return cmd_hash(ROOT, cmd) in open(path).read().split()
    except OSError:
        return False


def show(text):
    """Text for a terminal: every non-printable character escaped (`\\x1b`), so a cmd: cannot hide itself."""
    return ''.join(c if c.isprintable() else c.encode('unicode_escape').decode() for c in text)


def approve_line(bl):
    """The owner's copy-ready approval line, or None: the id comes from front matter, so
    only a plain BL-NNN id is ever printed into a shell line."""
    if not re.fullmatch(r'BL-\d+', bl or ''):
        return None
    import shlex
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'approve-ready-when.sh')
    return f"! bash {shlex.quote(script)} {bl}   (owner only: agents must not run this)"


def ready(value):
    """`ready_when` -> True (met), False (not met), APPROVE (a cmd: nobody approved) or None
    (no value / not a known form). `date:YYYY-MM-DD` is met on or after that day; an approved
    `cmd:<shell>` is met when it exits 0 (run from the project root, 10 s cap — a timeout counts
    as not met)."""
    kind, _, arg = value.partition(':')
    arg = arg.strip()
    if kind == 'date':
        if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', arg):  # fromisoformat also takes 20261005 and 2026-W40-1
            return None
        try:
            return datetime.date.today() >= datetime.date.fromisoformat(arg)
        except ValueError:  # 2026-02-30: the form defer-item.sh refuses, not a wait
            return None
    if kind == 'cmd' and arg:
        if not approved(arg):
            return APPROVE
        proc = subprocess.Popen(arg, shell=True, cwd=ROOT, start_new_session=True, stdin=subprocess.DEVNULL,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            return proc.wait(timeout=10) == 0
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)  # the shell's children too, not just the shell
            except (ProcessLookupError, PermissionError):
                pass  # it exited between the timeout and the kill
            proc.wait()
            return False
    return None


def ready_when_of(path, fm):
    """The `ready_when` value as written: defer-item.sh stores it yaml-escaped (`\\"`, `\\\\`), and
    define-check's unquote only strips quotes, which would hand the shell the escaped text."""
    m = re.search(r'^ready_when:[ \t]*(.*)$', open(path, encoding='utf-8').read().split('\n---', 1)[0], re.M)
    raw = m.group(1).strip() if m else ''
    if raw.startswith('"') and raw.endswith('"') and len(raw) >= 2:
        try:
            return json.loads(raw)
        except ValueError:
            pass
    return fm.get('ready_when', '')


def deferred_items(root):
    """Every `_deferred/` item with the verdict of its `ready_when`."""
    d = os.path.join(root, '.context', 'backlog', '_deferred')
    out = []
    for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if not f.endswith('.md') or f.startswith('00-'):
            continue
        it = define_check.parse(os.path.join(d, f))
        if not it:
            continue
        fm = it['fm']
        rw = ready_when_of(os.path.join(d, f), fm)
        r = ready(rw) if rw else None
        bad = bool(rw) and r is None
        if r == APPROVE:
            r, verdict = None, 'NEEDS APPROVAL'
        else:
            verdict = 'BAD FORM' if bad else 'ASK OWNER' if r is None else 'READY' if r else 'WAITING'
        out.append({'id': fm.get('id', '?'), 'priority': fm.get('priority', '-'), 'title': fm.get('title', ''),
                    'ready_when': rw, 'blocked_by': fm.get('blocked_by', ''), 'file': f,
                    'verdict': verdict})
    return out


_QUEUED = re.compile(r'^[ \t]*\d+\.[ \t]+\[ \][ \t]+(BL-\d+)\b', re.M)


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
    d = define_check.parse(path)
    if d is None:
        return None
    fm = d['fm']
    dc = define_check.check(ROOT, d)
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
        'ready_when': ready_when_of(path, fm),
        'signals': body_signals(d['text']),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--size', default='', help='comma-separated estimates to keep, e.g. XS,S')
    ap.add_argument('--json', action='store_true')
    a = ap.parse_args()
    sizes = [s.strip().upper() for s in a.size.split(',') if s.strip()]

    global ROOT
    ROOT = define_check.find_root()
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
        elif i['ready_when'] and (i.setdefault('ready', ready(i['ready_when']))) is not True:
            rw = i['ready_when']
            i['reason'] = 'waiting: ' + ('needs approval: ' + show(rw[4:].strip()) if i['ready'] == APPROVE else show(rw))
            review.append(i)
        elif i['signals']:
            i['reason'] = ', '.join(i['signals'])
            review.append(i)
        else:
            eligible.append(i)

    # cheapest first inside each priority, oldest first on ties
    rank = dict(define_check.ESTIMATE_RANK, **{'-': 5})  # '-': no estimate, ahead of an unknown one
    eligible.sort(key=lambda i: (i['priority'], rank.get(i['estimate'].upper(), 9), i['file']))

    review.sort(key=lambda i: (i['priority'], rank.get(i['estimate'].upper(), 9), i['file']))

    deferred = deferred_items(ROOT)

    if a.json:
        open_wl = {}
        for where in queued.values():
            open_wl[where] = open_wl.get(where, 0) + 1
        print(json.dumps({'eligible': eligible, 'review': review, 'needs_decision': needs,
                          'deferred': deferred,
                          'open_worklists': open_wl}, indent=2))
        return

    print(f'ELIGIBLE ({len(eligible)}) — defined (define-check.py), in this repo, no autonomy signal')
    for i in eligible:
        print(f"  {i['id']:8} {i['priority']:3} {i['estimate']:3}  {i['title'][:70]}")
    print()
    print(f'REVIEW ({len(review)}) — defined, but read the body before starting')
    for i in review:
        # the reason carries the quoted sentence; a 34-char column cut it at «A decision
        label, _, quote = i['reason'].partition(' — ')
        print(f"  {i['id']:8} {i['priority']:3} {i['estimate']:3}  {label[:34]:34} {i['title'][:40]}")
        if len(label) > 34:  # `waiting: <value>`: the clipped part is the value the reader needs
            print(f"  {'':8} {'':3} {'':3}  {label}")
        if quote:
            print(f"  {'':8} {'':3} {'':3}  {quote}")
    print()
    print(f'NEEDS-DECISION ({len(needs)}) — route to the user, never into the run')
    for i in needs:
        print(f"  {i['id']:8} {i['priority']:3} {i['estimate']:3}  {i['reason'][:40]:40} {i['title'][:40]}")
        if len(i['reason']) > 40:  # the clipped part is the work-list name — the part the reader needs
            print(f"  {'':8} {'':3} {'':3}  {i['reason']}")
    print()
    print(f'DEFERRED — condition check ({len(deferred)}) — READY items go back with `defer-item.sh reactivate`')
    for i in deferred:
        rw = show(i['ready_when'])
        why = {'READY': rw, 'WAITING': rw,
               'NEEDS APPROVAL': 'not run, not approved: ' + rw,
               'BAD FORM': 'ready_when ' + rw + ' (not date:YYYY-MM-DD or cmd:...)',
               'ASK OWNER': 'blocked_by ' + i['blocked_by']}[i['verdict']]
        print(f"  {i['id']:8} {i['priority']:3} {i['verdict']:14} {i['title'][:50]}")
        print(f"  {'':8} {'':3} {'':14} {why}")
        if i['verdict'] == 'NEEDS APPROVAL':
            print(f"  {'':8} {'':3} {'':14} {approve_line(i['id']) or 'approve it by hand: id ' + show(i['id']) + ' is not BL-NNN'}")


if __name__ == '__main__':
    main()
