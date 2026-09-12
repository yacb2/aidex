#!/usr/bin/env bash
# test-facet-run.sh — the facet run end to end (usage-retro-facets, phase 5):
# `facet-run.sh artifacts` over the hand-written corpus, in a throwaway workspace.
#
# Guarded:
#   - the run folder audits/usage-retro/<date>-usage-retro-artifacts/ holds
#     dataset.jsonl, candidates.jsonl, reader.txt, index.md with a `## Facets` row
#   - the reader ran on NON-EMPTY input (pages processed > 0 is the row's last cell)
#   - coverage.json gains one `artifacts` window naming the run; cursor.json is
#     byte-identical before and after (checksum printed)
#   - validate-audit.sh over the produced tree is clean and saw the run (runs: 1)
#   - a second run the same day is refused; a window with zero records records no
#     coverage; a facet with a reader refuses to run without a projects root
#
# Run with: bash skills/aidex-audit/tests/test-facet-run.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL="$(cd "$TESTS_DIR/.." && pwd -P)"
RETRO="$SKILL/scripts/usage-retro"
FIXTURE="$TESTS_DIR/fixtures/usage-retro-corpus.sh"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

read -r PROJ TX <<< "$(bash "$FIXTURE")"
trap 'rm -rf "$PROJ" "$TX"' EXIT
WS="$PROJ/demo_ws"
AUD="$WS/.context/audits"
TODAY="$(date +%F)"
RUN="$AUD/usage-retro/$TODAY-usage-retro-artifacts"

# a pre-existing weekly cursor that the facet run must not touch
mkdir -p "$AUD/.usage-retro"
printf '{"through": "2026-01-03T00:00:00+00:00"}\n' > "$AUD/.usage-retro/cursor.json"
before="$(shasum "$AUD/.usage-retro/cursor.json" | cut -d' ' -f1)"

# (1) the run ------------------------------------------------------------------
out="$(cd "$WS" && env -u AIDEX_PROJECTS_ROOT bash "$RETRO/facet-run.sh" artifacts --since 2025-12-01 \
        --transcripts-root "$TX" --projects-root "$PROJ" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "facet-run.sh artifacts exits 0" || bad "facet-run.sh rc=$rc: $out"
for f in dataset.jsonl candidates.jsonl reader.txt index.md findings.md; do
  [[ -s "$RUN/$f" ]] || bad "missing or empty $RUN/$f"
done
[[ -s "$RUN/dataset.jsonl" && -s "$RUN/index.md" ]] && ok "run folder scaffolded with the -artifacts suffix"
grep -q '^extract: 5 records' <<<"$out" && ok "extract count echoed (5 records)" || bad "extract count: $out"
grep -Eq '^prefilter: [0-9]+ admitted, [0-9]+ facet-only' <<<"$out" && ok "prefilter counts echoed" || bad "prefilter line: $out"
grep -q '"facet:artifacts"' "$RUN/candidates.jsonl" && ok "candidates carry facet:artifacts" || bad "no facet tag in candidates"
n="$(tail -1 "$RUN/reader.txt" | sed -E 's/pages processed: ([0-9]+)/\1/')"
[[ "$n" =~ ^[0-9]+$ && "$n" -gt 0 ]] && ok "reader saw non-empty input (pages processed: $n)" || bad "reader count: $(tail -1 "$RUN/reader.txt")"
grep -q '^## Facets' "$RUN/index.md" && grep -Eq "^\| artifacts \| [0-9]+ \| [0-9]+ \| never \| pages processed: $n \|$" "$RUN/index.md" \
  && ok "index.md carries the facet row (gap 'never' on first run)" || bad "facet row: $(grep -A3 '^## Facets' "$RUN/index.md")"
grep -q -- "— usage-retro-artifacts" "$RUN/index.md" && ok "index title names the facet run" || bad "index title: $(head -3 "$RUN/index.md")"

# (2) coverage recorded, cursor untouched ----------------------------------------
python3 - "$AUD/.usage-retro/coverage.json" "$TODAY-usage-retro-artifacts" <<'EOF' && ok "coverage.json holds one artifacts window naming the run" || bad "coverage.json wrong"
import json, sys
d = json.load(open(sys.argv[1])); w = d.get("artifacts") or []
assert len(w) == 1 and w[0]["run"] == sys.argv[2] and w[0]["from"].startswith("2025-12-01"), d
EOF
after="$(shasum "$AUD/.usage-retro/cursor.json" | cut -d' ' -f1)"
echo "  cursor.json checksum: $before"
[[ "$before" == "$after" ]] && ok "cursor.json byte-identical" || bad "cursor moved: $before -> $after"

