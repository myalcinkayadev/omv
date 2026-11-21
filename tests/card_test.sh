#!/usr/bin/env bash
# Runs the card page tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/card_test.lua" "$REPO_DIR"
