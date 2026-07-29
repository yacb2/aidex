#!/usr/bin/env bash
# Thin wrapper around docs-census.py so the skill can call one stable path.
# Usage: docs-census.sh [--dry-run] [--json] [--write PATH] [--advisory]
set -euo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/docs-census.py" "$@"
