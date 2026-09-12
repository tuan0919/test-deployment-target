#!/usr/bin/env bash
set -euo pipefail

URL="${1:?URL is required}"
REQUESTS="${2:-30}"
CONCURRENCY="${3:-5}"
MAX_AVERAGE_MS="${4:-750}"
RESULTS=$(mktemp)
trap 'rm -f "$RESULTS"' EXIT

case "$REQUESTS:$CONCURRENCY:$MAX_AVERAGE_MS" in
  *[!0-9:]*|'') printf 'requests, concurrency and max average latency must be positive integers\n' >&2; exit 64 ;;
esac
if [ "$REQUESTS" -lt 1 ] || [ "$CONCURRENCY" -lt 1 ] || [ "$MAX_AVERAGE_MS" -lt 1 ]; then
  printf 'requests, concurrency and max average latency must be greater than zero\n' >&2
  exit 64
fi

export URL
seq "$REQUESTS" | xargs -P "$CONCURRENCY" -I '{}' \
  sh -c 'curl --silent --show-error --connect-timeout 5 --max-time 15 --output /dev/null --write-out "%{http_code} %{time_total}\n" "$URL"' \
  > "$RESULTS"

awk -v expected="$REQUESTS" -v max_ms="$MAX_AVERAGE_MS" '
  $1 !~ /^2[0-9][0-9]$/ { failures++ }
  { total_seconds += $2; count++ }
  END {
    average_ms = count ? (total_seconds * 1000 / count) : 0
    printf "performance test: requests=%d failures=%d average_ms=%.2f limit_ms=%d\n", count, failures, average_ms, max_ms
    if (count != expected || failures > 0 || average_ms > max_ms) exit 1
  }
' "$RESULTS"
