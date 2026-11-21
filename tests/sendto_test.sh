#!/usr/bin/env bash
# Runs the Send to agent tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/sendto_test.lua" "$REPO_DIR"
