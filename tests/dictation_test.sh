#!/usr/bin/env bash
# Runs the dictation tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/dictation_test.lua" "$REPO_DIR"
