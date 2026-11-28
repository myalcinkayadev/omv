#!/usr/bin/env bash
# Runs the talkback tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/talkback_test.lua" "$REPO_DIR"
