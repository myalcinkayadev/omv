#!/usr/bin/env bash
# Runs the translate tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/translate_test.lua" "$REPO_DIR"
