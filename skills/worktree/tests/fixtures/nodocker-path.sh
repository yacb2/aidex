#!/usr/bin/env bash
# nodocker-path.sh — sourced, never run. One owner for the "docker is not on PATH"
# fixture the BL-890 cells share (test-teardown-and-scope.sh, test-list-rows.sh).
#
# nodocker_path <PATH-string>: that PATH with every directory that holds an
# executable `docker` dropped (a stub's directory included). No trailing ':', which
# would put the cwd on PATH.
#
# Known limit: on a host whose docker sits beside git and awk (Linux, /usr/bin/docker)
# those go too, and the cells fail on a missing tool instead of on the guard. Fix it
# here, once, if a suite ever runs there.
nodocker_path() {
  local d out=""
  while IFS= read -r d; do
    [[ -n "$d" && ! -x "$d/docker" ]] && out+="$d:"
  done < <(printf '%s\n' "$1" | tr ':' '\n')
  printf '%s\n' "${out%:}"
}
