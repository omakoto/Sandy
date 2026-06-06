#!/usr/bin/env bash

set -euo pipefail

# Ensure bpftool and clang are installed
for cmd in bpftool clang make; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is required but not installed." >&2
    exit 1
  fi
done

echo "Building eBPF program as current user..."
make clean
make

# Helper to run commands with sudo if not already root
run_sudo() {
  if [ "$EUID" -ne 0 ]; then
    sudo "$@"
  else
    "$@"
  fi
}

echo "Setting up BPF filesystem (may request sudo)..."
# Mount bpffs if not already mounted
if ! mount | grep -q "type bpf"; then
  run_sudo mount -t bpf bpffs /sys/fs/bpf || true
fi

# Create directory for sandy eBPF pins
run_sudo mkdir -p /sys/fs/bpf/sandy

# Unload previous instance if pinned
if run_sudo test -e /sys/fs/bpf/sandy/sandy_lsm; then
  echo "Unloading existing program..."
  run_sudo rm -f /sys/fs/bpf/sandy/sandy_lsm
  run_sudo rm -f /sys/fs/bpf/sandy/bootstrap_pids
fi

echo "Loading and attaching eBPF LSM program..."
run_sudo bpftool prog load sandy_lsm.bpf.o /sys/fs/bpf/sandy/sandy_lsm type lsm pinmaps /sys/fs/bpf/sandy

# Check if the map was successfully pinned
if ! run_sudo test -e /sys/fs/bpf/sandy/bootstrap_pids; then
  echo "Error: Failed to pin BPF map 'bootstrap_pids'." >&2
  exit 1
fi

echo "Setting map permissions..."
# Allow regular users to register their PIDs in the map
run_sudo chmod 666 /sys/fs/bpf/sandy/bootstrap_pids

echo "eBPF program loaded successfully!"
echo "Program pinned at: /sys/fs/bpf/sandy/sandy_lsm"
echo "PID map pinned at: /sys/fs/bpf/sandy/bootstrap_pids"
