#!/usr/bin/env python3
"""email-draft.py - turn one email spec into an email-safe HTML copy page and a plain-text twin.

Usage: email-draft.py <spec.md> [--out DIR]

Spec: front matter (subject, to, cc, language) then a markdown body. Subset supported:
paragraphs, **bold**, *italic*, [links](https://...), # headings, - / 1. lists, pipe tables,
one fenced block. Output: <name>.html (subject + recipients, each with its own copy button, on top;
the body below with one Copy email button; the page is a centered max-width column, the body and
the clipboard HTML carry no width; inline styles only) and <name>.txt. Stdlib only.
"""
import html
import re
import sys
from pathlib import Path

FONT = 'font-family:Aptos,\'Aptos Display\',Calibri,Carlito,\'Segoe UI\',Arial,sans-serif;font-size:12pt;color:#222;'
TD = 'border:1px solid #bbb;padding:4px 8px;text-align:left;vertical-align:top;'
LABELS = {'es': ('Copiar', 'Copiar correo', 'Copiado', 'Para', 'CC', 'Asunto'),
          'en': ('Copy', 'Copy email', 'Copied', 'To', 'Cc', 'Subject')}
# Copy handler: puts the body's own (inline-styled) html on the clipboard, never the page chrome.
COPY_BODY = ("document.addEventListener('copy',function(e){var b=document.getElementById('body');"
             "e.clipboardData.setData('text/html','<div style=\"" + FONT.replace("'", "\\'") + "\">'+b.innerHTML+'</div>');"
             "e.clipboardData.setData('text/plain',b.innerText);e.preventDefault()},{once:true});"
             "getSelection().selectAllChildren(document.getElementById('body'));"
             "document.execCommand('copy')")
COPY_TEXT = ("navigator.clipboard.writeText(document.getElementById('{id}').innerText)")


def parse(text):
    m = re.match(r'---\n(.*?)\n---\n?(.*)', text, re.S)
    if not m:
        sys.exit('error: spec needs a front-matter block (subject, to, cc, language)')
    meta = {}
    for line in m.group(1).splitlines():
        k, _, v = line.partition(':')
        v = v.strip()
        if len(v) > 1 and v[0] == v[-1] and v[0] in '"\'':
            v = v[1:-1]
        meta[k.strip()] = v
    if not meta.get('subject'):
        sys.exit('error: front matter needs a subject')
    return meta, m.group(2).strip('\n')


def inline(s):
    s = html.escape(s, quote=False)
    s = re.sub(r'\[([^\]]+)\]\(((?:https?://|mailto:)[^)\s]+)\)',
               lambda m: f'<a href="{html.escape(m.group(2), quote=True)}" style="color:#0b57d0;">{m.group(1)}</a>', s)
    s = re.sub(r'\*\*\*(.+?)\*\*\*', r'<strong style="font-weight:bold;"><em style="font-style:italic;">\1</em></strong>', s)
    s = re.sub(r'\*\*(.+?)\*\*', r'<strong style="font-weight:bold;">\1</strong>', s)
    s = re.sub(r'(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])', r'<em style="font-style:italic;">\1</em>', s)
    return s


def plain(s):
    s = re.sub(r'\[([^\]]+)\]\(([^)\s]+)\)', r'\1 (\2)', s)
    s = re.sub(r'\*\*\*(.+?)\*\*\*', r'\1', s)
    s = re.sub(r'\*\*(.+?)\*\*', r'\1', s)
    return re.sub(r'(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])', r'\1', s)


def cells(line):
    return [c.strip() for c in line.strip().strip('|').split('|')]


def is_sep(line):
    return bool(re.match(r'^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$', line))


HEADING = re.compile(r'#{1,6} ')
ITEM = re.compile(r'\s*([-*]|\d+[.)]) ')


def blocks(body):
    """Yield ('p'|'h'|'ul'|'ol'|'table'|'pre', payload) from the markdown subset."""
    lines = body.splitlines()
    i = 0
    while i < len(lines):
        ln = lines[i]
        if not ln.strip():
            i += 1
        elif ln.startswith('```'):
            i += 1
            buf = []
            while i < len(lines) and not lines[i].startswith('```'):
                buf.append(lines[i])
                i += 1
            i += 1
            yield 'pre', '\n'.join(buf)
        elif HEADING.match(ln):
            lvl = len(ln) - len(ln.lstrip('#'))
            yield 'h', (lvl, ln[lvl:].strip())
            i += 1
        elif '|' in ln and i + 1 < len(lines) and is_sep(lines[i + 1]):
            head = cells(ln)
            i += 2
            rows = []
            while i < len(lines) and '|' in lines[i] and lines[i].strip():
                rows.append(cells(lines[i]))
                i += 1
            yield 'table', (head, rows)
        elif re.match(r'\s*[-*] ', ln) or re.match(r'\s*\d+[.)] ', ln):
            kind = 'ul' if re.match(r'\s*[-*] ', ln) else 'ol'
            items = []
            while i < len(lines):
                if ITEM.match(lines[i]):
                    items.append(ITEM.sub('', lines[i], count=1))
                elif lines[i].strip() and lines[i][0] in ' \t' and items:
                    items[-1] += ' ' + lines[i].strip()
                else:
                    break
                i += 1
            yield kind, items
        else:
            buf = [ln.strip()]
            i += 1
            while i < len(lines) and lines[i].strip() and not lines[i].startswith('```') \
                    and not HEADING.match(lines[i]) and not ITEM.match(lines[i]) \
                    and not ('|' in lines[i] and i + 1 < len(lines) and is_sep(lines[i + 1])):
                buf.append(lines[i].strip())
                i += 1
            yield 'p', '\n'.join(buf)


