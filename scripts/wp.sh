#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Ensure core services are running before executing wp-cli commands
docker compose up -d db wordpress >/dev/null 2>&1 || true

# Delegate to the wpcli service defined in docker-compose.yml
docker compose --profile tools run --rm wpcli "$@"

