#!/usr/bin/env python3
"""sweep-report.py — render a sweep's report from what is already on disk.

Never hand-narrated: every section is derived from the work-list, the backlog items it
queued (active or archived), the gate history sweep-gate.sh appends, and git. Called by
sweep-report.sh, which resolves the project root and the output path.

usage: sweep-report.py <project-root> <worklist-path> [--out <file>] [--print] [--lang <code>]

`--lang` (default en) localizes the generator's own prose only — for the PAGE render;
the `.md` record is always rendered en (BL-382).
"""
import json, os, re, subprocess, sys
from datetime import datetime

# BL-382: the generator's OWN prose, per language. The .md is a `.context/` record
# and is always rendered `en` (D-04); the page beside it is what the owner reads —
# it carries the owner rows and the needs-decision list — so it is rendered a
# second time in the profile's `language:`. Quoted material (item titles, owner
# rows, gate rows, work-list lines) is never translated: it is what is on disk.
STRINGS = {
    'en': {},
    'es': {
        'Sweep report': 'Informe del sweep',
        'Generated from disk by `sweep-report.sh` on {today}; anchored to `worklist/{wl}` (status `{status}`, gate policy publish `{publish}`).':
            'Generado desde disco por `sweep-report.sh` el {today}; anclado a `worklist/{wl}` (estado `{status}`, política de gate publish `{publish}`).',
        'see worklist': 'ver work-list',
        '## Metrics': '## Métricas',
        '| metric | value |': '| métrica | valor |',
        'items queued at kickoff': 'items en cola al kickoff',
        '? (no queue-size-at-kickoff line)': '? (sin línea queue-size-at-kickoff)',
        'items closed': 'items cerrados',
        'commits (from `commits:`)': 'commits (desde `commits:`)',
        'emergent items appended': 'items emergentes añadidos',
        '  **> 25 % of the original queue**': '  **> 25 % de la cola original**',
        'wall time (first → last resolving commit)': 'tiempo total (primer → último commit resolutivo)',
        '? (fewer than two dated commits)': '? (menos de dos commits con fecha)',
        'time in boundary-gate suites': 'tiempo en suites del boundary gate',
        '? (no gate-history.jsonl)': '? (sin gate-history.jsonl)',
        'share of wall time in gate suites': 'proporción del tiempo total en suites del gate',
        ' — per-item targeted runs are not measured': ' — las corridas dirigidas por item no se miden',
        'gate runs / legs re-run': 'corridas del gate / legs repetidos',
        '## Closed items': '## Items cerrados',
        '_none_': '_ninguno_',
        ' (emergent)': ' (emergente)',
        '- estimate `{estimate}` · surface `{surface}` · commits: {commits}': '- estimación `{estimate}` · superficie `{surface}` · commits: {commits}',
        '_none recorded_': '_ninguno registrado_',
        '| kind | what | proof |': '| tipo | qué | prueba |',
        '| — | no verification rows | |': '| — | sin filas de verificación | |',
        '## Awaiting owner — proven, parked, not closed': '## Esperando al owner — probados, aparcados, sin cerrar',
        '_Mechanically proven; each still owes a judgement. Fill the proof cell, then `close-item.sh --sweep` again. Never archive by hand._':
            '_Probados mecánicamente; cada uno debe todavía un juicio. Rellena la celda de prueba y vuelve a ejecutar `close-item.sh --sweep`. Nunca archives a mano._',
        '## Owner rows — what only the owner can judge': '## Filas del owner — lo que solo el owner puede juzgar',
        '| item | what | answer |': '| item | qué | respuesta |',
        '**unanswered**': '**sin responder**',
        'human-verification: skipped — no queued item carries an owner row (nothing only a person can judge)':
            'human-verification: omitida — ningún item en cola lleva una fila owner (nada que solo una persona pueda juzgar)',
        '## Needs decision — unchanged and unattempted': '## Necesita decisión — sin cambios y sin intentar',
        '_none recorded at kickoff_': '_ninguna registrada al kickoff_',
        '## Deferrals and mid-flight skips': '## Aplazamientos y saltos a mitad de corrida',
        '## Boundary gate — verbatim': '## Boundary gate — literal',
        '- run {i} ({at}): verdict **{verdict}**': '- corrida {i} ({at}): veredicto **{verdict}**',
        '_no gate run recorded (`.context/proofs/sweep-gate/gate-history.jsonl` absent) — the boundary gate did not run, or ran elsewhere_':
            '_sin corrida del gate registrada (falta `.context/proofs/sweep-gate/gate-history.jsonl`) — el boundary gate no corrió, o corrió en otro sitio_',
    },
}


