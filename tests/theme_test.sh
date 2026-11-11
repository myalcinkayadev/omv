#!/usr/bin/env bash
# Runs the theme tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/theme_test.lua" "$REPO_DIR"
