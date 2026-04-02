# Reference Module Conventions

Standards for creating numbered reference documentation modules.

## Structure Pattern

```
<topic>/
├── 00-index.md              # Master index with quick reference
├── 01-<first-topic>.md      # First module
├── 02-<second-topic>.md     # Second module
├── ...
├── NN-<final-topic>.md      # Final module
└── _archive/                # Superseded versions (optional)
    └── YYYY-MM-DD-<old-file>.md
```

## No README.md at Root Level

Do **NOT** create a `README.md` inside `references/` or `docs/`. Each module has its own `00-index.md` for navigation, and `CLAUDE.md` serves as the top-level entry point linking to modules. A README at the references root becomes a maintenance burden that desynchronizes with the actual module count.

**Entry point chain:** `CLAUDE.md` → `module/00-index.md` → `module/NN-topic.md`

## File Naming

### Numbering Rules

- **Two-digit prefix**: `00-` through `99-`
- **Index always 00**: `00-index.md` is the master entry point
- **Sequential numbering**: No gaps (01, 02, 03... not 01, 03, 05)
- **Separator**: Single hyphen after number

### Name Format

```
NN-<kebab-case-description>.md

Examples:
- 00-index.md
- 01-environment-setup.md
- 02-deployment-steps.md
- 11-troubleshooting.md
```

### Category Prefixes (Optional)

For larger references, use number ranges:

| Range | Category |
|-------|----------|
| 00 | Index |
| 01-09 | Core workflow/phases |
| 10-19 | Architecture/concepts |
| 20-29 | Operations/maintenance |
| 30+ | Reference/appendix |

## 00-index.md Template

```markdown
# [Topic Name] Reference

**Version:** 1.0.0
**Last Updated:** YYYY-MM-DD
**Context:** [Brief description of what this reference covers]

---

## Quick Reference

| Action | Document | Section |
|--------|----------|---------|
| [Task 1] | [01-filename](./01-filename.md) | [Section](#anchor) |
| [Task 2] | [02-filename](./02-filename.md) | [Section](#anchor) |

## Documents in This Reference

| # | Document | Description |
|---|----------|-------------|
| 00 | This index | Master reference and navigation |
| 01 | [First Topic](./01-topic.md) | Brief description |
| 02 | [Second Topic](./02-topic.md) | Brief description |

## Prerequisites

- [Prerequisite 1]
- [Prerequisite 2]

## Key Information

[Critical information that applies to all modules - server URLs, credentials location, etc.]

## Related References

- [Related Reference 1](../related/00-index.md)

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | YYYY-MM-DD | Initial version |
```

## Module Template (01-NN)

```markdown
# [Module Title]

**Version:** 1.0.0
**Last Updated:** YYYY-MM-DD
**Context:** [Module-specific context]

---

## Overview

[1-2 paragraph overview of this module's content and purpose]

## Prerequisites

- [Prerequisite 1]
- [Prerequisite 2]

---

## [Main Section 1]

### [Subsection 1.1]

[Content with code examples]

```bash
# Example command
command --flag value
```

**Expected Output:**
```
Output here
```

### [Subsection 1.2]

[More content]

---

## [Main Section 2]

[Content]

---

## Verification

- [ ] Check 1
- [ ] Check 2
- [ ] Check 3

## Troubleshooting

### [Issue 1]

**Symptom:** [What user sees]

**Cause:** [Why it happens]

**Solution:**
```bash
# Fix command
```

---

## Next Steps

- [Next document](./NN-next.md)

## See Also

- [Related document](./NN-related.md#section)
```

## Warning Format

Use blockquotes with bold prefix:

```markdown
> **Warning** Deploy CMS before frontend to avoid build failures.

> **Critical** Never run this command in production without backup.

> **Note** This step is optional for development environments.
```

## Cross-Reference Format

### Within Same Reference

```markdown
[See Setup Steps](./01-setup.md#configuration)
```

### To Other References

```markdown
[See Related Reference](../other-topic/00-index.md)
```

### With Anchors

```markdown
[Troubleshooting section](./08-troubleshooting.md#database-connection-issues)
```

## Archive Convention

When superseding a document:

1. Create `_archive/` directory if not exists
2. Move old file with date prefix: `YYYY-MM-DD-original-name.md`
3. Add note at top of archived file:

```markdown
> **Archived** Superseded by [new-file](../NN-new-file.md) on YYYY-MM-DD
```

## Code Block Standards

### Always Include Language Hint

```markdown
```bash
# Shell commands
```

```typescript
// TypeScript code
```

```json
// JSON config
```
```

### Include Expected Output

```markdown
```bash
npm run build
```

**Expected Output:**
```
Build completed successfully
```
```

## Metadata Requirements

Every file MUST include:

| Field | Required | Format |
|-------|----------|--------|
| Version | Yes | Semantic (X.Y.Z) |
| Last Updated | Yes | YYYY-MM-DD |
| Context | Recommended | Brief description |

## Validation Rules

### Structure Checks

- [ ] `00-index.md` exists
- [ ] Files numbered sequentially (no gaps)
- [ ] File names use kebab-case
- [ ] `_archive/` used correctly (if present)

### Metadata Checks

- [ ] Version field in all files
- [ ] Last Updated field in all files
- [ ] Version follows semantic format

### Content Checks

- [ ] Overview section in each module
- [ ] Prerequisites section present
- [ ] Quick Reference table in index
- [ ] Documents table in index complete

### Link Checks

- [ ] All cross-references resolve
- [ ] No broken anchor links
- [ ] Relative paths used (not absolute)
