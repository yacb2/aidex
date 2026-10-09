Shared `<script>`/`<style>` bodies of the kit pages used as grader fixtures by the
`scn-*` cases (`<case>/grader-fixtures/<grader>.{pass,fail}.*`). A fixture holds
`@@kit:<sha>@@` where the body was; expand it before matching, so a regex grader is
checked against the full kit JS (a pattern that matches bare kit tokens passes
anything). The dot keeps this folder out of `collect-cases.sh`'s `*/` glob.
