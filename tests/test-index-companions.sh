#!/usr/bin/env bash
# An auto-generated index must list the rendered companions anchored to its entries.
#
# The gap this locks (BL-234, 2026-08-25): `plans/00-index.md`, `backlog/00-index.md`
# and `audits/00-index.md` are all regenerated from front-matter in MARKDOWN files, and
# none of the three generators contained the string `html` at all. So a `.html` companion
# could be orphaned by an archive sweep, duplicated, or left pointing at a moved anchor,
# and every index still rendered as if nothing were wrong — which is exactly what happened
# when `plan/2026-08-22-suite-speed-and-coverage-rollout` was archived: two companions
# moved with the folder, a third was left behind in `plans/`, `validate.py` reported 0
# violations, and it was found by listing the directory by hand.
#
# The join already exists in the page — `<meta name="artifact-anchor" content="…">` — so
# discovery needs no registry and no naming rule, only for the generators to read it.
#
# What this test proves, and what it does not:
#   PROVES  — each of the three generators lists a companion under the entry it is
#             anchored to, matching on the anchor and not on a filename resemblance;
#             the sub-bullet survives the `sort` those sections run their rows through;
#             a page that declares NO anchor stays absent.
#   DOES NOT — check that the anchor resolves. That is `validate.py`'s
#             `artifact-anchor-target-missing`, covered by its own suite; an index
#             reports what pages claim, the validator judges the claim.
#
# Run with: bash tests/test-index-companions.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILLS="$SCRIPT_DIR/../skills"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PROJ="$TMP/proj"
CTX="$PROJ/.context"
mkdir -p "$CTX/plans/_archive" "$CTX/backlog/_archive" \
         "$CTX/audits/code-quality/2026-01-01-live-run"

page() {  # $1 = path, $2 = anchor (empty string writes no meta at all)
  mkdir -p "$(dirname "$1")"
  { printf '<!doctype html><meta charset="utf-8"><title>Companion</title>\n'
    [[ -n "$2" ]] && printf '<meta name="artifact-anchor" content="%s">\n' "$2"
    printf '<h1>Companion</h1>\n'
  } > "$1"
}

# --- plans: one archived plan folder with two companions, plus a decoy ----------
mkdir -p "$CTX/plans/_archive/2026-01-01-archived-plan"
cat > "$CTX/plans/_archive/2026-01-01-archived-plan/00-index.md" <<'EOF'
---
title: "Archived plan"
status: done
created: 2026-01-01
updated: 2026-01-05
---
EOF
cat > "$CTX/plans/2026-01-03-active-plan.md" <<'EOF'
---
title: "Active plan"
status: open
created: 2026-01-03
updated: 2026-01-03
---
EOF
# A second archived plan, dated so the ANCHORED one sorts FIRST in the Closed section.
# That ordering is what gives cell (1) teeth: a companion sub-bullet begins with spaces,
# so when a multi-line row is torn apart by `sort` the sub-bullet always sinks to the
# BOTTOM of the section. With the anchored plan sorting last, the orphan lands right
# under it by accident and the bug reads as a pass.
cat > "$CTX/plans/_archive/2026-01-02-other-plan.md" <<'EOF'
---
title: "Other archived plan"
status: done
created: 2026-01-02
updated: 2026-01-03
---
EOF
page "$CTX/plans/_archive/2026-01-01-archived-plan/outcomes.html" "plan/2026-01-01-archived-plan"
page "$CTX/plans/2026-01-03-active-plan-report.html"              "plan/2026-01-03-active-plan"
# The decoy: same directory, name that looks related, no anchor. Must not be listed —
# an index that guessed by filename would pick this up.
page "$CTX/plans/2026-01-03-active-plan-scratch.html"             ""

# --- backlog: one active item with a companion ---------------------------------
cat > "$CTX/backlog/2026-01-04-bl-001-an-item.md" <<'EOF'
---
title: "An item with a companion"
id: BL-001
status: open
created: 2026-01-04
updated: 2026-01-04
priority: P2
type: task
---

Body.
EOF
# Anchored with the explicit `.md` filename — the canon accepts bare slug and filename
# as the same target (§3), so the index must join them too.
page "$CTX/backlog/2026-01-04-bl-001-report.html" "backlog/2026-01-04-bl-001-an-item.md"

