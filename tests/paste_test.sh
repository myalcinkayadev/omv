#!/usr/bin/env bash
# Runs the paste tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/paste_test.lua" "$REPO_DIR"
