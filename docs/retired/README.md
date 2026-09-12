# Retired: the pre-plugin installer

This folder holds what the plugin migration retired: `install.sh` (with its
`--update`, `--doctor` and `--uninstall` modes and the `~/.claude/aidex/` manifest it
maintained), its two tests `tests/test-install.sh` and `tests/test-doctor.sh`, and the
`rules/` folder that used to be copied into `~/.claude/rules/`. Since v1.0.0
(2026-09-12) aidex ships as a Claude Code plugin: skills, agents and hooks are loaded
from the plugin itself, so copying files into `~/.claude/` has no job left, and a
plugin cannot ship always-on rules at all — each retired rule's canon lives on in the
`conventions` skill's `references/`, cited by the skills that need it. To roll back to
a pre-plugin setup, check out the last pre-plugin tag and run the installer from there
(`git checkout v0.55.0 && ./install.sh`); running `bash docs/retired/install.sh` from
this tree does not work, because the script resolves `skills/` and `rules/` relative to
its own directory. The install diagnosis that `--doctor` provided returns as a skill
sub-action under backlog item BL-404.
