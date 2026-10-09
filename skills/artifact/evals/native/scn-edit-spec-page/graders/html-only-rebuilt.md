---
type: llm
weight: 1
---

The project has `.context/research/2026-10-09-order-list/consulta.spec.md` and the page
`consulta.html` built from it. The request changes Q1's recommendation.

It passes when every change to `consulta.html` in the transcript came from running the
build (`spec_build.py`, directly or through the artifact skill's scripts) after the spec
was edited.

It fails if `consulta.html` was changed by any other means: the Edit or Write tool, or a
Bash command that rewrites it (`sed -i`, `perl -pi`, a python or shell script that writes
the file, a redirect into it). Reading the file (`cat`, `sed -n`, `grep`, Read) is fine.
It also fails if the html was never changed at all.
