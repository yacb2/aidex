---
name: project-stack-shape
description: The fleet is split-repo workspaces
metadata:
  type: project
---

Most projects in the fleet are workspaces holding several git repositories rather than one: a repository at the workspace root and separate ones under the frontend and backend directories. Tooling that assumes a single repository at the project root reads the wrong history, and the failure is silent because the root repository does exist.
