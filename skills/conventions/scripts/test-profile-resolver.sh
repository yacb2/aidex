#!/usr/bin/env bash
# test-profile-resolver.sh — the one profile resolver (BL-674): .context/profiles/<name>.md
# wins, the legacy root file is the read-only fallback, neither -> empty + non-zero.
# Layer: unit (a path decision, no browser, no repo). Both twins are checked against the
# same table so they cannot drift: resolve_profile in _lib.sh and profiles.py.
#
# Run with: bash skills/conventions/scripts/test-profile-resolver.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CTX="$TMP/.context"

sh_resolve() { ( . "$HERE/_lib.sh"; resolve_profile "$1" "$2" ); }
py_resolve() { python3 "$HERE/profiles.py" "$1" "$2"; }

# name:legacy file — the canon table (00-global.md §12)
for pair in artifact:artifact-style.md communication:communication-style.md \
            testing:testing-profile.md deploy:deploy-profile.md ui-contract:ui-contract.md; do
  name="${pair%%:*}" legacy="${pair##*:}"
  rm -rf "$CTX"; mkdir -p "$CTX"

  for fn in sh_resolve py_resolve; do
    out="$($fn "$CTX" "$name")"; rc=$?
    [[ $rc -ne 0 && -z "$out" ]] || fail "$fn $name: neither file must give empty output and a non-zero exit (rc=$rc out=$out)"
  done

  printf 'old\n' > "$CTX/$legacy"
  for fn in sh_resolve py_resolve; do
    out="$($fn "$CTX" "$name")" || fail "$fn $name: the legacy root file must resolve"
    [[ "$out" == "$CTX/$legacy" ]] || fail "$fn $name: legacy fallback gave '$out', want $CTX/$legacy"
  done

  mkdir -p "$CTX/profiles"; printf 'new\n' > "$CTX/profiles/$name.md"
  for fn in sh_resolve py_resolve; do
    out="$($fn "$CTX" "$name")" || fail "$fn $name: the new path must resolve"
    [[ "$out" == "$CTX/profiles/$name.md" ]] || fail "$fn $name: new path must win over legacy, gave '$out'"
  done
done

# An unknown name is a refusal, never a guess.
sh_resolve "$CTX" nonsense >/dev/null 2>&1 && fail "sh_resolve accepted an unknown profile name"
py_resolve "$CTX" nonsense >/dev/null 2>&1 && fail "py_resolve accepted an unknown profile name"

# Writers get the new path only.
w="$(. "$HERE/_lib.sh"; profile_write_path "$CTX" artifact)"
[[ "$w" == "$CTX/profiles/artifact.md" ]] || fail "profile_write_path gave '$w'"

if [[ $failures -gt 0 ]]; then printf '%d failure(s)\n' "$failures"; exit 1; fi
echo "OK — profile resolver: 5 names x (none, legacy, new wins) in bash and python, unknown name refused"
