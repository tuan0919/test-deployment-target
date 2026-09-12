#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d)
PORT_FILE="$TEST_DIR/port"
SERVER_PID=''

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

node -e '
  const fs = require("fs");
  const http = require("http");
  const portFile = process.argv[1];
  const server = http.createServer((request, response) => {
    if (request.url === "/health") {
      response.writeHead(200, {"content-type": "application/json"});
      return response.end(JSON.stringify({status: "ok"}));
    }
    if (request.url === "/version") {
      response.writeHead(200, {"content-type": "application/json"});
      return response.end(JSON.stringify({version: "release-123"}));
    }
    if (request.url === "/") {
      response.writeHead(200, {"content-type": "text/html"});
      return response.end("<!doctype html><title>EAC Notes</title>");
    }
    response.writeHead(404);
    response.end();
  });
  server.listen(0, "127.0.0.1", () => fs.writeFileSync(portFile, String(server.address().port)));
' "$PORT_FILE" &
SERVER_PID=$!

for _ in $(seq 1 50); do
  [ -s "$PORT_FILE" ] && break
  sleep 0.1
done

BASE_URL="http://127.0.0.1:$(cat "$PORT_FILE")"

"$ROOT_DIR/scripts/integration-test.sh" "$BASE_URL" release-123
"$ROOT_DIR/scripts/performance-test.sh" "$BASE_URL/health" 10 2 1000

if "$ROOT_DIR/scripts/integration-test.sh" "$BASE_URL" wrong-version > /dev/null 2>&1; then
  printf 'integration test must reject an unexpected version\n' >&2
  exit 1
fi

if "$ROOT_DIR/scripts/performance-test.sh" "$BASE_URL/missing" 3 1 1000 > /dev/null 2>&1; then
  printf 'performance test must reject HTTP failures\n' >&2
  exit 1
fi

printf 'post-deploy checks tests passed\n'
