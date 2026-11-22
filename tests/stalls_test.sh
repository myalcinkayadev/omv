#!/usr/bin/env bash
# Runs the stall detector tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/stalls_test.lua" "$REPO_DIR"
