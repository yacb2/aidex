# Registry Operations

Manage the skill registry programmatically using `registry.sh`.

## Registry File

Located at `~/.aidex/skill-registry.json`. Created automatically during installation from the template. Contains three collections: skills, stacks, and projects.

## Three Scopes

| Scope | Location | Loaded in | When to use |
|-------|----------|-----------|-------------|
| **Shared** | `~/.aidex/skills/` → symlinked | Opt-in projects | Reusable toolkit skills |
| **Global** | `~/.claude/skills/` (real files) | All projects | Personal skills |
| **Local** | `.claude/skills/` (real files) | This project only | Project-specific |

## registry.sh — Programmatic CLI

Located at `~/.aidex/skills/aidex/scripts/registry.sh` after installation.

### Quick Reference

| Subcommand | Purpose |
|------------|---------|
| `init` | Initialize registry from template (no-op if exists) |
| `show [section]` | Display registry contents |
| `add-skill` | Register a skill |
| `update-skill` | Modify skill fields |
| `remove-skill` | Delete a skill entry |
| `set-stack` | Define a tech stack |
| `remove-stack` | Delete a stack entry |
| `add-project` | Register a project |
| `update-project` | Modify project fields |
| `remove-project` | Delete a project entry |
| `scan` | Auto-populate from filesystem |

### Usage from Agents

The registry-builder subagent calls the script instead of generating JSON:

```bash
REGISTRY_SH="$HOME/.aidex/skills/aidex/scripts/registry.sh"

# Scan filesystem and populate registry
bash "$REGISTRY_SH" scan --project-dir "$(pwd)"

# Read current state
bash "$REGISTRY_SH" show summary
bash "$REGISTRY_SH" show skills

# Update after analysis
bash "$REGISTRY_SH" update-skill django-backend --add-used-by my_project
bash "$REGISTRY_SH" update-project my_project --last-audited "$(date +%Y-%m-%d)"
```

### Usage from Terminal

```bash
# View registry
~/.aidex/skills/aidex/scripts/registry.sh show summary
~/.aidex/skills/aidex/scripts/registry.sh show skill django-backend

# Add a skill manually
~/.aidex/skills/aidex/scripts/registry.sh add-skill my-tool \
  --category devtools --tags git,automation --scope global

# Define a stack
~/.aidex/skills/aidex/scripts/registry.sh set-stack django-vue \
  --label "Django + Vue 3" \
  --detect '{"backend/pyproject.toml":"django","frontend/package.json":"vue"}' \
  --skills django-backend,form-system,shadcn-vue,vue-component-builder

# Scan a project
~/.aidex/skills/aidex/scripts/registry.sh scan --project-dir ~/Documents/projects/my-app
```

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `REGISTRY_FILE` | `~/.aidex/skill-registry.json` | Override registry path |
| `AIDEX_DIR` | `~/.aidex` | Override aidex directory |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error (missing file, bad args) |
| 2 | No-op (already in desired state) |

## Schema (v2.0)

### Skill Entry

```json
{
  "category": "frontend|backend|testing|design|animation|devtools|fileops|api|other",
  "tags": ["vue", "django"],
  "scope": "global|library|shared|archived",
  "lastUpdated": "YYYY-MM-DD",
  "usedBy": ["project_id"],
  "localOverrides": ["project_id"],
  "symlinkedBy": ["project_id"],
  "libraryPath": "~/path (only for library scope)"
}
```

### Stack Entry

```json
{
  "label": "Django + Vue 3",
  "detect": {"backend/pyproject.toml": "django", "frontend/package.json": "vue"},
  "skills": ["django-backend", "form-system"]
}
```

### Project Entry

```json
{
  "path": "~/Documents/projects/my-app",
  "stacks": ["django", "vue"],
  "localSkills": ["custom-tool"],
  "symlinkedSkills": ["django-backend"],
  "lastAudited": "YYYY-MM-DD"
}
```

## Scan Logic

The `scan` subcommand auto-populates the registry:

1. Walk `~/.aidex/skills/*/` → register as scope "shared"
2. Walk `~/.claude/skills/*/` → symlink to aidex = skip (already shared), other symlink = "global" with `libraryPath`, real dir = "global"
3. If `--project-dir`: walk `.claude/skills/*/` → register local/symlinked skills, detect stack, create project entry
4. Update `lastScanned` timestamp

## Migration Patterns

**Make shared skill opt-in (remove from global):**
```bash
rm ~/.claude/skills/<name>  # remove global symlink
# Projects opt-in individually:
ln -s ~/.aidex/skills/<name> <project>/.claude/skills/<name>
```

**Promote local → shared:**
```bash
cp -r .claude/skills/<name> ~/.aidex/skills/<name>
rm -rf .claude/skills/<name>
ln -s ~/.aidex/skills/<name> .claude/skills/<name>
```

**Copy shared → local (for customization):**
```bash
rm .claude/skills/<name>  # remove symlink
cp -r ~/.aidex/skills/<name> .claude/skills/<name>
```
