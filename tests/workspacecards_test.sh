#!/usr/bin/env bash
# Runs the Workspaces card tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/workspacecards_test.lua" "$REPO_DIR"
