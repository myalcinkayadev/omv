#!/usr/bin/env bash
# Runs the tests of the targets kept for clicked notifications. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/notices_test.lua" "$REPO_DIR"
