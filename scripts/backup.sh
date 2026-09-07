#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="${APP_ROOT:-/srv/eac-demo/app}"
PERSIST_DIR="${PERSIST_DIR:-/srv/eac-demo/persist}"
RUNTIME_ENV="$APP_ROOT/runtime.env"
COMPOSE_FILE="$APP_ROOT/docker-compose.yml"
started=0
restart_compose() { if [[ "$started" == 0 ]]; then docker compose --env-file "$RUNTIME_ENV" -f "$COMPOSE_FILE" up -d --wait; fi; }
trap restart_compose EXIT
docker compose --env-file "$RUNTIME_ENV" -f "$COMPOSE_FILE" exec -T postgres pg_dump -U notes notes > "$PERSIST_DIR/predeploy/predeploy.sql"
docker compose --env-file "$RUNTIME_ENV" -f "$COMPOSE_FILE" down
kopia repository connect server --url="$KOPIA_SERVER" --server-username="$KOPIA_USERNAME" --server-password="$KOPIA_PASSWORD" --no-check-for-updates
kopia snapshot create "$PERSIST_DIR" --no-check-for-updates
kopia repository disconnect --no-check-for-updates || true
