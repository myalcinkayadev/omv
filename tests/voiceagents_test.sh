#!/usr/bin/env bash
# Runs the voiceagents tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/voiceagents_test.lua" "$REPO_DIR"
