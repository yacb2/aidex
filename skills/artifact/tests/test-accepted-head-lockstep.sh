#!/usr/bin/env bash
# test-accepted-head-lockstep.sh — composer.js STRINGS.<lang>.acceptedHead and
# reply_defect.ACCEPTED / ACCEPTED_HEAD are one contract: the composer writes
# `## <acceptedHead>` as the trailing section of a copied reply, and every reply reader
# ends the block above it at that line. A head edited on one side only makes the readers
# fold the accepted lines into the last `### id` block.
#
# Asserts: (1) each composer head, as `## <head>` at line start, matches ACCEPTED_HEAD;
# (2) the regex is no wider: its alternatives are exactly the two composer heads, and
# near-miss lines (other case, leading space, other heading level, trailing text, no
# space after ##) do NOT match.
#
# Run with: bash skills/artifact/tests/test-accepted-head-lockstep.sh
# Env: ACCEPTED_HEAD_COMPOSER=<path> reads composer.js from elsewhere (the mutation proof).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL="$HERE/.."
COMPOSER="${ACCEPTED_HEAD_COMPOSER:-$SKILL/assets/artifact-kit/composer.js}"
for f in "$COMPOSER" "$SKILL/scripts/dash/reply_defect.py"; do
  [[ -r "$f" ]] || { echo "SKIP: cannot read $f — the accepted-head lockstep DID NOT RUN"; exit 2; }
done
python3 -I - "$COMPOSER" "$SKILL/scripts/dash" <<'PY'
import re, sys
composer, dash = sys.argv[1], sys.argv[2]
sys.path.insert(0, dash)
import reply_defect as rd
src = open(composer, encoding="utf-8").read()
unesc = lambda t: re.sub(r"\\u([0-9a-fA-F]{4})", lambda m: chr(int(m.group(1), 16)), t)
heads = {}
for lang in ("en", "es"):
    block = re.search(r"^    %s: \{\n(.*?)^    \}," % lang, src, re.M | re.S)
    m = block and re.search(r"^      acceptedHead: '([^']*)',$", block.group(1), re.M)
    if not m:
        print("FAIL: composer.js STRINGS.%s has no acceptedHead" % lang); sys.exit(1)
    heads[lang] = unesc(m.group(1))
fails = []
for lang, h in heads.items():
    line = "## " + h
    if not rd.ACCEPTED_HEAD.match(line):
        fails.append("ACCEPTED_HEAD does not match the %s composer head %r" % (lang, line))
    for bad in (line.upper(), " " + line, "### " + h, line + " x", line.replace("## ", "##", 1)):
        if rd.ACCEPTED_HEAD.match(bad):
            fails.append("ACCEPTED_HEAD is wider than the %s head: it matches %r" % (lang, bad))
# No third head: the pattern's alternatives are exactly the two composer heads.
m = re.fullmatch(r"## \(\?:(.*)\)\[ \\t\]\*\$", rd.ACCEPTED)
alts = set(unesc(a) for a in m.group(1).split("|")) if m else None
if alts != set(heads.values()):
    fails.append("ACCEPTED alternatives %r are not exactly the composer heads %r" % (alts, sorted(heads.values())))
for f in fails:
    print("FAIL: " + f)
print("PASS: accepted-head lockstep (%s)" % " / ".join(repr(h) for h in heads.values()) if not fails else "FAILED: %d" % len(fails))
sys.exit(1 if fails else 0)
PY
