#!/usr/bin/env bash
# Runs the browser tab tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/tabs_test.lua" "$REPO_DIR"
