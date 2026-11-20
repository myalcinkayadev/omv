#!/usr/bin/env bash
# Runs the currency rates tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/rates_test.lua" "$REPO_DIR"
