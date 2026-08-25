---
argument-hint: [version|major|minor|patch]
description: Create a new release with version bump, changelog update, and tag
---

# version:release

<!--
  Template for a project-level `.claude/commands/version/release.md`.
  A project command is a THIN INVOCATION. It carries no workflow steps, no repo
  topology, no version-file list and no changelog rules — every one of those is
  either a `.claude/git-repos.json` field or a step in the published procedure.
  If a per-project fact has nowhere to go, extend the schema; do not write it here.
-->

Cut a release for this workspace.

**Procedure:** `~/.claude/skills/aidex-conventions/references/fleet-version-conventions.md`
**Per-project facts:** `.claude/git-repos.json`

Read both, then run the release procedure with `$ARGUMENTS` as the requested bump.
