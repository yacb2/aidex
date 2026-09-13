#!/bin/bash
set -e
mkdir -p src .context
printf '# Orders service\n\nDjango API. `docker compose up` starts db + web.\n' > CLAUDE.md
cat > docker-compose.yml <<'YML'
services:
  db:
    image: postgres:16
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
  web:
    build: .
    ports:
      - "8000:8000"
    depends_on:
      - db
volumes:
  pgdata:
YML
printf 'FROM python:3.12-slim\nCOPY src /app/src\nCMD ["python", "-m", "http.server", "8000"]\n' > Dockerfile
printf 'print("orders")\n' > src/main.py
git init -q && git add -A && git -c user.email=e@x -c user.name=e commit -qm init
