#!/usr/bin/env bash
# Runs the calendar card tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/calendar_test.lua" "$REPO_DIR"
