#!/usr/bin/env bash
# Runs the mic mute decisions tests. Hammerspoon is not needed.

source "$(dirname "$0")/lib.sh"

luajit "$REPO_DIR/tests/micmute_test.lua" "$REPO_DIR"
