#!/bin/bash
set -e
mkdir -p .context/decisions .context/references
printf '# Project\n\nSmall Django + Vue app.\n' > CLAUDE.md
