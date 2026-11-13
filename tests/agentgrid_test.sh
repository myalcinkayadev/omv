#!/usr/bin/env bash
# Runs the agent grid tests. Hammerspoon and tmux are not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/agentgrid_test.lua" "$REPO_DIR"
