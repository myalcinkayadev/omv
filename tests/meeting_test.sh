#!/usr/bin/env bash
# Runs the meeting mode tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/meeting_test.lua" "$REPO_DIR"
