#!/usr/bin/env python3
"""sweep-report.py — render a sweep's report from what is already on disk.

Never hand-narrated: every section is derived from the work-list, the backlog items it
queued (active or archived), the gate history sweep-gate.sh appends, and git. Called by
sweep-report.sh, which resolves the project root and the output path.

usage: sweep-report.py <project-root> <worklist-path> [--out <file>] [--print]
"""
import json, os, re, subprocess, sys
from datetime import datetime


def fm_and_body(text):
    m = re.match(r'---\n(.*?)\n---\n?(.*)', text, re.S)
    if not m:
        return {}, text
    fm = {k: v.strip().strip('"') for k, v in re.findall(r'^([\w_-]+):\s*(.*)$', m.group(1), re.M)}
    return fm, m.group(2)


def section(body, name):
    m = re.search(r'^## ' + re.escape(name) + r'[^\n]*\n(.*?)(?=^## |\Z)', body, re.S | re.M)
    return m.group(1) if m else ''


def verification_rows(text):
    rows = []
    for ln in section(fm_and_body(text)[1], 'Verification').splitlines():
        if not ln.startswith('|'):
            continue
        cells = [c.strip() for c in ln.strip().strip('|').split('|')]
        if not cells or cells[0] in ('kind', '') or re.match(r'^-+$', cells[0]):
            continue
        cells += [''] * (3 - len(cells))
        rows.append({'kind': cells[0], 'what': cells[1], 'proof': cells[2]})
    return rows


def find_item(root, bl_id):
    bdir = os.path.join(root, '.context', 'backlog')
    for sub, state in (('', 'active'), ('_archive', 'archived'), ('_deferred', 'deferred')):
        d = os.path.join(bdir, sub)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if not f.endswith('.md') or f.startswith('00-'):
                continue
            p = os.path.join(d, f)
            t = open(p, encoding='utf-8', errors='replace').read()
            fm, _ = fm_and_body(t)
            if fm.get('id') == bl_id:
                return {'path': p, 'state': state, 'fm': fm, 'text': t, 'file': f}
    return None


def git_times(root, shas):
    times = []
    for sha in shas:
        try:
            out = subprocess.run(['git', 'log', '-1', '--format=%ct', sha], cwd=root,
                                 capture_output=True, text=True, timeout=10)
            if out.returncode == 0 and out.stdout.strip():
                times.append(int(out.stdout.strip()))
        except (OSError, subprocess.SubprocessError):
            pass
    return times


