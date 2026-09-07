#!/usr/bin/env bash
set -euo pipefail

SNAPSHOT_ID="${1:?Kopia snapshot ID is required}"
IMAGE_REF="${2:?rollback image reference is required}"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
"$SCRIPT_DIR/backup.sh"
"$SCRIPT_DIR/restore.sh" "$SNAPSHOT_ID"
"$SCRIPT_DIR/deploy.sh" "$IMAGE_REF"
"$SCRIPT_DIR/health-check.sh" "${IMAGE_REF##*:}"
