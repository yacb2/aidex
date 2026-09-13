#!/bin/bash
set -e
mkdir -p .context/backlog/_archive .context/plans src
printf '# Notes app\n\nSmall Flask app. Source in src/.\n' > CLAUDE.md
printf 'def export_csv(notes):\n    raise NotImplementedError\n' > src/export.py
cat > .context/backlog/2026-09-01-bl-001-add-tags-to-notes.md <<'MD'
---
title: "Add tags to notes"
id: BL-001
status: open
created: 2026-09-01
updated: 2026-09-01
origin: manual
origin_ref: ""
priority: P2
type: feature
estimate: S
surface: backend
verify: ""
blocked_by: ""
escalated_to: ""
commits: ""
---

# Add tags to notes

## Context

Users want to group notes.
MD
