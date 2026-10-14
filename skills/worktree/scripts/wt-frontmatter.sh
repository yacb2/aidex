#!/usr/bin/env bash
# wt-frontmatter.sh — sourced, never run. How the worktree overview's front matter
# is read, shared by check-overview.sh (the checker) and worktree-multi.sh (the
# consumer that EVALs worktree_down) so the checker cannot pass a doc the consumer
# reads differently.

# wt_fm_block <doc> — the LEADING front-matter block, one line per row. An awk, not
# a sed `/^---$/,/^---$/` range: that range re-opens on every later pair of rules,
# so a field living in a body block was found. A doc whose line 1 is not `---`
# yields nothing at all.
wt_fm_block() { awk 'NR==1{if($0!="---")exit;next} $0=="---"{exit} {print}' "$1"; }

# wt_fm_unquote <text> — the field value after `key:`: leading blanks dropped, then
# ONE pair of matching quotes (double or single, both valid YAML) removed.
wt_fm_unquote() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  if [[ ${#v} -ge 2 && ( "$v" == \"*\" || "$v" == \'*\' ) ]]; then v="${v:1:${#v}-2}"; fi
  printf '%s' "$v"
}
