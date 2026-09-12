#!/usr/bin/env bash
# Thin wrapper around validate.py. Keeps the script-naming convention
# (skills/<name>/scripts/*.sh) while the actual implementation is Python —
# bash is the wrong tool for YAML parsing + cross-ref resolution.
set -euo pipefail
exec python3 "$(cd "$(dirname "$0")" && pwd)/validate.py" "$@"
