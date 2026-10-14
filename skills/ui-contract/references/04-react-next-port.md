# Porting the harness to React / Next.js — what one port recorded

Read this when the presence check (`01-harness-contract.md`) finds the harness absent in a
React or Next.js tree. No Next form of the boilerplate harness migration exists. This file
describes what the one known port did; it ships no harness code, and the project's own
source stays the authority.

Source of every sentence below: the findings of a 2026-10-14 spike that ported the harness
to a Next.js fork of the boilerplate (kept in that project's
`.context/ui-contracts/_spike/`). Section numbers in brackets are that file's. Paths are
relative to the fork's `frontend/` unless noted. A port is one data point (Next.js 16 /
React 19, App Router), not a verified recipe.

## What was ported [findings 1]

- The Vue `frontend/` of the boilerplate has the state-gallery harness; its `frontend-next`
  had no `tests/demo/`, no demo config, no meta-suite and no contact-sheet scripts. The
  port added them to the fork; a backport to the boilerplate was filed as a candidate.
- The ops-root `test-e2e.sh` had no `--demo` mode; the port added `run_demo`
  (`refuse_demo_paths` was not ported).
- `tests/e2e-setup/test-config.ts` and `global-setup.ts` fell back to the main tree's ports,
  so a run from a worktree dropped and recreated the dev database; the port added
  `loadSlotEnv()` in `test-config.ts`, reading the worktree `.env` first.

## Vue anchor to Next equivalent [findings 2]

| Harness assumption (Vue) | What the port used |
|---|---|
| Content scroller (`MainLayout.vue:39`) | `main[data-slot="sidebar-inset"] > .overflow-auto` (`ContentContainer.tsx:13`, `components/ui/sidebar.tsx:400`) |
| Theme planted in `localStorage` before paint | A cookie read on the server (`lib/theme/theme.ts:15`, `app/layout.tsx:35-53`), pinned with `context.addCookies` |
| Persona by patching `/auth/me/` with `page.route` | Not possible: the Next server fetches it (`lib/api/session.ts:7`, `app/(app)/layout.tsx:58`). The port logs in as another seeded user (`CellDrive.as`) |
| In-page MSW worker | `page.route` reaches browser requests only |
| `vite-warmup` project | Dropped: the demo run serves a production build |
| Version mask (`AppSidebar.vue`) | `components/app-shell/VersionButton.tsx:26` |
| Error toast (`App.vue:38`) | `app/layout.tsx:71`, Sonner `<Toaster/>` |
| `networkidle`, `waitForTimeout` | Banned by that repo's eslint (`eslint.config.mjs:67-73`); the port used `waitForHydration` and `page.clock` |
| `import.meta.env.DEV` dev routes | `NEXT_PUBLIC_DEV_SURFACES` guard as in `(auth)/login/page.tsx:18`, `lib/dev-surfaces.ts` |

Any Server Component data has the same limit as the session: fixtures must be props, not
mocked requests [findings 2].

## React-specific capture problems [findings 3]

Workarounds are in the port's `tests/demo/state-gallery.ts`.

| Problem | Workaround |
|---|---|
| The server-rendered page is visible before it is interactive, a click before hydration is lost, and the shell has no hydration marker | `waitForHydration` checks React's `__reactFiber$` on the content root |
| Streamed RSC copy sits in `div[hidden][id^="S:"]` for about 250 ms beside the rendered one, so every `ready` locator matched two nodes (all mobile rows failed on the first run) | Wait until no `S:` / `B:` streaming node is left; a named cause, not a flake |
| Every `page.tsx` needs a `pageTitle` catalog key (`app/__tests__/page-titles.test.tsx`) | A key per gallery page |
| Removing a route breaks `next build` because `tsconfig.json` includes `.next*/types/**` (stale typegen) | Guard the route with `notFound()` instead of deleting it |
| Split git: the board's `git diff` from the ops root sees nothing under the ignored `frontend/` | `owning_repo()` in `gallery_board.py` |

## Left open

The findings record no decision on: backporting the harness to the boilerplate's Next
frontend, or shipping a React harness template with this skill. Until decided, a React/Next
fork ports it by hand as above.
