# Fleet version and release conventions

Shared canon. It owns two things a fleet of related workspaces otherwise copies by hand:
the **release / dependency procedure**, and the **`.claude/git-repos.json` schema** that
carries every per-project fact the procedure needs.

Decided in `decision/2026-08-25-aidex-owns-the-fleet-version-procedure.md`, superseding the
owner named in `decision/2026-08-20-version-and-deps-commands-are-owned-by-the-global-skill.md`.

**Why the procedure lives here and not in a rule.** Rules install always-on for every aidex
user, and aidex is public. A fleet-length release procedure there is paid for by readers who
do not have this fleet. What each project keeps always-on is a short norm —
`assets/templates/versioning-rule.md` — that states the invariants and points here.

**Why it lives here and not in a per-project command.** Measured 2026-08-19/20 and again
2026-08-25: four command families across nine workspaces, 36 files, seven distinct
`release.md` bodies diverging by up to 223 lines, with identical section structure. The
prose grew exactly where the data was missing. A project-level `commands/version/*` or
`commands/deps/*` is a **thin invocation** carrying no procedure text.

## The standing rule

> When a genuinely per-project fact has nowhere to live, **extend this schema**. Never
> re-grow prose in `commands/`.

That rule is what makes the single owner safe, and it has already been exercised: the
2026-08-25 reconciliation of the seven distinct bodies found three facts the schema could not
express (`release.preChecks`, `release.migrationLog`, `release.boilerplateVersion`) and they
are fields below, not paragraphs in nine files.

## `.claude/git-repos.json` — the schema

```json
{
  "repos": [
    {
      "name": "backend",
      "path": "backend",
      "suspicious": [".env", "__pycache__/"],
      "versionFile": "backend/pyproject.toml",
      "versionFormat": "pyproject",
      "releaseParticipant": true
    },
    {
      "name": "frontend",
      "path": "frontend",
      "suspicious": [".env", "node_modules/"],
      "versionFile": "frontend/package.json",
      "versionFormat": "package-json",
      "releaseParticipant": true
    }
  ],
  "versionSync": { "policy": "locked", "tagging": "together" },
  "changelog": {
    "enabled": true,
    "path": "frontend/CHANGELOG.md",
    "language": "es",
    "unified": false,
    "structure": "split-by-minor",
    "schemaPath": "frontend/changelog/schema.json"
  },
  "release": {
    "preChecks": [
      { "name": "frontend build", "cwd": "frontend", "command": "pnpm build", "why": "vue-tsc -b catches what --noEmit misses, and Vercel runs this" }
    ],
    "migrationLog": "_bp/MIGRATION_LOG.md",
    "migrationStagePaths": ["_bp/migrations/", "_bp/ops-by-version.json"],
    "boilerplateVersion": "update"
  },
  "boilerplateCheck": false
}
```

### Top level

| Field | Meaning |
|---|---|
| `repos` | The repositories this workspace contains, or the string `"auto-detect"` |
| `versionSync` | How the participants' version numbers relate to each other |
| `changelog` | Where the changelog lives and which writer handles it |
| `release` | Gates and side files the release procedure needs |
| `boilerplateCheck` | Whether a derived project is checked against its boilerplate after a commit. Default `false` — the fleet majority — so a project that wants the prompt opts in |

### `repos[]`

| Field | Meaning |
|---|---|
| `name` | Label used in output and as the command's repo argument |
| `path` | Directory, relative to the workspace root |
| `suspicious` | Paths that must never be staged from this repo |
| `versionFile` | Where this repo's version number lives, relative to the workspace root |
| `versionFormat` | `pyproject` · `package-json` · `plain` |
| `releaseParticipant` | `false` excludes the repo from version bump and tagging |

`repos` may instead be the string `"auto-detect"`: `.git` at the root means mono-repo,
`<dir>/.git` means one repo per directory. Auto-detect is also the fallback when the file is
absent.

**`versionFormat` is named, never sniffed.** Sniffing picks the wrong writer the first time a
project carries both a `package.json` and a `pyproject.toml` in one repo, and it fails
silently — the release completes with one file un-bumped.

**`releaseParticipant` exists because a repo can be present and not part of the product.** Two
live cases: a workspace-root **ops repo** holding only `dev.sh`, `test-e2e.sh` and compose
files, and a **frozen** dashboard kept for reference. Both are real repos `/git:commit` must
know about and neither may be tagged.

### `versionSync`

| Field | Values | Meaning |
|---|---|---|
| `policy` | `locked` · `independent` | `locked` = every participant carries the same number and the files must always match |
| `tagging` | `together` · `per-repo` | Whether one `vX.Y.Z` is applied to every participant in the same operation |

This is the fact the longest prose blocks were carrying. Where it is absent, treat it as
`locked` + `together` only if there is exactly one participant; otherwise it is unanswered and
must be written down before a release runs.

