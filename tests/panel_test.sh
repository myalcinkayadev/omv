#!/usr/bin/env bash
# Runs the status-card layout tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/panel_test.lua" "$REPO_DIR"
