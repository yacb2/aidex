# Versioning — invariants

<!--
  Template for a project-level `.claude/rules/versioning.md`.
  A rule is ALWAYS-ON: every line is paid for in every session, release or not.
  So it carries invariants only. The procedure lives in
  `~/.claude/skills/aidex-conventions/references/fleet-version-conventions.md`,
  and the per-project facts live in `.claude/git-repos.json`.
  Replace the bracketed values, delete this comment, and delete any line that
  states a fact `git-repos.json` already holds.
-->

- This workspace is **[mono-repo | N independent repos]**. The repos, their paths and their
  version files are declared in `.claude/git-repos.json` — read it, never infer them.
- Version sync policy: **[locked | independent]**, tagging **[together | per-repo]**.
  Under `locked`, the version files must always match; a mismatch is a bug, not a state.
- Never bump a version, fold a changelog or create a tag by hand. `/version:release` runs the
  published procedure and reads the config; a hand edit is how the two drift.
- Changelog section headings come from **[the schema file | the canon's mapping table]** and
  are never invented at write time.
- `.boilerplate-version` is **[the boilerplate sync marker — do NOT touch on a release |
  this project's released version — bump it]**.
- Releases are created locally and **never pushed automatically**.

Procedure: `~/.claude/skills/aidex-conventions/references/fleet-version-conventions.md`
