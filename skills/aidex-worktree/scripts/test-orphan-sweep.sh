#!/usr/bin/env bash
# test-orphan-sweep.sh — regression test for orphan-sweep.sh's scoping and its
# two blind spots.
#
# The bug this pins down (field-observed 2026-07-25): the sweep scanned Docker
# GLOBALLY for anything containing `-wt-`, but built its "still live on disk"
# set only from the CURRENT workspace's siblings. Run from a project with no
# worktrees, every OTHER project's live worktree was reported as an orphan —
# with `docker volume rm <its postgres volume>` printed next to it. One of those
# volumes belonged to a worktree with three running containers.
#
# Docker is stubbed via PATH so the whole inventory is deterministic and no
# daemon (or resource) is required.
#
# Run with: bash skills/aidex-worktree/scripts/test-orphan-sweep.sh

set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/orphan-sweep.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- fixture: workspace `alpha` with ONE live worktree; `alpha-wt-dead` has no
#     directory (true orphan); `beta-wt-other` belongs to a different project
#     that is live in ITS own workspace — invisible from here either way. ---
mkdir -p "$TMP/projects/alpha" "$TMP/projects/alpha-wt-live" "$TMP/projects/beta" "$TMP/projects/beta-wt-other"

# --- fake docker ---
mkdir -p "$TMP/bin"
cat > "$TMP/bin/docker" <<'FAKE'
#!/usr/bin/env bash
# Deterministic inventory:
#   alpha-wt-live  — live worktree (dir exists)
#   alpha-wt-dead  — orphan (no dir)          -> must be reported
#   beta-wt-other  — another project's live worktree -> must NEVER be reported
case "$*" in
  "info") exit 0 ;;
  *"ps -a"*)
    printf '%s\n' alpha-wt-live alpha-wt-dead beta-wt-other ;;
  *"volume ls"*)
    printf '%s\n' alpha-wt-live_postgres_data alpha-wt-dead_postgres_data beta-wt-other_postgres_data ;;
  *"images -f dangling=true -f label=com.docker.compose.project=alpha-wt-dead -q")
    printf '%s\n' d0000000dead d1111111dead ;;
  *"images -f dangling=true -f label="*)
    : ;;
  *"images -f dangling=true -q")
    printf '%s\n' d0000000dead d1111111dead d2222222live d3333333beta ;;
  *"inspect -f"*"com.docker.compose.project"*)
    case "${!#}" in
      d0000000dead|d1111111dead) echo alpha-wt-dead ;;
      d2222222live)              echo alpha-wt-live ;;
      d3333333beta)              echo beta-wt-other ;;
    esac ;;
  *"images --format"*)
    printf '%s\n' alpha-wt-live-backend alpha-wt-dead-backend beta-wt-other-backend ;;
  *"network ls"*)
    printf '%s\n' alpha-wt-live_net alpha-wt-dead_net beta-wt-other_net bridge ;;
  *"network inspect"*)
    echo 0 ;;
  *) exit 0 ;;
esac
FAKE
chmod +x "$TMP/bin/docker"
export PATH="$TMP/bin:$PATH"

cd "$TMP/projects/alpha"
out="$(bash "$SCRIPT" 2>&1)"; rc=$?

# --- the P0 regression: another project's resources are out of scope ---
if grep -q 'beta-wt-other' <<<"$out"; then
  fail "reported ANOTHER project's worktree resources (beta-wt-other) — the destructive false positive"
fi

# --- a live worktree of THIS project is not an orphan ---
if grep -q 'alpha-wt-live' <<<"$out"; then
  fail "reported a live worktree (alpha-wt-live) as an orphan"
fi

# --- the true orphan is reported, across all five resource kinds ---
grep -q 'compose project: alpha-wt-dead'          <<<"$out" || fail "missed orphan compose project"
grep -q 'volume: alpha-wt-dead_postgres_data'     <<<"$out" || fail "missed orphan volume"
grep -q 'image: alpha-wt-dead-backend'            <<<"$out" || fail "missed orphan tagged image"
grep -q 'dangling images: alpha-wt-dead (2)'      <<<"$out" || fail "missed orphan dangling images (the untagged build layers --rmi local cannot reclaim)"
grep -q 'network: alpha-wt-dead_net'              <<<"$out" || fail "missed orphan network (compose leaves it when another stack was attached)"

# reclaim command for dangling layers must list the IDs, not a bare prune
grep -q 'docker rmi d0000000dead d1111111dead'    <<<"$out" || fail "dangling reclaim must enumerate exact IDs"

[[ "$rc" -eq 0 ]] || fail "plain run must exit 0 (report-only), got $rc"

# --- --check turns findings into a gate failure ---
bash "$SCRIPT" --check >/dev/null 2>&1 && fail "--check must exit non-zero when orphans exist"

# --- clean project: no worktrees at all, no findings, exit 0 either way ---
cd "$TMP/projects/beta"
out_beta="$(bash "$SCRIPT" 2>&1)"
grep -q 'alpha-wt' <<<"$out_beta" && fail "beta must not see alpha's resources"
grep -q 'beta-wt-other' <<<"$out_beta" && fail "beta-wt-other is live on disk — must not be an orphan"
bash "$SCRIPT" --check >/dev/null 2>&1 || fail "--check must exit 0 for a clean project"

# --- --slug: attribution pre-flight lists a LIVE worktree's own resources ---
cd "$TMP/projects/alpha"
pre="$(bash "$SCRIPT" --slug live 2>&1)"; prc=$?
grep -q 'RESOURCE compose project: alpha-wt-live' <<<"$pre" || fail "--slug must enumerate the live worktree's own resources"
grep -q 'ORPHAN' <<<"$pre" && fail "--slug output must not call live resources orphans"
grep -q 'alpha-wt-dead' <<<"$pre" && fail "--slug must not leak a DIFFERENT slug's resources"
grep -q 'beta-wt-other' <<<"$pre" && fail "--slug must not leak another project's resources"
[[ "$prc" -eq 1 ]] || fail "--slug must exit 1 when resources exist (the teardown guard), got $prc"

# --- --slug on a slug with nothing left: exit 0, the post-teardown all-clear ---
bash "$SCRIPT" --slug gone >/dev/null 2>&1 || fail "--slug must exit 0 when nothing is attributable"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — orphan-sweep scoping (no cross-project false positives), 5 resource kinds, --check gate, --slug pre-flight"
