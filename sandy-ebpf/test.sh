#!/usr/bin/env bash

set -euo pipefail

# Helper to run commands with sudo if not already root
run_sudo() {
  if [ "$EUID" -ne 0 ]; then
    sudo "$@"
  else
    "$@"
  fi
}

# Verify the map exists
MAP_PATH="/sys/fs/bpf/sandy/bootstrap_pids"
if ! run_sudo test -e "$MAP_PATH"; then
  echo "Error: eBPF program is not loaded. Please run ./install.sh first." >&2
  exit 1
fi

echo "Starting sandbox shell for testing..."

# Start background shell that we can control
coproc TEST_SHELL { bash --noprofile --norc; }

# Get its PID
SHELL_PID=$TEST_SHELL_PID
echo "Sandbox Shell PID: $SHELL_PID"

# Format PID to 4-byte little-endian hex bytes
key_bytes=$(printf "%08x" $SHELL_PID | sed 's/\(..\)\(..\)\(..\)\(..\)/\4 \3 \2 \1/')

# Register PID in the eBPF map
run_sudo bpftool map update pinned "$MAP_PATH" key $key_bytes value 01

# Helper to send a command to the test shell and read output/error
run_cmd_in_shell() {
  local cmd="$1"
  echo "$cmd" >&"${TEST_SHELL[1]}"
  # We append a sentinel to check when the command completes
  echo "echo __DONE__ \$?" >&"${TEST_SHELL[1]}"
  
  local line
  while read -r line <&"${TEST_SHELL[0]}"; do
    if [[ "$line" =~ __DONE__\ ([0-9]+) ]]; then
      return "${BASH_REMATCH[1]}"
    fi
    echo "$line"
  done
}

echo "------------------------------------------------"
echo "Running test cases inside the sandboxed shell:"
echo "------------------------------------------------"

# Test Case 1: Read standard folder
echo -n "Test 1: Read /etc/hostname (should succeed)... "
if run_cmd_in_shell "cat /etc/hostname" >/dev/null; then
  echo "PASSED"
else
  echo "FAILED"
fi

# Test Case 2: Read ~/.ssh/config (should fail with ENOENT / No such file or directory)
echo -n "Test 2: Read ~/.ssh/config (should fail with ENOENT)... "
output=$(run_cmd_in_shell "cat \$HOME/.ssh/config 2>&1" || true)
if [[ "$output" == *"No such file or directory"* ]]; then
  echo "PASSED"
else
  echo "FAILED (Output: $output)"
fi

# Test Case 3: Read ~/.config/git/config (whitelisted, should succeed or return ENOENT if file missing but NOT Permission Denied)
echo -n "Test 3: Read ~/.config/git/config (whitelisted, should not return Permission Denied)... "
output=$(run_cmd_in_shell "cat \$HOME/.config/git/config 2>&1" || true)
if [[ "$output" == *"Permission denied"* ]]; then
  echo "FAILED (Output: $output)"
else
  echo "PASSED"
fi

# Test Case 4: Read a non-whitelisted config, e.g. ~/.config/sandy-blocked-test-dir/file (should fail with Permission Denied)
# Create a dummy blocked file on host for testing
mkdir -p "$HOME/.config/sandy-blocked-test-dir"
touch "$HOME/.config/sandy-blocked-test-dir/file"

echo -n "Test 4: Read non-whitelisted ~/.config/... (should fail with Permission Denied)... "
output=$(run_cmd_in_shell "cat \$HOME/.config/sandy-blocked-test-dir/file 2>&1" || true)

# Cleanup dummy file
rm -rf "$HOME/.config/sandy-blocked-test-dir"

if [[ "$output" == *"Permission denied"* ]]; then
  echo "PASSED"
else
  echo "FAILED (Output: $output)"
fi

# Test Case 5: Nested child process inheritance (should also be restricted)
echo -n "Test 5: Read ~/.ssh/config from a nested subshell (should inherit restriction and fail)... "
output=$(run_cmd_in_shell "bash -c 'cat \$HOME/.ssh/config 2>&1'" || true)
if [[ "$output" == *"No such file or directory"* ]]; then
  echo "PASSED"
else
  echo "FAILED (Output: $output)"
fi

# Cleanup BPF map (should already be deleted by eBPF program during bootstrap)
run_sudo bpftool map delete pinned "$MAP_PATH" key $key_bytes 2>/dev/null || true

# Kill background shell
kill "$SHELL_PID" 2>/dev/null || true
wait "$SHELL_PID" 2>/dev/null || true

echo "Tests completed!"
