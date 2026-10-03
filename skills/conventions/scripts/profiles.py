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
    for path in (profile_write_path(context_dir, name),
                 os.path.join(context_dir, LEGACY[name])):
        if os.path.isfile(path):
            return path
    return None


if __name__ == "__main__":
    found = resolve_profile(sys.argv[1], sys.argv[2])
    if found:
        print(found)
    sys.exit(0 if found else 1)