# --- audits: one live run with a companion -------------------------------------
# The methodology board file is what marks `code-quality/` as a container rather than
# a run folder; without it reindex-audits.sh never recurses into the run (D-02 layout).
cat > "$CTX/audits/code-quality/00-methodology.md" <<'EOF'
---
title: "Code quality"
status: open
created: 2026-01-01
updated: 2026-01-01
---
EOF
cat > "$CTX/audits/code-quality/2026-01-01-live-run/index.md" <<'EOF'
---
title: "Live audit run"
status: open
methodology: code-quality
created: 2026-01-01
updated: 2026-01-01
---
EOF
page "$CTX/audits/code-quality/2026-01-01-live-run/findings.html" \
     "audit/code-quality/2026-01-01-live-run"

cd "$PROJ" || exit 1
bash "$SKILLS/aidex-plan/scripts/reindex-plans.sh"          >/dev/null 2>&1
bash "$SKILLS/aidex-backlog/scripts/register-item.sh" --reindex >/dev/null 2>&1
bash "$SKILLS/aidex-audit/scripts/reindex-audits.sh"        >/dev/null 2>&1

PLANS="$(cat "$CTX/plans/00-index.md" 2>/dev/null)"
BACKLOG="$(cat "$CTX/backlog/00-index.md" 2>/dev/null)"
AUDITS="$(cat "$CTX/audits/00-index.md" 2>/dev/null)"

# A companion sub-bullet must sit under ITS entry, not merely somewhere in the file:
# the first attempt at this feature emitted rows containing a real newline, `sort`
# tore them apart, and all four sub-bullets landed under an unrelated plan.
under() {  # $1 = index text, $2 = entry substring, $3 = companion filename
  awk -v entry="$2" -v comp="$3" '
    index($0, entry) { hit=1; next }
    hit && /^  - companion: / { if (index($0, comp)) { print "yes"; exit } next }
    hit { hit=0 }
  ' <<<"$1"
}

# ---------- (1) plans: an archived plan lists the companion inside its folder ----------
[[ "$(under "$PLANS" "2026-01-01-archived-plan/00-index.md" "outcomes.html")" == yes ]] \
  || fail "(1) plans/00-index.md did not list outcomes.html under the archived plan it is anchored to"

# ---------- (2) plans: an ACTIVE plan lists its companion too ----------
[[ "$(under "$PLANS" "2026-01-03-active-plan.md" "2026-01-03-active-plan-report.html")" == yes ]] \
  || fail "(2) plans/00-index.md did not list the active plan's companion — the Open section needs the same treatment as Closed"

# ---------- (3) an unanchored page is NOT listed ----------
if grep -q "active-plan-scratch.html" <<<"$PLANS"; then
  fail "(3) an .html file with no artifact-anchor was listed — discovery must join on the declared anchor, never on a filename resemblance"
fi

# ---------- (4) backlog: joins a `<type>/<filename>.md` anchor to the bare entry ----------
[[ "$(under "$BACKLOG" "2026-01-04-bl-001-an-item.md" "2026-01-04-bl-001-report.html")" == yes ]] \
  || fail "(4) backlog/00-index.md did not list the item's companion — an anchor written with the .md filename must join the same entry as the bare slug"

# ---------- (5) audits: a run lists its companion ----------
[[ "$(under "$AUDITS" "2026-01-01-live-run/index.md" "findings.html")" == yes ]] \
  || fail "(5) audits/00-index.md did not list the run's companion"

# ---------- (6) the generators stay idempotent ----------
for pair in "plans/00-index.md:$SKILLS/aidex-plan/scripts/reindex-plans.sh" \
            "audits/00-index.md:$SKILLS/aidex-audit/scripts/reindex-audits.sh"; do
  idx="$CTX/${pair%%:*}"; gen="${pair#*:}"
  before="$(cat "$idx")"
  bash "$gen" >/dev/null 2>&1
  [[ "$before" == "$(cat "$idx")" ]] \
    || fail "(6) $(basename "$(dirname "$idx")")/00-index.md changed on a second run — the companion pass is not idempotent"
done

if [[ $failures -eq 0 ]]; then
  echo "OK: plans, backlog and audits indexes each list their anchored companions; unanchored pages stay out"
  exit 0
fi
printf '\n%d assertion(s) failed\n' "$failures"
exit 1
