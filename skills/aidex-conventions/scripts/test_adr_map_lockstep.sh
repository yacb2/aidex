#!/usr/bin/env bash
# ADR-map lockstep guard for 00-global.md §11.
#
# Regressions this locks (deep audit 2026-07-25):
#   1. INCOMPLETE MAP — D-09/D-10/D-11 were cited across skills/ + rules/ but absent from
#      §11. That is the root cause of the mis-citation class, not a cosmetic gap: an author
#      who looks up D-11 and finds nothing guesses (aidex-comm cited D-11 where D-04 governs).
#   2. DEAD LINKS FOR EVERY INSTALLED USER — the rows linked
#      `../../../.context/decisions/…`, but `.context/` is gitignored (0 tracked files) and
#      from an installed `~/.aidex/skills/…` that path resolves to `~/.aidex/.context/`,
#      which does not exist. All 7 links were dead for everyone but the maintainer.
#   3. STALE ROW — D-06 pointed at a `-deferred.md` file that does not exist, and its label
#      still said "deferred" for a decision that had been made.
#
# Invariants: every cited D-NN is mapped · no row links into .context/ · every named ADR
# filename exists (maintainer-only; skipped where .context/decisions/ is absent).
#
# Run with: bash skills/aidex-conventions/scripts/test_adr_map_lockstep.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
CANON="$SCRIPT_DIR/../references/00-global.md"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

[[ -f "$CANON" ]] || { echo "FAIL: canon not found at $CANON"; exit 1; }

# The §11 table body.
MAP="$(awk '/^## 11\. ADR map/{f=1;next} /^## /{f=0} f' "$CANON")"
[[ -n "$MAP" ]] || { echo "FAIL: could not extract §11 ADR map from $CANON"; exit 1; }

mapped="$(grep -oE '^\| *D-[0-9]{2}' <<<"$MAP" | grep -oE 'D-[0-9]{2}' | sort -u)"
[[ -n "$mapped" ]] || { echo "FAIL: no D-NN rows parsed from the ADR map"; exit 1; }

# ---------- (1) every cited D-NN is mapped ----------
cited="$(grep -rhoE '\bD-[0-9]{2}\b' "$REPO_ROOT/skills" "$REPO_ROOT/rules" \
  --include='*.md' 2>/dev/null | sort -u)"
while IFS= read -r d; do
  [[ -z "$d" ]] && continue
  grep -qx "$d" <<<"$mapped" \
    || fail "(1) $d is cited in skills/ or rules/ but is missing from the §11 ADR map"
done <<<"$cited"

# ---------- (2) no row links into .context/ (dead for every installed user) ----------
if grep -qE '\]\([^)]*\.context/' <<<"$MAP"; then
  fail "(2) an ADR map row links into .context/ — gitignored, so it resolves for nobody but the maintainer; name the filename instead"
fi

# ---------- (3) every named ADR filename exists (maintainer-only) ----------
DEC="$REPO_ROOT/.context/decisions"
if [[ -d "$DEC" ]]; then
  names="$(grep -oE '`[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+\.md`' <<<"$MAP" | tr -d '`' | sort -u)"
  [[ -n "$names" ]] || fail "(3) no ADR filenames parsed from the map rows"
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    [[ -f "$DEC/$n" ]] || [[ -f "$DEC/_archive/$n" ]] \
      || fail "(3) ADR map names $n but it exists in neither decisions/ nor decisions/_archive/"
  done <<<"$names"
  # ---------- (4) each row's D-NN must match the ADR's OWN decision_id ----------
  # This is the assertion that matters. Hand-maintaining a number->file mapping is exactly
  # the drift shape this repo keeps getting bitten by, and it bit the 2026-07-25 repair
  # itself: the first attempt mapped D-06 to the file that supersedes it and D-10 to the
  # ADR it amends. Both were wrong, and only comparing against each file's self-declared
  # decision_id caught them.
  while IFS= read -r row; do
    rid="$(grep -oE 'D-[0-9]{2}' <<<"$row" | head -1)"
    rfile="$(grep -oE '`[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+\.md`' <<<"$row" | tr -d '`' | head -1)"
    [[ -n "$rid" && -n "$rfile" ]] || continue
    path="$DEC/$rfile"; [[ -f "$path" ]] || path="$DEC/_archive/$rfile"
    [[ -f "$path" ]] || continue          # (3) already reported this
    own="$(grep -m1 '^decision_id:' "$path" | sed 's/decision_id: *//' | tr -d ' ')"
    if [[ -n "$own" && "$own" != "$rid" ]]; then
      fail "(4) map row $rid names $rfile, but that ADR declares decision_id: $own"
    fi
  done < <(grep -E '^\| *D-[0-9]{2} *\|' <<<"$MAP")

  # ---------- (5) no two ADRs may claim the same decision_id ----------
  dupes="$(for f in "$DEC"/*.md "$DEC"/_archive/*.md; do
             [[ -f "$f" ]] || continue
             grep -m1 '^decision_id:' "$f" 2>/dev/null | sed 's/decision_id: *//' | tr -d ' '
           done | sort | uniq -d)"
  # The D-07 collision was resolved on 2026-07-27 (topology ADR renumbered to D-12), so
  # there is no longer a whitelist: any duplicate at all is a failure.
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    fail "(5) decision_id $d is claimed by more than one ADR"
  done <<<"$dupes"
else
  echo "note: .context/decisions/ absent — skipping filename-existence check (installed copy)"
fi

if [[ "$failures" -eq 0 ]]; then
  echo "OK — ADR map in lockstep: $(wc -l <<<"$mapped" | tr -d ' ') mapped, all cited D-NN present, no .context/ links"
  exit 0
fi
exit 1
