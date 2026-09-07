#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d)
export PATH="$ROOT_DIR/tests/fixtures:$PATH"
export MULTIPASS_LOG="$TEST_DIR/multipass.log"

assert_contains() {
  local expected="$1"
  if ! grep -Fqx -- "$expected" "$MULTIPASS_LOG"; then
    printf 'expected command not found: %s\n' "$expected" >&2
    sed -n '1,120p' "$MULTIPASS_LOG" >&2
    exit 1
  fi
}

MULTIPASS_INFO_EXIT=1 "$ROOT_DIR/scripts/multipass.sh" apply "$TEST_DIR/cloud-init.yaml"
assert_contains "info eac-demo-vm"
assert_contains "launch 24.04 --name eac-demo-vm --cpus 2 --memory 2G --disk 10G --network localbr --cloud-init $TEST_DIR/cloud-init.yaml"

: > "$MULTIPASS_LOG"
MULTIPASS_INFO_EXIT=0 "$ROOT_DIR/scripts/multipass.sh" apply "$TEST_DIR/cloud-init.yaml"
assert_contains "info eac-demo-vm"
if grep -Fq 'launch ' "$MULTIPASS_LOG"; then
  printf 'apply must not launch an existing instance\n' >&2
  exit 1
fi

: > "$MULTIPASS_LOG"
"$ROOT_DIR/scripts/multipass.sh" destroy
assert_contains "delete --purge eac-demo-vm"

printf 'multipass adapter tests passed\n'
