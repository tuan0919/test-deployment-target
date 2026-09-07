#!/usr/bin/env bash
set -euo pipefail

IMAGE_REF="${1:?immutable image reference is required}"
APP_ROOT="${APP_ROOT:-/srv/eac-demo/app}"
STATE_ROOT="${STATE_ROOT:-/srv/eac-demo/state}"
RUNTIME_ENV="$APP_ROOT/runtime.env"
COMPOSE_FILE="$APP_ROOT/docker-compose.yml"

case "$IMAGE_REF" in *:latest|*':') printf 'immutable image tag is required\n' >&2; exit 64;; esac
sed -i "s|^IMAGE_REF=.*|IMAGE_REF=$IMAGE_REF|; s|^APP_VERSION=.*|APP_VERSION=${IMAGE_REF##*:}|" "$RUNTIME_ENV"
docker compose --env-file "$RUNTIME_ENV" -f "$COMPOSE_FILE" pull
docker compose --env-file "$RUNTIME_ENV" -f "$COMPOSE_FILE" up -d --wait --remove-orphans
mkdir -p "$STATE_ROOT"
printf '%s\n' "$IMAGE_REF" > "$STATE_ROOT/current-image"
