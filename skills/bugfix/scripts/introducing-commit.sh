#!/usr/bin/env bash
# introducing-commit.sh — point at the commit that most likely introduced a bug (SZZ).
#
# Usage: introducing-commit.sh [--repo DIR] [FIX]
#   FIX given   the fix is FIX^..FIX; the pre-fix version is FIX^.
#   no FIX      the uncommitted diff against HEAD (staged + unstaged, untracked ignored);
#               the pre-fix version is HEAD.
#
# Stdout, one line per candidate commit, best first (R-SZZ: the first line is the pick):
#   <short sha> TAB <committer date YYYY-MM-DD> TAB <blamed line count> TAB <subject>
# Ordered by committer time, most recent first; ties by line count, descending.
# Exit: 0 candidates found; 3 none (only tests, only new files, only whitespace);
#       2 usage error, not a git repo, unknown FIX, or a FIX with no parent (reason on stderr).
#
# Method: test files and files absent from the pre-fix version are skipped. In the rest, lines
# the fix removes or modifies are blamed in the pre-fix version (git blame -w -M -C). A hunk that
# only ADDS lines (a missing guard, a missing branch) has none, so the nearest non-blank line
# above and below the insertion point is blamed instead. The result is a pointer, not a proof.
# Known misses, left on purpose: a fix that moves a file and leaves a shim at the old path blames
# the whole old file; uncommitted mode reads the working-tree file without clean/smudge filters.
set -uo pipefail

die() { printf 'introducing-commit: %s\n' "$*" >&2; exit 2; }

repo=.; fix=
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || die "--repo needs a directory"; repo="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$fix" ] || die "more than one FIX given"; fix="$1"; shift ;;
  esac
done

top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || die "not a git repository: $repo"
cd "$top" || die "cannot enter $top"
export GIT_LITERAL_PATHSPECS=1   # a path with * or [ in its name is a path, not a glob

if [ -n "$fix" ]; then
  fixsha="$(git rev-parse --verify -q "$fix^{commit}")" || die "unknown commit: $fix"
  pre="$(git rev-parse --verify -q "$fixsha^")" || die "commit $fix has no parent"
  diff_args=("$pre" "$fixsha")
else
  pre="$(git rev-parse --verify -q HEAD^{commit})" || die "no HEAD commit to compare against"
  diff_args=(HEAD)
fi
shallow="$(git rev-parse --is-shallow-repository 2>/dev/null || echo false)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/introducing-commit.XXXXXX")" || die "cannot create a temp dir"
trap 'rm -rf "$TMP"' EXIT

# test path: a component tests|test|__tests__|spec|e2e (any case), or a test-named basename
# (test_x, test-x, x_test.y, x-test.y, x.test.y, x.spec.y, tests.py, FooTest.cs, FooTests.swift)
is_test_path() {
  local lower base
  lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "/$lower/" in */tests/*|*/test/*|*/__tests__/*|*/spec/*|*/e2e/*) return 0 ;; esac
  base="${lower##*/}"
  case "$base" in test_*|test-*|*_test.*|*-test.*|*.test.*|*.spec.*|tests.*) return 0 ;; esac
  case "${1##*/}" in *Test.*|*Tests.*) return 0 ;; esac
  return 1
}

# name-status with renames: a renamed file is blamed under its old path, a deleted file is a
# meta-change (not a line the fix repaired), an added file has nothing to blame.
git diff -M --name-status -z "${diff_args[@]}" > "$TMP/files" || die "git diff failed"

