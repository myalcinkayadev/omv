#!/usr/bin/env bash
# Runs the Do Not Disturb tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/focus_test.lua" "$REPO_DIR"
