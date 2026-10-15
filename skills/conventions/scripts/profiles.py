#!/usr/bin/env python3
"""Resolve a per-project profile: .context/profiles/<name>.md, else the legacy root file.

Canon: skills/conventions/references/00-global.md, "Profiles". The bash twin is
`resolve_profile` in _lib.sh; tests/test-profile-resolver.sh pins that both agree.

CLI: profiles.py <context-dir> <name>   prints the path, exit 1 when there is none.
"""
import os
import sys

LEGACY = {
    "artifact": "artifact-style.md",
    "communication": "communication-style.md",
    "testing": "testing-profile.md",
    "deploy": "deploy-profile.md",
    "ui-contract": "ui-contract.md",
}


def profile_write_path(context_dir, name):
    """Where a profile is CREATED: always the new path, never the legacy one."""
    return os.path.join(context_dir, "profiles", name + ".md")


def resolve_profile(context_dir, name):
    """Path of the profile that exists (new path first, legacy root second), or None."""
    if name not in LEGACY:  # unknown name: a refusal, like the bash twin
        return None
    for path in (profile_write_path(context_dir, name),
                 os.path.join(context_dir, LEGACY[name])):
        if os.path.isfile(path):
            return path
    return None


def resolve_profile_or_root(root, name):
    """Like resolve_profile, then the tracked repo-root file <root>/<legacy name> as the fallback (BL-289):
    a project that gitignores .context/ cannot ship its profile there. .context/ still wins. None when neither.
    backlog/scripts/sweep-gate.sh (PROFILE_ALT) keeps its own shell copy of this fallback."""
    found = resolve_profile(os.path.join(root, ".context"), name)
    if found:
        return found
    alt = os.path.join(root, LEGACY[name]) if name in LEGACY else None
    return alt if alt and os.path.isfile(alt) else None


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: profiles.py <context-dir> <name>", file=sys.stderr)
        sys.exit(2)
    found = resolve_profile(sys.argv[1], sys.argv[2])
    if found:
        print(found)
    sys.exit(0 if found else 1)
