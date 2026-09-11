#!/usr/bin/env bash
# facet-run.sh — one usage-retro run scoped to ONE facet of the aidex suite.
#
#   facet-run.sh <facet> [--since X] [--until Y] [--transcripts-root DIR] [--projects-root DIR]
#
# Steps, every count echoed (plan usage-retro-facets, phase 5):
#   1. window    facet_coverage.py window  — explicit bounds, or "end of the facet's
#                last covered window -> now"; the general cursor is NEVER passed.
#   2. scaffold  audits/usage-retro/<date>-usage-retro-<facet>/ (boards on first use)
#   3. extract   extract.py --since --until   (zero records: stop, record nothing)
#   4. prefilter prefilter.py --facet <facet> (the facet's view; every facet tagged)
#   5. reader    the residue reader the facet file declares, if any -> reader.txt
#   6. index     one `## Facets` row in index.md: admitted, facet-only, coverage gap
#   7. record    facet_coverage.py record — only after everything above succeeded
#
# The projects root (workspace holding <project>/.context/) is needed only when the
# facet declares a reader: `--projects-root` or AIDEX_PROJECTS_ROOT, no default.
# The facet spec: references/facets/<facet>.md (schema in references/facets/00-index.md).

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../_lib.sh"

RETRO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
AUDIT_SCRIPTS="$(cd "$RETRO/.." && pwd -P)"

[[ $# -ge 1 && "$1" != --* ]] || die "usage: facet-run.sh <facet> [--since X] [--until Y] [--transcripts-root DIR] [--projects-root DIR]"
FACET="$1"; shift
SINCE="" UNTIL="" TX_ROOT="" PROJ_ROOT="${AIDEX_PROJECTS_ROOT:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) SINCE="$2"; shift 2 ;;
    --until) UNTIL="$2"; shift 2 ;;
    --transcripts-root) TX_ROOT="$2"; shift 2 ;;
    --projects-root) PROJ_ROOT="$2"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

# The facet file decides the reader and whether a coverage gap is meaningful.
read -r READER PRIMARY < <(PYTHONPATH="$RETRO" python3 -c '
import sys, facets
s = facets.load(sys.argv[1])
print(s["reader"] or "-", s["primary_source"])' "$FACET")

ROOT="$(find_project_root)"
AUDITS="$ROOT/.context/audits"
LEDGER="$AUDITS/.usage-retro/coverage.json"
DATE_ISO="$(today_iso)"
M_DIR="$AUDITS/usage-retro"
RUN="$M_DIR/$DATE_ISO-usage-retro-$FACET"
[[ -e "$RUN" ]] && die "facet run already exists: $RUN"

# 1. window
W_ARGS=(--facet "$FACET" --ledger "$LEDGER")
[[ -n "$SINCE" ]] && W_ARGS+=(--since "$SINCE")
[[ -n "$UNTIL" ]] && W_ARGS+=(--until "$UNTIL")
read -r FROM TO LABEL < <(python3 "$RETRO/facet_coverage.py" window "${W_ARGS[@]}")
echo "window: $FROM -> $TO ($LABEL)"

# 2. scaffold — new-audit.sh owns the boards and the run layout; the run slug gains
#    the facet suffix afterwards. When today's weekly run already occupies the plain
#    slug, only the run folder is rendered (the boards exist by then).
PLAIN="$M_DIR/$DATE_ISO-usage-retro"
if [[ -e "$PLAIN" ]]; then
  mkdir -p "$RUN"
  render_template "$TEMPLATES_DIR/index.md.template" "$RUN/index.md" \
    METHODOLOGY="usage-retro" METHODOLOGY_NAME="$(methodology_name usage-retro)" SLUG="usage-retro-$FACET" DATE="$DATE_ISO"
  render_template "$TEMPLATES_DIR/findings.md.template" "$RUN/findings.md" \
    METHODOLOGY="usage-retro" METHODOLOGY_NAME="$(methodology_name usage-retro)" SLUG="usage-retro-$FACET" DATE="$DATE_ISO"
else
  bash "$AUDIT_SCRIPTS/new-audit.sh" custom usage-retro >/dev/null 2>&1
  mv "$PLAIN" "$RUN"
  sed -i '' "s/— usage-retro\([ \"]\)/— usage-retro-$FACET\1/" "$RUN/index.md" "$RUN/findings.md"
fi
echo "run: $RUN"

# 3. extract — an explicit window, never the cursor
X_ARGS=(--out "$RUN/dataset.jsonl" --since "$FROM" --until "$TO")
[[ -n "$TX_ROOT" ]] && X_ARGS+=(--transcripts-root "$TX_ROOT")
python3 "$RETRO/extract.py" "${X_ARGS[@]}" > "$RUN/extract.txt"
N_REC="$(grep -c . "$RUN/dataset.jsonl" || true)"
echo "extract: $N_REC records"
if [[ "$N_REC" -eq 0 ]]; then
  echo "no records in the window; coverage NOT recorded (nothing was read)"
  exit 0
fi

# 4. prefilter — the facet's view
python3 "$RETRO/prefilter.py" --in "$RUN/dataset.jsonl" --out "$RUN/candidates.jsonl" --facet "$FACET" > "$RUN/prefilter.txt"
ROW="$(grep "^facet $FACET:" "$RUN/prefilter.txt")"
ADMITTED="$(sed -E 's/^facet [a-z0-9-]+: ([0-9]+) admitted.*/\1/' <<<"$ROW")"
F_ONLY="$(sed -E 's/.*\(([0-9]+) facet-only.*/\1/' <<<"$ROW")"
echo "prefilter: $ADMITTED admitted, $F_ONLY facet-only ($(grep -c . "$RUN/candidates.jsonl" || true) candidates)"

# 5. reader — optional, declared by the facet; prints its own count last
READER_COUNT="—"
if [[ "$READER" != "-" ]]; then
  [[ -n "$PROJ_ROOT" ]] || die "facet $FACET declares reader $READER, which needs --projects-root (or AIDEX_PROJECTS_ROOT)"
  python3 "$RETRO/facets/$READER" --projects-root "$PROJ_ROOT" > "$RUN/reader.txt"
  READER_COUNT="$(tail -1 "$RUN/reader.txt")"
  echo "reader: $READER_COUNT"
fi

# 6. index — the facet row; the coverage gap only for disk-residue facets (pages, items)
GAP="—"
case "$PRIMARY" in
  pages|items) GAP="$(python3 "$RETRO/facet_coverage.py" gap --facet "$FACET" --ledger "$LEDGER")"
               [[ "$GAP" == never ]] || GAP="${GAP}d" ;;
esac
cat >> "$RUN/index.md" <<EOF

## Facets

Window \`$FROM\` -> \`$TO\` ($LABEL); $N_REC records extracted, cursor untouched.

| Facet | Rows admitted | Facet-only | Coverage gap before this run | Reader |
|---|---|---|---|---|
| $FACET | $ADMITTED | $F_ONLY | $GAP | $READER_COUNT |
EOF

# 7. record — last, so a failed step above leaves the ledger as it was
python3 "$RETRO/facet_coverage.py" record --facet "$FACET" --from "$FROM" --to "$TO" --run "$(basename "$RUN")" --ledger "$LEDGER"
bash "$AUDIT_SCRIPTS/reindex-audits.sh" >/dev/null 2>&1 || true
ok "facet run ready: $RUN"
