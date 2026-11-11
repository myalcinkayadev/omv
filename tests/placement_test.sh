#!/usr/bin/env bash
# Runs the placement tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/placement_test.lua" "$REPO_DIR"
