#!/usr/bin/env bash
# Runs the clipboard history tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/clipboard_test.lua" "$REPO_DIR"
