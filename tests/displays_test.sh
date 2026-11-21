#!/usr/bin/env bash
# Runs the display profile tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/displays_test.lua" "$REPO_DIR"
