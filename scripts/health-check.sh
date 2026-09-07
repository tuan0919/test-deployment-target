#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8080}"
EXPECTED_VERSION="${1:?expected immutable version is required}"
curl --fail --retry 12 --retry-all-errors --retry-delay 2 "$BASE_URL/health"
curl --fail "$BASE_URL/version" | grep -Fq "\"version\":\"$EXPECTED_VERSION\""
curl --fail "$BASE_URL/notes" >/dev/null
