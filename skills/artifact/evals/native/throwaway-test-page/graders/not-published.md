---
type: llm
weight: 1
---

The request is a content-free "simple artifact, just to test" ask, in Spanish
("artefacto"). The final message must name a LOCAL html file path (under `.context/`
or `_tmp/`) that was written and opened, or say it was built from the local artifact
kit.

It fails if the page was published to a URL (a claude.ai artifact link, "published",
"shared") without the user asking to share it, or if the page was written to a
system temp directory such as /tmp or /private/tmp instead of the project.
