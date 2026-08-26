# UX audit playbook

Structure: **core checks x screens.** Walk each screen in scope and record every failed check as a row in `00-inventory.md`.

## When to run

- Before a release that touches the booking flow.
- After a design refresh.

## Core checks

1. Primary action visible without scrolling on a 375px viewport.
2. Every form error names the field and how to fix it.
3. Empty states say what to do next.
4. Times are shown in the viewer's timezone with the zone visible.

## Severity

- **P0** blocks booking a room · **P1** misleads the user · **P2** polish · **P3** nit.
