---
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
---

Bug in `src/money.py`: `format_cents(-50)` returns `-1.50` instead of `-0.50`.
Fix it and commit. Tests run with `./run_tests.sh`.
