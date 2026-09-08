#!/usr/bin/env bash
# sweep-report.sh — the one artifact a sweep leaves, generated from disk.
#
# Usage:
#   sweep-report.sh <worklist slug|path> [--out <file>] [--print]
#
# Writes TWO files: the markdown report (the canon, and the only path on stdout)
# and a `.html` page beside it — `<report>.html` — wrapped through aidex-dash's
# artifact kit and named on stderr as `page: <path>`. It opens neither: the one
# open belongs to stage 6 of the sweep policy, after `worklist-close.sh`, per
# `rules/artifacts-local-first.md` gate 2.
#
# Resolves the work-list (active or worklists/_archive/), then renders
# `.context/worklists/_archive/<worklist-basename>-report.md` — the run's COMPANION: it is
# born from the work-list and archived with it (owner's call 2026-08-27, Q12: research/
# is for investigations, not for what a run did). Rendered by sweep-report.py: closed
# items with their commits and
# `## Verification` rows; the OWNER rows aggregated across every item — the one list the
# owner reads; the NEEDS-DECISION list recorded at kickoff, unchanged; deferrals and
# mid-flight skips; emergent growth (flagged past 25 % of the kickoff queue); the gate
# rows from `.context/proofs/sweep-gate/gate-history.jsonl` verbatim; and the per-sweep metrics —
# items, commits, wall time, share of time in gate suites, legs re-run.
#
# Anchored `origin_ref: worklist/<file>` (ADR 2026-08-27, worklists are referenceable).
# Never hand-narrated: if a section is empty on disk, the report says so.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

ARG="" OUT="" PRINT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)   [[ $# -ge 2 ]] || die "--out needs a file"; OUT="$2"; shift 2 ;;
    --print) PRINT=1; shift ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*)      die "unknown option: $1" ;;
    *)       ARG="$1"; shift ;;
  esac
done
[[ -n "$ARG" ]] || die "usage: sweep-report.sh <worklist slug|path> [--out <file>] [--print]"

ROOT="$(find_project_root)"
WL_DIR="$ROOT/.context/worklists"
if [[ -f "$ARG" ]]; then WL="$ARG"
else
  # `<wl>-report.md` sorts before `<wl>.md` (`-` < `.`): on 2026-08-28 the report was
  # rendered from its own previous output. The companion is never the work-list.
  WL="$(ls "$WL_DIR/"*"$ARG"*.md "$WL_DIR/_archive/"*"$ARG"*.md 2>/dev/null | grep -v -- '-report\.md$' | head -1 || true)"
fi
[[ -n "${WL:-}" && -f "$WL" ]] || die "worklist not found: $ARG"

if [[ $PRINT -eq 1 ]]; then
  python3 "$SCRIPT_DIR/sweep-report.py" "$ROOT" "$WL" --print
  exit 0
fi
if [[ -z "$OUT" ]]; then
  mkdir -p "$ROOT/.context/worklists/_archive"
  OUT="$ROOT/.context/worklists/_archive/$(basename "$WL" .md)-report.md"
fi
python3 "$SCRIPT_DIR/sweep-report.py" "$ROOT" "$WL" --out "$OUT"

# ...and the page beside it (BL-345). The markdown stayed the canon and nothing
# wrapped it, so close-out handed over an .md and the reader asked for the
# artifact every time — measured corpus-wide as the "summarise the run you just
# finished" class (audit finding real-4-02). The .md is written FIRST and this is
# a projection of it: a wrap that fails leaves the run's one mandatory artifact
# intact and says so, rather than taking the report down with the page.
#
# `--lang en` is not a default being restated. A project whose artifact-style.md
# says `language: es` would stamp lang="es" over a body that is `.context/`
# English by D-04, and check-artifact.sh fails exactly that mismatch (BL-279).
#
# It does NOT open the page. `rules/artifacts-local-first.md` gate 2 opens a page
# once, when it is final, and that call belongs to the close-out step (stage 6),
# after `worklist-close.sh` — not to a script that a run may re-run while items
# are still moving. An `open` in here would also be invisible to
# `hooks/artifact-open-once.sh`, which sees the Bash call and not what it spawns.
WRAP="$(cd "$SCRIPT_DIR/../../aidex-dash/scripts" 2>/dev/null && pwd -P || true)/wrap-report.sh"
HTML="${OUT%.md}.html"
TITLE="$(sed -n 's/^title: *"\{0,1\}\(.*[^"]\)"\{0,1\} *$/\1/p' "$OUT" | head -1)"
if [[ "$OUT" != *.md ]]; then
  # `wrap-report.sh` keys the markdown conversion on the `--in` EXTENSION, so a report
  # written to a non-`.md` path would be wrapped VERBATIM — `${OUT%.md}.html` resolves to
  # `<out>.html`, carrying the raw markdown as page content, which check-artifact.sh then
  # fails. The report itself is correct; it is only the page that has no way to exist.
  # Say so, rather than writing a broken one and reporting a contract failure for it.
  echo "NOTE: --out $OUT is not a .md path, so no page was written beside it — the wrap converts a .md input only." >&2
elif [[ -x "$WRAP" ]]; then
  if bash "$WRAP" --title "${TITLE:-Sweep report}" --lang en --in "$OUT" --out "$HTML" >/dev/null; then
    # stdout stays ONE path — the markdown, the canon. Callers consume this
    # script's stdout as a filename (`OUT="$(sweep-report.sh …)"`), so a second
    # line there is not an extra path, it is a broken one: adding it turned 24
    # green cells red in one run. The page is named on stderr and its location is
    # derivable anyway (`<report>.html` beside `<report>.md`).
    echo "page: $HTML" >&2
  else
    echo "NOTE: the report was written but the page beside it FAILED the artifact contract above." >&2
    echo "NOTE: hand over $OUT and fix the page before opening it." >&2
  fi
else
  echo "NOTE: aidex-dash is not installed next to this skill, so no page was written beside $OUT." >&2
fi
