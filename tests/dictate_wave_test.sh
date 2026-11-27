#!/usr/bin/env bash
# Builds the dictation helper and runs its own checks of the wave it draws: the gain, the
# curves and the commands Hammerspoon sends it. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
/usr/bin/swiftc -Onone "$REPO_DIR/config/hammerspoon/dictate.swift" -o "$build_dir/dictate" 2>"$build_dir/errors" || {
  cat "$build_dir/errors" >&2
  echo "FAIL - should build the dictation helper"
  exit 1
}
"$build_dir/dictate" selftest
