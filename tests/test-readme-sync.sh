#!/usr/bin/env bash
# test-readme-sync.sh — the README is documentation that goes stale silently.
# It drifted four releases (badge 0.21.1 vs VERSION 0.23.2), lost 3 of 17 skills
# from its own tree while the table below listed all 17, documented 1 of 3
# installed rules, and taught YYYYMMDD paths its own validator flags (BL-099).
# Each of those is mechanical, so each is asserted here instead of re-audited.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
README="$REPO_ROOT/README.md"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
pass() { printf 'ok: %s\n' "$*"; }

# --- badge tracks install.sh VERSION ---
version="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$REPO_ROOT/install.sh" | head -1)"
badge="$(sed -n 's|.*badge/version-\([0-9][^-]*\)-blue.*|\1|p' "$README" | head -1)"
if [ -n "$version" ] && [ "$badge" = "$version" ]; then
  pass "version badge matches install.sh ($version)"
else
  fail "version badge '$badge' != install.sh VERSION '$version' — bump the badge in the release commit"
fi

# --- every shipped skill appears in the tree AND in the table ---
skills=()
while IFS= read -r d; do skills+=("$(basename "$d")"); done \
  < <(find "$REPO_ROOT/skills" -maxdepth 1 -mindepth 1 -type d | sort)

missing_tree=() missing_table=()
for s in "${skills[@]}"; do
  grep -q "├── $s/\|└── $s/" "$README" || missing_tree+=("$s")
  grep -q "\*\*\`$s\`\*\*" "$README" || missing_table+=("$s")
done
[ ${#missing_tree[@]} -eq 0 ] \
  && pass "all ${#skills[@]} skills appear in the installed-tree diagram" \
  || fail "skills missing from the tree diagram: ${missing_tree[*]}"
[ ${#missing_table[@]} -eq 0 ] \
  && pass "all ${#skills[@]} skills appear in the skills table" \
  || fail "skills missing from the skills table: ${missing_table[*]}"

# --- the "### N skills" heading states the real count ---
declared="$(sed -n 's/^### \([0-9][0-9]*\) skills$/\1/p' "$README" | head -1)"
if [ "$declared" = "${#skills[@]}" ]; then
  pass "the skills heading declares the real count (${#skills[@]})"
else
  fail "README says '### $declared skills' but skills/ holds ${#skills[@]}"
fi

# --- every installed rule is documented ---
missing_rules=()
for r in "$REPO_ROOT"/rules/*.md; do
  grep -q "$(basename "$r")" "$README" || missing_rules+=("$(basename "$r")")
done
[ ${#missing_rules[@]} -eq 0 ] \
  && pass "all installed rules are documented" \
  || fail "rules installed but undocumented: ${missing_rules[*]}"

# --- no YYYYMMDD paths: the README must not teach what validate.py flags ---
if legacy="$(grep -nE '/2[0-9]{7}-' "$README")"; then
  fail "YYYYMMDD dates violate D-01 (ISO YYYY-MM-DD):
$legacy"
else
  pass "no YYYYMMDD example paths"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — README tracks version, skills, rules and the date convention"
