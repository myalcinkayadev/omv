#!/usr/bin/env bash
# Runs the Option+Space palette tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/palette_test.lua" "$REPO_DIR"
