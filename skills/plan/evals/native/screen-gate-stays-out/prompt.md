---
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
---

Create a plan for moving the nightly billing job to a queue worker. Backend
only: new worker, retry policy and a data backfill; no UI changes. Everything is
already defined, do not ask me anything.

Write the plan exactly at `.context/plans/2026-10-01-billing-queue-worker.md`;
do not change that file name.
