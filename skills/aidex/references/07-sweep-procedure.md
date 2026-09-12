# Fleet Sweep Procedure

The whole procedure behind `/aidex:aidex sweep`: check the fleet for drift instead of one
project at a time. **Read-only — it never writes to a project.** Every instrument below
reports and offers; none of them fixes anything for you.

Split out of `SKILL.md` on 2026-09-08 (BL-343), which had reached the token maximum the
`/aidex:aidex context` procedure had already been split out for (ADR 2026-08-06). Same contract:
the SKILL documents *that* this exists and routes here, this file is *how*.

## The seven instruments

1. **Fleet conformance** — `bash ${CLAUDE_PLUGIN_ROOT}/skills/aidex/scripts/compliance-sweep.sh`.
   Add `--root <dir>` to scan somewhere other than the workspace root
   (`$AIDEX_WORKSPACE_ROOT`, default `~/Documents/projects`), or name project paths to
   check only those. Add `--verbose` to also see the clean and skipped ones.

2. **Read the output.** **A clean run prints nothing and exits 0** — that is the whole
   point, so it is safe to schedule. Each drifting project prints its name and which of
   the three instruments fired: `validate` (`.context/` conformance, ratchet-checked),
   `reconcile` (closure that did not propagate, stale roll-up indexes), `sweep`
   (done/dropped items never archived, D-10).

3. **Fix per project** by running the named instrument there — nothing is fixed for you.

4. **Rule-propagation drift** — a project restating a globally-owned rule, or
   `skillOverrides` that contradict one:
   `python3 ${CLAUDE_PLUGIN_ROOT}/skills/aidex/scripts/conformance-sweep.py`.

5. **Workspace-root litter** — what has accumulated OUTSIDE any project's `.claude/` and
   `.context/`: `python3 ${CLAUDE_PLUGIN_ROOT}/skills/aidex/scripts/root-litter-sweep.py`. Read-only;
   it reports and offers, never deletes.

   It covers holding folders that only grow (`_toDelete`, `_backups`, `_archive`), loose
   files dropped at the root, a repo cloned among the projects with no `CLAUDE.md`, an
   in-project `.aidex-backups` (a regression — backups belong in
   `~/.claude/aidex/backups/`), and `Bash(x:*)` permissions naming a command no longer on
   PATH.

   Each finding is labelled `aidex` or `foreign`: **aidex leaving something behind is a
   bug in aidex, you leaving something behind is information, and the two must not read
   the same.** **Report the categories and offer to act; never act on them yourself.**
   Several are things a person keeps on purpose — an `_archive/` is a decision, not a
   mistake.

6. **Auditor freshness** — before trusting any of the auditor's own configuration advice,
   especially after updating Claude Code:
   `python3 ${CLAUDE_PLUGIN_ROOT}/skills/aidex/scripts/surface-drift-check.py`.

   It reads `references/06-claude-code-surface.md`, which records which Claude Code
   version each of the auditor's own recommendations was last verified against —
   `skillOverrides` values and cost model, MCP scoping, plugin handling, settings
   precedence. **Exit 1 means "go look", never "something broke": a newer Claude Code
   makes a recommendation UNVERIFIED, not wrong.**

   Re-verify the named rows (ask the `claude-code-guide` agent, not memory), then bump
   the version column in that reference. Unchanged behaviour is the normal outcome and
   bumping the column IS the work: it converts "nobody has looked" into "checked on this
   version". This exists because the auditor once recommended removing plugins that were
   fine, and nothing made that visible.

7. **Done-but-not-archived across all four tiers of ONE project** — plans, audits,
   requests, backlog: `python3 ${CLAUDE_PLUGIN_ROOT}/skills/conventions/scripts/archive-sweep.py`.
   `sweep.sh` covers the backlog only, which is how D-10 came to be applied there and
   skipped in the other three. Dry run by default; `--check` exits 1 for a gate;
   `--apply` moves the terminal set and never the status-drift set.

## Cadence

Yours to pick: it is a plain command, so schedule it with a routine, cron, or `/loop`.
Nothing about the schedule is baked into the script.
