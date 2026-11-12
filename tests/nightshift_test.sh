#!/usr/bin/env bash
# Runs the night light tests. Hammerspoon and nightlight are not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/nightshift_test.lua" "$REPO_DIR"
