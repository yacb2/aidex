# Plan Conventions

Standards for creating implementation plans with checkbox tracking for multi-session work.

## Structure Pattern

### Multi-File Plan (Default)

For plans with **3 or more phases**, use a folder structure:

```
.context/plans/YYYYMMDD-<feature-name>/
├── 00-index.md              # Master index with overview
├── 01-<phase-1-name>.md     # Phase 1 details
├── 02-<phase-2-name>.md     # Phase 2 details
└── ...
```

**Naming:**
- Date format: `YYYYMMDD` (no dashes, e.g., `20260119`)
- Feature name: kebab-case (e.g., `audit-system`)
- Phase files: numbered with descriptive name (e.g., `01-backend-models.md`)

### Single-File Plan (Simple Tasks)

For plans with **1-2 phases only**:

```
.context/plans/YYYYMMDD-<feature-name>.md
```

## Index File Template (00-index.md)

```markdown
# [Feature Name] Implementation Plan

**Goal:** [One sentence describing what this builds]

**Architecture:**
- [Key architectural decision 1]
- [Key architectural decision 2]

**Tech Stack:**
- Backend: [technologies]
- Frontend: [technologies]

---

## Phases Overview

| Phase | File | Description | Tasks |
|-------|------|-------------|-------|
| 1 | [01-phase-name.md](01-phase-name.md) | Brief description | N |
| 2 | [02-phase-name.md](02-phase-name.md) | Brief description | N |

---

## Session Checkpoint

**Status:** Planning | In Progress | Completed

**Plan Documentation Complete:**
- [ ] Phase 1: [Name] (N tasks)
- [ ] Phase 2: [Name] (N tasks)

**Total:** X tasks across N phases
**Next:** Start with Phase 1, Task 1.1
```

## Phase File Template (NN-phase-name.md)

```markdown
# Phase N: [Phase Name]

[← Back to Index](00-index.md)

---

## Task N.1: [Task Name]

**Files:**
- Create: `exact/path/to/new-file.py`
- Modify: `exact/path/to/existing.py`

**Step 1: [Action description]**

```python
# Full code snippet - not just reference
from module import something

class MyClass:
    def method(self):
        pass
```

**Step 2: [Next action]**

[Continue with implementation steps...]

**Verify:**

```bash
command-to-verify
```

Expected: `OK`

---

## Task N.2: [Next Task Name]

[Same format as Task N.1...]

---

## Phase N Checkpoint

**Completed:**
- [ ] Task N.1: [Brief description]
- [ ] Task N.2: [Brief description]

**Next:** [Phase N+1: Name](0N+1-phase-name.md)
```

## Task Format Rules

### Step Granularity

Each step should be **2-5 minutes** of work:

| Good (Atomic) | Bad (Too Large) |
|---------------|-----------------|
| Create directory structure | Implement authentication |
| Create serializer class | Add user management |
| Update __init__.py exports | Set up the backend |
| Verify import works | Fix all bugs |

### Code Inclusion

**Always include full code** in steps, not just references. Show the actual implementation, not "follow the pattern in `other_file.py`".

## Status Tracking

### Frontmatter (in 00-index.md)

```yaml
---
status: planning | in-progress | blocked | completed
current-phase: 1
last-updated: 2026-01-19
---
```

### Session Checkpoint Format

At end of each work session, update:

```markdown
## Session Checkpoint

**Date:** 2026-01-19
**Session:** 3

**Completed:**
- [x] Task 1.1: TreeNodeSerializer
- [ ] Task 1.3: URL registration (50% complete)

**Blockers:** None

**Next Session:**
- [ ] Complete Task 1.3
- [ ] Task 1.4: Tests
```

## Phase Organization

Group tasks by layer (models → serializers → views → URLs → tests), feature area (one component end-to-end), or dependency order (what must exist before what). Example phase names: `01-backend-models.md`, `02-backend-api.md`, `03-frontend-components.md`, `04-testing-verification.md`.

## Validation Checklist

### Index File (00-index.md)
- [ ] Title, Goal, Architecture, Tech Stack
- [ ] Phases Overview table with links
- [ ] Session Checkpoint section

### Phase Files
- [ ] Phase title with number and name
- [ ] Link back to index
- [ ] Tasks numbered as N.1, N.2, etc.
- [ ] Each task has Files section
- [ ] Each step has full code (not references)
- [ ] Phase Checkpoint at end

### Task Checks
- [ ] Steps are atomic (2-5 minutes each)
- [ ] Code is complete (not placeholders)
- [ ] Verification included where appropriate
