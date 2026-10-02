#!/usr/bin/env python3
"""The `::: video` block (BL-456): a local film referenced by path, never inlined.

Layer: the builder's decision (unit), plus one CLI run for the page contract and
the CLI build of a page whose only visual is the film (player width is
render-probe's, not asserted here). Each cell fails on its named regression:

  - the film's bytes reach the page (a data URI)      -> "not inlined"
  - the path is not relative to the page under -o      -> "relative to the PAGE"
  - a bad src is accepted instead of refused at the fence
  - the block is not in the dispatch / vocabulary      -> test_lockstep.py
  - the page contract rejects a page whose only visual is a film -> CLI cell

Stdlib only: `python3 test_video.py`, prints OK, exits 0.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
SCRIPTS = os.path.join(SKILL, "scripts")
sys.path.insert(0, SCRIPTS)
sys.path.insert(0, os.path.join(SCRIPTS, "dash"))

from spec_build import SpecBuildError, build       # noqa: E402

BUILD = os.path.join(SCRIPTS, "spec_build.py")
failures = []


def check(label, cond, detail=""):
    if cond:
        print("  ok: " + label)
    else:
        failures.append(label)
        print("FAIL: %s%s" % (label, (": " + detail) if detail else ""))


def refused(label, spec, base, *needles):
    try:
        build(spec, base_dir=base)
    except SpecBuildError as exc:
        check(label, exc.line == 3 and all(n in exc.message for n in needles),
              "line %d: %s" % (exc.line, exc.message))
        return
    check(label, False, "built without complaint")


def write(tmp, name, data):
    path = os.path.join(tmp, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(data)
    return path


def run(tmp):
    film = b"\x00\x00\x00\x18ftypmp42" + b"\x01" * 64
    write(tmp, "films/a.mp4", film)
    write(tmp, "films/b.webm", film)
    pre = "# t\n\n"

    html = build('::: video {#v1 .wide src="films/a.mp4" title="Un <film> & más"}\n:::\n',
                 base_dir=tmp)
    check("a video is one <figure class=video> with a controls <video> and a caption",
          '<figure id="v1" class="video wide">\n'
          '<video controls preload="metadata" src="films/a.mp4"></video>\n'
          '<figcaption>Un &lt;film&gt; &amp; más</figcaption>\n</figure>' in html, html)
    check("not inlined: no data URI reaches the page",
          "data:" not in html and "base64" not in html)
    check("a .webm is accepted",
          'src="films/b.webm"' in build('::: video {src="films/b.webm"}\n:::\n',
                                        base_dir=tmp))

    write(tmp, "films/a#1.mp4", film)
    write(tmp, "films/q?x.mp4", film)
    write(tmp, "films/sp ace.mp4", film)
    for name, want in (("a#1", "a%231"), ("q?x", "q%3Fx"), ("sp ace", "sp%20ace")):
        html = build('::: video {src="films/%s.mp4"}\n:::\n' % name, base_dir=tmp)
        check("src %r is URL-encoded so the browser fetches the whole name" % name,
              'src="films/%s.mp4"' % want in html, html)
    html = build('::: video {src="films/a#1.mp4"}\n:::\n', base_dir=tmp,
                 page=os.path.join(tmp, "reports", "p.html"))
    check("...and under -o as well", 'src="../films/a%231.mp4"' in html, html)

    out = os.path.join(tmp, "reports", "p.html")
    html = build('::: video {src="films/a.mp4"}\n:::\n', base_dir=tmp, page=out)
    check("with a page, src is rewritten relative to the PAGE",
          'src="../films/a.mp4"' in html, html)

    refused("no src", pre + "::: video {title=t}\n:::\n", tmp, "needs a non-empty src")
    refused("an absolute src", pre + '::: video {src="%s"}\n:::\n'
            % os.path.join(tmp, "films", "a.mp4"), tmp, "is absolute")
    refused("an unknown extension", pre + '::: video {src="films/a.mov"}\n:::\n',
            tmp, "has type '.mov'", ".mp4")
    refused("a missing file", pre + '::: video {src="films/nope.mp4"}\n:::\n',
            tmp, "no such file")
    refused("an unknown attr", pre + '::: video {src="films/a.mp4" alt="x"}\n:::\n',
            tmp, "takes no attr")
    refused("a body", pre + '::: video {src="films/a.mp4"}\nTexto.\n:::\n', tmp,
            "takes no body")

    # The page contract and the kit, end to end, from `/` (src is spec-relative).
    spec = write(tmp, "page.spec.md", (
        '::: masthead\n'
        '# Una película\n\nUna página con su film.\n:::\n\n'
        '::: video {src="films/a.mp4" title="Película"}\n:::\n\n'
        '::: notes {title="Notas generales"}\n:::\n').encode())
    page = os.path.join(tmp, "reports", "page.html")
    r = subprocess.run([sys.executable, BUILD, spec, "-o", page],
                       capture_output=True, text=True, cwd="/")
    check("the built page passes check-artifact through the CLI",
          r.returncode == 0, (r.stdout + r.stderr)[-600:])
    with open(page, encoding="utf-8") as fh:
        text = fh.read()
    check("the page references the film relative to itself, no data URI",
          'src="../films/a.mp4"' in text and "data:video" not in text)

    # BL-593: poster= (spec-relative, must exist) and a height cap in the kit.
    write(tmp, "films/p.jpg", b"\xff\xd8\xff\xe0" + b"\x01" * 16)
    html = build('::: video {src="films/a.mp4" poster="films/p.jpg"}\n:::\n',
                 base_dir=tmp)
    check("poster= is emitted on the <video>",
          '<video controls preload="metadata" poster="films/p.jpg" '
          'src="films/a.mp4"></video>' in html, html)
    html = build('::: video {src="films/a.mp4" poster="films/p.jpg"}\n:::\n',
                 base_dir=tmp, page=out)
    check("...rewritten relative to the PAGE under -o",
          'poster="../films/p.jpg"' in html, html)
    refused("a missing poster", pre + '::: video {src="films/a.mp4" poster="films/no.jpg"}\n:::\n',
            tmp, "poster", "no such file")
    refused("an absolute poster", pre + '::: video {src="films/a.mp4" poster="%s"}\n:::\n'
            % os.path.join(tmp, "films", "p.jpg"), tmp, "poster", "is absolute")
    refused("a poster of the wrong type", pre + '::: video {src="films/a.mp4" poster="films/b.webm"}\n:::\n',
            tmp, "poster", "has type")
    css = os.path.join(SCRIPTS, "..", "assets", "artifact-kit", "components.css")
    with open(css, encoding="utf-8") as fh:
        rule = re.search(r"figure\.video video \{[^}]*\}", fh.read())
    check("the kit caps a film's height so a 3:4 film fits the viewport",
          bool(rule) and "max-height" in rule.group(0) and "vh" in rule.group(0))

    # BL-547: a video nests inside an item, in written order, like a figure.
    html = build('::: group {#G1 title="G"}\n::: item {#q1 title="Q"}\n'
                 'Which cut?\n\n::: video {src="films/a.mp4" title="Cut A"}\n:::\n\n'
                 '- A\n- B\n:::\n:::\n', base_dir=tmp)
    item = html.split('id="q1"', 1)[-1]
    check("a video renders inside its item, before the options",
          '<figure class="video">' in item and
          item.index('<figure class="video">') < item.index('class="opts'), item[:900])
    spec = write(tmp, "item.spec.md", (
        '::: masthead\n# Una película\n\nUna página con su film.\n:::\n\n'
        '::: group {#G1 title="G"}\n::: item {#q1 title="Q"}\n'
        'Which cut?\n\n::: video {src="films/a.mp4" title="Cut A"}\n:::\n\n'
        '- A\n- B\n:::\n:::\n\n::: notes {title="Notas generales"}\n:::\n').encode())
    ipage = os.path.join(tmp, "reports", "item.html")
    r = subprocess.run([sys.executable, BUILD, spec, "-o", ipage],
                       capture_output=True, text=True, cwd="/")
    check("a page with a video inside an item passes check-artifact",
          r.returncode == 0, (r.stdout + r.stderr)[-600:])


def main():
    tmp = tempfile.mkdtemp(prefix="spec-video-")
    try:
        run(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if failures:
        print("NOT OK — %d failure(s)" % len(failures))
        return 1
    print("OK — test_video.py: a film is referenced by path, never inlined, "
          "every bad src refused at the fence")
    return 0


if __name__ == "__main__":
    sys.exit(main())
