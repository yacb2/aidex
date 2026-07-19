# Context Audit Checks (.context/)

**Single carrier: the agent prompt.** The runtime source of truth for
`.context/` structural checks is the `context-auditor` agent at
[../agents/context-auditor.md](../agents/context-auditor.md). It holds the check
codes, the canonical/acceptable-optional tier lists, the empty-directory
decision matrix, and the output format. Type-agnostic and type-specific
front-matter/filename/status rules are owned by `validate.py` (run by the
`conventions-auditor` agent). Do not duplicate the checks here — this file is a
pointer only.

Canonical `.context/` types covered by those checks: `backlog`, `plans`,
`requests`, `decisions`, `references`, `research`, `audits`, `communications`,
`loops`, `worktrees`. Acceptable-optional (project-local, may be gitignored):
`data`, `diagrams`, `drafts`, `experiments`, `worklists`, `workflows`.
