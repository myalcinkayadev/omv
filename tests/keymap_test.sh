#!/usr/bin/env bash
# Runs the cheat sheet parser tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/keymap_test.lua" "$REPO_DIR"
