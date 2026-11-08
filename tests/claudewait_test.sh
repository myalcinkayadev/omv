#!/usr/bin/env bash
# Runs the Claude focus tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/claudewait_test.lua" "$REPO_DIR"
