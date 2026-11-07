#!/usr/bin/env bash
# Runs the quick reminders tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/reminders_test.lua" "$REPO_DIR"
