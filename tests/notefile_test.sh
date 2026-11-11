#!/usr/bin/env bash
# Runs the note file tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/notefile_test.lua" "$REPO_DIR"
