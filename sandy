#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -euo pipefail

# Check if bwrap is installed
if ! command -v bwrap >/dev/null 2>&1; then
  echo "Error: bubblewrap (bwrap) is not installed." >&2
  exit 1
fi

# Ensure HOME is set
if [ -z "${HOME:-}" ]; then
  echo "Error: HOME environment variable is not set." >&2
  exit 1
fi

# Build bubblewrap arguments
bwrap_args=(
  --bind / /
  --dev-bind /dev /dev
  --tmpfs "$HOME"
)

# Populate $HOME, excluding .ssh and .config
# Use nullglob/dotglob to safely iterate over all files, including hidden ones
shopt -s nullglob dotglob

for entry in "$HOME"/*; do
  name="${entry##*/}"
  
  # Skip current and parent directories (just in case)
  if [ "$name" = "." ] || [ "$name" = ".." ]; then
    continue
  fi
  
  # Exclude .ssh and .config
  if [ "$name" = ".ssh" ] || [ "$name" = ".config" ]; then
    continue
  fi
  
  # Recreate symlinks, bind mount files/directories
  if [ -L "$entry" ]; then
    target=$(readlink "$entry")
    bwrap_args+=(--symlink "$target" "$entry")
  else
    bwrap_args+=(--bind "$entry" "$entry")
  fi
done

# Run bubblewrap
if [ $# -eq 0 ]; then
  exec bwrap "${bwrap_args[@]}" /bin/bash
elif [[ "$1" == -* ]]; then
  exec bwrap "${bwrap_args[@]}" /bin/bash "$@"
else
  exec bwrap "${bwrap_args[@]}" "$@"
fi
