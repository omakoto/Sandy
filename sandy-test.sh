#!/usr/bin/env bash

# Exit on error, but manage individual test failures manually
set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "Running tests for sandy..."
failed=0

# Setup temporary test directories in host's ~/.config for testing whitelisting
HOST_CONFIG_DIR="$HOME/.config"
TEST_WHITE_DIR="$HOST_CONFIG_DIR/sandy-test-whitelist-ok"
TEST_BLOCK_DIR="$HOST_CONFIG_DIR/sandy-test-whitelist-blocked"
CONFIG_DIR_CREATED=false

if [ ! -d "$HOST_CONFIG_DIR" ]; then
  mkdir -p "$HOST_CONFIG_DIR"
  CONFIG_DIR_CREATED=true
fi

mkdir -p "$TEST_WHITE_DIR"
mkdir -p "$TEST_BLOCK_DIR"

cleanup() {
  rm -rf "$TEST_WHITE_DIR" "$TEST_BLOCK_DIR"
  if [ "$CONFIG_DIR_CREATED" = true ]; then
    rmdir "$HOST_CONFIG_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT

run_test() {
  local name="$1"
  local cmd="$2"
  
  echo -n "Test: $name... "
  if eval "$cmd" >/dev/null 2>&1; then
    echo -e "${GREEN}PASSED${NC}"
  else
    echo -e "${RED}FAILED${NC}"
    failed=$((failed + 1))
  fi
}

# 1. Test direct command execution
run_test "Direct execution (echo ok)" '[ "$(./sandy echo ok)" = "ok" ]'

# 2. Test bash option execution
run_test "Bash -c option" '[ "$(./sandy -c "echo ok")" = "ok" ]'

# 3. Test .ssh exclusion
run_test ".ssh is empty or does not exist" './sandy -c "[ ! -e \"\$HOME/.ssh\" ] || [ -z \"\$(ls -A \"\$HOME/.ssh\")\" ]"'

# 4. Test .config whitelisting
run_test ".config/sandy-test-whitelist-ok exists in sandbox" \
  'CONFIG_WHITELIST_REGEX="sandy-test-whitelist-ok" ./sandy -c "[ -d \"\$HOME/.config/sandy-test-whitelist-ok\" ]"'

run_test ".config/sandy-test-whitelist-blocked does not exist in sandbox" \
  'CONFIG_WHITELIST_REGEX="sandy-test-whitelist-ok" ./sandy -c "[ ! -e \"\$HOME/.config/sandy-test-whitelist-blocked\" ]"'

# 5. Test device nodes are writable (/dev/null)
run_test "/dev/null is writable" './sandy -c "echo test > /dev/null"'

# 6. Test other $HOME entries exist (e.g., .bashrc if it exists on host)
if [ -e "$HOME/.bashrc" ]; then
  run_test ".bashrc exists in sandbox" './sandy -c "[ -e \"\$HOME/.bashrc\" ]"'
fi

# 7. Test workspace files are accessible
run_test "Workspace files visible" './sandy -c "[ -f \"\$(pwd)/sandy\" ]"'

# 8. Test file creation visibility on host
rm -f "$HOME/sandy-test-visibility-check"
run_test "File created in sandbox is visible on host" \
  './sandy touch "$HOME/sandy-test-visibility-check" && [ -f "$HOME/sandy-test-visibility-check" ]'
rm -f "$HOME/sandy-test-visibility-check"

# 9. Test git status inside sandbox does not report dot_ssh files as deleted
PARENT_REPO=$(git -C ../.. rev-parse --show-toplevel 2>/dev/null || true)
if [ -n "$PARENT_REPO" ]; then
  run_test "Git status does not show hidden dot_ssh files as deleted" \
    "! (./sandy git -C \"$PARENT_REPO\" status --porcelain | grep -E \"^( D|D ) .*dot_ssh\")"

  # 10. Test git status inside sandbox reports dot_ssh files as deleted when wrapper is disabled (-N)
  run_test "Git status shows hidden dot_ssh files as deleted with -N" \
    "./sandy -N git -C \"$PARENT_REPO\" status --porcelain | grep -q -E \"^( D|D ) .*dot_ssh\""
fi

if [ "$failed" -eq 0 ]; then
  echo -e "\n${GREEN}All tests passed!${NC}"
  exit 0
else
  echo -e "\n${RED}$failed test(s) failed.${NC}"
  exit 1
fi
