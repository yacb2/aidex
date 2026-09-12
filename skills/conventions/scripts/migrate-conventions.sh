#!/usr/bin/env bash
# Thin wrapper around migrate-conventions.py. Mirrors validate.sh.
set -euo pipefail
exec python3 "$(cd "$(dirname "$0")" && pwd)/migrate-conventions.py" "$@"
