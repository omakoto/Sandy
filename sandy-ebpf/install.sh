#!/usr/bin/env bash

set -euo pipefail

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run as root (sudo ./install.sh)" >&2
  exit 1
fi

# Ensure bpftool and clang are installed
for cmd in bpftool clang make; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is required but not installed." >&2
    exit 1
  fi
done

echo "Building eBPF program..."
make clean
make

echo "Setting up BPF filesystem..."
# Mount bpffs if not already mounted
if ! mount | grep -q "type bpf"; then
  mount -t bpf bpffs /sys/fs/bpf || true
fi

# Create directory for sandy eBPF pins
mkdir -p /sys/fs/bpf/sandy

# Unload previous instance if pinned
if [ -e /sys/fs/bpf/sandy/sandy_lsm ]; then
  echo "Unloading existing program..."
  rm -f /sys/fs/bpf/sandy/sandy_lsm
  rm -f /sys/fs/bpf/sandy/sandboxed_pids
fi

echo "Loading and attaching eBPF LSM program..."
bpftool prog load sandy_lsm.bpf.o /sys/fs/bpf/sandy/sandy_lsm type lsm pinmaps /sys/fs/bpf/sandy

# Check if the map was successfully pinned
if [ ! -e /sys/fs/bpf/sandy/sandboxed_pids ]; then
  echo "Error: Failed to pin BPF map 'sandboxed_pids'." >&2
  exit 1
fi

echo "Setting map permissions..."
# Allow regular users to register their PIDs in the map
chmod 666 /sys/fs/bpf/sandy/sandboxed_pids

echo "eBPF program loaded successfully!"
echo "Program pinned at: /sys/fs/bpf/sandy/sandy_lsm"
echo "PID map pinned at: /sys/fs/bpf/sandy/sandboxed_pids"
