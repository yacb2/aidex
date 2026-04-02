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

### I. Registry Consistency
Skills in registry match what's on disk. Flag unregistered skills.

### J. Migration Candidates
- Global skills used by 0-1 projects → candidate for library or archive
- Stack-specific globals → candidate for opt-in

## Scope Decision Matrix

| Signal | Shared (~/.aidex/) | Global (~/.claude/) | Local (.claude/) |
|--------|-------------------|--------------------|--------------------|
| Reusable toolkit skill | ✓ | | |
| Personal, all projects | | ✓ | |
| Project-specific paths | | | ✓ |
| Stack-specific, 2+ projects | ✓ (library) | | |
| Universal devtools | | ✓ | |
