#!/usr/bin/env bash
# Runs the Battery card tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/battery_test.lua" "$REPO_DIR"
