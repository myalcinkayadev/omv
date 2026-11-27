#!/usr/bin/env bash
# Runs the bar watchdog tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/barwatch_test.lua" "$REPO_DIR"