# (3) the produced tree validates, and the validator saw the run -----------------
v="$(bash "$SKILL/scripts/validate-audit.sh" "$AUD" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && grep -q 'runs: 1' <<<"$v" && ok "validate-audit.sh clean over the produced tree (runs: 1)" || bad "validate: rc=$rc $v"
grep -q 'usage-retro-artifacts' "$AUD/00-index.md" && ok "reindex-audits.sh lists the facet run" || bad "00-index.md lacks the run"
# `facet:<name>` at the start of Notes is a prefix inside the cell, no schema change (Q15)
printf '| USAGE-90 | gap | artifacts | pre-wrapper pages fail the v18 checker | open | P3 | %s | — | facet:artifacts source=residue band=pre-wrapper |\n' \
  "$TODAY-usage-retro-artifacts" >> "$AUD/usage-retro/00-inventory.md"
v="$(bash "$SKILL/scripts/validate-audit.sh" "$AUD" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && grep -q 'findings: 1' <<<"$v" && ok "a facet:<name> Notes prefix validates as a 9-column row" || bad "facet notes row: rc=$rc $v"

# (3b) today's weekly run already occupies the plain slug: the facet run still scaffolds
mkdir -p "$AUD/usage-retro/$TODAY-usage-retro"
out="$(cd "$WS" && bash "$RETRO/facet-run.sh" planning --since 2025-12-01 --transcripts-root "$TX" 2>&1)"; rc=$?
[[ $rc -eq 0 && -s "$AUD/usage-retro/$TODAY-usage-retro-planning/index.md" ]] \
  && grep -q -- "— usage-retro-planning" "$AUD/usage-retro/$TODAY-usage-retro-planning/index.md" \
  && grep -Eq '^\| planning \| [0-9]+ \| [0-9]+ \| — \| — \|$' "$AUD/usage-retro/$TODAY-usage-retro-planning/index.md" \
  && ok "beside today's weekly run the facet run renders its own folder (transcript facet: gap and reader are —)" \
  || bad "planning beside weekly: rc=$rc $out"
rm -rf "$AUD/usage-retro/$TODAY-usage-retro"

# (4) refusals ----------------------------------------------------------------------
out="$(cd "$WS" && bash "$RETRO/facet-run.sh" artifacts --since 2025-12-01 --transcripts-root "$TX" --projects-root "$PROJ" 2>&1)"; rc=$?
[[ $rc -ne 0 ]] && grep -q 'already exists' <<<"$out" && ok "a second run the same day is refused" || bad "second run: rc=$rc $out"
out="$(cd "$WS" && env -u AIDEX_PROJECTS_ROOT bash "$RETRO/facet-run.sh" backlog --since 2025-12-01 --transcripts-root "$TX" 2>&1)"; rc=$?
[[ $rc -ne 0 ]] && grep -q 'projects-root' <<<"$out" && ok "a facet with a reader refuses to run rootless" || bad "rootless backlog: rc=$rc $out"
[[ ! -e "$AUD/usage-retro/$TODAY-usage-retro-backlog" ]] && ok "a refused run leaves no run folder" || bad "rootless backlog left $TODAY-usage-retro-backlog behind"
# an empty window: the corpus is dated 2026-01-01, so [2020, 2021) holds nothing
out="$(cd "$WS" && bash "$RETRO/facet-run.sh" session --since 2020-01-01T00:00:00+00:00 --until 2021-01-01T00:00:00+00:00 --transcripts-root "$TX" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && grep -q 'coverage NOT recorded' <<<"$out" && ! grep -q '"session"' "$AUD/.usage-retro/coverage.json" \
  && ok "a zero-record window stops before recording coverage" || bad "empty window: rc=$rc $out"
[[ ! -e "$AUD/usage-retro/$TODAY-usage-retro-session" ]] && ok "a zero-record run leaves no run folder" || bad "empty window left $TODAY-usage-retro-session behind"

echo "facet run: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