def tr(lang, s):
    return STRINGS.get(lang, {}).get(s, s)


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


def render(root, wl_path, lang='en'):
    T = lambda s: tr(lang, s)
    wl_text = open(wl_path, encoding='utf-8', errors='replace').read()
    wl_fm, wl_body = fm_and_body(wl_text)
    wl_file = os.path.basename(wl_path)
    queue_lines = [ln for ln in section(wl_body, 'Queue').splitlines() if re.match(r'^\d+\. \[[ x]\] ', ln)]
    kickoff_n = re.search(r'^queue-size-at-kickoff:\s*(\d+)', wl_text, re.M)
    kickoff_n = int(kickoff_n.group(1)) if kickoff_n else None
    emergent_n = sum(1 for ln in queue_lines if '<!-- emergent -->' in ln)

    closed, skipped, owner_rows, all_shas, parked = [], [], [], [], []
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
        # `commits:` may read `backend 25e07c2 frontend 5b4e89b` in a multi-repo project:
        # the repo names locate the hash and are not commits (they were counted, 2026-08-28)
        shas = [s for s in it['fm'].get('commits', '').split() if re.fullmatch(r'[0-9a-f]{7,40}', s)]
        if it['state'] == 'archived' and st == 'done':
            closed.append({'id': bl, 'title': it['fm'].get('title', ''), 'commits': shas, 'rows': rows,
                           'surface': it['fm'].get('surface', 'internal'), 'estimate': it['fm'].get('estimate', '-'),
                           'emergent': '<!-- emergent -->' in ln})
            all_shas += shas
        elif it['state'] == 'archived':
            skipped.append((bl, f'closed as {st}'))
        elif it['fm'].get('awaiting'):
            parked.append({'id': bl, 'title': it['fm'].get('title', ''), 'rows': rows,
                           'open': [r for r in rows if r['kind'] == 'owner' and not r['proof']]})
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
    hist_path = os.path.join(root, '.context', 'proofs', 'sweep-gate', 'gate-history.jsonl')
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
    out.append(f'title: "{T("Sweep report")} — {wl_fm.get("title", wl_file)}"')
    out.append('status: done')
    out.append(f'created: {today}')
    out.append(f'updated: {today}')
    out.append('origin: sweep')
    out.append(f'origin_ref: worklist/{wl_file}')
    out.append('proof_links:')
    out.append(f'  - worklist/{wl_file}')
    if runs:
        out.append('  - .context/proofs/sweep-gate/gate-history.jsonl')
    out.append('---')
    out.append('')
    out.append(f'# {T("Sweep report")} — {wl_fm.get("title", wl_file)}')
    out.append('')
    out.append(T('Generated from disk by `sweep-report.sh` on {today}; anchored to `worklist/{wl}` (status `{status}`, gate policy publish `{publish}`).')
               .format(today=today, wl=wl_file, status=wl_fm.get('status', '?'),
                       publish=wl_fm.get('publish', '?') if 'publish' in wl_fm else T('see worklist')))
    out.append('')
    out.append(T('## Metrics'))
    out.append('')
    out.append(T('| metric | value |'))
    out.append('|---|---|')
    out.append(f'| {T("items queued at kickoff")} | {kickoff_n if kickoff_n is not None else T("? (no queue-size-at-kickoff line)")} |')
    out.append(f'| {T("items closed")} | {len(closed)} |')
    out.append(f'| {T("commits (from `commits:`)")} | {len(all_shas)} |')
    out.append(f'| {T("emergent items appended")} | {emergent_n}{T("  **> 25 % of the original queue**") if kickoff_n and emergent_n > 0.25 * kickoff_n else ""} |')
    out.append(f'| {T("wall time (first → last resolving commit)")} | {("%.1f h" % (wall / 3600)) if wall is not None else T("? (fewer than two dated commits)")} |')
    out.append(f'| {T("time in boundary-gate suites")} | {"%d s" % gate_secs if runs else T("? (no gate-history.jsonl)")} |')
    out.append(f'| {T("share of wall time in gate suites")} | {("%.0f %%" % share) if share is not None else "?"}{T(" — per-item targeted runs are not measured")} |')
    out.append(f'| {T("gate runs / legs re-run")} | {len(runs)} / {leg_reruns} |')
    out.append('')
    out.append(T('## Closed items'))
    out.append('')
    if not closed:
        out.append(T('_none_'))
    for c in closed:
        tag = T(' (emergent)') if c['emergent'] else ''
        out.append(f'### {c["id"]} — {c["title"]}{tag}')
        out.append('')
        out.append(T('- estimate `{estimate}` · surface `{surface}` · commits: {commits}').format(
            estimate=c['estimate'], surface=c['surface'],
            commits=', '.join('`' + s + '`' for s in c['commits']) or T('_none recorded_')))
        out.append('')
        out.append(T('| kind | what | proof |'))
        out.append('|---|---|---|')
        for r in c['rows']:
            out.append(f'| {r["kind"]} | {r["what"]} | {r["proof"]} |')
        if not c['rows']:
            out.append(T('| — | no verification rows | |'))
        out.append('')
    out.append(T('## Awaiting owner — proven, parked, not closed'))
    out.append('')
    if parked:
        out.append(T('_Mechanically proven; each still owes a judgement. Fill the proof cell, then `close-item.sh --sweep` again. Never archive by hand._'))
        out.append('')
        for c in parked:
            out.append(f'- {c["id"]} — {c["title"]}: ' + '; '.join(r['what'] for r in c['open']))
    else:
        out.append(T('_none_'))
    out.append('')
    out.append(T('## Owner rows — what only the owner can judge'))
    out.append('')
    if owner_rows:
        out.append(T('| item | what | answer |'))
        out.append('|---|---|---|')
        for r in owner_rows:
            out.append(f'| {r["id"]} — {r["title"]} | {r["what"]} | {r["proof"] or T("**unanswered**")} |')
    else:
        out.append(T('human-verification: skipped — no queued item carries an owner row (nothing only a person can judge)'))
    out.append('')
    out.append(T('## Needs decision — unchanged and unattempted'))
    out.append('')
    out.extend(needs or [T('_none recorded at kickoff_')])
    out.append('')
    out.append(T('## Deferrals and mid-flight skips'))
    out.append('')
    for bl, why in skipped:
        out.append(f'- {bl}: {why}')
    out.extend(deferred_lines)
    out.extend(forced)
    if not skipped and not deferred_lines and not forced:
        out.append(T('_none_'))
    out.append('')
    out.append(T('## Boundary gate — verbatim'))
    out.append('')
    if runs:
        for i, run in enumerate(runs, 1):
            verdict = next((r for r in run if 'verdict' in r), {})
            out.append(T('- run {i} ({at}): verdict **{verdict}**').format(i=i, at=verdict.get('at', '?'), verdict=verdict.get('verdict', '?')))
            for r in run:
                if 'leg' in r:
                    out.append(f'  - leg={r["leg"]} exit={r["exit"]} count={r["count"]} secs={r.get("secs", "-")}')
    else:
        out.append(T('_no gate run recorded (`.context/proofs/sweep-gate/gate-history.jsonl` absent) — the boundary gate did not run, or ran elsewhere_'))
    out.append('')
    return '\n'.join(out) + '\n'


def main():
    argv = sys.argv[1:]
    args = [a for i, a in enumerate(argv) if not a.startswith('--') and (i == 0 or argv[i-1] not in ('--out', '--lang'))]
    root, wl = args[0], args[1]
    out = None
    if '--out' in sys.argv:
        out = sys.argv[sys.argv.index('--out') + 1]
    lang = sys.argv[sys.argv.index('--lang') + 1] if '--lang' in sys.argv else 'en'
    text = render(root, wl, lang)
    if '--print' in sys.argv or not out:
        sys.stdout.write(text)
        return
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, 'w', encoding='utf-8').write(text)
    print(out)


if __name__ == '__main__':
    main()
