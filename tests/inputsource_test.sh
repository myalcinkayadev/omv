#!/usr/bin/env bash
# Runs the input source tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/inputsource_test.lua" "$REPO_DIR"