### `changelog`

Unchanged from the 2026-08-20 contract, restated here because this file is now its owner.

| Field | Meaning |
|---|---|
| `enabled` | `false` skips every changelog step; the release still bumps and tags |
| `path` | The `CHANGELOG.md` file, or — under `split-by-minor` — the folder that holds the family files |
| `language` | Language the entries are written in. It is the changelog's own language, not the project's |
| `unified` | Whether one changelog covers every repo (`true`) or each repo carries its own (`false`) |
| `structure` | Selects the writer, below |
| `schemaPath` | The changelog's `schema.json`, which owns the section vocabulary. Required by `split-by-minor` |

| `structure` | Layout | Writer |
|---|---|---|
| **absent** (or `"single"`) | `path` is one `CHANGELOG.md` file | single-file writer |
| `"split-by-minor"` | `path` is a **folder**: `unreleased.md` + one `X.Y.md` per minor family | split writer |

**Absence is the contract.** A project that declares no `structure` gets exactly the behaviour
it had before the split existed. That is the containment for every project that has not
migrated, and it must never be "improved" into auto-detection. `split-by-minor` also expects
`schemaPath`, the changelog's `schema.json`, which owns the section vocabulary — a heading
spelling is never invented at write time; a missing category is added to the schema.

### `release`

| Field | Meaning |
|---|---|
| `preChecks[]` | Blocking gates run before anything is written. `name`, `cwd`, `command`, `why`. Non-zero exit stops the release — no commit, no tag |
| `migrationLog` | Path to a `MIGRATION_LOG.md`, or absent if the project has none |
| `migrationStagePaths[]` | Extra paths staged with the release commit when the migration log is processed |
| `boilerplateVersion` | `update` · `ignore` · `absent`. Whether `.boilerplate-version` is bumped by a release |

**`boilerplateVersion` distinguishes two things that look alike.** In a derived project
`.boilerplate-version` is a sync marker owned by the `/bp:*` family and must **not** move on a
product release (`ignore`); in the boilerplate itself it tracks the released version and must
(`update`). Getting it backwards makes derived projects believe they are current.

**`preChecks` is a gate, not advice.** The one live instance is a mandatory `pnpm build`,
recorded with its reason: `vue-tsc --noEmit` runs flat and misses what `vue-tsc -b` catches,
the deploy runs the latter, and a release tagged past a broken build fails in production
instead of locally.

## The release procedure

1. **Run `release.preChecks`.** Any non-zero exit stops here.
2. **Analyse commits since the last tag**, per participating repo. In a split-repo workspace
   never run `git` at the workspace root — `cd` into each repo. Use relative paths: an
   absolute `/Users/...` path in a procedure is drift, and it is already present in one copy.
3. **Determine the bump**, unless one was given: `BREAKING CHANGE:`/`feat!:` → MAJOR,
   `feat:` → MINOR, otherwise → PATCH.
4. **Show the proposal and confirm.**
5. **Write the version files** named by `versionFile`, using the writer `versionFormat`
   selects. Under `versionSync.policy: locked` all participants get the same number and are
   verified equal afterwards.
6. **Fold the changelog**, using the writer `changelog.structure` selects.
7. **Process `release.migrationLog`** if declared: `[Unreleased]` → `[X.Y.Z] - YYYY-MM-DD`,
   a fresh empty `[Unreleased]` above it, and the entry files moved out of `unreleased/`.
   The migration log is developer instructions; the changelog is user-facing changes.
8. **Handle `.boilerplate-version`** as `release.boilerplateVersion` says.
9. **Commit and tag.** Stage only the release files — never `git add -A`, because unrelated
   work in progress is the normal state. Under `tagging: together` every participant gets the
   same `vX.Y.Z` in the same operation.
10. **Report; do not push.** Publishing is gated (`autonomy-conventions.md` class 2). Print
    the push command and, where a boilerplate propagation step exists, name it.

## The dependency procedure

`deps/update-frontend` and `deps/update-backend` were the least-drifted of the four families —
two distinct bodies across nine workspaces for the backend, three for the frontend — which is
what a procedure with no per-project facts in it looks like. They take their targets from
`repos[]` (`versionFormat` selects the manifest) and need no fields of their own.

## What a project-level command may contain

A thin invocation: front-matter (`argument-hint`, `description`), one line naming what it
does, and a pointer to this canon. **No workflow steps, no repo topology, no version-file
list, no changelog rules.** Every one of those is a schema field or a step above. The
template is `assets/templates/version-command.md`.

## What a project-level rule may contain

Invariants only — what a session must hold in mind at all times, because a rule is always-on
and pays its cost in every session whether or not a release is happening. The template is
`assets/templates/versioning-rule.md`. Measured before this canon existed: eight copies of
`rules/versioning.md`, 42 to 155 lines, four of them byte-identical.
