# Skills Audit Checks

Detailed checks for skills across all scopes + scope decision matrix.

## Checks A-J

### A. Broken Extension Claims
Local skill claims "Extension of global X" but global doesn't exist.

### B. Duplication
Local and global skill >50% identical content → trim local to project-specific additions only.

### C. Naming Consistency
Local skill extends a global but has a different directory name → rename to match.

### D. Size Compliance
- SKILL.md >500 lines → split into references/
- Local <30 lines extending a global → evaluate if it adds value
- Inline code blocks >5 lines → move to references/

### E. Orphaned References
Files in `references/` not linked from SKILL.md → link or delete.

### F. Frontmatter Compliance
Only supported fields. Description includes triggers + negative triggers.

### G. Behavioral Testing
Check for `evals/evals.json` → INFO if missing.

### H. Symlink Validation
All symlinks resolve to existing targets.

### I. Stack Relevance
Skills loaded globally but irrelevant to the project stack → propose `skillOverrides` patch in `<project>/.claude/settings.local.json`. See [skills-auditor agent](../agents/skills-auditor.md) for the full decision matrix and override values.

## Scope Decision Matrix

| Signal | Storage in `~/.aidex/skills/` | Symlinked global (`~/.claude/skills/`) | Project local (`.claude/skills/`) |
|--------|:--:|:--:|:--:|
| Personal skill, all projects | ✓ | ✓ | |
| Project-specific paths or behavior | | | ✓ |
| Stack-specific, irrelevant in some projects | ✓ | ✓ | per-project `skillOverrides` to silence |

There is a single canonical storage (`~/.aidex/skills/`) plus symlinks. Per-project relevance is handled at runtime via `skillOverrides` in `settings.local.json` (`name-only`, `user-invocable-only`, `off`), not by moving files between scopes.
