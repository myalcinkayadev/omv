#!/usr/bin/env bash
# Runs the workspaces tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/workspaces_test.lua" "$REPO_DIR"
