#!/usr/bin/env bash
# Runs the windowsize tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/windowsize_test.lua" "$REPO_DIR"
