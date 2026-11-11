#!/usr/bin/env bash
# Runs the app setting tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/apps_test.lua" "$REPO_DIR"
