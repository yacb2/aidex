# Fix Procedures

## Safe Fixes (batch with single confirmation)

### Loose File Conversion
For each `.md` file directly in `.context/references/` or `.context/docs/`:
1. Create directory from filename
2. Move file as `01-content.md`
3. Generate `00-index.md`
4. Update all links to old path

### Metadata Fixes
- Add missing Version/Last Updated/Context headers
- Use file modification date for Last Updated, default version 1.0.0

### Index Fixes
- Add missing file links to `00-index.md` Documents table

### Numbering Fixes
- Close gaps by renaming (03→02, 04→03, etc.)
- Update all internal links after renumbering

### Script Permissions
- `chmod +x` on all files in `scripts/` directories

### Memory Condensation
- Replace multi-line entries with 1-line links
- Remove entries classified as REMOVE

## Reorganization Fixes (per-item approval)

### Consolidate bugs/ + fixes/ into issues/
```
Found: .context/bugs/ (3 files) and .context/fixes/ (2 files)
Convention: issues/ with ISSUE-NNN format (problem + root cause + fix in one file)
Options:
  [1] Merge into issues/ with ISSUE-NNN structure
  [2] Keep separate
```
When merging: create ISSUE-NNN-description.md with Status/Severity/Date fields, combine bug description with fix into single file, create 00-index.md.

### Remove redundant README.md from references/
```
Found: .context/references/README.md
Convention: Each module has 00-index.md. CLAUDE.md is the entry point.
The README adds a maintenance layer that desynchronizes.
Options:
  [1] Delete (modules have their own indexes)
  [2] Keep
```

### Restructure issues/ to ISSUE-NNN format
```
Found: .context/issues/ with ad-hoc filenames
Convention: ISSUE-NNN-description.md with Status/Severity/Date/Root Cause/Fix fields
Options:
  [1] Rename and restructure existing files
  [2] Keep current names
```

### Suggest missing directories
```
Missing: .context/roadmap/
This project has multiple active phases but no roadmap.
Options:
  [1] Create with README.md template
  [2] Skip
```

## Destructive Fixes (per-item approval)

### Delete Orphaned Files
```
Orphaned: skills/my-skill/references/old-patterns.md
Not linked from SKILL.md. Options:
  [1] Delete  [2] Add link to SKILL.md  [3] Skip
```

### Remove Banned Files
```
Banned: skills/my-skill/README.md
SKILL.md serves this purpose. Delete? (y/n)
```

### Trim Duplicated Skills
```
.claude/skills/my-skill: ~80% identical to ~/.claude/skills/my-skill
Options:
  [1] Delete local (use global)
  [2] Trim local to project-specific only
  [3] Keep both
```

### Archive Completed Plans
```
.context/plans/20250115-auth-migration.md
Status: completed | All tasks done
Options:
  [1] Archive to .context/plans/_archive/
  [2] Delete permanently
  [3] Keep
```

### Fix Broken Symlinks
```
.claude/skills/gsap-core → ~/.aidex/skills/gsap-core (BROKEN)
Options:
  [1] Remove symlink
  [2] Skip
```
