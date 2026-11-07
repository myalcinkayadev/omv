#!/usr/bin/env bash
# Runs the card renderer and system menu tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/menu_test.lua" "$REPO_DIR"
