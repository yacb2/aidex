#!/bin/bash
set -e
mkdir -p .context/reports
printf '# Project\n\nSmall Django + Vue app used to smoke-test tooling.\n' > CLAUDE.md
touch .context/.aidex-artifact-style-offered
