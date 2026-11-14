#!/usr/bin/env bash
# Runs the palette file search tests with luajit. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/files_test.lua" "$REPO_DIR"
