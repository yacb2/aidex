#!/bin/bash
set -e
mkdir -p src
printf '# Inventory API\n\nFastAPI service. Run with `uvicorn src.main:app`.\n' > README.md
printf 'from fastapi import FastAPI\n\napp = FastAPI()\n' > src/main.py
