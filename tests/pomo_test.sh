#!/usr/bin/env bash
# Runs the Pomodoro break cards tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/pomo_test.lua" "$REPO_DIR"
