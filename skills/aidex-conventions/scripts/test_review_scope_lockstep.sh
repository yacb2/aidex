#!/usr/bin/env bash
# Two-sided lockstep guard for the review-scope enum.
#
# The scope enum is declared in three places that must agree:
#
#   1. scripts/resolve-review-scope.sh   — the SCOPES variable (what is accepted)
#   2. references/review-scope-conventions.md — the enum table (what is documented)
#   3. aidex-plan-exec/SKILL.md          — must delegate to the reference, so the
#                                          consumer cannot drift into its own list
#
# Both enum sets are DERIVED from their files; nothing here hard-codes a scope
# name. A guard that names what it guards rots the moment the owner edits — two
# repo tests were found silently dead this way on 2026-07-24.
#
# Site 3 is a delegation check, not a copy of the enum: plan-exec must point at
# the reference rather than restate the scopes, because a restated list is a
# fourth place to drift. The SKILL.md is line-wrapped, so it is matched against a
# whitespace-flattened copy.
#
# Run with: bash skills/aidex-conventions/scripts/test_review_scope_lockstep.sh

set -uo pipefail

SKILLS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SCRIPT="$SKILLS/aidex-conventions/scripts/resolve-review-scope.sh"
REF="$SKILLS/aidex-conventions/references/review-scope-conventions.md"
EXEC="$SKILLS/aidex-plan-exec/SKILL.md"

fail=0
err() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }
die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

for f in "$SCRIPT" "$REF" "$EXEC"; do
  [ -f "$f" ] || die "missing file: $f"
done

# ---------- site 1: the SCOPES variable the resolver enforces ----------
impl=$(grep -m1 '^SCOPES=' "$SCRIPT" | sed 's/^SCOPES="//; s/"$//' | tr ' ' '\n' \
  | grep -v '^$' | sort -u)
[ -n "$impl" ] || die "could not parse SCOPES from $SCRIPT"

# ---------- site 2: the enum table in the reference ----------
# Rows look like: | `working-diff` | ... |  — `module-path <path>` keeps only the
# scope name, since the argument is not part of the enum.
doc=$(awk '/^## 2\. The scope enum/{f=1;next} /^## /{f=0} f' "$REF" \
  | grep '^| `' | sed 's/^| `//; s/`.*//' | awk '{print $1}' | grep -v '^$' | sort -u)
[ -n "$doc" ] || die "no enum rows found in the scope-enum table of $REF"

if [ "$impl" != "$doc" ]; then
  err "resolver vs reference mismatch — resolver: [$(echo $impl)] vs reference: [$(echo $doc)]"
fi

# ---------- the resolver must actually REJECT a name outside the enum ----------
# Without this, both sides could agree on a list the code never enforces.
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git init -q -b main "$tmp/r"
git -C "$tmp/r" config user.email t@t.test
git -C "$tmp/r" config user.name Test
printf 'x\n' > "$tmp/r/f.txt"
# `module-path` needs its target to exist, so the probe path is a real directory.
mkdir -p "$tmp/r/mod" && printf 'y\n' > "$tmp/r/mod/g.txt"
git -C "$tmp/r" add -A >/dev/null && git -C "$tmp/r" commit -qm base
if ( cd "$tmp/r" && bash "$SCRIPT" not-a-real-scope >/dev/null 2>&1 ); then
  err "the resolver accepted a scope outside its own enum — the enum is decorative"
fi
for s in $impl; do
  if ( cd "$tmp/r" && bash "$SCRIPT" "$s" mod >/dev/null 2>&1 ); then :; else
    rc=$?
    # 3 (empty scope) is fine here; 2 (usage/unknown) means a documented scope is
    # not actually accepted by the code.
    [ "$rc" = "3" ] || err "documented scope '$s' is not accepted by the resolver (exit $rc)"
  fi
done

# ---------- site 3: plan-exec delegates instead of restating ----------
flat=$(tr '\n' ' ' < "$EXEC" | tr -s ' ')
case "$flat" in
  *review-scope-conventions.md*) ;;
  *) err "aidex-plan-exec/SKILL.md does not reference review-scope-conventions.md — the consumer is free to drift" ;;
esac
case "$flat" in
  *resolve-review-scope.sh*) ;;
  *) err "aidex-plan-exec/SKILL.md does not name resolve-review-scope.sh — the checkpoint has no resolver to call" ;;
esac

# The path plan-exec tells an installed user to run must point at a script that
# exists. A shipped doc naming a path that resolves nowhere is the "shipped ADR
# map dead for all installed users" failure from the 2026-07-25 audit — and a
# grep for the bare filename passes happily against it.
named=$(printf '%s' "$flat" | tr ' `' '\n\n' | grep 'resolve-review-scope\.sh' | head -1)
if [ -n "$named" ]; then
  base=$(basename "$named")
  [ -f "$SKILLS/aidex-conventions/scripts/$base" ] \
    || err "plan-exec names '$named' but no such script exists under aidex-conventions/scripts/"
  case "$named" in
    '~/.aidex/skills/aidex-conventions/scripts/'*) ;;
    *) err "plan-exec must name the INSTALLED path (~/.aidex/skills/...); '$named' does not resolve where the SKILL.md is read" ;;
  esac
fi

# ---------- every reference must be routed from the skill's entry point ------
# A canon doc nobody can reach is a doc that does not exist. Verified empty at
# the time this guard was added (all 14 references routed), so it starts honest
# rather than inheriting somebody else's debt.
CONV_SKILL="$SKILLS/aidex-conventions/SKILL.md"
for f in "$SKILLS"/aidex-conventions/references/*.md; do
  b=$(basename "$f")
  grep -q "references/$b" "$CONV_SKILL" \
    || err "references/$b is not routed from aidex-conventions/SKILL.md — unreachable canon"
done

if [ "$fail" -eq 0 ]; then
  echo "OK — scope enum in lockstep and enforced: [$(echo $impl)]"
  exit 0
fi
exit 1
