#!/usr/bin/env bash
# Runs the quick note tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/quicknote_test.lua" "$REPO_DIR"
