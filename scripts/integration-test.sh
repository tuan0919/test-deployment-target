#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:?base URL is required}"
EXPECTED_VERSION="${2:?expected version is required}"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

curl --fail --silent --show-error --connect-timeout 5 --max-time 15 "$BASE_URL/" > /dev/null
curl --fail --silent --show-error --connect-timeout 5 --max-time 15 "$BASE_URL/health" > "$TEST_DIR/health.json"
curl --fail --silent --show-error --connect-timeout 5 --max-time 15 "$BASE_URL/version" > "$TEST_DIR/version.json"

if ! jq --exit-status '.status == "ok"' "$TEST_DIR/health.json" > /dev/null; then
  printf 'unexpected health response: %s\n' "$(cat "$TEST_DIR/health.json")" >&2
  exit 1
fi

if ! jq --exit-status --arg expected "$EXPECTED_VERSION" '.version == $expected' "$TEST_DIR/version.json" > /dev/null; then
  printf 'expected version %s, received %s\n' "$EXPECTED_VERSION" "$(jq -r '.version // "missing"' "$TEST_DIR/version.json")" >&2
  exit 1
fi

printf 'integration test passed for %s\n' "$EXPECTED_VERSION"
