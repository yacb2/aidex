# Skills Audit Checks

**Single carrier: the agent prompt.** The runtime source of truth for skills
audit checks and the scope decision matrix is the `skills-auditor` agent at
[../agents/skills-auditor.md](../agents/skills-auditor.md). It holds the check
codes, the `skillOverrides` values, and the storage/symlink guidance. Do not
duplicate the checks here — this file is a pointer only.
