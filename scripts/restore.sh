#!/usr/bin/env bash
set -euo pipefail

SNAPSHOT_ID="${1:?Kopia snapshot ID is required}"
APP_ROOT="${APP_ROOT:-/srv/eac-demo/app}"
PERSIST_DIR="${PERSIST_DIR:-/srv/eac-demo/persist}"
RUNTIME_ENV="$APP_ROOT/runtime.env"
COMPOSE_FILE="$APP_ROOT/docker-compose.yml"
STAGING=$(mktemp -d /srv/eac-demo/restore.XXXXXX)
docker compose --env-file "$RUNTIME_ENV" -f "$COMPOSE_FILE" down
kopia repository connect server --url="$KOPIA_SERVER" --server-username="$KOPIA_USERNAME" --server-password="$KOPIA_PASSWORD" --no-check-for-updates
kopia snapshot restore "$SNAPSHOT_ID" --target-path "$STAGING" --no-check-for-updates
kopia repository disconnect --no-check-for-updates || true
mv "$PERSIST_DIR" "${PERSIST_DIR}.pre-restore.$(date +%s)"
mv "$STAGING/persist" "$PERSIST_DIR"
chown -R deploy:deploy "$PERSIST_DIR"