def render(body):
    h, t = [], []
    for kind, p in blocks(body):
        if kind == 'p':
            h.append(f'<p style="margin:0 0 12px 0;">{inline(p).replace(chr(10), "<br>")}</p>')
            t.append(plain(p))
        elif kind == 'h':
            size = {1: 18, 2: 16}.get(p[0], 14)
            h.append(f'<h{p[0]} style="margin:0 0 10px 0;font-size:{size}pt;font-weight:bold;">{inline(p[1])}</h{p[0]}>')
            t.append(plain(p[1]).upper() if p[0] == 1 else plain(p[1]))
        elif kind in ('ul', 'ol'):
            li = ''.join(f'<li style="margin:0 0 4px 0;">{inline(x)}</li>' for x in p)
            h.append(f'<{kind} style="margin:0 0 12px 0;padding-left:24px;">{li}</{kind}>')
            t.append('\n'.join((f'{n}. ' if kind == 'ol' else '- ') + plain(x) for n, x in enumerate(p, 1)))
        elif kind == 'table':
            head, rows = p
            th = ''.join(f'<th style="{TD}background:#f1f1f1;font-weight:bold;">{inline(c)}</th>' for c in head)
            tr = ''.join('<tr>' + ''.join(f'<td style="{TD}">{inline(c)}</td>' for c in r) + '</tr>' for r in rows)
            h.append(f'<table style="border-collapse:collapse;margin:0 0 12px 0;" cellpadding="0" cellspacing="0">'
                     f'<tr>{th}</tr>{tr}</table>')
            t.append('\n'.join(' | '.join(plain(c) for c in r) for r in [head] + rows))
        elif kind == 'pre':
            h.append('<pre style="margin:0 0 12px 0;padding:8px;background:#f5f5f5;border:1px solid #ddd;'
                     f'font-family:Consolas,\'Courier New\',monospace;font-size:10pt;white-space:pre-wrap;">{html.escape(p, quote=False)}</pre>')
            t.append(p)
    return '\n'.join(h), '\n\n'.join(t) + '\n'


def page(meta, body_html):
    lang = meta.get('language', 'es')
    b_copy, b_mail, b_done, l_to, l_cc, l_subj = LABELS.get(lang, LABELS['en'])
    e = lambda s: html.escape(s)
    btn = ('font:13px sans-serif;padding:4px 12px;cursor:pointer;color:#1f5fbf;background:#fff;'
           'border:1px solid #1f5fbf;border-radius:6px;')
    # Confirmation shown on the pressed button for 1.5 s.
    done = f"var b=this,t=b.textContent;b.textContent='{b_done}';setTimeout(function(){{b.textContent=t}},1500)"
    rows = []
    for key, label in (('subject', l_subj), ('to', l_to), ('cc', l_cc)):
        val = meta.get(key)
        if val:
            rows.append(f'<div style="margin:0 0 8px 0;"><strong style="font-weight:bold;">{label}:</strong> '
                        f'<span id="{key}">{e(val)}</span> '
                        f'<button type="button" style="{btn}margin-left:8px;" '
                        f'onclick="{html.escape(COPY_TEXT.format(id=key) + ";" + done, quote=True)}">{b_copy}</button></div>')
    return (f'<!DOCTYPE html>\n<html lang="{e(lang)}"><head><meta charset="utf-8"><title>{e(meta["subject"])}</title></head>\n'
            '<body style="margin:0;padding:16px;background:#ffffff;color:#222;">\n'
            '<div style="max-width:720px;margin:0 auto;">\n'
            '<div style="padding:12px;margin:0 0 16px 0;background:#f3f4f6;border:1px solid #d0d4da;font:14px sans-serif;">\n'
            + '\n'.join(rows) + '\n</div>\n'
            '<div style="position:relative;padding:48px 16px 16px 16px;border:1px solid #d0d4da;">\n'
            f'<button type="button" style="{btn}position:absolute;top:10px;right:10px;" '
            f'onclick="{html.escape(COPY_BODY + ";" + done, quote=True)}">{b_mail}</button>\n'
            f'<div id="body" style="{FONT}">\n{body_html}\n</div>\n</div>\n</div>\n</body></html>\n')


def main():
    args = sys.argv[1:]
    out = None
    if '--out' in args:
        k = args.index('--out')
        if k + 1 >= len(args):
            sys.exit(__doc__)
        out = Path(args[k + 1])
        del args[k:k + 2]
    if len(args) != 1:
        sys.exit(__doc__)
    spec = Path(args[0])
    meta, body = parse(spec.read_text(encoding='utf-8'))
    body_html, body_txt = render(body)
    out = out or spec.parent
    out.mkdir(parents=True, exist_ok=True)
    hp, tp = out / (spec.stem + '.html'), out / (spec.stem + '.txt')
    hp.write_text(page(meta, body_html), encoding='utf-8')
    head = f'Subject: {meta["subject"]}\n' + ''.join(
        f'{k.capitalize()}: {meta[k]}\n' for k in ('to', 'cc') if meta.get(k))
    tp.write_text(head + '\n' + body_txt, encoding='utf-8')
    print(hp)
    print(tp)


if __name__ == '__main__':
    main()
