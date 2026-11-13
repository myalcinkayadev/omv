#!/usr/bin/env bash
# Runs the README screenshot list tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/shots_test.lua" "$REPO_DIR"
