#!/usr/bin/env bash
# Runs the away digest tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/digest_test.lua" "$REPO_DIR"
