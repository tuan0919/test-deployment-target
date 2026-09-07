#!/usr/bin/env bash
set -euo pipefail

INSTANCE_NAME="${INSTANCE_NAME:-eac-demo-vm}"
NETWORK_NAME="${MULTIPASS_NETWORK:-localbr}"
VM_IP="${VM_IP:-10.13.31.15}"

if [[ "$INSTANCE_NAME" != "eac-demo-vm" ]]; then
  printf 'refusing to operate on unexpected instance: %s\n' "$INSTANCE_NAME" >&2
  exit 64
fi

case "${1:-}" in
  apply)
    cloud_init_file="${2:?cloud-init path is required}"
    if ! multipass info "$INSTANCE_NAME" >/dev/null 2>&1; then
      if ! multipass launch 24.04 \
        --name "$INSTANCE_NAME" \
        --cpus 2 \
        --memory 2G \
        --disk 10G \
        --network "$NETWORK_NAME" \
        --cloud-init "$cloud_init_file" \
        --timeout 90; then
        printf 'Multipass initialization timed out; waiting for SSH on %s\n' "$VM_IP" >&2
      fi
    fi

    for _ in $(seq 1 60); do
      if timeout 2 bash -c "</dev/tcp/$VM_IP/22" 2>/dev/null; then
        exit 0
      fi
      sleep 2
    done
    printf 'VM SSH did not become reachable at %s\n' "$VM_IP" >&2
    exit 1
    ;;
  destroy)
    multipass delete --purge "$INSTANCE_NAME"
    ;;
  *)
    printf 'usage: %s {apply CLOUD_INIT_FILE|destroy}\n' "$0" >&2
    exit 64
    ;;
esac
