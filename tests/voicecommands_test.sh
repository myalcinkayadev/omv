#!/usr/bin/env bash
# Runs the voicecommands tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/voicecommands_test.lua" "$REPO_DIR"