sts=(); olds=(); news=()
while IFS= read -r -d '' st; do
  case "$st" in
    R*|C*) IFS= read -r -d '' old; IFS= read -r -d '' f ;;
    *) IFS= read -r -d '' old; f="$old" ;;
  esac
  sts[${#sts[@]}]="$st"; olds[${#olds[@]}]="$old"; news[${#news[@]}]="$f"
done < "$TMP/files"

: > "$TMP/counts"
i=0
while [ "$i" -lt "${#sts[@]}" ]; do
  st="${sts[$i]}"; old="${olds[$i]}"; f="${news[$i]}"; i=$((i + 1))
  case "$st" in D*|A*) continue ;; esac
  is_test_path "$f" && continue
  is_test_path "$old" && continue
  git show "$pre:$old" > "$TMP/pre" 2>/dev/null || continue   # absent before the fix: nothing to blame
  # the new side, diffed blob against blob so a rename or copy compares with its own old path.
  # --inter-hunk-context=0: a diff.interHunkContext setting must not merge hunks, the lines
  # between two hunks are not the fix's.
  if [ -n "$fix" ]; then git show "$fixsha:$f" > "$TMP/new" 2>/dev/null || continue; else cp "$f" "$TMP/new" 2>/dev/null || continue; fi
  git diff --no-index -U0 --inter-hunk-context=0 -w --ignore-blank-lines --no-color --no-ext-diff "$TMP/pre" "$TMP/new" > "$TMP/diff"
  # One range per line: "start,end". Blamed: the NON-BLANK lines of the old side of each hunk. A hunk
  # with none (add-only, or only blank lines replaced) yields the nearest non-blank line each side.
  awk -v pre="$TMP/pre" '
    BEGIN { n = 0; while ((getline l < pre) > 0) { n++; nb[n] = (l ~ /^[[:space:]]*$/) ? 0 : 1 } }
    /^@@ / {
      split($2, o, ","); a = substr(o[1], 2) + 0; b = (o[2] == "") ? 1 : o[2] + 0
      s = 0; found = 0
      for (i = a; i < a + b; i++) {
        if (nb[i]) { if (!s) s = i }
        else if (s) { print s "," (i - 1); found = 1; s = 0 }
      }
      if (s) { print s "," (a + b - 1); found = 1 }
      if (found) next
      up = (b > 0) ? a - 1 : a; while (up >= 1 && !nb[up]) up--
      dn = (b > 0) ? a + b : a + 1; while (dn <= n && !nb[dn]) dn++
      if (up >= 1) print up "," up
      if (dn <= n) print dn "," dn
    }' "$TMP/diff" > "$TMP/ranges"
  largs=()
  while IFS= read -r r; do largs[${#largs[@]}]="-L$r"; done < "$TMP/ranges"
  [ "${#largs[@]}" -gt 0 ] || continue
  git blame -w -M -C --porcelain "${largs[@]}" "$pre" -- "$old" > "$TMP/blame" 2>/dev/null || {
    printf 'introducing-commit: cannot blame %s, skipped\n' "$old" >&2; continue; }
  # porcelain: one "<sha> <orig> <final>" header per blamed line; "boundary" follows a commit's first header
  awk -v shallow="$shallow" '
    substr($0, 1, 1) != "\t" && length($1) == 40 && $1 ~ /^[0-9a-f]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ { cur = $1; c[cur]++; next }
    $1 == "boundary" { bd[cur] = 1 }
    END { for (s in c) { if (s ~ /^0+$/) continue; if (shallow == "true" && bd[s]) continue; print s, c[s] } }
  ' "$TMP/blame" >> "$TMP/counts"
done < "$TMP/files"

awk '{ t[$1] += $2 } END { for (s in t) print s, t[s] }' "$TMP/counts" > "$TMP/total"
: > "$TMP/out"
while read -r sha cnt; do
  short="$(git rev-parse --short "$sha")"
  meta="$(git show -s --date=short --format='%ct%x09%cd%x09%s' "$sha")"
  ct="${meta%%$'\t'*}"; rest="${meta#*$'\t'}"
  printf '%s\t%s\t%s\t%s\t%s\n' "$ct" "$short" "${rest%%$'\t'*}" "$cnt" "${rest#*$'\t'}" >> "$TMP/out"
done < "$TMP/total"

[ -s "$TMP/out" ] || exit 3
sort -t "$(printf '\t')" -k1,1nr -k4,4nr -k2,2 "$TMP/out" | cut -f2-
exit 0
