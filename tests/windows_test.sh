#!/usr/bin/env bash
# Runs the window summon tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/windows_test.lua" "$REPO_DIR"
