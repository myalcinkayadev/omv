#!/usr/bin/env bash
# Runs the Disk card tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/disk_test.lua" "$REPO_DIR"
