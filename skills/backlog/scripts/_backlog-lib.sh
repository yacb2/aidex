#!/usr/bin/env bash
# _backlog-lib.sh — helpers the backlog scripts used to carry one copy each. Sourced, never run.
# Source it after conventions/scripts/_lib.sh.

# Append the cited shas to a `commits:` value (c14). The existing value is kept verbatim
# (it may carry repeated repo labels); a cited sha is skipped when it is the same commit as
# a token already there: equal, or both 7+ hex with one a prefix of the other.
MERGE_AWK='function ishex(s) { return (s ~ /^[0-9a-f]+$/ && length(s) >= 7) }
function same(x, y) { if (x == y) return 1; if (ishex(x) && ishex(y)) return (index(x, y) == 1 || index(y, x) == 1); return 0 }
function merge(val, add,   n, a, m, t, i, j, dup, out) {
  out = val; gsub(/^ +| +$/, "", out); m = split(val, t, " "); n = split(add, a, " ")
  for (i = 1; i <= n; i++) {
    dup = 0; for (j = 1; j <= m; j++) if (same(a[i], t[j])) dup = 1
    if (!dup) { out = out (out == "" ? "" : " ") a[i]; t[++m] = a[i] }
  }
  return out
}
'

# append_commit <file> <shas>: merge the shas into the front-matter `commits:` line, or add the
# line before the closing `---`. A sha already recorded (a whole token of that line, equal or
# short/full prefix) returns before any rewrite, so a non-canonical line is never normalised.
append_commit() {
  local file="$1" shas="$2"
  awk -v sha="$shas" "$MERGE_AWK"'/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && /^commits:/{gsub(/"/,""); for(i=2;i<=NF;i++) if(same($i,sha)) f=1} END{exit !f}' "$file" 2>/dev/null && return 0
  awk -v commits="$shas" "$MERGE_AWK"'BEGIN { d=0; seen=0 }
    /^---[[:space:]]*$/ {
      d++
      if (d==2 && !seen) print "commits: \"" merge("", commits) "\""
      print; next
    }
    d==1 && /^commits:/ {
      val=$0; sub(/^commits:[[:space:]]*/,"",val); gsub(/"/,"",val)
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",val)
      if (val=="[]") val=""
      print "commits: \"" merge(val, commits) "\""
      seen=1; next
    }
    { print }' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

# Escape a value for a double-quoted YAML scalar.
#
# Without this, `--title` and `--blocked-by` land raw inside `key: "$VALUE"`. A title
# containing a newline followed by `---` terminates the front-matter early: every key
# after it (id included) becomes body prose, the id reader returns empty, and the id is
# re-minted for the next item. A double quote closes the scalar and lets a second key be
# injected, which a last-write-wins parser honours. Found 2026-08-10 by review.
yaml_escape() {
  printf '%s' "$1" \
    | tr '\n\r\t' '   ' \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# The raw `id:` value of a file's front-matter, or empty. Quotes are NOT stripped here: that
# policy is an owner question (backlog-s31); register-item.sh read_entry_id is a different reader.
read_id() { awk '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2; exit}' "$1"; }