def render(root, wl_path):
    wl_text = open(wl_path, encoding='utf-8', errors='replace').read()
    wl_fm, wl_body = fm_and_body(wl_text)
    wl_file = os.path.basename(wl_path)
    queue_lines = [ln for ln in section(wl_body, 'Queue').splitlines() if re.match(r'^\d+\. \[[ x]\] ', ln)]
    kickoff_n = re.search(r'^queue-size-at-kickoff:\s*(\d+)', wl_text, re.M)
    kickoff_n = int(kickoff_n.group(1)) if kickoff_n else None
    emergent_n = sum(1 for ln in queue_lines if '<!-- emergent -->' in ln)

    closed, skipped, owner_rows, all_shas = [], [], [], []
    for ln in queue_lines:
        if 'ref: backlog' not in ln:
            continue
        m = re.search(r'\bBL-\d+\b', ln)
        if not m:
            continue
        bl = m.group(0)
        ticked = ln.startswith(tuple(f'{i}. [x]' for i in range(1, 10000)))
        it = find_item(root, bl)
        if not it:
            skipped.append((bl, 'item not found in backlog/, _archive/ or _deferred/'))
            continue
        rows = verification_rows(it['text'])
        for r in rows:
            if r['kind'] == 'owner':
                owner_rows.append({'id': bl, 'title': it['fm'].get('title', ''), **r})
        st = it['fm'].get('status', '?')
        shas = [s for s in it['fm'].get('commits', '').split() if s]
        if it['state'] == 'archived' and st == 'done':
            closed.append({'id': bl, 'title': it['fm'].get('title', ''), 'commits': shas, 'rows': rows,
                           'surface': it['fm'].get('surface', 'internal'), 'estimate': it['fm'].get('estimate', '-'),
                           'emergent': '<!-- emergent -->' in ln})
            all_shas += shas
        elif it['state'] == 'archived':
            skipped.append((bl, f'closed as {st}'))
        elif it['state'] == 'deferred':
            skipped.append((bl, f"deferred — blocked_by: {it['fm'].get('blocked_by', '')}"))
        elif ticked:
            skipped.append((bl, f'ticked in the queue but the item is still {st} (closed out of band? never closed?)'))
        else:
            skipped.append((bl, f'not reached ({st})'))

    deferred_lines = [ln.strip() for ln in section(wl_body, 'Deferred / emergent').splitlines() if ln.strip().startswith('- [')]
    forced = [ln.strip() for ln in wl_text.splitlines() if 'with --force, overriding' in ln]
    needs = [ln.strip() for ln in section(wl_body, 'Needs decision (kickoff)').splitlines() if ln.strip().startswith('- ')]

    # the gate, verbatim: every run sweep-gate.sh appended
    hist_path = os.path.join(root, '_tmp', 'sweep-gate', 'gate-history.jsonl')
    runs = []
    if os.path.isfile(hist_path):
        for ln in open(hist_path, encoding='utf-8', errors='replace'):
            ln = ln.strip()
            if ln:
                try:
                    runs.append(json.loads(ln))
                except json.JSONDecodeError:
                    pass
    gate_secs = sum(int(r['secs']) for run in runs for r in run if 'leg' in r and str(r.get('secs', '')).isdigit())
    leg_reruns = 0
    seen = set()
    for run in runs:
        for r in run:
            if 'leg' in r:
                if r['leg'] in seen:
                    leg_reruns += 1
                seen.add(r['leg'])

    times = git_times(root, all_shas)
    wall = (max(times) - min(times)) if len(times) >= 2 else None
    share = (100.0 * gate_secs / wall) if wall else None

    today = datetime.now().strftime('%Y-%m-%d')
    out = []
    out.append('---')
    out.append(f'title: "Sweep report — {wl_fm.get("title", wl_file)}"')
    out.append('status: done')
    out.append(f'created: {today}')
    out.append(f'updated: {today}')
    out.append('origin: sweep')
    out.append(f'origin_ref: worklist/{wl_file}')
    out.append('proof_links:')
    out.append(f'  - worklist/{wl_file}')
    if runs:
        out.append('  - _tmp/sweep-gate/gate-history.jsonl')
    out.append('---')
    out.append('')
    out.append(f'# Sweep report — {wl_fm.get("title", wl_file)}')
    out.append('')
    out.append(f'Generated from disk by `sweep-report.sh` on {today}; anchored to `worklist/{wl_file}` '
               f'(status `{wl_fm.get("status", "?")}`, gate policy publish `{wl_fm.get("publish", "?") if "publish" in wl_fm else "see worklist"}`).')
    out.append('')
    out.append('## Metrics')
    out.append('')
    out.append('| metric | value |')
    out.append('|---|---|')
    out.append(f'| items queued at kickoff | {kickoff_n if kickoff_n is not None else "? (no queue-size-at-kickoff line)"} |')
    out.append(f'| items closed | {len(closed)} |')
    out.append(f'| commits (from `commits:`) | {len(all_shas)} |')
    out.append(f'| emergent items appended | {emergent_n}{"  **> 25 % of the original queue**" if kickoff_n and emergent_n > 0.25 * kickoff_n else ""} |')
    out.append(f'| wall time (first → last resolving commit) | {("%.1f h" % (wall / 3600)) if wall is not None else "? (fewer than two dated commits)"} |')
    out.append(f'| time in boundary-gate suites | {"%d s" % gate_secs if runs else "? (no gate-history.jsonl)"} |')
    out.append(f'| share of wall time in gate suites | {("%.0f %%" % share) if share is not None else "?"} — per-item targeted runs are not measured |')
    out.append(f'| gate runs / legs re-run | {len(runs)} / {leg_reruns} |')
    out.append('')
    out.append('## Closed items')
    out.append('')
    if not closed:
        out.append('_none_')
    for c in closed:
        tag = ' (emergent)' if c['emergent'] else ''
        out.append(f'### {c["id"]} — {c["title"]}{tag}')
        out.append('')
        out.append(f'- estimate `{c["estimate"]}` · surface `{c["surface"]}` · commits: {", ".join("`" + s + "`" for s in c["commits"]) or "_none recorded_"}')
        out.append('')
        out.append('| kind | what | proof |')
        out.append('|---|---|---|')
        for r in c['rows']:
            out.append(f'| {r["kind"]} | {r["what"]} | {r["proof"]} |')
        if not c['rows']:
            out.append('| — | no verification rows | |')
        out.append('')
    out.append('## Owner rows — what only the owner can judge')
    out.append('')
    if owner_rows:
        out.append('| item | what | answer |')
        out.append('|---|---|---|')
        for r in owner_rows:
            out.append(f'| {r["id"]} — {r["title"]} | {r["what"]} | {r["proof"] or "**unanswered**"} |')
    else:
        out.append('human-verification: skipped — no queued item carries an owner row (nothing only a person can judge)')
    out.append('')
    out.append('## Needs decision — unchanged and unattempted')
    out.append('')
    out.extend(needs or ['_none recorded at kickoff_'])
    out.append('')
    out.append('## Deferrals and mid-flight skips')
    out.append('')
    for bl, why in skipped:
        out.append(f'- {bl}: {why}')
    out.extend(deferred_lines)
    out.extend(forced)
    if not skipped and not deferred_lines and not forced:
        out.append('_none_')
    out.append('')
    out.append('## Boundary gate — verbatim')
    out.append('')
    if runs:
        for i, run in enumerate(runs, 1):
            verdict = next((r for r in run if 'verdict' in r), {})
            out.append(f'- run {i} ({verdict.get("at", "?")}): verdict **{verdict.get("verdict", "?")}**')
            for r in run:
                if 'leg' in r:
                    out.append(f'  - leg={r["leg"]} exit={r["exit"]} count={r["count"]} secs={r.get("secs", "-")}')
    else:
        out.append('_no gate run recorded (`_tmp/sweep-gate/gate-history.jsonl` absent) — the boundary gate did not run, or ran elsewhere_')
    out.append('')
    return '\n'.join(out) + '\n'


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    root, wl = args[0], args[1]
    out = None
    if '--out' in sys.argv:
        out = sys.argv[sys.argv.index('--out') + 1]
    text = render(root, wl)
    if '--print' in sys.argv or not out:
        sys.stdout.write(text)
        return
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, 'w', encoding='utf-8').write(text)
    print(out)


if __name__ == '__main__':
    main()
